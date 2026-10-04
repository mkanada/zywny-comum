import 'package:flutter/widgets.dart';

/// Na Web não há o motor nativo que o painel de debug exercita.
class SoundEngineDebugPanel extends StatelessWidget {
  const SoundEngineDebugPanel({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
