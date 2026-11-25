/// O relógio do zywny (CT05a): a hora do calendário, o tempo contínuo e os timers
/// atrás de uma interface só. O de verdade é o [SystemClock]; o de teste e de
/// roteiro, o [ManualClock], que só anda quando mandam. Dart puro, sem Flutter.
library;

export 'src/app_clock.dart';
export 'src/manual_clock.dart';
export 'src/system_clock.dart';
