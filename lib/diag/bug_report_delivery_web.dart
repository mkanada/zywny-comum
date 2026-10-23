import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'bug_report_delivery.dart';

/// Baixa o arquivo pelo navegador (vai para a pasta de downloads).
Future<BugReportDelivery> deliverBugReport(
  String fileName,
  Uint8List bytes,
) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/zip'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return const BugReportDelivery();
}

String platformDescription() => web.window.navigator.userAgent;
