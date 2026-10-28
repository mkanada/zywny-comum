// EX03 (D-EXE-CIFRA) — a grafia da cifra nas configurações: padrão brasileira,
// a escolha volta depois de recarregar, e um valor estragado vale o padrão.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/settings/app_settings.dart';
import 'package:zywny_music/chord.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('cifra: padrão brasileira, e a escolha volta ao recarregar', () async {
    final prefs = SharedPreferencesAsync();
    final settings = AppSettings(prefs: prefs);
    expect(settings.chordNotation, ChordNotation.brazilian);

    settings.chordNotation = ChordNotation.american;
    await Future<void>.delayed(Duration.zero);

    final again = AppSettings(prefs: prefs);
    await again.load();
    expect(again.chordNotation, ChordNotation.american);
    expect(again.diagSnapshot()['cifra'], 'american');
  });

  test('cifra estragada vale o padrão', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('ui_chord_notation', 'alema');
    final settings = AppSettings(prefs: prefs);
    await settings.load();
    expect(settings.chordNotation, ChordNotation.brazilian);
  });
}
