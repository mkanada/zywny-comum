// A volta na hora: o tempo do aviso "Errou"/"Acertou" nas configurações. Padrão
// 2 s, de 0 (sem aviso) a 6 s; a escolha volta ao recarregar e o que passa do
// limite é cortado.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/settings/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('padrão 2 s, e a escolha (inclusive 0) volta ao recarregar', () async {
    final prefs = SharedPreferencesAsync();
    final settings = AppSettings(prefs: prefs);
    expect(settings.repeatNoticeSeconds, 2);

    settings.repeatNoticeSeconds = 0;
    await Future<void>.delayed(Duration.zero);
    final again = AppSettings(prefs: prefs);
    await again.load();
    expect(again.repeatNoticeSeconds, 0);
    expect(again.diagSnapshot()['avisoDaVoltaS'], 0);
  });

  test('o valor é cortado entre 0 e 6 s', () {
    final settings = AppSettings(prefs: SharedPreferencesAsync());
    settings.repeatNoticeSeconds = 99;
    expect(settings.repeatNoticeSeconds, kMaxRepeatNoticeSeconds);
    settings.repeatNoticeSeconds = -3;
    expect(settings.repeatNoticeSeconds, kMinRepeatNoticeSeconds);
  });
}
