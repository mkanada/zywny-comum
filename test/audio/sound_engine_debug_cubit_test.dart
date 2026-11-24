import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/native_sound_engine.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_comum/audio/sound_engine_debug_cubit.dart';

/// O motor nativo sem a biblioteca: `implements` não chama o construtor (que
/// abre o `.so`). Só o que o Cubit usa é implementado; o resto cai no
/// `noSuchMethod`.
class _MotorFalso implements NativeSoundEngine {
  _MotorFalso({this.falhaCarga = false});

  final bool falhaCarga;
  int inicios = 0;
  int descartes = 0;
  int? bytesCarregados;
  final List<ScheduledMidi> agendados = [];

  @override
  Future<void> start() async {
    inicios++;
  }

  @override
  Future<void> loadSoundFont(Uint8List bytes) async {
    if (falhaCarga) throw StateError('sf2 ruim');
    bytesCarregados = bytes.length;
  }

  @override
  double get earliestScheduleSeconds => 1;

  @override
  void schedule(List<ScheduledMidi> events) => agendados.addAll(events);

  @override
  Future<void> dispose() async {
    descartes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Um arquivo em memória; no IO o nome sai do caminho (o `name:` é ignorado).
XFile _sf2(String nome) =>
    XFile.fromData(Uint8List.fromList([1, 2, 3]), path: '/sf2/$nome');

void main() {
  group('SoundEngineDebugState', () {
    test('o estado inicial: motor não iniciado, sem toque, serial zero', () {
      const estado = SoundEngineDebugState();
      expect(estado.status, 'motor não iniciado');
      expect(estado.busy, isFalse);
      expect(estado.serial, 0);
    });

    test('é igual pelo valor, e o serial diferente já é outro estado', () {
      expect(
        const SoundEngineDebugState(serial: 1),
        isNot(equals(const SoundEngineDebugState())),
      );
      expect(
        const SoundEngineDebugState(busy: true).copyWith(busy: false),
        const SoundEngineDebugState(),
      );
    });
  });

  group('SoundEngineDebugCubit', () {
    late _MotorFalso motor;

    setUp(() => motor = _MotorFalso());

    blocTest<SoundEngineDebugCubit, SoundEngineDebugState>(
      'cancelar o arquivo: o motor abre e a tela diz que nada foi escolhido',
      build: () => SoundEngineDebugCubit(
        criarMotor: () => motor,
        escolherSoundfont: () async => null,
      ),
      act: (cubit) => cubit.tocarEscalaDeTeste(),
      expect: () => [
        const SoundEngineDebugState(
          status: 'abrindo motor de áudio…',
          busy: true,
        ),
        const SoundEngineDebugState(
          status: 'cancelado (nenhum .sf2 escolhido)',
        ),
      ],
      verify: (_) => expect(motor.inicios, 1),
    );

    blocTest<SoundEngineDebugCubit, SoundEngineDebugState>(
      'escolher um .sf2: carrega e agenda a escala de oito notas',
      build: () => SoundEngineDebugCubit(
        criarMotor: () => motor,
        escolherSoundfont: () async => _sf2('piano.sf2'),
      ),
      act: (cubit) => cubit.tocarEscalaDeTeste(),
      expect: () => [
        const SoundEngineDebugState(
          status: 'abrindo motor de áudio…',
          busy: true,
        ),
        const SoundEngineDebugState(
          status: 'carregando piano.sf2…',
          busy: true,
        ),
        const SoundEngineDebugState(status: 'tocando a escala de teste…'),
      ],
      verify: (_) {
        expect(motor.bytesCarregados, 3);
        expect(
          motor.agendados,
          hasLength(16),
          reason: '8 notas, ligar e desligar',
        );
        expect(motor.agendados.first.at, closeTo(1.2, 1e-9));
      },
    );

    blocTest<SoundEngineDebugCubit, SoundEngineDebugState>(
      'o .sf2 não carrega: a tela mostra o erro e o botão volta',
      build: () => SoundEngineDebugCubit(
        criarMotor: () => _MotorFalso(falhaCarga: true),
        escolherSoundfont: () async => _sf2('ruim.sf2'),
      ),
      act: (cubit) => cubit.tocarEscalaDeTeste(),
      expect: () => [
        const SoundEngineDebugState(
          status: 'abrindo motor de áudio…',
          busy: true,
        ),
        const SoundEngineDebugState(status: 'carregando ruim.sf2…', busy: true),
        const SoundEngineDebugState(status: 'erro: Bad state: sf2 ruim'),
      ],
    );

    test('um segundo toque enquanto o primeiro está ocupado não faz nada', () async {
      final escolha = Completer<XFile?>();
      var escolhas = 0;
      final cubit = SoundEngineDebugCubit(
        criarMotor: () => motor,
        escolherSoundfont: () {
          escolhas++;
          return escolha.future;
        },
      );
      addTearDown(cubit.close);

      final primeiro = cubit.tocarEscalaDeTeste();
      await pumpEventQueue(); // o motor abre, e o primeiro toque pede o arquivo
      await cubit.tocarEscalaDeTeste();
      expect(escolhas, 1);

      escolha.complete(null);
      await primeiro;
    });

    test('o motor abre uma vez só, e o fechar o descarta', () async {
      final cubit = SoundEngineDebugCubit(
        criarMotor: () => motor,
        escolherSoundfont: () async => null,
      );

      await cubit.tocarEscalaDeTeste();
      await cubit.tocarEscalaDeTeste();
      expect(motor.inicios, 1);
      expect(cubit.motor, same(motor));

      await cubit.close();
      await pumpEventQueue();
      expect(motor.descartes, 1);
    });

    test('fechar enquanto o arquivo não chega: o motor aberto é descartado e nada é agendado', () async {
      final escolha = Completer<XFile?>();
      final cubit = SoundEngineDebugCubit(
        criarMotor: () => motor,
        escolherSoundfont: () => escolha.future,
      );

      final toque = cubit.tocarEscalaDeTeste();
      await pumpEventQueue(); // o motor abriu e o arquivo está sendo pedido
      await cubit.close();
      escolha.complete(_sf2('tarde.sf2'));

      await expectLater(toque, completes);
      expect(cubit.isClosed, isTrue);
      expect(cubit.state.busy, isTrue, reason: 'parou onde estava');
      expect(motor.descartes, 1);
      expect(motor.agendados, isEmpty);
    });

    test('fechar enquanto o motor abre: o motor que chega depois é descartado e o arquivo não é pedido', () async {
      var pediu = 0;
      final cubit = SoundEngineDebugCubit(
        criarMotor: () => motor,
        escolherSoundfont: () {
          pediu++;
          return Future.value(null);
        },
      );

      final toque = cubit.tocarEscalaDeTeste();
      await cubit.close(); // antes de o start terminar
      await expectLater(toque, completes);

      expect(pediu, 0);
      expect(motor.inicios, 1);
      await pumpEventQueue();
      expect(motor.descartes, 1, reason: 'o motor não fica vivo sem dono');
      expect(cubit.motor, isNull);
    });

    test('o tique das estatísticas sobe o serial a cada 500 ms', () async {
      final cubit = SoundEngineDebugCubit(
        criarMotor: () => motor,
        escolherSoundfont: () async => null,
      );

      await cubit.tocarEscalaDeTeste();
      final antes = cubit.state.serial;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(cubit.state.serial, greaterThanOrEqualTo(antes + 2));

      await cubit.close();
    });
  });
}
