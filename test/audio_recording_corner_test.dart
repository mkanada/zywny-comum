import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/audio_recording_corner.dart';
import 'package:zywny_comum/diag/audio_recording_service.dart';

class _Fake implements AudioRecordingService {
  _Fake({this.canStart = true});
  final bool canStart;
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> start() async {
    starts++;
    return canStart;
  }

  @override
  Future<AudioRecordingResult?> stop() async {
    stops++;
    return const AudioRecordingResult(savedAt: 'Download/Zywny/a.m4a');
  }

  @override
  Future<void> dispose() async {}
}

Widget _app(_Fake fake, {VoidCallback? onTap}) => MaterialApp(
  home: Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
      ),
      Positioned.fill(child: AudioRecordingCorner(service: fake)),
    ],
  ),
);

void main() {
  testWidgets('segurar o canto liga e desliga a gravação', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_app(fake));
    final corner =
        tester.getBottomLeft(find.byType(MaterialApp)) + const Offset(20, -20);

    var g = await tester.startGesture(corner);
    await tester.pump(kAudioRecordingHold + const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();
    expect(fake.starts, 1);
    expect(find.textContaining('Gravando'), findsOneWidget);

    g = await tester.startGesture(corner);
    await tester.pump(kAudioRecordingHold + const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();
    expect(fake.stops, 1);
    expect(find.textContaining('Gravação salva'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('toque curto, ou fora do canto, não grava', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_app(fake));
    final corner =
        tester.getBottomLeft(find.byType(MaterialApp)) + const Offset(20, -20);

    var g = await tester.startGesture(corner);
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pump(kAudioRecordingHold);

    g = await tester.startGesture(const Offset(400, 100));
    await tester.pump(kAudioRecordingHold + const Duration(milliseconds: 50));
    await g.up();
    expect(fake.starts, 0);
  });

  testWidgets('o canto não toma o toque da tela de baixo', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(_Fake(), onTap: () => taps++));
    await tester.tapAt(
      tester.getBottomLeft(find.byType(MaterialApp)) + const Offset(20, -20),
    );
    expect(taps, 1);
  });

  testWidgets('sem microfone avisa e não fica gravando', (tester) async {
    final fake = _Fake(canStart: false);
    await tester.pumpWidget(_app(fake));
    final g = await tester.startGesture(
      tester.getBottomLeft(find.byType(MaterialApp)) + const Offset(20, -20),
    );
    await tester.pump(kAudioRecordingHold + const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();
    expect(find.textContaining('Não deu para gravar'), findsOneWidget);
    expect(find.textContaining('Gravando'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
