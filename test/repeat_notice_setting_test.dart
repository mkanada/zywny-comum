// A volta na hora: o tempo do aviso "Errou"/"Acertou" nas configurações. Padrão
// 2 s, de 0 (sem aviso) a 6 s; a escolha volta ao recarregar e o que passa do
// limite é cortado.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/settings/settings_cubit.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('padrão 2 s, e a escolha (inclusive 0) volta ao recarregar', () async {
    final prefs = SharedPreferencesAsync();
    final settings = SettingsCubit(prefs: prefs);
    expect(settings.state.repeatNoticeSeconds, 2);

    settings.setRepeatNoticeSeconds(0);
    await Future<void>.delayed(Duration.zero);
    final again = SettingsCubit(prefs: prefs);
    await again.load();
    expect(again.state.repeatNoticeSeconds, 0);
    expect(again.state.diagSnapshot()['avisoDaVoltaS'], 0);
  });

  test('o valor é cortado entre 0 e 6 s', () {
    final settings = SettingsCubit(prefs: SharedPreferencesAsync());
    settings.setRepeatNoticeSeconds(99);
    expect(settings.state.repeatNoticeSeconds, kMaxRepeatNoticeSeconds);
    settings.setRepeatNoticeSeconds(-3);
    expect(settings.state.repeatNoticeSeconds, kMinRepeatNoticeSeconds);
  });
}
