// Padrão de referência do BLoC (BL01): o estado é imutável (Equatable e
// copyWith) e o Cubit mora ao lado da tela, que o cria com
// BlocProvider(create:) e o fecha. Trabalho assíncrono confere `isClosed`
// antes do `emit`, porque um emit depois do close lança erro.

import 'package:zywny_bloc/zywny_bloc.dart';

/// O que a tela "Sobre o Zywny" mostra além do texto fixo: a versão do app.
class AboutState extends Equatable {
  const AboutState({this.version = ''});

  /// "Versão 1.0.3 (4)", ou vazio enquanto carrega (ou se o aparelho não sabe).
  final String version;

  AboutState copyWith({String? version}) =>
      AboutState(version: version ?? this.version);

  @override
  List<Object?> get props => [version];
}

/// Lê a versão do app uma vez, para o cabeçalho da tela "Sobre".
class AboutCubit extends Cubit<AboutState> {
  AboutCubit({required this.loadVersion}) : super(const AboutState());

  /// De onde vem a versão; os testes trocam por um texto fixo.
  final Future<String> Function() loadVersion;

  Future<void> load() async {
    final version = await loadVersion();
    if (isClosed) return;
    emit(state.copyWith(version: version));
  }
}
