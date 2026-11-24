# zywny_bloc

O BLoC do zywny: o pacote que os repositórios e os pacotes do comum importam
para usar Cubit e Bloc. Ele reexporta `flutter_bloc` (e, com ele, `bloc`) e
`equatable`, e traz um adaptador próprio.

- `BlocRepaint`: transforma o estado de um Cubit num `Listenable`, só para
  `CustomPainter(repaint:)`. O pintor não guarda estado: ele lê `cubit.state` ao
  pintar, e o adaptador só avisa quando repintar. Assina o `stream` com o primeiro
  ouvinte e cancela com o último (o `RenderCustomPaint` tira o ouvinte quando o
  pintor sai da árvore).

Uso (`import 'package:zywny_bloc/zywny_bloc.dart';`):

```dart
class MeuPintor extends CustomPainter {
  MeuPintor(this.cubit) : super(repaint: BlocRepaint(cubit));

  final MeuCubit cubit;

  @override
  void paint(Canvas canvas, Size size) {
    final estado = cubit.state; // o pintor lê o estado ao pintar
  }

  @override
  bool shouldRepaint(MeuPintor old) => false;
}
```

Testes: `flutter test` neste pacote.
