import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'native_sound_engine.dart';
import 'sound_engine.dart';

/// Painel de depuração do motor de áudio (K02/K03), só com `--debug`: um
/// botão que carrega um `.sf2` (D-SF ainda aberta — sem asset embutido
/// ainda) e toca uma escala de teste, e o sample rate/latência/estatísticas
/// do motor nativo. Fora de escopo em K03: tocar a partitura de verdade
/// (isso é K04).
class SoundEngineDebugPanel extends StatefulWidget {
  const SoundEngineDebugPanel({super.key});

  @override
  State<SoundEngineDebugPanel> createState() => _SoundEngineDebugPanelState();
}

/// Dó maior, C4-C5, a 120 bpm — a mesma escala de teste de K01/K02.
const List<int> _kScaleKeys = [60, 62, 64, 65, 67, 69, 71, 72];
const double _kBeatSeconds = 0.5;

class _SoundEngineDebugPanelState extends State<SoundEngineDebugPanel> {
  NativeSoundEngine? _engine;
  String _status = 'motor não iniciado';
  bool _busy = false;
  Timer? _statsTimer;

  @override
  void dispose() {
    _statsTimer?.cancel();
    unawaited(_engine?.dispose());
    super.dispose();
  }

  Future<NativeSoundEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final engine = NativeSoundEngine();
    await engine.start();
    _engine = engine;
    _statsTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => mounted ? setState(() {}) : null,
    );
    return engine;
  }

  Future<void> _carregarSoundfontETocarEscala() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'abrindo motor de áudio…';
    });
    try {
      final engine = await _ensureEngine();
      const typeGroup = XTypeGroup(label: 'soundfont', extensions: ['sf2']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) {
        setState(() {
          _busy = false;
          _status = 'cancelado (nenhum .sf2 escolhido)';
        });
        return;
      }
      setState(() => _status = 'carregando ${file.name}…');
      await engine.loadSoundFont(await file.readAsBytes());
      _agendarEscala(engine);
      setState(() {
        _busy = false;
        _status = 'tocando a escala de teste…';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'erro: $e';
      });
    }
  }

  void _agendarEscala(SoundEngine engine) {
    final start = engine.earliestScheduleSeconds + 0.2;
    final events = <ScheduledMidi>[];
    for (var i = 0; i < _kScaleKeys.length; i++) {
      final key = _kScaleKeys[i];
      final on = start + i * _kBeatSeconds;
      final off = on + _kBeatSeconds * 0.9;
      events.add(ScheduledMidi(on, 0x90, key, 100));
      events.add(ScheduledMidi(off, 0x80, key, 0));
    }
    engine.schedule(events);
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final stats = engine == null
        ? null
        : 'sample rate: ${engine.sampleRate} Hz  •  '
              'latência: ${(engine.outputLatencySeconds * 1000).round()} ms  •  '
              'underruns: ${engine.stat(zyStatUnderruns)}  •  '
              'descartados: ${engine.stat(zyStatDroppedEvents)}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _carregarSoundfontETocarEscala,
              icon: const Icon(Icons.graphic_eq),
              label: const Text('Tocar escala de teste (.sf2)'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (stats != null)
                    Text(
                      stats,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
