import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum CompressionPreset {
  screen('/screen', '高压缩', '体积最小，适合传输和归档', 0.34, 22),
  ebook('/ebook', '推荐', '平衡清晰度和文件大小', 0.55, 58),
  printer('/printer', '高质量', '优先保留细节，压缩较温和', 0.78, 86);

  const CompressionPreset(
    this.ghostscriptSetting,
    this.label,
    this.description,
    this.estimatedRatio,
    this.qualityValue,
  );

  final String ghostscriptSetting;
  final String label;
  final String description;
  final double estimatedRatio;
  final int qualityValue;
}

enum PdfCompatibility {
  standard14('1.4', '兼容旧版'),
  modern17('1.7', '保留新版');

  const PdfCompatibility(this.value, this.label);

  final String value;
  final String label;
}

class CompressionOptions {
  const CompressionOptions.preset(
    this.preset, {
    this.grayscale = false,
    this.compatibility = PdfCompatibility.standard14,
  }) : customQuality = null;

  const CompressionOptions.custom({
    required int quality,
    this.grayscale = false,
    this.compatibility = PdfCompatibility.standard14,
  }) : preset = null,
       customQuality = quality;

  final CompressionPreset? preset;
  final int? customQuality;
  final bool grayscale;
  final PdfCompatibility compatibility;

  bool get isCustom => customQuality != null;

  String get label {
    if (isCustom) {
      return '自定义 $customQuality';
    }
    return preset?.label ?? CompressionPreset.ebook.label;
  }

  double get estimatedRatio {
    final quality = customQuality;
    if (quality != null) {
      final clamped = quality.clamp(0, 100);
      return 0.28 + (clamped / 100) * 0.64;
    }
    return (preset ?? CompressionPreset.ebook).estimatedRatio;
  }

  List<String> toGhostscriptArgs() {
    final args = <String>[
      '-dCompatibilityLevel=${compatibility.value}',
      '-dDetectDuplicateImages=true',
      '-dCompressFonts=true',
      '-dSubsetFonts=true',
    ];

    if (grayscale) {
      args.addAll(<String>[
        '-sColorConversionStrategy=Gray',
        '-dProcessColorModel=/DeviceGray',
      ]);
    }

    final quality = customQuality;
    if (quality == null) {
      args.add(
        '-dPDFSETTINGS=${(preset ?? CompressionPreset.ebook).ghostscriptSetting}',
      );
      return args;
    }

    final clamped = quality.clamp(0, 100);
    final imageDpi = (72 + (clamped / 100) * 228).round();
    final monoDpi = (150 + (clamped / 100) * 450).round();
    final jpegQuality = (45 + (clamped / 100) * 50).round();

    args.addAll(<String>[
      '-dAutoFilterColorImages=false',
      '-dColorImageFilter=/DCTEncode',
      '-dAutoFilterGrayImages=false',
      '-dGrayImageFilter=/DCTEncode',
      '-dDownsampleColorImages=true',
      '-dColorImageDownsampleType=/Bicubic',
      '-dColorImageResolution=$imageDpi',
      '-dDownsampleGrayImages=true',
      '-dGrayImageDownsampleType=/Bicubic',
      '-dGrayImageResolution=$imageDpi',
      '-dDownsampleMonoImages=true',
      '-dMonoImageDownsampleType=/Subsample',
      '-dMonoImageResolution=$monoDpi',
      '-dJPEGQ=$jpegQuality',
    ]);
    return args;
  }
}

class CompressionEstimate {
  const CompressionEstimate({
    required this.outputBytes,
    required this.lowerBytes,
    required this.upperBytes,
    required this.savedRatio,
    required this.confidence,
  });

  final int outputBytes;
  final int lowerBytes;
  final int upperBytes;
  final double savedRatio;
  final String confidence;
}

class CompressionResult {
  const CompressionResult({
    required this.inputPath,
    required this.outputPath,
    required this.inputBytes,
    required this.outputBytes,
  });

  final String inputPath;
  final String outputPath;
  final int inputBytes;
  final int outputBytes;

  int get savedBytes => inputBytes - outputBytes;

  double get savedRatio {
    if (inputBytes == 0) {
      return 0;
    }
    return savedBytes / inputBytes;
  }
}

enum CompressionPhase { preparing, processing, finalizing }

class CompressionProgress {
  const CompressionProgress({
    required this.phase,
    this.currentPage = 0,
    this.totalPages,
    this.message,
  });

  final CompressionPhase phase;
  final int currentPage;
  final int? totalPages;
  final String? message;

  double? get fraction {
    final total = totalPages;
    if (phase == CompressionPhase.preparing) {
      return 0;
    }
    if (phase == CompressionPhase.finalizing) {
      return 1;
    }
    if (total == null || total <= 0) {
      return null;
    }
    return (currentPage / total).clamp(0, 1).toDouble();
  }

  String get displayText {
    final total = totalPages;
    if (phase == CompressionPhase.preparing) {
      return '准备压缩';
    }
    if (phase == CompressionPhase.finalizing) {
      return '写入文件';
    }
    if (total != null && total > 0 && currentPage > 0) {
      return '第 $currentPage / $total 页';
    }
    return message ?? '处理中';
  }
}

typedef CompressionProgressCallback =
    void Function(CompressionProgress progress);

class GhostscriptBundle {
  const GhostscriptBundle({
    required this.root,
    required this.executable,
    required this.environment,
  });

  final String root;
  final String executable;
  final Map<String, String> environment;
}

class PdfCompressionException implements Exception {
  const PdfCompressionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PdfCompressionService {
  const PdfCompressionService();

  Future<CompressionResult> compress({
    required String inputPath,
    required String outputPath,
    CompressionPreset? preset,
    CompressionOptions? options,
    int? pageCount,
    CompressionProgressCallback? onProgress,
  }) async {
    final resolvedOptions =
        options ?? CompressionOptions.preset(preset ?? CompressionPreset.ebook);
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw const PdfCompressionException('找不到输入 PDF。');
    }

    final normalizedOutputPath = ensurePdfExtension(outputPath);
    if (samePath(inputPath, normalizedOutputPath)) {
      throw const PdfCompressionException('输出路径不能和原文件相同。');
    }

    final outputFile = File(normalizedOutputPath);
    final outputParent = outputFile.parent;
    if (!await outputParent.exists()) {
      await outputParent.create(recursive: true);
    }

    final ghostscript = await resolveGhostscriptBundle();
    final inputBytes = await inputFile.length();
    onProgress?.call(
      CompressionProgress(
        phase: CompressionPhase.preparing,
        totalPages: pageCount,
      ),
    );

    final stderrLines = <String>[];
    final stdoutLines = <String>[];
    final parser = _GhostscriptProgressParser(
      fallbackTotalPages: pageCount,
      onProgress: onProgress,
    );
    final process = await Process.start(
      ghostscript.executable,
      <String>[
        '-sDEVICE=pdfwrite',
        ...resolvedOptions.toGhostscriptArgs(),
        '-dNOPAUSE',
        '-dBATCH',
        '-sOutputFile=$normalizedOutputPath',
        inputPath,
      ],
      environment: ghostscript.environment,
      workingDirectory: ghostscript.root,
    );
    final stdoutDone = process.stdout
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdoutLines.add(line);
          parser.parse(line);
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrLines.add(line);
          parser.parse(line);
        })
        .asFuture<void>();
    final exitCode = await process.exitCode;
    await Future.wait<void>([stdoutDone, stderrDone]);

    if (exitCode != 0) {
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      final details = [
        stderrLines.join('\n').trim(),
        stdoutLines.join('\n').trim(),
      ].where((line) => line.isNotEmpty).join('\n');
      throw PdfCompressionException(
        details.isEmpty ? 'PDF 压缩失败。' : 'PDF 压缩失败：\n$details',
      );
    }

    if (!await outputFile.exists()) {
      throw const PdfCompressionException('压缩命令执行完成，但没有生成输出文件。');
    }

    onProgress?.call(
      CompressionProgress(
        phase: CompressionPhase.finalizing,
        currentPage: parser.currentPage,
        totalPages: parser.totalPages ?? pageCount,
      ),
    );

    final outputBytes = await outputFile.length();
    return CompressionResult(
      inputPath: inputPath,
      outputPath: normalizedOutputPath,
      inputBytes: inputBytes,
      outputBytes: outputBytes,
    );
  }

  Future<GhostscriptBundle> resolveGhostscriptBundle() async {
    if (Platform.isMacOS) {
      return _resolveMacOSBundle();
    }
    if (Platform.isWindows) {
      return _resolveWindowsBundle();
    }
    throw const PdfCompressionException('当前版本只支持 macOS 和 Windows。');
  }

  Future<GhostscriptBundle> _resolveMacOSBundle() async {
    for (final root in _macOSCandidateRoots()) {
      final executable = p.join(root, 'bin', 'gs');
      if (await File(executable).exists()) {
        final share = p.join(root, 'share', 'ghostscript');
        return GhostscriptBundle(
          root: root,
          executable: executable,
          environment: <String, String>{
            'GS_LIB': <String>[
              p.join(share, 'Resource', 'Init'),
              p.join(share, 'lib'),
              p.join(share, 'Resource', 'Font'),
              p.join(share, 'fonts'),
            ].join(':'),
            'DYLD_LIBRARY_PATH': p.join(root, 'lib'),
          },
        );
      }
    }
    throw const PdfCompressionException('找不到随应用打包的 Ghostscript。');
  }

  Future<GhostscriptBundle> _resolveWindowsBundle() async {
    for (final root in _windowsCandidateRoots()) {
      final executable = p.join(root, 'bin', 'gswin64c.exe');
      if (await File(executable).exists()) {
        return GhostscriptBundle(
          root: root,
          executable: executable,
          environment: <String, String>{
            'GS_LIB': <String>[
              p.join(root, 'lib'),
              p.join(root, 'Resource', 'Init'),
              p.join(root, 'Resource', 'Font'),
              p.join(root, 'iccprofiles'),
            ].join(';'),
          },
        );
      }
    }
    throw const PdfCompressionException('找不到随应用打包的 Ghostscript。');
  }

  List<String> _macOSCandidateRoots() {
    final executableDir = p.dirname(Platform.resolvedExecutable);
    final contentsDir = p.basename(executableDir) == 'MacOS'
        ? p.dirname(executableDir)
        : executableDir;
    return <String>[
      p.join(contentsDir, 'Resources', 'ghostscript'),
      p.join(
        contentsDir,
        'Frameworks',
        'App.framework',
        'Resources',
        'flutter_assets',
        'third_party',
        'ghostscript',
        'macos',
      ),
      p.join(Directory.current.path, 'third_party', 'ghostscript', 'macos'),
    ];
  }

  List<String> _windowsCandidateRoots() {
    final executableDir = p.dirname(Platform.resolvedExecutable);
    return <String>[
      p.join(executableDir, 'ghostscript'),
      p.join(
        executableDir,
        'data',
        'flutter_assets',
        'third_party',
        'ghostscript',
        'windows',
      ),
      p.join(Directory.current.path, 'third_party', 'ghostscript', 'windows'),
    ];
  }
}

class _GhostscriptProgressParser {
  _GhostscriptProgressParser({
    required this.fallbackTotalPages,
    required this.onProgress,
  });

  final int? fallbackTotalPages;
  final CompressionProgressCallback? onProgress;
  int? totalPages;
  int currentPage = 0;

  static final _rangePattern = RegExp(
    r'Processing pages\s+\d+\s+through\s+(\d+)',
    caseSensitive: false,
  );
  static final _pagePattern = RegExp(r'Page\s+(\d+)', caseSensitive: false);

  void parse(String line) {
    final rangeMatch = _rangePattern.firstMatch(line);
    if (rangeMatch != null) {
      totalPages = int.tryParse(rangeMatch.group(1) ?? '');
      onProgress?.call(
        CompressionProgress(
          phase: CompressionPhase.processing,
          currentPage: currentPage,
          totalPages: totalPages ?? fallbackTotalPages,
          message: line.trim(),
        ),
      );
      return;
    }

    final pageMatch = _pagePattern.firstMatch(line);
    if (pageMatch == null) {
      return;
    }

    currentPage = int.tryParse(pageMatch.group(1) ?? '') ?? currentPage;
    onProgress?.call(
      CompressionProgress(
        phase: CompressionPhase.processing,
        currentPage: currentPage,
        totalPages: totalPages ?? fallbackTotalPages,
        message: line.trim(),
      ),
    );
  }
}

CompressionEstimate estimateCompression({
  required int inputBytes,
  required CompressionOptions options,
  int? pageCount,
}) {
  var ratio = options.estimatedRatio;

  if (options.grayscale) {
    ratio *= 0.82;
  }

  if (pageCount != null && pageCount > 0) {
    final bytesPerPage = inputBytes / pageCount;
    if (bytesPerPage < 120 * 1024) {
      ratio = ratio.clamp(0.72, 0.95);
    } else if (bytesPerPage > 900 * 1024) {
      ratio *= 0.86;
    }
  }

  ratio = ratio.clamp(0.18, 0.96);
  final outputBytes = (inputBytes * ratio).round();
  final lowerBytes = (outputBytes * 0.82).round();
  final upperBytes = (outputBytes * 1.18).round();
  final savedRatio = inputBytes == 0
      ? 0.0
      : (inputBytes - outputBytes) / inputBytes;
  final confidence = pageCount == null || pageCount == 0
      ? '粗略预计'
      : inputBytes / pageCount < 120 * 1024
      ? '文本型 PDF，压缩空间有限'
      : '按页数和质量估算';

  return CompressionEstimate(
    outputBytes: outputBytes,
    lowerBytes: lowerBytes,
    upperBytes: upperBytes,
    savedRatio: savedRatio,
    confidence: confidence,
  );
}

String defaultOutputPath(String inputPath) {
  final directory = p.dirname(inputPath);
  final baseName = p.basenameWithoutExtension(inputPath);
  return p.join(directory, '${baseName}_compressed.pdf');
}

String ensurePdfExtension(String outputPath) {
  final trimmed = outputPath.trim();
  if (p.extension(trimmed).toLowerCase() == '.pdf') {
    return trimmed;
  }
  return '$trimmed.pdf';
}

bool samePath(String left, String right) {
  final normalizedLeft = p.normalize(p.absolute(left));
  final normalizedRight = p.normalize(p.absolute(right));
  if (Platform.isWindows) {
    return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
  }
  return normalizedLeft == normalizedRight;
}

String formatBytes(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  if (unitIndex == 0) {
    return '$bytes ${units[unitIndex]}';
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
}
