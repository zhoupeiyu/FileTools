import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_compression_service.dart';

class PdfDocumentInfo {
  const PdfDocumentInfo({
    required this.path,
    required this.fileName,
    required this.bytes,
    required this.pageCount,
    required this.firstPageWidth,
    required this.firstPageHeight,
    required this.version,
    required this.isEncrypted,
    required this.textSampleLength,
  });

  final String path;
  final String fileName;
  final int bytes;
  final int pageCount;
  final double? firstPageWidth;
  final double? firstPageHeight;
  final String? version;
  final bool isEncrypted;
  final int textSampleLength;

  String get sizeText => formatBytes(bytes);

  String get pageCountText => pageCount <= 0 ? '-' : '$pageCount 页';

  String get pageSizeText {
    final width = firstPageWidth;
    final height = firstPageHeight;
    if (width == null || height == null) {
      return '-';
    }
    final label = _paperSizeLabel(width, height);
    return '${width.toStringAsFixed(0)} x ${height.toStringAsFixed(0)} pt ($label)';
  }

  String get orientationText {
    final width = firstPageWidth;
    final height = firstPageHeight;
    if (width == null || height == null) {
      return '-';
    }
    if ((width - height).abs() < 8) {
      return '接近方形';
    }
    return width > height ? '横向' : '纵向';
  }

  String get documentKind {
    if (pageCount <= 0) {
      return '未知';
    }
    final bytesPerPage = bytes / pageCount;
    if (textSampleLength >= 160 && bytesPerPage < 650 * 1024) {
      return '文本型';
    }
    if (bytesPerPage > 900 * 1024) {
      return '扫描件/图片型';
    }
    return '图文混合';
  }

  static String _paperSizeLabel(double width, double height) {
    final short = math.min(width, height);
    final long = math.max(width, height);
    if ((short - 595).abs() < 18 && (long - 842).abs() < 18) {
      return 'A4';
    }
    if ((short - 612).abs() < 18 && (long - 792).abs() < 18) {
      return 'Letter';
    }
    if ((short - 420).abs() < 18 && (long - 595).abs() < 18) {
      return 'A5';
    }
    if ((short - 842).abs() < 24 && (long - 1191).abs() < 24) {
      return 'A3';
    }
    return '自定义';
  }
}

class PdfInspectionException implements Exception {
  const PdfInspectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PdfInspectionService {
  const PdfInspectionService();

  Future<PdfDocumentInfo> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const PdfInspectionException('找不到 PDF 文件。');
    }

    final bytes = await file.length();
    final version = await _readPdfVersion(file);
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(path);
      final pages = document.pages;
      final firstPage = pages.isEmpty ? null : pages.first;
      var textLength = 0;
      if (firstPage != null) {
        try {
          final text = await firstPage.loadText();
          textLength = text?.fullText.trim().length ?? 0;
        } catch (_) {
          textLength = 0;
        }
      }

      return PdfDocumentInfo(
        path: path,
        fileName: p.basename(path),
        bytes: bytes,
        pageCount: pages.length,
        firstPageWidth: firstPage?.width,
        firstPageHeight: firstPage?.height,
        version: version,
        isEncrypted: document.isEncrypted,
        textSampleLength: textLength,
      );
    } catch (error) {
      throw PdfInspectionException('无法读取 PDF 参数：$error');
    } finally {
      await document?.dispose();
    }
  }

  Future<String?> _readPdfVersion(File file) async {
    final reader = file.openSync();
    try {
      final length = math.min(1024, await file.length());
      final bytes = reader.readSync(length);
      final header = latin1.decode(bytes, allowInvalid: true);
      final match = RegExp(r'%PDF-(\d\.\d)').firstMatch(header);
      return match?.group(1);
    } finally {
      await reader.close();
    }
  }
}
