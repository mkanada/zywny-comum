import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Põe na página de licenças do Flutter o que não é pacote Dart e viaja
/// dentro do app: o soundfont do piano (TimGM6mb, GPL-2), com o aviso de
/// copyright que vem ao lado dele. Chame uma vez, antes de `runApp`.
void registerBundledLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final text = await (bundle ?? rootBundle).loadString(
      'assets/soundfonts/TimGM6mb.copyright',
    );
    yield LicenseEntryWithLineBreaks(['TimGM6mb (som do piano)'], text);
  });
}
