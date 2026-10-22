import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zywny_diag/diag_log.dart';

import 'web_midi_access.dart';

/// Por que a lista de teclados não existe (só na Web, W03): `null` em
/// [MidiDeviceManager.unavailable] quer dizer que o MIDI está acessível.
enum MidiUnavailable {
  /// O navegador não tem Web MIDI (Safari, iOS, Firefox sem add-on).
  unsupported,

  /// O navegador ainda não perguntou: a pergunta de permissão só abre num
  /// clique do usuário ([MidiDeviceManager.refresh] a partir do seletor).
  notAsked,

  /// O usuário (ou a política do navegador) recusou o acesso.
  denied,
}

/// Lista dispositivos MIDI, conecta, guarda o último escolhido e conecta
/// sozinho — na abertura do app e a cada hot-plug (M01, critério de aceite
/// 1): plugou o fio, o teclado entra, sem passar pela configuração. Não decodifica mensagens: isso é `MidiInputService`.
class MidiDeviceManager {
  /// [isWeb], [webSupported] e [webGranted] existem para testar o caminho da
  /// Web fora do navegador; o padrão é o ambiente de verdade.
  ///
  /// [bluetooth] deixa procurar teclados Bluetooth LE (M01): quem chama liga
  /// só no Android. O transporte BLE só nasce na primeira busca, então
  /// nada de Bluetooth (nem permissão) é tocado antes de o usuário pedir.
  /// [newBleTransport] existe para testar; o padrão é o transporte de verdade.
  MidiDeviceManager({
    MidiCommand? midi,
    SharedPreferencesAsync? prefs,
    bool isWeb = kIsWeb,
    bool Function()? webSupported,
    Future<bool> Function()? webGranted,
    bool bluetooth = false,
    MidiBleTransport Function()? newBleTransport,
  }) : _midi = midi ?? MidiCommand(),
       _prefs = prefs ?? SharedPreferencesAsync(),
       _isWeb = isWeb,
       _bluetooth = bluetooth, // ignore: prefer_initializing_formals
       _newBleTransport = newBleTransport ?? _defaultBleTransport {
    if (!isWeb) {
      _listenSetup();
      unawaited(refresh());
      return;
    }
    // Na Web, mexer no plugin (até assinar `onMidiSetupChanged`) já pede o
    // acesso ao navegador — então só se começa se não vai abrir pergunta
    // sozinha, na abertura do app (W03: a pergunta vem de um clique).
    unawaited(_startWeb(webSupported ?? () => webMidiSupported, webGranted));
  }

  final bool _isWeb;

  final bool _bluetooth;

  /// Se a busca pelo Bluetooth existe nesta plataforma ([searchBluetooth]).
  bool get bluetooth => _bluetooth;

  /// Por que a busca pelo Bluetooth não pôde começar (desligado, sem
  /// permissão...); `null` quando está tudo certo.
  final ValueNotifier<String?> bluetoothNote = ValueNotifier(null);

  /// Fim da janela de [searchBluetooth]; `null` quando não está procurando.
  Completer<void>? _searchStop;

  final StreamController<void> _transportInstalled =
      StreamController<void>.broadcast();

  /// Dispara quando o transporte BLE entra no [MidiCommand]. Quem já assinou
  /// `onMidiDataReceived` antes disso não recebe nada do Bluetooth e precisa
  /// assinar de novo (`FlutterMidiInputService.resubscribeOn`).
  Stream<void> get transportInstalled => _transportInstalled.stream;

  /// Se o transporte BLE já foi instalado no [MidiCommand] (ver [_startBle]).
  bool _bleReady = false;

  final MidiBleTransport Function() _newBleTransport;

  /// `null` com o MIDI acessível; senão o motivo (Web, W03).
  final ValueNotifier<MidiUnavailable?> unavailable = ValueNotifier(null);

  Future<void> _startWeb(
    bool Function() supported,
    Future<bool> Function()? granted,
  ) async {
    if (!supported()) {
      unavailable.value = MidiUnavailable.unsupported;
      return;
    }
    if (await (granted ?? webMidiGranted)()) {
      await refresh();
    } else if (!_disposed) {
      unavailable.value = MidiUnavailable.notAsked;
    }
  }

  void _listenSetup() {
    _setupSub ??= _midi.onMidiSetupChanged?.listen((c) {
      DiagLog.log('midi-dev', 'setup mudou: $c');
      refresh();
    });
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
    final List<MidiDevice> list;
    try {
      list = await _midi.devices ?? const <MidiDevice>[];
    } on Object catch (e) {
      if (!_isWeb) rethrow;
      // Web: sem Web MIDI (UnsupportedError do plugin) ou acesso recusado.
      DiagLog.log('midi-dev', 'Web MIDI indisponível: $e');
      if (_disposed) return;
      unavailable.value = e is UnsupportedError
          ? MidiUnavailable.unsupported
          : MidiUnavailable.denied;
      devices.value = const [];
      return;
    }
    if (_disposed) return;
    unavailable.value = null;
    if (_isWeb) _listenSetup();
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

  /// Procura teclados Bluetooth por [window] (só com [bluetooth] ligado): liga
  /// o Bluetooth — o Android pede a permissão aqui, num toque do usuário —,
  /// escaneia e relista. Um teclado que aparece e é o último escolhido conecta
  /// sozinho, como o USB. [stopBluetoothSearch] encerra antes do tempo.
  Future<void> searchBluetooth({
    Duration window = const Duration(seconds: 20),
  }) async {
    if (!_bluetooth || _disposed || _searchStop != null) return;
    final stop = _searchStop = Completer<void>();
    bluetoothNote.value = null;
    try {
      _startBle();
      await _midi.startBluetooth();
      await _midi.waitUntilBluetoothIsInitialized().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      final state = _midi.bluetoothState;
      if (_disposed) return;
      bluetoothNote.value = _bluetoothNote(state);
      if (state == BluetoothState.poweredOn) {
        await _midi.startScanningForBluetoothDevices();
        await stop.future.timeout(window, onTimeout: () {});
      }
    } on Object catch (e) {
      DiagLog.log('midi-dev', 'busca pelo Bluetooth falhou: $e');
      if (!_disposed) {
        bluetoothNote.value = 'Não deu para procurar pelo Bluetooth. $e';
      }
    } finally {
      _searchStop = null;
      _midi.stopScanningForBluetoothDevices();
    }
    await refresh();
  }

  /// Encerra a busca de [searchBluetooth] agora (ao fechar o seletor).
  void stopBluetoothSearch() {
    final stop = _searchStop;
    if (stop != null && !stop.isCompleted) stop.complete();
  }

  /// Instala o transporte BLE, uma vez. O plugin mescla os canais de eventos
  /// só no momento em que a assinatura é feita, então ela é refeita aqui para
  /// ouvir os teclados Bluetooth também.
  void _startBle() {
    if (_bleReady) return;
    _bleReady = true;
    _midi.configureBleTransport(_newBleTransport());
    unawaited(_setupSub?.cancel());
    _setupSub = null;
    _listenSetup();
    _transportInstalled.add(null);
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
    stopBluetoothSearch();
    unawaited(_setupSub?.cancel());
    unawaited(_transportInstalled.close());
    devices.dispose();
    connected.dispose();
    lastError.dispose();
    unavailable.dispose();
    bluetoothNote.dispose();
  }
}

MidiBleTransport _defaultBleTransport() => UniversalBleMidiTransport();

/// O que dizer quando a busca pelo Bluetooth não pode começar; `null` se pode.
String? _bluetoothNote(BluetoothState state) => switch (state) {
  BluetoothState.poweredOn => null,
  BluetoothState.poweredOff => 'O Bluetooth do celular está desligado. Ligue-o e toque em Procurar de novo.',
  BluetoothState.unauthorized =>
    'O celular não deixou o zywny usar o Bluetooth. Libere a permissão nas '
        'configurações do app e tente de novo.',
  BluetoothState.unsupported => 'Este celular não tem Bluetooth de baixa energia (BLE), que o MIDI sem fio usa.',
  _ => 'O Bluetooth ainda está iniciando. Toque em Procurar de novo.',
};
