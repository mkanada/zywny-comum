import 'package:flutter/material.dart';

/// Cores do modo treino (T02). No modo espera a nota pendente ("esperado
/// agora") é cor fixa posta pelo `PracticeController` enquanto o passo
/// espera, e a certa acende por cima dela enquanto a tecla está apertada; no
/// tempo real a pendente acende pelo player, como a mão que o app
/// está tocando. Pendente, certa e errada são configuráveis em
/// Cores (`AppSettings.practicePendingColor`, `highlightColor` — a certa é a
/// mesma do destaque da reprodução — e `practiceWrongColor`); as daqui são
/// os padrões.

/// Nota certa: verde, some com fade curto.
const kPracticeCorrectColor = Color(0xFF2E7D32);
const kPracticeCorrectRelease = Duration(milliseconds: 400);

/// Nota pendente ("esperado agora") durante o treino: azul — distinta do
/// vermelho de errada e do verde de certa. Fora do treino vale a cor de
/// destaque da reprodução (`AppSettings.highlightColor`).
const kPracticePendingColor = Color(0xFF1E88E5);

/// Nota errada: pisca em vermelho na nota esperada mais próxima (a nota
/// errada em si pode não existir na partitura) — um pulso só, sem repetir
/// sozinho. No modo espera com fantasma, a errada aparece só na fantasma.
const kPracticeWrongColor = Color(0xFFC62828);
const kPracticeWrongAttack = Duration(milliseconds: 60);
const kPracticeWrongHold = Duration(milliseconds: 150);
const kPracticeWrongRelease = Duration(milliseconds: 250);

/// Tempo real (T03): adiantado/atrasado — âmbar escuro (o mesmo tom de
/// `kOkColor`, "fora do tempo" no resumo), distinto do laranja vivo da
/// fantasma (`kDefaultGhostColor`).
const kPracticeOffBeatColor = Color(0xFFC07A00);

/// Tempo real: nota que passou sem ser tocada.
const kPracticeMissedColor = Color(0xFF8E8E93);
const kPracticeMissedHold = Duration(milliseconds: 500);

/// A mão que o app toca no treino de uma mão só (U08): cinza claro, mais
/// fraco que o de perdida, para a outra pauta não parecer "toque esta".
const kPracticeAppHandColor = Color(0xFFB8B8BD);
