import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta extraída do artefato "zywny — interface de estudo" (telas
/// `Celular*`). Sem pacote de fontes externo: título usa a pilha serif do
/// sistema (`serifDisplay`), o resto a sans padrão da plataforma.
const kInk = Color(0xFF1C1D20);
const kInkCaption = Color(0xFF5B5E66);
const kInkMuted = Color(0xFF9A9CA3);

/// Ícones "quietos" da barra de transporte larga (parar, andamento,
/// repetir, metrônomo) — mesmo `#4A4D55` do artboard, um tom mais escuro
/// que [kInkCaption].
const kIconQuiet = Color(0xFF4A4D55);

const kAccent = Color(0xFF2F5BD3);
const kAccentDark = Color(0xFF1F3F9E);
const kAccentSoftBg = Color(0xFFE3E9FA);

const kGoodColor = Color(0xFF0E7A5F);
const kOkColor = Color(0xFFC07A00);
const kBadColor = Color(0xFFC8412B);
const kLowScoreColor = Color(0xFF8A8D94);
const kScoreNeverColor = Color(0xFFDDD9D0);

const kLibraryBg = Color(0xFFEEECE7);
const kLibraryCardBg = Color(0xFFF4F2ED);
const kSurface = Color(0xFFFFFFFF);
const kPanelSideBg = Color(0xFFFBFAF7);
const kChipBg = Color(0xFFECEAE4);

const kBorder = Color(0xFFD2CEC4);
const kBorderSoft = Color(0xFFE2DED5);
const kBorderPanel = Color(0xFFDDD9D0);

const kScrim = Color(0x611C1D22);

/// Título de tela ("Biblioteca", "Opções de estudo"…) — mesma fonte do
/// artboard, Source Serif 4 (via `google_fonts`; buscada uma vez e mantida
/// em cache pelo pacote).
TextStyle serifDisplay({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color color = kInk,
}) => GoogleFonts.sourceSerif4(
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
);

/// O esquema de cores do app, escrito à mão a partir da paleta acima. O
/// `fromSeed` gerava um primário arroxeado e superfícies lavanda: diálogos,
/// botões, interruptores e controles deslizantes não tinham a cor do resto
/// (U18, E1).
const kAppColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: kAccent,
  onPrimary: Colors.white,
  primaryContainer: kAccentSoftBg,
  onPrimaryContainer: kAccentDark,
  secondary: kAccentDark,
  onSecondary: Colors.white,
  secondaryContainer: kAccentSoftBg,
  onSecondaryContainer: kAccentDark,
  tertiary: kGoodColor,
  onTertiary: Colors.white,
  error: kBadColor,
  onError: Colors.white,
  surface: kSurface,
  onSurface: kInk,
  onSurfaceVariant: kInkCaption,
  surfaceContainerLowest: kSurface,
  surfaceContainerLow: kPanelSideBg,
  surfaceContainer: kLibraryCardBg,
  surfaceContainerHigh: kChipBg,
  surfaceContainerHighest: kChipBg,
  outline: kBorder,
  outlineVariant: kBorderSoft,
  shadow: Colors.black,
  scrim: kScrim,
  inverseSurface: kInk,
  onInverseSurface: Colors.white,
  inversePrimary: kAccentSoftBg,
  surfaceTint: Colors.transparent,
);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: kAppColorScheme,
    scaffoldBackgroundColor: kLibraryBg,
  );
  return base.copyWith(
    // IBM Plex Sans no corpo, como no artboard.
    textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme)
        .apply(bodyColor: kInk, displayColor: kInk),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: kSurface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kAccent),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAccent,
        side: const BorderSide(color: kBorder),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : kInkMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? kAccent : kChipBg,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? kAccent : kBorder,
      ),
    ),
    // O primário (kAccent) já vem do esquema de cores.
    sliderTheme: const SliderThemeData(inactiveTrackColor: kBorder),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: kAccentSoftBg,
        selectedForegroundColor: kAccentDark,
        side: const BorderSide(color: kBorder),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kInk,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccent),
  );
}
