// "Sobre o Zywny": de onde vem o nome e o que o aplicativo quer ser.
//
// Os fatos sobre Wojciech Żywny (1756–1842) foram conferidos em fontes:
// nascido em Mšeno, na Boêmia; radicado em Varsóvia; primeiro professor de
// piano de Chopin a partir de 1816. As fontes divergem sobre quando as aulas
// terminaram (1819, 1821 ou 1822), por isso o texto diz só "a partir de
// 1816".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../ui/brand.dart';
import '../ui/theme.dart';

/// O motto da abertura (`SplashScreen`); aqui, no cabeçalho.
const String kAboutMotto = 'Todo grande pianista começou na primeira tecla.';

/// "Versão 1.0.3 (4)", ou vazio se o aparelho não souber dizer.
Future<String> packageVersionText() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isEmpty) return '';
    final build = info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})';
    return 'Versão ${info.version}$build';
  } on Object {
    return '';
  }
}

/// A página padrão do Flutter com as licenças dos pacotes (e a do soundfont,
/// registrada em `lib/about/licenses.dart`).
void showAppLicenses(BuildContext context, String version) {
  showLicensePage(
    context: context,
    applicationName: 'Zywny',
    applicationVersion: version.isEmpty ? null : version,
    applicationLegalese: 'Copyright (c) 2023, mkanada',
  );
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({
    super.key,
    this.loadVersion = packageVersionText,
    this.openLicenses = showAppLicenses,
  });

  /// De onde vem a versão; os testes trocam por um texto fixo.
  final Future<String> Function() loadVersion;

  /// Abre a página de licenças; os testes trocam por um falso.
  final void Function(BuildContext context, String version) openLicenses;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final version = await widget.loadVersion();
    if (mounted) setState(() => _version = version);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kLibraryCardBg,
      appBar: AppBar(
        title: const Text('Sobre o Zywny'),
        backgroundColor: kLibraryCardBg,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            // Rolagem simples, sem `ListView`: o conteúdo é curto, e assim
            // tudo está montado (leitor de tela, busca de texto).
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(version: _version),
                  const SizedBox(height: 26),
                  const _Section(title: 'De onde vem o nome'),
                  const _Paragraph(
                    'Wojciech Żywny (1756–1842) foi violinista, pianista e '
                    'professor. Nasceu na Boêmia, hoje República Tcheca, e viveu '
                    'em Varsóvia, onde, a partir de 1816, ensinou piano a um '
                    'menino de seis anos chamado Frédéric Chopin.',
                  ),
                  const _Paragraph(
                    'Żywny deu a Chopin o alicerce: as primeiras lições, o gosto '
                    'por Bach e Mozart, a alegria de tocar. E, segundo se conta, '
                    'teve a humildade de admitir quando o aluno já não tinha '
                    'mais o que aprender com ele.',
                  ),
                  const _Paragraph(
                    'O nome do app é uma homenagem a esse professor: o de quem '
                    'ensina a primeira tecla, com paciência, para que o aluno '
                    'possa ir mais longe do que ele. No app, o Ż perdeu o ponto: '
                    'Zywny. Lê-se, mais ou menos, “JÍV-ni”.',
                  ),
                  const SizedBox(height: 18),
                  const _Section(title: 'O que o Zywny quer ser'),
                  const _Paragraph(
                    'Um professor de bolso para quem toca teclado. A ideia é '
                    'simples: você toca de verdade, e o app escuta.',
                  ),
                  const SizedBox(height: 4),
                  const _Goal(
                    icon: Icons.piano,
                    lead: 'Treinar no seu teclado.',
                    text:
                        'Ligue um teclado MIDI e o Zywny acompanha cada nota que '
                        'você toca: espera por você (modo espera) ou anda no '
                        'ritmo da música (tempo real), e mostra o que acertou e '
                        'o que errou.',
                  ),
                  const _Goal(
                    icon: Icons.school_outlined,
                    lead: 'Ensinar do zero.',
                    text:
                        'O curso inicial leva do teclado e da pauta até uma '
                        'peça a duas mãos. Professores podem escrever os seus '
                        'próprios cursos.',
                  ),
                  const _Goal(
                    icon: Icons.route,
                    lead: 'Estudar com método.',
                    text:
                        'Cada música vira uma trilha de trechos curtos e etapas '
                        'que se liberam como fases de um jogo, do devagar ao '
                        'andamento real.',
                  ),
                  const _Goal(
                    icon: Icons.library_music_outlined,
                    lead: 'Trazer a sua música.',
                    text:
                        'O Zywny não traz partituras: elas chegam em '
                        'bibliotecas que você instala. Dá para transpor para um '
                        'tom mais fácil, mudar o tamanho da notação e escolher '
                        'as cores.',
                  ),
                  const _Goal(
                    icon: Icons.devices_outlined,
                    lead: 'Estar onde você estiver.',
                    text: 'No celular, no computador e no navegador.',
                  ),
                  const SizedBox(height: 18),
                  const _Section(title: 'Créditos'),
                  const _Paragraph(
                    'As partituras são desenhadas com o Verovio. O som do piano '
                    'vem do soundfont TimGM6mb.',
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => widget.openLicenses(context, _version),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('Licenças de código aberto'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: kBrandWine,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const MonogramZ(size: 84),
          const SizedBox(height: 6),
          const Text(
            'Zywny',
            style: TextStyle(
              fontFamily: kBrandSerif,
              fontWeight: FontWeight.w600,
              fontSize: 38,
              color: kBrandCream,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            kAboutMotto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kBrandSerif,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              fontSize: 20,
              height: 1.3,
              color: kBrandSoft,
            ),
          ),
          if (version.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              version,
              style: const TextStyle(
                fontFamily: kBrandSans,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: kBrandMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(title, style: serifDisplay(fontSize: 26)),
    ),
  );
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15.5, height: 1.5, color: kInk),
    ),
  );
}

class _Goal extends StatelessWidget {
  const _Goal({required this.icon, required this.lead, required this.text});

  final IconData icon;
  final String lead;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: kAccentSoftBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: kAccentDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$lead ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: const TextStyle(fontSize: 15, height: 1.45, color: kInk),
            ),
          ),
        ],
      ),
    );
  }
}
