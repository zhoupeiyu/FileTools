import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_compression/src/pdf_compression_service.dart';

void main() {
  group('PDF path helpers', () {
    test('builds default output name with compressed suffix', () {
      expect(
        defaultOutputPath('/tmp/report.final.pdf'),
        '/tmp/report.final_compressed.pdf',
      );
    });

    test('adds pdf extension when missing', () {
      expect(ensurePdfExtension('/tmp/output'), '/tmp/output.pdf');
      expect(ensurePdfExtension('/tmp/output.PDF'), '/tmp/output.PDF');
    });

    test('formats byte counts', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.50 KB');
      expect(formatBytes(1048576), '1.00 MB');
    });

    test('rejects identical input and output paths', () {
      expect(samePath('/tmp/report.pdf', '/tmp/report.pdf'), isTrue);
    });

    test('estimates output size from preset and document shape', () {
      final estimate = estimateCompression(
        inputBytes: 10 * 1024 * 1024,
        options: const CompressionOptions.preset(CompressionPreset.ebook),
        pageCount: 10,
      );

      expect(estimate.outputBytes, greaterThan(0));
      expect(estimate.outputBytes, lessThan(10 * 1024 * 1024));
      expect(estimate.savedRatio, greaterThan(0));
    });

    test('custom quality generates detailed Ghostscript image options', () {
      final options = const CompressionOptions.custom(
        quality: 40,
        grayscale: true,
        compatibility: PdfCompatibility.modern17,
      );
      final args = options.toGhostscriptArgs();

      expect(args, contains('-dCompatibilityLevel=1.7'));
      expect(args, contains('-sColorConversionStrategy=Gray'));
      expect(
        args.any((arg) => arg.startsWith('-dColorImageResolution=')),
        isTrue,
      );
      expect(args.any((arg) => arg.startsWith('-dJPEGQ=')), isTrue);
      expect(args.any((arg) => arg.startsWith('-dPDFSETTINGS=')), isFalse);
    });

    test('preset quality values are ordered for the UI slider', () {
      expect(
        CompressionPreset.screen.qualityValue,
        lessThan(CompressionPreset.ebook.qualityValue),
      );
      expect(
        CompressionPreset.ebook.qualityValue,
        lessThan(CompressionPreset.printer.qualityValue),
      );
    });
  });

  group('PDF compression service', () {
    test('compresses a real PDF with bundled Ghostscript', () async {
      if (!Platform.isMacOS && !Platform.isWindows) {
        markTestSkipped(
          'Desktop Ghostscript bundle only supports macOS/Windows.',
        );
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'pdf_compression_service_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final input = File('${tempDir.path}/input.pdf');
      final output = File('${tempDir.path}/input_compressed.pdf');
      await _writeSimplePdf(input);
      final progressEvents = <CompressionProgress>[];

      final result = await const PdfCompressionService().compress(
        inputPath: input.path,
        outputPath: output.path,
        preset: CompressionPreset.ebook,
        pageCount: 1,
        onProgress: progressEvents.add,
      );

      expect(result.inputPath, input.path);
      expect(result.outputPath, output.path);
      expect(result.inputBytes, greaterThan(0));
      expect(result.outputBytes, greaterThan(0));
      expect(await output.exists(), isTrue);
      expect(
        await output.openRead(0, 4).transform(latin1.decoder).join(),
        '%PDF',
      );
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.first.phase, CompressionPhase.preparing);
      expect(progressEvents.last.phase, CompressionPhase.finalizing);
      expect(
        progressEvents.any(
          (event) => event.phase == CompressionPhase.processing,
        ),
        isTrue,
      );
    });
  });
}

Future<void> _writeSimplePdf(File file) async {
  final objects = <String>[
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
    '3 0 obj\n'
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\n'
        'endobj\n',
    '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
    '5 0 obj\n<< /Length 44 >>\nstream\n'
        'BT /F1 18 Tf 40 80 Td (PDF Compression) Tj ET\n'
        'endstream\nendobj\n',
  ];

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (final object in objects) {
    offsets.add(latin1.encode(buffer.toString()).length);
    buffer.write(object);
  }

  final xrefOffset = latin1.encode(buffer.toString()).length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );

  await file.writeAsBytes(latin1.encode(buffer.toString()), flush: true);
}
