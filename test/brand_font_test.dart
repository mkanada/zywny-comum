import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/ui/brand.dart';

void main() {
  // As fontes da marca são declaradas no pubspec deste pacote. Quem as usa de
  // outro app precisa do prefixo `packages/zywny_comum/`, que só o `package:`
  // do TextStyle põe; sem ele, o Flutter usa a fonte padrão sem avisar.
  testWidgets('o monograma usa a fonte da marca do zywny_comum', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MonogramZ(size: 40))),
    );

    final text = tester.widget<Text>(find.text('Z'));
    expect(text.style?.fontFamily, 'packages/zywny_comum/Cormorant Garamond');
  });
}
