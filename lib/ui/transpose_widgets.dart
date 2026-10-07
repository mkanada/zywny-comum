import 'package:flutter/material.dart';

import '../music/note_names.dart' show NoteNaming;
import '../music/tone_choices.dart';
import '../music/transposition.dart';
import '../trail/trail_progress.dart' show StudiedTone;
import 'phone_chrome.dart';
import 'theme.dart';

/// As peças de tela de "Transpor" (fase Q, docs/plano/Q08): o selo da
/// partitura, as três escolhas da gaveta, a lista dos 12 tons e a linha
/// "Também estudada". Só apresentação; quem guarda e regrava é `lib/main.dart`.

/// O que a música está fazendo hoje com a transposição.
enum TransposeMode {
  /// "Não": o tom original.
  none,

  /// "Sem acidentes": a armadura vai a zero.
  noAccidentals,

  /// "Escolher…": um dos 12 tons.
  other,
}

/// Qual das três escolhas descreve [current], a transposição em uso, dado o
/// "sem acidentes" desta música ([noAccidentals], `null` se ela já é em Dó).
TransposeMode transposeModeOf(
  Transposition? current,
  Transposition? noAccidentals,
) {
  if (current == null) return TransposeMode.none;
  return current == noAccidentals
      ? TransposeMode.noAccidentals
      : TransposeMode.other;
}

/// O selo da partitura transposta, na barra do título: "Mi♭ → Dó · teclado
/// +3". Tocar nele abre a conferência do teclado. Uma linha, que corta com
/// reticências: nunca tira espaço da pauta.
class TransposeSeal extends StatelessWidget {
  const TransposeSeal({
    super.key,
    required this.text,
    required this.onTap,
    this.maxWidth = 230,
  });

  final String text;
  final VoidCallback onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Transposição: $text',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: kAccentSoftBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert, size: 15, color: kAccentDark),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kAccentDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// O item "Transpor" da gaveta: "Não (3♭)", "Sem acidentes" e "Escolher…".
/// Com a armadura em 0 sobra só "Escolher…" ([fifths] == 0), e sem armadura
/// conhecida o item nem existe (quem monta decide).
class TransposeSection extends StatelessWidget {
  const TransposeSection({
    super.key,
    required this.fifths,
    required this.mode,
    required this.noAccidentals,
    required this.currentTone,
    required this.onNone,
    required this.onNoAccidentals,
    required this.onPick,
    this.alsoStudied,
  });

  /// A armadura da música.
  final int fifths;
  final TransposeMode mode;

  /// A transposição de "Sem acidentes"; `null` se a música já é sem acidentes.
  final Transposition? noAccidentals;

  /// A transposição em uso (para dizer em "Escolher…" qual tom é).
  final Transposition? currentTone;
  final VoidCallback onNone;
  final VoidCallback onNoAccidentals;
  final VoidCallback onPick;

  /// "Também estudada: original, 3 de 8 etapas"; `null` = nada a dizer.
  final String? alsoStudied;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PhoneSectionLabel('TRANSPOR'),
        if (fifths != 0) ...[
          _ChoiceRow(
            label: 'Não (${keySignatureShort(fifths)})',
            selected: mode == TransposeMode.none,
            onTap: onNone,
          ),
          _ChoiceRow(
            label: 'Sem acidentes',
            caption: noAccidentals == null
                ? null
                : 'teclado ${noAccidentals!.keyboardLabel}',
            selected: mode == TransposeMode.noAccidentals,
            onTap: onNoAccidentals,
          ),
        ],
        _ChoiceRow(
          label: 'Escolher…',
          caption: mode == TransposeMode.other && currentTone != null
              ? '${currentTone!.toKeyName(fifths)} · '
                    'teclado ${currentTone!.keyboardLabel}'
              : null,
          selected: mode == TransposeMode.other,
          onTap: onPick,
        ),
        if (alsoStudied case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: kInkCaption),
            ),
          ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.caption,
  });

  final String label;
  final String? caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PhoneActionRow(
      icon: selected ? Icons.radio_button_checked : Icons.radio_button_off,
      label: label,
      onTap: onTap,
      trailing: caption == null
          ? null
          : Text(
              caption!,
              style: const TextStyle(fontSize: 13, color: kInkCaption),
            ),
    );
  }
}

/// A lista dos 12 tons: cada linha com a armadura resultante e o TRANSPOSE
/// ("Ré · 2♯ · teclado −1"), a original marcada. Devolve a escolha, ou `null`
/// se a pessoa fechou. [currentFifths] é o tom que está em uso (marcado).
Future<ToneChoice?> showToneList(
  BuildContext context, {
  required List<ToneChoice> choices,
  required int currentFifths,
}) {
  return showDialog<ToneChoice>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Transpor para…'),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      children: [
        for (final choice in choices)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, choice),
            child: Row(
              children: [
                Icon(
                  choice.fifths == currentFifths
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: choice.fifths == currentFifths ? kAccent : kIconQuiet,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(choice.label)),
              ],
            ),
          ),
      ],
    ),
  );
}

/// "Também estudada: original, 3 de 8 etapas" — os tons, fora o que está em
/// uso, em que a música já tem trilha começada. `null` quando não há nenhum.
/// [fifths] é a armadura da música (para dar nome ao tom).
String? alsoStudiedText(
  List<StudiedTone> tones, {
  required Transposition? current,
  required int? fifths,
  NoteNaming naming = NoteNaming.latin,
}) {
  final parts = [
    for (final tone in tones)
      if (tone.transposition != current)
        '${_toneName(tone.transposition, fifths, naming)}, '
            '${tone.progress.done} de ${tone.progress.total} etapas',
  ];
  return parts.isEmpty ? null : 'Também estudada: ${parts.join(' · ')}';
}

String _toneName(Transposition? tone, int? fifths, NoteNaming naming) {
  if (tone == null || fifths == null) return 'original';
  return tone.toKeyName(fifths, naming: naming);
}
