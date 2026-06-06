import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/pdf_compression_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
  runApp(const PdfCompressionApp());
}
