// W03: o que só a Web sabe sobre o MIDI — se o navegador tem Web MIDI e se o
// usuário já deu permissão. Fora da Web (stub), nada disto se aplica.
export 'web_midi_access_stub.dart'
    if (dart.library.js_interop) 'web_midi_access_web.dart';
