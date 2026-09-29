import 'package:flutter/material.dart';

/// Cores do modo treino (T02). "Esperado agora" não tem cor própria aqui:
/// a nota pendente do aluno já acende com a cor de destaque padrão do
/// player (`ScoreController.kDefaultHighlightColor`, configurável em
/// Opções) assim que o freio do relógio estaciona no `onMs` dela — mesmo
/// mecanismo que já destaca a mão que o app está tocando.

/// Nota certa: verde, some com fade curto.
const kPracticeCorrectColor = Color(0xFF2E7D32);
const kPracticeCorrectRelease = Duration(milliseconds: 400);

/// Nota errada: pisca em vermelho na nota esperada mais próxima (a nota
/// errada em si pode não existir na partitura) — um pulso só, sem repetir
/// sozinho.
const kPracticeWrongColor = Color(0xFFC62828);
const kPracticeWrongAttack = Duration(milliseconds: 60);
const kPracticeWrongHold = Duration(milliseconds: 150);
const kPracticeWrongRelease = Duration(milliseconds: 250);

/// Tempo real (T03): adiantado/atrasado — laranja, diferente do vermelho de
/// errado.
const kPracticeOffBeatColor = Color(0xFFEF8A00);

/// Tempo real: nota que passou sem ser tocada.
const kPracticeMissedColor = Color(0xFF8E8E93);
const kPracticeMissedHold = Duration(milliseconds: 500);
