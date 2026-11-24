import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/audio_recording_cubit.dart';
import 'package:zywny_comum/diag/audio_recording_service.dart';
import 'package:zywny_diag/diag_log.dart';

class _Fake implements AudioRecordingService {
  _Fake({this.podeComecar = true});

  final bool podeComecar;

  @override
  Future<bool> start() async => podeComecar;

  @override
  Future<AudioRecordingResult?> stop() async =>
      const AudioRecordingResult(savedAt: 'Download/Zywny/a.m4a');

  @override
  Future<void> dispose() async {}
}

void main() {
  // O Cubit pede a vibração ao canal da plataforma; o binding de teste basta.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await DiagLog.init(storage: MemoryDiagStorage(), installHandlers: false);
  });
  tearDown(DiagLog.reset);

  group('AudioRecordingState', () {
    test('começa parado, sem aviso, sem tempo e sem paradas', () {
      const estado = AudioRecordingState();

      expect(estado.gravando, isFalse);
      expect(estado.aviso, isNull);
      expect(estado.decorrido, Duration.zero);
      expect(estado.paradas, 0);
    });

    test('é igual pelo valor (Equatable)', () {
      expect(
        const AudioRecordingState(gravando: true),
        const AudioRecordingState(gravando: true),
      );
      expect(
        const AudioRecordingState(gravando: true),
        isNot(const AudioRecordingState()),
      );
    });
  });

  group('AudioRecordingCubit', () {
    blocTest<AudioRecordingCubit, AudioRecordingState>(
      'alternar liga a gravação',
      build: () => AudioRecordingCubit(service: _Fake()),
      act: (cubit) => cubit.alternar(),
      expect: () => [const AudioRecordingState(gravando: true)],
    );

    blocTest<AudioRecordingCubit, AudioRecordingState>(
      'alternar de novo para e guarda o arquivo: conta uma parada e avisa',
      build: () => AudioRecordingCubit(service: _Fake()),
      act: (cubit) async {
        await cubit.alternar();
        await cubit.alternar();
      },
      expect: () => [
        const AudioRecordingState(gravando: true),
        const AudioRecordingState(paradas: 1),
        const AudioRecordingState(
          paradas: 1,
          aviso: 'Gravação salva: Download/Zywny/a.m4a',
        ),
      ],
    );

    blocTest<AudioRecordingCubit, AudioRecordingState>(
      'sem microfone avisa e não conta parada',
      build: () => AudioRecordingCubit(service: _Fake(podeComecar: false)),
      act: (cubit) => cubit.alternar(),
      expect: () => [
        const AudioRecordingState(
          aviso: 'Não deu para gravar (microfone ou permissão)',
        ),
      ],
    );

    test('a gravação abre uma sessão de depuração e close a fecha', () async {
      final cubit = AudioRecordingCubit(service: _Fake());

      await cubit.alternar();
      expect(
        DiagLog.collect()
            .singleWhere((f) => f.text.contains('#sessao tipo=gravacao'))
            .text,
        isNot(contains('fim: gravacao microfone')),
      );

      await cubit.close();
      expect(
        DiagLog.collect()
            .singleWhere((f) => f.text.contains('#sessao tipo=gravacao'))
            .text,
        contains('fim: gravacao microfone'),
      );
    });
  });
}
