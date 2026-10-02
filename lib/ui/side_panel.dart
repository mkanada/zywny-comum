import 'package:flutter/material.dart';

import 'theme.dart';

/// Largura do painel lateral da partitura no celular.
const double kPhoneSidePanelWidth = 400;

/// A casca comum de tudo o que, na tela da partitura do celular, ajusta ou
/// mostra algo da partitura (U18, E2): um painel que entra pela direita, com
/// título e botão de fechar, e deixa a pauta à vista do lado esquerdo.
///
/// [scrim] escurece o resto da tela e fecha ao toque (as gavetas de opções e
/// da trilha). Sem ele (os resumos e os seletores de compasso) a pauta fica
/// como está — é onde as marcas de erro aparecem. [child] ocupa o espaço
/// abaixo do cabeçalho (quem precisa rolar traz a própria rolagem).
class PhoneSidePanel extends StatelessWidget {
  const PhoneSidePanel({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.scrim = true,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        if (scrim)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: const ColoredBox(color: kScrim),
            ),
          ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: width * 0.6 < kPhoneSidePanelWidth
              ? width * 0.6
              : kPhoneSidePanelWidth,
          child: Material(
            color: kSurface,
            elevation: 8,
            child: SafeArea(
              left: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: kInk,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: onClose,
                          iconSize: 20,
                          color: kIconQuiet,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Um painel lateral como rota modal: devolve o que o corpo [builder] der em
/// `Navigator.pop`, ou `null` ao fechar. O toque fora do painel (na pauta) e
/// o "voltar" do Android fecham. Sem escurecer a partitura.
Future<T?> showPhoneSidePanel<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => PhoneSidePanel(
      title: title,
      scrim: false,
      onClose: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(child: builder(context)),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Mostra [builder] como painel lateral no celular ([sidePanel]) ou como
/// folha inferior (layout largo e biblioteca), como sempre foi.
Future<T?> showSheetOrSidePanel<T>(
  BuildContext context, {
  required bool sidePanel,
  required String title,
  required WidgetBuilder builder,
}) {
  if (sidePanel) {
    return showPhoneSidePanel<T>(context, title: title, builder: builder);
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: builder,
  );
}

/// O corpo de uma folha inferior ou de um painel lateral. No painel a casca
/// já dá a margem e a rolagem ([showPhoneSidePanel]); na folha o corpo traz a
/// própria margem, a área segura e a rolagem.
Widget sheetBody({required bool sidePanel, required Widget child}) => sidePanel
    ? child
    : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: child,
        ),
      );
