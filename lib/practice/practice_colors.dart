import 'package:flutter/material.dart';

/// Cores do modo treino (T02). "Esperado agora" não tem cor própria aqui:
/// a nota pendente do aluno já acende com a cor de destaque padrão do
/// player (`ScoreController.kDefaultHighlightColor`, configurável em
/// Opções) assim que o freio do relógio estaciona no `onMs` dela — mesmo
/// mecanismo que já destaca a mão que o app está tocando.

/// Nota certa: verde, some com fade curto.
const kPracticeCorrectColor = Color(0xFF2E7D32);
const kPracticeCorrectRelease = Duration(milliseconds: 400);

/// Nota pendente ("esperado agora") durante o treino: azul — distinta do
/// vermelho de errada e do verde de certa. Fora do treino continua valendo
/// `kDefaultHighlightColor` (vermelho escuro, configurável em Opções).
const kPracticePendingColor = Color(0xFF1E88E5);

/// Nota errada: pisca em vermelho na nota esperada mais próxima (a nota
/// errada em si pode não existir na partitura) — um pulso só, sem repetir
/// sozinho.
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
