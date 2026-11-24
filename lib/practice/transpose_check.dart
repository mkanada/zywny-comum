// Q06: conferência do TRANSPOSE do teclado (docs/plano/Q06). Diz à pessoa qual
// valor ajustar, lê pelo MIDI (ou de ouvido) se ela ajustou e descobre de uma
// vez como aquele teclado trata a própria transposição.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_midi/midi_input_service.dart';

import '../midi/piano_keyboard.dart';

import 'package:zywny_music/note_names.dart' show NoteNaming;
import 'package:zywny_music/transposition.dart';

import '../settings/settings_cubit.dart' show KeyboardTransposeBehavior;
import '../ui/theme.dart';

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

/// Os dados que a decisão de abrir a conferência sozinha usa (ver
/// [shouldAutoCheckTranspose]).
class AutoCheckState {
  const AutoCheckState({
    required this.transposition,
    required this.deviceName,
    required this.behavior,
    required this.appIsSound,
    required this.alreadyAsked,
  });

  final Transposition? transposition;
  final String? deviceName;
  final KeyboardTransposeBehavior behavior;
  final bool appIsSound;
  final bool alreadyAsked;
}

/// A conferência abre sozinha? Ao ligar a transposição ou abrir uma música
/// transposta, **se** há um teclado conectado que ainda não foi conferido, o
/// som não é só do app (nada a ajustar no teclado) e a pessoa não a fechou
/// antes nesta tela. Depois disso, só pelo selo (Q08).
bool shouldAutoCheckTranspose({required AutoCheckState state}) {
  final transposition = state.transposition;
  return transposition != null &&
      transposition.semitones != 0 &&
      state.deviceName != null &&
      !state.behavior.isChecked &&
      !state.appIsSound &&
      !state.alreadyAsked;
}

/// O que a conferência precisa para abrir (ver [showTransposeCheck]).
///
/// - [input] entrega a tecla apertada;
/// - [playOwnSound] toca [pitch] (MIDI) pelo som do **próprio app** para o
///   teste de ouvido e devolve `false` sem som disponível (Web sem gesto, motor
///   desligado): aí vale a palavra da pessoa;
/// - [playOnKeyboard], quando o app toca pelo teclado (M03), manda [pitch]
///   cru ao teclado, sem conversão, para o teste da entrada. `null` pula esse
///   passo.
class TransposeCheckRequest {
  const TransposeCheckRequest({
    required this.transposition,
    required this.deviceName,
    required this.input,
    required this.previous,
    this.playOwnSound,
    this.playOnKeyboard,
    this.naming = NoteNaming.latin,
    this.keyTimeout = kCheckKeyTimeout,
    this.inputGap = kCheckInputGap,
  });

  final Transposition transposition;
  final String deviceName;
  final MidiInputService input;

  /// O que já se sabia do teclado; a conferência acrescenta o que descobrir.
  final KeyboardTransposeBehavior previous;
  final Future<bool> Function(int pitch)? playOwnSound;
  final Future<void> Function(int pitch)? playOnKeyboard;
  final NoteNaming naming;
  final Duration keyTimeout;
  final Duration inputGap;
}

/// Abre a conferência de [TransposeCheckRequest.deviceName] para a
/// transposição do pedido. Devolve o que se descobriu do teclado — o
/// `previous` com o que a conferência acrescentou — ou `null` se a pessoa
/// fechou antes de terminar (nada fica guardado).
Future<KeyboardTransposeBehavior?> showTransposeCheck(
  BuildContext context, {
  required TransposeCheckRequest request,
}) {
  return showDialog<KeyboardTransposeBehavior>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TransposeCheckDialog(
      transposition: request.transposition,
      deviceName: request.deviceName,
      input: request.input,
      previous: request.previous,
      playOwnSound: request.playOwnSound,
      playOnKeyboard: request.playOnKeyboard,
      naming: request.naming,
      keyTimeout: request.keyTimeout,
      inputGap: request.inputGap,
    ),
  );
}

/// Os passos da conferência (o que a caixa mostra).
enum TransposeStep {
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

/// O que a conferência sabe: o passo, e o que já se descobriu nele.
class TransposeCheckState extends Equatable {
  const TransposeCheckState({
    this.step = TransposeStep.instruction,
    this.out,
    this.offset = 0,
    this.inShifts,
    this.inputPlayed = 0,
  });

  final TransposeStep step;

  /// O teclado transpõe a saída? Preenchido no passo da tecla / do ouvido.
  final bool? out;

  /// O TRANSPOSE em que o teclado parece estar ([TransposeStep.offset]).
  final int offset;

  /// A resposta do passo 4 (`null` = não se perguntou).
  final bool? inShifts;

  /// Quantas notas do teste da entrada já soaram (0 = ainda não começou).
  final int inputPlayed;

  TransposeCheckState copyWith({
    TransposeStep? step,
    bool? out,
    int? offset,
    bool? inShifts,
    int? inputPlayed,
  }) => TransposeCheckState(
    step: step ?? this.step,
    out: out ?? this.out,
    offset: offset ?? this.offset,
    inShifts: inShifts ?? this.inShifts,
    inputPlayed: inputPlayed ?? this.inputPlayed,
  );

  @override
  List<Object?> get props => [step, out, offset, inShifts, inputPlayed];
}

/// A conferência do TRANSPOSE: ouve a tecla do Dó central (com prazo), faz o
/// teste de ouvido e o da entrada, e diz o que o teclado faz. Os Timers e a
/// escuta do MIDI param no [close].
class TransposeCheckCubit extends Cubit<TransposeCheckState> {
  TransposeCheckCubit({
    required this.transposition,
    required this.input,
    required this.previous,
    this.playOwnSound,
    this.playOnKeyboard,
    required this.keyTimeout,
    required this.inputGap,
  }) : super(const TransposeCheckState());

  final Transposition transposition;
  final MidiInputService input;
  final KeyboardTransposeBehavior previous;
  final Future<bool> Function(int pitch)? playOwnSound;
  final Future<void> Function(int pitch)? playOnKeyboard;
  final Duration keyTimeout;
  final Duration inputGap;

  StreamSubscription<PlayedNote>? _sub;
  Timer? _prazo;
  bool _testeDaEntradaRodando = false;

  int get _k => transposition.semitones;
  int get _tomSoando => kCheckKeyMidi - _k;

  /// Passo 1 → 2: espera a tecla do Dó central, até o prazo.
  void ouvirTecla() {
    _pararEscuta();
    _ir(TransposeStep.listening);
    _sub = input.notes.listen((n) {
      if (n.on) _aoApertar(n.pitch);
    });
    _prazo = Timer(keyTimeout, () {
      _pararEscuta();
      _ir(TransposeStep.noKey);
    });
  }

  /// "Tentar de novo": volta ao passo 1.
  void tentarDeNovo() => _ir(TransposeStep.instruction);

  /// Passo do ouvido: "Ouvir de novo".
  Future<void> repetirEscuta() async {
    await playOwnSound?.call(_tomSoando);
  }

  /// Passo do ouvido, "Sim", ou o "Já ajustei" sem som: o teclado só muda o
  /// som, e o app segue.
  void soSomNoTeclado() {
    _atualizar(state.copyWith(out: false));
    _depoisDaSaida();
  }

  /// Passo do ouvido, "Não": o teclado não soou igual ao app.
  void ouvidoDiferente() => _ir(TransposeStep.earNo);

  /// Passo 4, "A 1ª" ou "A 2ª": qual das duas notas soou igual ao Dó.
  void respostaEntrada({required bool shiftsIn}) =>
      _atualizar(state.copyWith(inShifts: shiftsIn, step: TransposeStep.done));

  /// Passo 4: toca de novo as duas notas do teste da entrada.
  Future<void> repetirEntrada() async {
    final play = playOnKeyboard;
    if (play == null || _testeDaEntradaRodando) return;
    _testeDaEntradaRodando = true;
    _atualizar(state.copyWith(inputPlayed: 0));
    await play(kCheckKeyMidi);
    _atualizar(state.copyWith(inputPlayed: 1));
    await Future<void>.delayed(inputGap);
    if (isClosed) return;
    await play(_tomSoando);
    _atualizar(state.copyWith(inputPlayed: 2));
    _testeDaEntradaRodando = false;
  }

  /// O que se descobriu do teclado, sobre o que já se sabia.
  KeyboardTransposeBehavior resultado() => KeyboardTransposeBehavior(
    shiftsOut: state.out,
    shiftsIn: state.inShifts ?? previous.shiftsIn,
  );

  void _aoApertar(int pitch) {
    _pararEscuta();
    final leitura = classifyCheckKey(pitch, _k);
    switch (leitura.kind) {
      case CheckKeyKind.shiftsOut:
        _atualizar(state.copyWith(out: true));
        _depoisDaSaida();
      case CheckKeyKind.ambiguous:
        unawaited(_testeDeOuvido());
      case CheckKeyKind.offset:
        // Só quem transpõe a saída manda deslocado.
        _atualizar(
          state.copyWith(
            out: true,
            offset: leitura.offset,
            step: TransposeStep.offset,
          ),
        );
      case CheckKeyKind.wrongOctave:
        _ir(TransposeStep.wrongOctave);
    }
  }

  Future<void> _testeDeOuvido() async {
    final play = playOwnSound;
    final tocou = play == null ? false : await play(_tomSoando);
    _ir(tocou ? TransposeStep.ear : TransposeStep.earNoSound);
  }

  /// Passo 4: só se o app toca pelo teclado.
  void _depoisDaSaida() {
    if (playOnKeyboard != null) {
      _ir(TransposeStep.inputTest);
      unawaited(repetirEntrada());
    } else {
      _ir(TransposeStep.done);
    }
  }

  void _pararEscuta() {
    _prazo?.cancel();
    _prazo = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _ir(TransposeStep step) => _atualizar(state.copyWith(step: step));

  void _atualizar(TransposeCheckState next) {
    if (isClosed) return;
    emit(next);
  }

  @override
  Future<void> close() {
    _pararEscuta();
    return super.close();
  }
}

/// A caixa da conferência: o texto de cada passo e os botões. O estado é do
/// [TransposeCheckCubit], que a caixa cria e fecha.
class _TransposeCheckDialog extends StatelessWidget {
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
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => TransposeCheckCubit(
      transposition: transposition,
      input: input,
      previous: previous,
      playOwnSound: playOwnSound,
      playOnKeyboard: playOnKeyboard,
      keyTimeout: keyTimeout,
      inputGap: inputGap,
    ),
    child: BlocBuilder<TransposeCheckCubit, TransposeCheckState>(
      builder: (context, state) => _caixa(context, state),
    ),
  );

  Widget _caixa(BuildContext context, TransposeCheckState state) {
    final cubit = context.read<TransposeCheckCubit>();
    final t = transposition;
    final target = signedTranspose(t.keyboard);
    final (:body, :actions) = _passo(
      context,
      cubit,
      state,
      t,
      target,
      _nomeDaTecla,
    );
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
              if (state.step == TransposeStep.listening ||
                  state.step == TransposeStep.instruction) ...[
                const SizedBox(height: 12),
                _KeyboardHint(input: input, naming: naming),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            state.step == TransposeStep.done ? 'Descartar' : 'Cancelar',
          ),
        ),
        ...actions,
      ],
    );
  }

  String get _nomeDaTecla =>
      naming == NoteNaming.latin ? 'Dó central' : 'C central';

  /// O conteúdo de um passo: os textos e os botões.
  ({List<Widget> body, List<Widget> actions}) _passo(
    BuildContext context,
    TransposeCheckCubit cubit,
    TransposeCheckState state,
    Transposition t,
    String target,
    String key,
  ) => switch (state.step) {
    TransposeStep.instruction => _instrucao(cubit, t, target),
    TransposeStep.listening => _escutando(key),
    TransposeStep.noKey => _semTecla(cubit),
    TransposeStep.wrongOctave => _outraOitava(cubit, key),
    TransposeStep.offset => _deslocado(cubit, state, target),
    TransposeStep.ear => _ouvido(cubit),
    TransposeStep.earNoSound => _ouvidoSemSom(cubit, target),
    TransposeStep.earNo => _ouvidoNao(cubit, target),
    TransposeStep.inputTest => _testeDaEntrada(cubit, state),
    TransposeStep.done => _concluido(context, cubit, state),
  };

  /// O passo 1: ajustar o TRANSPOSE do teclado para a [target].
  ({List<Widget> body, List<Widget> actions}) _instrucao(
    TransposeCheckCubit cubit,
    Transposition t,
    String target,
  ) => (
    body: [
      _stepText('No seu teclado, ajuste o TRANSPOSE para $target.', bold: true),
      _stepText('Assim ${t.soundsLike(kCheckKeyMidi, naming: naming)}.'),
      _stepCaption(
        'Costuma ser um botão TRANSPOSE ou uma função no menu; veja o '
        'manual do seu teclado.',
      ),
    ],
    actions: [
      FilledButton(
        onPressed: cubit.ouvirTecla,
        child: const Text('Já ajustei'),
      ),
    ],
  );

  /// Toque a tecla [key] (o Dó) e espera.
  ({List<Widget> body, List<Widget> actions}) _escutando(String key) => (
    body: [
      _stepText('Toque o $key.', bold: true),
      _stepCaption('A tecla marcada, no meio do teclado.'),
    ],
    actions: const [],
  );

  /// Nenhuma tecla chegou: confira a conexão.
  ({List<Widget> body, List<Widget> actions}) _semTecla(
    TransposeCheckCubit cubit,
  ) => (
    body: [_stepText('Não chegou nada do teclado. Ele está conectado?')],
    actions: [_botaoTentarDeNovo(cubit)],
  );

  /// A tecla veio, mas numa outra oitava.
  ({List<Widget> body, List<Widget> actions}) _outraOitava(
    TransposeCheckCubit cubit,
    String key,
  ) => (
    body: [_stepText('Essa não é o $key. Toque o Dó do meio do teclado.')],
    actions: [
      FilledButton(
        onPressed: cubit.ouvirTecla,
        child: const Text('Tentar de novo'),
      ),
    ],
  );

  /// O teclado está deslocado de [target] por alguns semitons.
  ({List<Widget> body, List<Widget> actions}) _deslocado(
    TransposeCheckCubit cubit,
    TransposeCheckState state,
    String target,
  ) => (
    body: [
      _stepText(
        'Seu teclado parece estar em ${signedTranspose(state.offset)}. '
        'Ajuste para $target.',
      ),
    ],
    actions: [_botaoTentarDeNovo(cubit)],
  );

  /// O teste de ouvido: a nota do app soa igual à tecla Dó?
  ({List<Widget> body, List<Widget> actions}) _ouvido(
    TransposeCheckCubit cubit,
  ) => (
    body: [
      _stepText('O app tocou essa nota pelo som dele.'),
      _stepText('Soou igual à sua tecla Dó?', bold: true),
    ],
    actions: [
      TextButton(
        onPressed: cubit.repetirEscuta,
        child: const Text('Ouvir de novo'),
      ),
      TextButton(onPressed: cubit.ouvidoDiferente, child: const Text('Não')),
      FilledButton(onPressed: cubit.soSomNoTeclado, child: const Text('Sim')),
    ],
  );

  /// O app não tem som aqui: a pessoa diz se já ajustou o teclado.
  ({List<Widget> body, List<Widget> actions}) _ouvidoSemSom(
    TransposeCheckCubit cubit,
    String target,
  ) => (
    body: [
      _stepText(
        'Não deu para tocar aqui. Você ajustou o TRANSPOSE para $target?',
      ),
    ],
    actions: [
      FilledButton(
        onPressed: cubit.soSomNoTeclado,
        child: const Text('Já ajustei'),
      ),
    ],
  );

  /// No teste de ouvido, a nota não soou igual: confira o TRANSPOSE.
  ({List<Widget> body, List<Widget> actions}) _ouvidoNao(
    TransposeCheckCubit cubit,
    String target,
  ) => (
    body: [_stepText('Confira o TRANSPOSE: precisa ser $target.')],
    actions: [_botaoTentarDeNovo(cubit)],
  );

  /// O teste da entrada: duas notas, e a pessoa diz qual soou igual ao Dó.
  ({List<Widget> body, List<Widget> actions}) _testeDaEntrada(
    TransposeCheckCubit cubit,
    TransposeCheckState state,
  ) {
    final tocadas = state.inputPlayed;
    return (
      body: [
        _stepText(
          tocadas < 2
              ? 'Vão soar duas notas no teclado, uma de cada vez…'
              : 'Qual soou igual à sua tecla Dó: a 1ª ou a 2ª?',
          bold: tocadas >= 2,
        ),
      ],
      actions: [
        TextButton(
          onPressed: tocadas < 2 ? null : cubit.repetirEntrada,
          child: const Text('Ouvir de novo'),
        ),
        TextButton(
          onPressed: tocadas < 2
              ? null
              : () => cubit.respostaEntrada(shiftsIn: false),
          child: const Text('A 2ª'),
        ),
        FilledButton(
          onPressed: tocadas < 2
              ? null
              : () => cubit.respostaEntrada(shiftsIn: true),
          child: const Text('A 1ª'),
        ),
      ],
    );
  }

  /// O fim: o que o teclado faz, e concluir.
  ({List<Widget> body, List<Widget> actions}) _concluido(
    BuildContext context,
    TransposeCheckCubit cubit,
    TransposeCheckState state,
  ) => (
    body: [
      _stepText('Pronto.', bold: true),
      _stepText(
        state.out == true
            ? 'Este teclado manda a nota já transposta; o app cuida do '
                  'resto.'
            : 'Este teclado só muda o som; o app cuida do resto.',
      ),
    ],
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context, cubit.resultado()),
        child: const Text('Concluir'),
      ),
    ],
  );

  /// "Tentar de novo": volta ao passo 1.
  Widget _botaoTentarDeNovo(TransposeCheckCubit cubit) => TextButton(
    onPressed: cubit.tentarDeNovo,
    child: const Text('Tentar de novo'),
  );
}

/// Um parágrafo do passo (em negrito, se [bold]).
Widget _stepText(String s, {bool bold = false}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    s,
    style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null,
  ),
);

/// A legenda discreta de um passo.
Widget _stepCaption(String s) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(s, style: const TextStyle(fontSize: 13, color: kInkCaption)),
);

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
