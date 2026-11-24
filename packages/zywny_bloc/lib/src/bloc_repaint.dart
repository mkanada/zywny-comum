import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

/// Adaptador do estado de um Cubit para `CustomPainter(repaint:)`, que pede um
/// [Listenable]. Serve só para isso: o pintor não guarda estado, ele lê
/// `cubit.state` ao pintar, e este objeto só avisa que vale repintar.
///
/// Assina o `stream` do bloc quando entra o primeiro ouvinte e cancela a
/// assinatura quando sai o último. A cada estado novo avisa os ouvintes, salvo
/// quando [when] (recebe o estado anterior e o novo) devolver `false`.
/// [dispose] cancela tudo.
class BlocRepaint<S> implements Listenable {
  BlocRepaint(this._source, {this.when});

  final StateStreamable<S> _source;

  /// Se devolver `false` para um par de estados, o estado novo não avisa.
  final bool Function(S previous, S next)? when;

  final List<VoidCallback> _listeners = <VoidCallback>[];
  StreamSubscription<S>? _subscription;
  late S _previous;
  bool _disposed = false;

  @override
  void addListener(VoidCallback listener) {
    assert(!_disposed, 'BlocRepaint usado depois de dispose.');
    _listeners.add(listener);
    if (_subscription == null) {
      _previous = _source.state;
      _subscription = _source.stream.listen(_onState);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) _cancel();
  }

  /// Cancela a assinatura e esquece os ouvintes.
  void dispose() {
    _disposed = true;
    _listeners.clear();
    _cancel();
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _onState(S next) {
    final previous = _previous;
    _previous = next;
    final test = when;
    if (test != null && !test(previous, next)) return;
    // Cópia: um ouvinte pode remover a si mesmo ao ser avisado.
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}
