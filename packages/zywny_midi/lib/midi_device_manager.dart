import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'package:zywny_diag/diag_log.dart';

import 'web_midi_access.dart';

/// Por que a lista de teclados não existe (só na Web, W03): `null` em
/// [MidiDeviceState.unavailable] quer dizer que o MIDI está acessível.
enum MidiUnavailable {
  /// O navegador não tem Web MIDI (Safari, iOS, Firefox sem add-on).
  unsupported,

  /// O navegador ainda não perguntou: a pergunta de permissão só abre num
  /// clique do usuário ([MidiDeviceManager.refresh] a partir do seletor).
  notAsked,

  /// O usuário (ou a política do navegador) recusou o acesso.
  denied,
}

/// O que o [MidiDeviceManager] sabe dos teclados, para quem desenha: a lista,
/// o teclado conectado, o último erro, o motivo de a lista não existir e a
/// nota da busca pelo Bluetooth.
class MidiDeviceState extends Equatable {
  const MidiDeviceState({
    this.devices = const [],
    this.connected,
    this.lastError,
    this.unavailable,
    this.bluetoothNote,
  });

  /// Os dispositivos MIDI vistos agora.
  final List<MidiDevice> devices;

  /// O teclado conectado; `null` se nenhum.
  final MidiDevice? connected;

  /// O texto do último erro de conectar; `null` se não houve.
  final String? lastError;

  /// Por que a lista não existe (só na Web, W03); `null` com o MIDI acessível.
  final MidiUnavailable? unavailable;

  /// Por que a busca pelo Bluetooth não pôde começar (desligado, sem
  /// permissão...); `null` quando está tudo certo.
  final String? bluetoothNote;

  /// Os campos anuláveis trocam por uma função: `connected: () => null` põe
  /// `null`; sem o argumento, o valor fica como está.
  MidiDeviceState copyWith({
    List<MidiDevice>? devices,
    MidiDevice? Function()? connected,
    String? Function()? lastError,
    MidiUnavailable? Function()? unavailable,
    String? Function()? bluetoothNote,
  }) => MidiDeviceState(
    devices: devices ?? this.devices,
    connected: connected == null ? this.connected : connected(),
    lastError: lastError == null ? this.lastError : lastError(),
    unavailable: unavailable == null ? this.unavailable : unavailable(),
    bluetoothNote: bluetoothNote == null ? this.bluetoothNote : bluetoothNote(),
  );

  @override
  List<Object?> get props => [
    devices,
    connected,
    lastError,
    unavailable,
    bluetoothNote,
  ];
}

/// Lista dispositivos MIDI, conecta, guarda o último escolhido e conecta
/// sozinho — na abertura do app e a cada hot-plug (M01, critério de aceite
/// 1): plugou o fio, o teclado entra, sem passar pela configuração. Não decodifica mensagens: isso é `MidiInputService`.
///
/// É um Cubit: o estado (a lista, o conectado, os erros) é [MidiDeviceState];
/// quem lê o teclado conectado usa `state.connected`, e quem reage a ele, um
/// `BlocSelector` ou o `stream`.
class MidiDeviceManager extends Cubit<MidiDeviceState> {
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
       _newBleTransport = newBleTransport ?? _defaultBleTransport,
       super(const MidiDeviceState()) {
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

  Future<void> _startWeb(
    bool Function() supported,
    Future<bool> Function()? granted,
  ) async {
    if (!supported()) {
      emit(state.copyWith(unavailable: () => MidiUnavailable.unsupported));
      return;
    }
    if (await (granted ?? webMidiGranted)()) {
      await refresh();
    } else if (!_disposed) {
      emit(state.copyWith(unavailable: () => MidiUnavailable.notAsked));
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
      final motivo = e is UnsupportedError
          ? MidiUnavailable.unsupported
          : MidiUnavailable.denied;
      emit(state.copyWith(unavailable: () => motivo, devices: const []));
      return;
    }
    if (_disposed) return;
    emit(state.copyWith(unavailable: () => null, devices: list));
    if (_isWeb) _listenSetup();
    DiagLog.log(
      'midi-dev',
      'dispositivos (${list.length}): ${[for (final d in list) '${d.name} id=${d.id} tipo=${d.type} conectado=${d.connected} '
            'in=${d.inputPorts.length} out=${d.outputPorts.length}'].join(' | ')}',
    );

    final current = state.connected;
    if (current != null && !list.any((d) => d.id == current.id)) {
      emit(state.copyWith(connected: () => null));
    }
    if (_pausedName != null && !list.any((d) => d.name == _pausedName)) {
      _pausedName = null;
    }

    if (state.connected != null || _bleReleased) return;
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
      _bleReleased = false;
      emit(state.copyWith(connected: () => device, lastError: () => null));
      if (device.type == MidiDeviceType.ble) _watchLifecycle();
      await _prefs.setString(_kLastDeviceIdKey, device.id);
      await _prefs.setString(_kLastDeviceNameKey, device.name);
    } on MidiConnectionException catch (e) {
      DiagLog.log('midi-dev', 'falha ao conectar: $e');
      if (!_disposed) emit(state.copyWith(lastError: () => e.toString()));
    }
  }

  void disconnect() {
    final device = state.connected;
    if (device == null) return;
    DiagLog.log('midi-dev', 'desconectando ${device.name}');
    _midi.disconnectDevice(device);
    _pausedName = device.name;
    if (!_disposed) emit(state.copyWith(connected: () => null));
  }

  AppLifecycleListener? _lifecycle;

  /// Se o teclado Bluetooth foi solto porque o app foi para segundo plano e
  /// ainda deve voltar quando o app voltar.
  bool _bleReleased = false;

  /// Só quando há um teclado Bluetooth conectado (e, portanto, um `binding`
  /// de verdade): a ponte com o ciclo de vida do app.
  void _watchLifecycle() {
    if (_isWeb || _disposed) return;
    _lifecycle ??= AppLifecycleListener(onStateChange: onLifecycleChanged);
  }

  /// Um teclado Bluetooth LE só aceita um aparelho conectado por vez: se o
  /// app fica em segundo plano segurando a conexão, o outro app zywny (o
  /// aprendizado e o músicas) não consegue conectar (issue #2). Então, ao ir
  /// para segundo plano o teclado Bluetooth é solto e, ao voltar, procurado
  /// de novo e reconectado sozinho. `inactive` (diálogo de permissão, painel
  /// do sistema) não solta nada; USB também não: o sistema já o isola.
  @visibleForTesting
  void onLifecycleChanged(AppLifecycleState estado) {
    switch (estado) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _releaseBle();
      case AppLifecycleState.resumed:
        _resumeBle();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _releaseBle() {
    final device = state.connected;
    if (_disposed || device == null || device.type != MidiDeviceType.ble) {
      return;
    }
    DiagLog.log('midi-dev', 'segundo plano: soltando ${device.name}');
    _bleReleased = true;
    _midi.disconnectDevice(device);
    emit(state.copyWith(connected: () => null));
  }

  void _resumeBle() {
    if (!_bleReleased || _disposed) return;
    DiagLog.log('midi-dev', 'primeiro plano: voltando ao teclado Bluetooth');
    unawaited(_reconnectBle());
  }

  Future<void> _reconnectBle() async {
    _bleReleased = false;
    await refresh();
    if (_disposed || state.connected != null || !_bluetooth) return;
    // Solto o teclado, o plugin o esquece: só volta à lista ao ser visto de
    // novo pela busca. A busca para assim que ele conecta (o stream do estado
    // avisa; a busca já está correndo quando a escuta começa).
    final parar = stream.listen((estado) {
      if (estado.connected != null) stopBluetoothSearch();
    });
    try {
      await searchBluetooth(window: const Duration(seconds: 15));
    } finally {
      unawaited(parar.cancel());
    }
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
    emit(state.copyWith(bluetoothNote: () => null));
    try {
      _startBle();
      await _midi.startBluetooth();
      await _midi.waitUntilBluetoothIsInitialized().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      final radio = _midi.bluetoothState;
      if (_disposed) return;
      emit(state.copyWith(bluetoothNote: () => _bluetoothNote(radio)));
      if (radio == BluetoothState.poweredOn) {
        await _midi.startScanningForBluetoothDevices();
        await stop.future.timeout(window, onTimeout: () {});
      }
    } on Object catch (e) {
      DiagLog.log('midi-dev', 'busca pelo Bluetooth falhou: $e');
      if (!_disposed) {
        emit(
          state.copyWith(
            bluetoothNote: () => 'Não deu para procurar pelo Bluetooth. $e',
          ),
        );
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
    final current = state.connected;
    if (current != null && current.id == deviceId) return current.name;
    for (final d in state.devices) {
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

  /// A última medida do medidor de latência do som (ms), por teclado: o
  /// tempo entre o app mandar a nota e o som sair. `corrected` diz se o atraso
  /// do microfone do celular foi descontado.
  Future<({double ms, bool corrected})?> soundLatency(String deviceId) async {
    final key = 'midi_sound_latency_${_deviceKey(deviceId)}';
    final ms = await _prefs.getDouble(key);
    if (ms == null) return null;
    return (
      ms: ms,
      corrected: await _prefs.getBool('${key}_corrected') ?? false,
    );
  }

  Future<void> setSoundLatency(
    String deviceId,
    double ms, {
    required bool corrected,
  }) async {
    final key = 'midi_sound_latency_${_deviceKey(deviceId)}';
    await _prefs.setDouble(key, ms);
    await _prefs.setBool('${key}_corrected', corrected);
  }

  /// Só para os testes (dos pacotes e dos apps): põe [device] como o teclado
  /// conectado, ou nenhum, sem passar pelo plugin. Não grava nada.
  void simularConectado(MidiDevice? device) =>
      emit(state.copyWith(connected: () => device));

  @override
  Future<void> close() {
    _disposed = true;
    _lifecycle?.dispose();
    stopBluetoothSearch();
    unawaited(_setupSub?.cancel());
    unawaited(_transportInstalled.close());
    return super.close();
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
