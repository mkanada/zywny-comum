import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diag_log.dart';

/// Lista dispositivos MIDI, conecta, guarda o último escolhido e conecta
/// sozinho — na abertura do app e a cada hot-plug (M01, critério de aceite
/// 1): plugou o fio, o teclado entra, sem passar pela configuração. Não decodifica mensagens: isso é `MidiInputService`.
class MidiDeviceManager {
  MidiDeviceManager({MidiCommand? midi, SharedPreferencesAsync? prefs})
    : _midi = midi ?? MidiCommand(),
      _prefs = prefs ?? SharedPreferencesAsync() {
    _setupSub = _midi.onMidiSetupChanged?.listen((c) {
      DiagLog.log('midi-dev', 'setup mudou: $c');
      refresh();
    });
    unawaited(refresh());
  }

  static const _kLastDeviceIdKey = 'midi_last_device_id';
  static const _kLastDeviceNameKey = 'midi_last_device_name';

  final MidiCommand _midi;
  final SharedPreferencesAsync _prefs;
  StreamSubscription<MidiSetupChange>? _setupSub;

  final ValueNotifier<List<MidiDevice>> devices = ValueNotifier(const []);
  final ValueNotifier<MidiDevice?> connected = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Relista os dispositivos e, se nada estiver conectado, conecta sozinho
  /// (ver [_autoConnectCandidate]). Chamado na abertura do serviço e a cada
  /// `onMidiSetupChanged` (plugue/desplugue). Chamadas sobrepostas (o plugue
  /// costuma disparar mais de um evento) viram uma rodada só, em fila.
  Future<void> refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await _refreshOnce();
      } while (_refreshAgain && !_disposed);
    } finally {
      _refreshing = false;
    }
  }

  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _disposed = false;

  /// Nome do dispositivo que o usuário desconectou à mão: não é reconectado
  /// sozinho enquanto continuar plugado (senão o "desconectar" não durava).
  String? _pausedName;

  Future<void> _refreshOnce() async {
    final list = await _midi.devices ?? const <MidiDevice>[];
    if (_disposed) return;
    devices.value = list;
    DiagLog.log(
      'midi-dev',
      'dispositivos (${list.length}): ${[for (final d in list) '${d.name} id=${d.id} tipo=${d.type} conectado=${d.connected} '
            'in=${d.inputPorts.length} out=${d.outputPorts.length}'].join(' | ')}',
    );

    final current = connected.value;
    if (current != null && !list.any((d) => d.id == current.id)) {
      connected.value = null;
    }
    if (_pausedName != null && !list.any((d) => d.name == _pausedName)) {
      _pausedName = null;
    }

    if (connected.value != null) return;
    final match = await _autoConnectCandidate(list);
    if (_disposed || match == null) return;
    await connect(match);
  }

  /// O dispositivo a conectar sozinho, nesta ordem: o último escolhido pelo
  /// id; o último escolhido pelo **nome** (no Android o id de um teclado USB
  /// é o número da conexão e muda a cada plugue — só pelo id, o teclado
  /// nunca voltava sozinho); e, sem nenhum dos dois, o único teclado com fio
  /// presente. `null` se não há o que conectar.
  Future<MidiDevice?> _autoConnectCandidate(List<MidiDevice> list) async {
    final candidates = [
      for (final d in list)
        if (!d.connected && d.name != _pausedName) d,
    ];
    if (candidates.isEmpty) return null;
    final lastId = await _prefs.getString(_kLastDeviceIdKey);
    final lastName = await _prefs.getString(_kLastDeviceNameKey);
    for (final d in candidates) {
      if (d.id == lastId) return d;
    }
    for (final d in candidates) {
      if (lastName != null && d.name == lastName) return d;
    }
    final wired = [
      for (final d in candidates)
        if (d.type == MidiDeviceType.serial) d,
    ];
    return wired.length == 1 ? wired.single : null;
  }

  Future<void> connect(MidiDevice device) async {
    DiagLog.log('midi-dev', 'conectando a ${device.name} (${device.id})');
    try {
      await _midi.connectToDevice(device);
      if (_disposed) return;
      DiagLog.log('midi-dev', 'conectado a ${device.name}');
      _pausedName = null;
      connected.value = device;
      lastError.value = null;
      await _prefs.setString(_kLastDeviceIdKey, device.id);
      await _prefs.setString(_kLastDeviceNameKey, device.name);
    } on MidiConnectionException catch (e) {
      DiagLog.log('midi-dev', 'falha ao conectar: $e');
      lastError.value = e.toString();
    }
  }

  void disconnect() {
    final device = connected.value;
    if (device == null) return;
    DiagLog.log('midi-dev', 'desconectando ${device.name}');
    _midi.disconnectDevice(device);
    _pausedName = device.name;
    connected.value = null;
  }

  /// Chave das preferências por dispositivo: o **nome**, porque o id não
  /// sobrevive a um replugue no Android (ver [_autoConnectCandidate]). Sem
  /// o dispositivo na lista, o próprio id.
  String _deviceKey(String deviceId) {
    final current = connected.value;
    if (current != null && current.id == deviceId) return current.name;
    for (final d in devices.value) {
      if (d.id == deviceId) return d.name;
    }
    return deviceId;
  }

  /// Preferência do monitor MIDI (M02), por dispositivo — desligada por
  /// padrão (som em dobro se o teclado já tiver som próprio).
  Future<bool> monitorEnabled(String deviceId) async =>
      await _prefs.getBool('midi_monitor_${_deviceKey(deviceId)}') ??
      // Gravado pelo id, antes de a chave ser o nome.
      await _prefs.getBool('midi_monitor_$deviceId') ??
      false;

  Future<void> setMonitorEnabled(String deviceId, bool value) =>
      _prefs.setBool('midi_monitor_${_deviceKey(deviceId)}', value);

  /// Latência de entrada+saída calibrada (T04, ms), por par (dispositivo de
  /// entrada, saída de som) — `output` é `'app'` ou `'midi'`.
  Future<double?> inputLatencyMs(String deviceId, String output) async =>
      await _prefs.getDouble('midi_latency_${_deviceKey(deviceId)}_$output') ??
      await _prefs.getDouble('midi_latency_${deviceId}_$output');

  Future<void> setInputLatencyMs(
    String deviceId,
    String output,
    double value,
  ) => _prefs.setDouble('midi_latency_${_deviceKey(deviceId)}_$output', value);

  void dispose() {
    _disposed = true;
    unawaited(_setupSub?.cancel());
    devices.dispose();
    connected.dispose();
    lastError.dispose();
  }
}
