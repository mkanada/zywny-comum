// A cor da parte do aluno (leitura pela música) nas configurações, "Notas do
// aluno": o padrão é o teal da paleta, a escolha volta ao recarregar e aparece
// no relatório de bug.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/practice/practice_colors.dart';
import 'package:zywny_comum/settings/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('padrão é o teal da paleta, e a escolha volta ao recarregar', () async {
    final prefs = SharedPreferencesAsync();
    final settings = AppSettings(prefs: prefs);
    expect(settings.studentPartColor, kPracticeStudentColor);

    const purple = Color(0xFF6A1B9A);
    settings.studentPartColor = purple;
    await Future<void>.delayed(Duration.zero);
    final again = AppSettings(prefs: prefs);
    await again.load();
    expect(again.studentPartColor, purple);
    expect(again.diagSnapshot()['corAluno'], '#ff6a1b9a');
  });
}
