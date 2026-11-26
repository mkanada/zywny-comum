# zywny_clock

O relógio do app: a hora do calendário, o tempo contínuo e os timers atrás de uma
interface só. Dart puro, sem Flutter. Não há relógio global: quem lê a hora ou
arma um timer recebe um `AppClock` pelo construtor (`required`).

- `AppClock`: `now()` (a data e a hora, para a meta, a constância, os minutos e o
  aviso), `seconds` (o tempo contínuo, para sessões, avisos e agendador),
  `timer(após, callback)` e `periodic(a_cada, callback)`.
- `clock.wait(d)` (extensão de `AppClock`): o `Future.delayed` do app, sobre o
  `timer`. Completa quando o relógio anda `d`.
- `AppTimer`: `cancel()`, `isActive` e `tick` (quantos disparos até agora).
- `SystemClock()`: o de verdade (`DateTime.now`, um `Stopwatch` e os `Timer` do Dart).
- `ManualClock(inicio)`: só anda com `advance(d)`, e os timers vencidos disparam
  na ordem do vencimento. Serve aos testes e ao roteiro de capturas.

Uso (`import 'package:zywny_clock/zywny_clock.dart';`):

```dart
class Aviso {
  Aviso({required this.clock});

  final AppClock clock;

  void armar(void Function() fechar) => clock.timer(const Duration(seconds: 2), fechar);
}

// No teste: o tempo só passa quando o teste manda.
final relogio = ManualClock(DateTime(2026));
final aviso = Aviso(clock: relogio)..armar(() => print('fechou'));
relogio.advance(const Duration(seconds: 2)); // dispara aqui
```

Regras: atraso negativo de `timer` vale zero; o intervalo de `periodic` tem de ser
positivo; `advance` não volta atrás e não pode ser chamado de dentro de um
disparo. Um erro num callback sai do `advance`, e o relógio fica no instante do
timer que falhou.

Os motores de som de verdade seguem no relógio do áudio (o `nowSeconds` do
`SoundEngine`). O `AppClock` é do que o app mede por conta própria: o agendador
arma o seu timer por ele, e o motor mudo (`SilentSoundEngine`) lê o tempo dele.

Testes: `dart test` neste pacote. A catraca do relógio (`zywny-comum/tool/catraca_relogio.sh`)
impede que volte a haver `DateTime.now()`, `Stopwatch()`, `Timer(` e `Future.delayed(`
fora deste pacote, salvo a linha marcada com `// relógio: <motivo>`.
