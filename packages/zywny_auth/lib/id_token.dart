import 'dart:convert';

/// O instante em que o `idToken` expira, lido do próprio token (um JWT).
/// Devolve `null` quando o token não é um JWT legível.
DateTime? idTokenExpiresAt(String idToken) {
  final parts = idToken.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = base64Url.decode(base64Url.normalize(parts[1]));
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is Map && decoded['exp'] is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (decoded['exp'] as num).toInt() * 1000,
      );
    }
  } on Object {
    // Token fora do formato esperado: a validade fica sem data.
  }
  return null;
}
