// O canto de gravação do microfone (modo depuração) como Cubit. Segurar o
// canto liga e desliga a gravação; o aviso e o tempo aparecem no canto. O
// toque também é daqui: o segurar é um Timer, e ele para no close().

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_clock/zywny_clock.dart';
import 'package:zywny_diag/diag_log.dart';

import 'audio_recording_service.dart';

/// Quanto tempo segurar o canto para ligar/desligar a gravação.
const Duration kAudioRecordingHold = Duration(seconds: 1);

/// O que o canto mostra: se está gravando, o aviso e o tempo da gravação.
class AudioRecordingState extends Equatable {
  const AudioRecordingState({
    this.gravando = false,
    this.aviso,
    this.decorrido = Duration.zero,
    this.paradas = 0,
  });

  /// Gravando agora: o ponto vermelho e o tempo aparecem.
  final bool gravando;

  /// A última nota no canto ("Gravação salva: …"), até sumir sozinha.
  final String? aviso;

  /// Há quanto tempo a gravação está ligada (atualizado a cada segundo).
  final Duration decorrido;

  /// Quantas gravações já foram paradas. A tela abre o relatório de bug quando
  /// este número sobe (um BlocListener: efeito de tela, fora do builder).
  final int paradas;

  AudioRecordingState copyWith({
    bool? gravando,
    String? aviso,
    bool limparAviso = false,
    Duration? decorrido,
    int? paradas,
  }) => AudioRecordingState(
    gravando: gravando ?? this.gravando,
    aviso: limparAviso ? null : (aviso ?? this.aviso),
    decorrido: decorrido ?? this.decorrido,
    paradas: paradas ?? this.paradas,
  );

  @override
  List<Object?> get props => [gravando, aviso, decorrido, paradas];
}

/// Liga e para a gravação e guarda o toque no canto. Abre uma sessão de
/// depuração (`gravacao`) ao ligar e a fecha ao parar, para o log.
class AudioRecordingCubit extends Cubit<AudioRecordingState> {
  AudioRecordingCubit({AudioRecordingService? service, required this.clock})
    : _servicoDado = service,
      super(const AudioRecordingState());

  /// Os testes passam um falso; sem ele, cria o da plataforma ao primeiro uso.
  final AudioRecordingService? _servicoDado;

  /// O relógio do app (CT05c): o segurar, o tempo gravado e o aviso são dele.
  final AppClock clock;
  AudioRecordingService? _servico;
  DiagSession? _sessao;
  AppTimer? _segurar;
  AppTimer? _tique;
  AppTimer? _tempoDoAviso;
  bool _ocupado = false;
  int? _ponteiro;
  Offset _origem = Offset.zero;

  AudioRecordingService get _svc =>
      _servico ??= _servicoDado ?? createAudioRecordingService();

  /// Um dedo encostou no canto: começa a contar o segurar.
  void pontoBaixo(int ponteiro, Offset posicao) {
    if (_ponteiro != null) return;
    _ponteiro = ponteiro;
    _origem = posicao;
    _segurar?.cancel();
    _segurar = clock.timer(kAudioRecordingHold, () => unawaited(alternar()));
  }

  /// O dedo andou mais de 24 px: era arrasto, não segurar.
  void pontoMovido(int ponteiro, Offset posicao) {
    if (ponteiro == _ponteiro && (posicao - _origem).distance > 24) {
      _soltar();
    }
  }

  /// O dedo saiu do canto antes do tempo: não liga nem desliga nada.
  void pontoSolto(int ponteiro) {
    if (ponteiro == _ponteiro) _soltar();
  }

  void _soltar() {
    _ponteiro = null;
    _segurar?.cancel();
    _segurar = null;
  }

  /// Liga a gravação, ou para e guarda o arquivo. Chamado pelo segurar do
  /// canto; sem mudança enquanto a chamada anterior ainda não terminou.
  Future<void> alternar() async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      unawaited(HapticFeedback.heavyImpact());
      if (state.gravando) {
        final resultado = await _svc.stop();
        _tique?.cancel();
        _tique = null;
        DiagLog.endSession(_sessao);
        _sessao = null;
        if (isClosed) return;
        emit(state.copyWith(gravando: false, paradas: state.paradas + 1));
        _avisar(
          resultado?.savedAt == null
              ? 'Gravação não salva'
              : 'Gravação salva: ${resultado!.savedAt}',
          const Duration(seconds: 6),
        );
      } else {
        // A sessão abre antes do microfone: o que o próprio início registrar
        // (permissão, arquivo) também fica nela.
        _sessao = DiagLog.beginSession('gravacao', 'microfone');
        final ok = await _svc.start();
        if (isClosed) return;
        if (!ok) {
          DiagLog.endSession(_sessao);
          _sessao = null;
          _avisar(
            'Não deu para gravar (microfone ou permissão)',
            const Duration(seconds: 4),
          );
          return;
        }
        final inicio = clock.now();
        _tique = clock.periodic(const Duration(seconds: 1), (_) {
          if (isClosed) return;
          emit(state.copyWith(decorrido: clock.now().difference(inicio)));
        });
        emit(state.copyWith(gravando: true, limparAviso: true));
      }
    } finally {
      _ocupado = false;
    }
  }

  void _avisar(String texto, Duration tempo) {
    _tempoDoAviso?.cancel();
    emit(state.copyWith(aviso: texto));
    _tempoDoAviso = clock.timer(tempo, () {
      if (isClosed) return;
      emit(state.copyWith(limparAviso: true));
    });
  }

  @override
  Future<void> close() {
    _segurar?.cancel();
    _tique?.cancel();
    _tempoDoAviso?.cancel();
    DiagLog.endSession(_sessao);
    _sessao = null;
    final servico = _servico;
    if (servico != null) unawaited(servico.dispose());
    return super.close();
  }
}
