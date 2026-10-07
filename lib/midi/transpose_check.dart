// Q06: conferência do TRANSPOSE do teclado (docs/plano/Q06). Diz à pessoa qual
// valor ajustar, lê pelo MIDI (ou de ouvido) se ela ajustou e descobre de uma
// vez como aquele teclado trata a própria transposição.
import 'dart:async';

import 'package:flutter/material.dart';

import '../course/note_names.dart' show NoteNaming;
import '../music/transposition.dart';
import '../settings/app_settings.dart' show KeyboardTransposeBehavior;
import '../ui/theme.dart';
import 'midi_input_service.dart';
import 'piano_keyboard.dart';

/// O Dó central, a tecla que a conferência pede (altura **escrita**).
const int kCheckKeyMidi = 60;

/// Quanto a conferência espera pela tecla.
const Duration kCheckKeyTimeout = Duration(seconds: 30);

/// Intervalo entre as duas notas do teste da entrada.
const Duration kCheckInputGap = Duration(milliseconds: 1200);

/// O que o número que chegou ao apertar o Dó central diz do teclado.
enum CheckKeyKind {
  /// Chegou a soada (`60 − k`): o teclado transpõe a saída MIDI e está certo.
  shiftsOut,

  /// Chegou 60: ou o teclado não transpõe a saída, ou a pessoa não ajustou.
  /// Só o ouvido separa os dois.
  ambiguous,

  /// Chegou `60 + d`: o teclado está em TRANSPOSE `d` (só quem transpõe a
  /// saída manda deslocado).
  offset,

  /// Chegou outra oitava do Dó (`60 ± 12n`): a pessoa tocou outro Dó.
  wrongOctave,
}

/// A leitura de uma tecla da conferência ([classifyCheckKey]).
class CheckKeyReading {
  const CheckKeyReading(this.kind, [this.offset = 0]);

  final CheckKeyKind kind;

  /// O TRANSPOSE em que o teclado parece estar (só em [CheckKeyKind.offset]).
  final int offset;
}

/// Lê [received], o número que chegou ao pedir o Dó central, com a partitura
/// deslocada de [k] semitons (`k != 0`: sem transposição não há o que
/// conferir). A grafia "outro valor" do Q06 é `offset`; as oitavas do Dó são
/// separadas antes, porque tocar o Dó do lado é um engano muito mais comum que
/// um TRANSPOSE de ±12.
CheckKeyReading classifyCheckKey(int received, int k) {
  assert(k != 0, 'sem transposição não há o que conferir');
  final soundingKey = kCheckKeyMidi - k;
  if (received == soundingKey) {
    return const CheckKeyReading(CheckKeyKind.shiftsOut);
  }
  if (received == kCheckKeyMidi) {
    return const CheckKeyReading(CheckKeyKind.ambiguous);
  }
  final d = received - kCheckKeyMidi;
  if (d % 12 == 0) return const CheckKeyReading(CheckKeyKind.wrongOctave);
  return CheckKeyReading(CheckKeyKind.offset, d);
}

/// "+2", "−5" (sinal de menos tipográfico), "0".
String signedTranspose(int value) => switch (value) {
  > 0 => '+$value',
  < 0 => '−${-value}',
  _ => '0',
};

/// A conferência abre sozinha? Ao ligar a transposição ou abrir uma música
/// transposta, **se** há um teclado conectado que ainda não foi conferido, o
/// som não é só do app (nada a ajustar no teclado) e a pessoa não a fechou
/// antes nesta tela. Depois disso, só pelo selo (Q08).
bool shouldAutoCheckTranspose({
  required Transposition? transposition,
  required String? deviceName,
  required KeyboardTransposeBehavior behavior,
  required bool appIsSound,
  required bool alreadyAsked,
}) =>
    transposition != null &&
    transposition.semitones != 0 &&
    deviceName != null &&
    !behavior.isChecked &&
    !appIsSound &&
    !alreadyAsked;

/// Abre a conferência de [deviceName] para [transposition]. Devolve o que se
/// descobriu do teclado — [previous] com o que a conferência acrescentou — ou
/// `null` se a pessoa fechou antes de terminar (nada fica guardado).
///
/// - [input] entrega a tecla apertada;
/// - [playOwnSound] toca [pitch] (MIDI) pelo som do **próprio app** para o
///   teste de ouvido e devolve `false` sem som disponível (Web sem gesto, motor
///   desligado): aí vale a palavra da pessoa;
/// - [playOnKeyboard], quando o app toca pelo teclado (M03), manda [pitch]
///   cru ao teclado, sem conversão, para o teste da entrada. `null` pula esse
///   passo.
Future<KeyboardTransposeBehavior?> showTransposeCheck(
  BuildContext context, {
  required Transposition transposition,
  required String deviceName,
  required MidiInputService input,
  required KeyboardTransposeBehavior previous,
  Future<bool> Function(int pitch)? playOwnSound,
  Future<void> Function(int pitch)? playOnKeyboard,
  NoteNaming naming = NoteNaming.latin,
  Duration keyTimeout = kCheckKeyTimeout,
  Duration inputGap = kCheckInputGap,
}) {
  return showDialog<KeyboardTransposeBehavior>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TransposeCheckDialog(
      transposition: transposition,
      deviceName: deviceName,
      input: input,
      previous: previous,
      playOwnSound: playOwnSound,
      playOnKeyboard: playOnKeyboard,
      naming: naming,
      keyTimeout: keyTimeout,
      inputGap: inputGap,
    ),
  );
}

enum _Step {
  instruction,
  listening,
  noKey,
  wrongOctave,
  offset,
  ear,
  earNoSound,
  earNo,
  inputTest,
  done,
}

class _TransposeCheckDialog extends StatefulWidget {
  const _TransposeCheckDialog({
    required this.transposition,
    required this.deviceName,
    required this.input,
    required this.previous,
    required this.playOwnSound,
    required this.playOnKeyboard,
    required this.naming,
    required this.keyTimeout,
    required this.inputGap,
  });

  final Transposition transposition;
  final String deviceName;
  final MidiInputService input;
  final KeyboardTransposeBehavior previous;
  final Future<bool> Function(int pitch)? playOwnSound;
  final Future<void> Function(int pitch)? playOnKeyboard;
  final NoteNaming naming;
  final Duration keyTimeout;
  final Duration inputGap;

  @override
  State<_TransposeCheckDialog> createState() => _TransposeCheckDialogState();
}

class _TransposeCheckDialogState extends State<_TransposeCheckDialog> {
  _Step _step = _Step.instruction;
  StreamSubscription<PlayedNote>? _sub;
  Timer? _deadline;

  /// O teclado transpõe a saída? Preenchido no passo da tecla / do ouvido.
  bool? _out;

  /// O TRANSPOSE em que o teclado parece estar ([_Step.offset]).
  int _offset = 0;

  /// A resposta do passo 4 (`null` = não se perguntou).
  bool? _inShifts;

  /// Quantas notas do teste da entrada já soaram (0 = ainda não começou).
  int _inputPlayed = 0;
  bool _inputTestRunning = false;

  int get _k => widget.transposition.semitones;
  int get _soundingKey => kCheckKeyMidi - _k;

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _go(_Step step) {
    if (!mounted) return;
    setState(() => _step = step);
  }

  void _listen() {
    _stopListening();
    _go(_Step.listening);
    _sub = widget.input.notes.listen((n) {
      if (n.on) _onKey(n.pitch);
    });
    _deadline = Timer(widget.keyTimeout, () {
      _stopListening();
      _go(_Step.noKey);
    });
  }

  void _stopListening() {
    _deadline?.cancel();
    _deadline = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _onKey(int pitch) {
    _stopListening();
    final reading = classifyCheckKey(pitch, _k);
    switch (reading.kind) {
      case CheckKeyKind.shiftsOut:
        _out = true;
        _afterOut();
      case CheckKeyKind.ambiguous:
        _startEarTest();
      case CheckKeyKind.offset:
        // Só quem transpõe a saída manda deslocado.
        _out = true;
        _offset = reading.offset;
        _go(_Step.offset);
      case CheckKeyKind.wrongOctave:
        _go(_Step.wrongOctave);
    }
  }

  Future<void> _startEarTest() async {
    final play = widget.playOwnSound;
    final played = play == null ? false : await play(_soundingKey);
    _go(played ? _Step.ear : _Step.earNoSound);
  }

  Future<void> _replayEar() async {
    await widget.playOwnSound?.call(_soundingKey);
  }

  /// Passo 4: só se o app toca pelo teclado.
  void _afterOut() {
    if (widget.playOnKeyboard != null) {
      _go(_Step.inputTest);
      unawaited(_playInputTest());
    } else {
      _go(_Step.done);
    }
  }

  Future<void> _playInputTest() async {
    final play = widget.playOnKeyboard;
    if (play == null || _inputTestRunning) return;
    _inputTestRunning = true;
    if (mounted) setState(() => _inputPlayed = 0);
    await play(kCheckKeyMidi);
    if (mounted) setState(() => _inputPlayed = 1);
    await Future<void>.delayed(widget.inputGap);
    if (!mounted) return;
    await play(_soundingKey);
    if (mounted) setState(() => _inputPlayed = 2);
    _inputTestRunning = false;
  }

  void _finish(KeyboardTransposeBehavior behavior) =>
      Navigator.pop(context, behavior);

  /// O que se descobriu, sobre o que já se sabia do teclado.
  KeyboardTransposeBehavior _result({bool? shiftsIn}) =>
      KeyboardTransposeBehavior(
        shiftsOut: _out,
        shiftsIn: shiftsIn ?? widget.previous.shiftsIn,
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.transposition;
    final target = signedTranspose(t.keyboard);
    final (:body, :actions) = _content(t, target, _keyName);
    return AlertDialog(
      title: const Text('Conferir o teclado'),
      // `maxFinite`: o teclado desenhado mede a largura que o diálogo der, e um
      // `LayoutBuilder` não responde à medida intrínseca do `AlertDialog`.
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...body,
              if (_step == _Step.listening || _step == _Step.instruction) ...[
                const SizedBox(height: 12),
                _KeyboardHint(input: widget.input, naming: widget.naming),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_step == _Step.done ? 'Descartar' : 'Cancelar'),
        ),
        ...actions,
      ],
    );
  }

  String get _keyName =>
      widget.naming == NoteNaming.latin ? 'Dó central' : 'C central';

  void _answerInput({required bool shiftsIn}) {
    _inShifts = shiftsIn;
    _go(_Step.done);
  }

  ({List<Widget> body, List<Widget> actions}) _content(
    Transposition t,
    String target,
    String key,
  ) {
    Widget text(String s, {bool bold = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        s,
        style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
    );
    Widget caption(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(s, style: const TextStyle(fontSize: 13, color: kInkCaption)),
    );
    final retry = TextButton(
      onPressed: () => _go(_Step.instruction),
      child: const Text('Tentar de novo'),
    );
    return switch (_step) {
      _Step.instruction => (
        body: [
          text('No seu teclado, ajuste o TRANSPOSE para $target.', bold: true),
          text('Assim ${t.soundsLike(kCheckKeyMidi, naming: widget.naming)}.'),
          caption(
            'Costuma ser um botão TRANSPOSE ou uma função no menu; veja o '
            'manual do seu teclado.',
          ),
        ],
        actions: [
          FilledButton(onPressed: _listen, child: const Text('Já ajustei')),
        ],
      ),
      _Step.listening => (
        body: [
          text('Toque o $key.', bold: true),
          caption('A tecla marcada, no meio do teclado.'),
        ],
        actions: const [],
      ),
      _Step.noKey => (
        body: [text('Não chegou nada do teclado. Ele está conectado?')],
        actions: [retry],
      ),
      _Step.wrongOctave => (
        body: [text('Essa não é o $key. Toque o Dó do meio do teclado.')],
        actions: [
          FilledButton(onPressed: _listen, child: const Text('Tentar de novo')),
        ],
      ),
      _Step.offset => (
        body: [
          text(
            'Seu teclado parece estar em ${signedTranspose(_offset)}. '
            'Ajuste para $target.',
          ),
        ],
        actions: [retry],
      ),
      _Step.ear => (
        body: [
          text('O app tocou essa nota pelo som dele.'),
          text('Soou igual à sua tecla Dó?', bold: true),
        ],
        actions: [
          TextButton(onPressed: _replayEar, child: const Text('Ouvir de novo')),
          TextButton(
            onPressed: () => _go(_Step.earNo),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () {
              _out = false;
              _afterOut();
            },
            child: const Text('Sim'),
          ),
        ],
      ),
      _Step.earNoSound => (
        body: [
          text(
            'Não deu para tocar aqui. Você ajustou o TRANSPOSE para '
            '$target?',
          ),
        ],
        actions: [
          FilledButton(
            onPressed: () {
              _out = false;
              _afterOut();
            },
            child: const Text('Já ajustei'),
          ),
        ],
      ),
      _Step.earNo => (
        body: [text('Confira o TRANSPOSE: precisa ser $target.')],
        actions: [retry],
      ),
      _Step.inputTest => (
        body: [
          text(
            _inputPlayed < 2
                ? 'Vão soar duas notas no teclado, uma de cada vez…'
                : 'Qual soou igual à sua tecla Dó: a 1ª ou a 2ª?',
            bold: _inputPlayed >= 2,
          ),
        ],
        actions: [
          TextButton(
            onPressed: _inputPlayed < 2 ? null : _playInputTest,
            child: const Text('Ouvir de novo'),
          ),
          TextButton(
            onPressed: _inputPlayed < 2
                ? null
                : () => _answerInput(shiftsIn: false),
            child: const Text('A 2ª'),
          ),
          FilledButton(
            onPressed: _inputPlayed < 2
                ? null
                : () => _answerInput(shiftsIn: true),
            child: const Text('A 1ª'),
          ),
        ],
      ),
      _Step.done => (
        body: [
          text('Pronto.', bold: true),
          text(
            _out == true
                ? 'Este teclado manda a nota já transposta; o app cuida do '
                      'resto.'
                : 'Este teclado só muda o som; o app cuida do resto.',
          ),
        ],
        actions: [
          FilledButton(
            onPressed: () => _finish(_result(shiftsIn: _inShifts)),
            child: const Text('Concluir'),
          ),
        ],
      ),
    };
  }
}

/// O teclado desenhado do passo 2: duas oitavas em volta do Dó central, com a
/// tecla pedida marcada e a que a pessoa aperta acesa.
class _KeyboardHint extends StatelessWidget {
  const _KeyboardHint({required this.input, required this.naming});

  final MidiInputService input;
  final NoteNaming naming;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, 360.0)
            : 320.0;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: ValueListenableBuilder<Set<int>>(
            valueListenable: input.held,
            builder: (context, held, _) => CustomPaint(
              size: Size(width, 88),
              painter: PianoKeyboardPainter(
                held: held,
                heldColor: kAccent,
                lowest: kCheckKeyMidi - 12,
                highest: kCheckKeyMidi + 12,
                marked: const {kCheckKeyMidi},
                markedColor: kAccent,
                names: true,
                naming: naming,
              ),
            ),
          ),
        );
      },
    );
  }
}
