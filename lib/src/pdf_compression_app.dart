import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_compression_service.dart';
import 'pdf_inspection_service.dart';

const _pdfTypeGroup = XTypeGroup(label: 'PDF', extensions: <String>['pdf']);

const _ink = Color(0xFF151A17);
const _muted = Color(0xFF6B756F);
const _line = Color(0xFFD9DFDA);
const _paper = Color(0xFFF5F6F1);
const _surface = Color(0xFFFEFFFC);
const _rail = Color(0xFF17201D);
const _accent = Color(0xFF0B7178);
const _accentSoft = Color(0xFFE4F2EF);
const _danger = Color(0xFFB42318);

enum _AppPage { compress, preview }

enum _PreviewTarget { source, compressed }

class PdfCompressionApp extends StatelessWidget {
  const PdfCompressionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文件工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.light,
          surface: _surface,
        ),
        scaffoldBackgroundColor: _paper,
        fontFamily: Platform.isMacOS ? '.AppleSystemUIFont' : null,
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: _accent, width: 1.3),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
      home: const PdfCompressionHome(),
    );
  }
}

class PdfCompressionHome extends StatefulWidget {
  const PdfCompressionHome({super.key});

  @override
  State<PdfCompressionHome> createState() => _PdfCompressionHomeState();
}

class _PdfCompressionHomeState extends State<PdfCompressionHome> {
  final _compressionService = const PdfCompressionService();
  final _inspectionService = const PdfInspectionService();
  final _fileNameController = TextEditingController();

  _AppPage _page = _AppPage.compress;
  _PreviewTarget _previewTarget = _PreviewTarget.source;
  XFile? _inputFile;
  PdfDocumentInfo? _documentInfo;
  String? _outputPath;
  CompressionPreset _preset = CompressionPreset.ebook;
  int _customQuality = 58;
  bool _useCustomQuality = false;
  bool _grayscale = false;
  PdfCompatibility _compatibility = PdfCompatibility.standard14;
  CompressionResult? _lastResult;
  CompressionProgress? _compressionProgress;
  String? _errorMessage;
  bool _isCompressing = false;
  bool _isInspecting = false;
  bool _isPreparingPreview = false;
  String? _previewOutputPath;
  String? _previewOptionsKey;

  @override
  void dispose() {
    _fileNameController.dispose();
    _deletePreviewOutput();
    super.dispose();
  }

  CompressionOptions get _options {
    if (_useCustomQuality) {
      return CompressionOptions.custom(
        quality: _customQuality,
        grayscale: _grayscale,
        compatibility: _compatibility,
      );
    }
    return CompressionOptions.preset(
      _preset,
      grayscale: _grayscale,
      compatibility: _compatibility,
    );
  }

  String get _optionsKey {
    return [
      _useCustomQuality ? 'custom:$_customQuality' : 'preset:${_preset.name}',
      'gray:$_grayscale',
      'compat:${_compatibility.value}',
      'input:${_inputFile?.path ?? ''}',
    ].join('|');
  }

  bool get _hasFreshPreview {
    return _previewOutputPath != null && _previewOptionsKey == _optionsKey;
  }

  CompressionEstimate? get _estimate {
    final info = _documentInfo;
    if (info == null) {
      return null;
    }
    return estimateCompression(
      inputBytes: info.bytes,
      options: _options,
      pageCount: info.pageCount,
    );
  }

  String get _settingsSummary {
    final quality = _useCustomQuality
        ? '自定义 $_customQuality'
        : '${_preset.label} ${_preset.qualityValue}';
    final color = _grayscale ? '灰度' : '彩色';
    return '$quality · $color · PDF ${_compatibility.value}';
  }

  bool get _canCompress {
    return !_isCompressing &&
        !_isInspecting &&
        _inputFile != null &&
        _documentInfo != null &&
        (_outputPath?.trim().isNotEmpty ?? false) &&
        _fileNameController.text.trim().isNotEmpty;
  }

  Future<void> _selectPdf() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_pdfTypeGroup],
      confirmButtonText: '选择 PDF',
    );
    if (file == null) {
      return;
    }

    final inputPath = file.path;
    final outputPath = defaultOutputPath(inputPath);
    _deletePreviewOutput();
    if (!mounted) {
      return;
    }
    setState(() {
      _inputFile = file;
      _documentInfo = null;
      _outputPath = outputPath;
      _fileNameController.text = p.basename(outputPath);
      _lastResult = null;
      _compressionProgress = null;
      _errorMessage = null;
      _previewOutputPath = null;
      _previewOptionsKey = null;
      _previewTarget = _PreviewTarget.source;
      _isInspecting = true;
    });

    try {
      final info = await _inspectionService.inspect(inputPath);
      if (!mounted || _inputFile?.path != inputPath) {
        return;
      }
      setState(() => _documentInfo = info);
    } on PdfInspectionException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = '读取 PDF 参数失败：$error');
    } finally {
      if (mounted && _inputFile?.path == inputPath) {
        setState(() => _isInspecting = false);
      }
    }
  }

  Future<void> _chooseSaveLocation() async {
    final inputPath = _inputFile?.path;
    final suggestedName = _safeOutputFileName();
    final initialDirectory = _outputPath != null
        ? p.dirname(_outputPath!)
        : inputPath == null
        ? null
        : p.dirname(inputPath);

    final location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_pdfTypeGroup],
      initialDirectory: initialDirectory,
      suggestedName: suggestedName,
      confirmButtonText: '保存',
      canCreateDirectories: true,
    );
    if (location == null || !mounted) {
      return;
    }

    final normalizedPath = ensurePdfExtension(location.path);
    setState(() {
      _outputPath = normalizedPath;
      _fileNameController.text = p.basename(normalizedPath);
      _lastResult = null;
      _compressionProgress = null;
      _errorMessage = null;
    });
  }

  void _updateOutputFileName(String value) {
    final currentOutput = _outputPath;
    final inputPath = _inputFile?.path;
    if (currentOutput == null && inputPath == null) {
      return;
    }
    final directory = currentOutput == null
        ? p.dirname(inputPath!)
        : p.dirname(currentOutput);
    setState(() {
      _outputPath = p.join(directory, ensurePdfExtension(value));
      _lastResult = null;
      _compressionProgress = null;
      _errorMessage = null;
    });
  }

  void _invalidatePreview() {
    _deletePreviewOutput();
    _previewOutputPath = null;
    _previewOptionsKey = null;
  }

  void _deletePreviewOutput() {
    final path = _previewOutputPath;
    if (path == null) {
      return;
    }
    File(path).delete().ignore();
  }

  Future<void> _prepareQualityPreview() async {
    final inputPath = _inputFile?.path;
    if (inputPath == null || _isPreparingPreview) {
      return;
    }
    setState(() {
      _isPreparingPreview = true;
      _errorMessage = null;
    });

    try {
      final previewDir = await Directory.systemTemp.createTemp(
        'file_tools_pdf_preview_',
      );
      final previewPath = p.join(
        previewDir.path,
        '${p.basenameWithoutExtension(inputPath)}_preview.pdf',
      );
      final result = await _compressionService.compress(
        inputPath: inputPath,
        outputPath: previewPath,
        options: _options,
        pageCount: _documentInfo?.pageCount,
      );
      if (!mounted) {
        return;
      }
      _deletePreviewOutput();
      setState(() {
        _previewOutputPath = result.outputPath;
        _previewOptionsKey = _optionsKey;
        _previewTarget = _PreviewTarget.compressed;
      });
    } on PdfCompressionException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = '生成预览失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isPreparingPreview = false);
      }
    }
  }

  Future<void> _compress() async {
    final inputPath = _inputFile?.path;
    final outputPath = _outputPath;
    if (inputPath == null || outputPath == null) {
      return;
    }

    setState(() {
      _isCompressing = true;
      _compressionProgress = CompressionProgress(
        phase: CompressionPhase.preparing,
        totalPages: _documentInfo?.pageCount,
      );
      _errorMessage = null;
      _lastResult = null;
    });

    try {
      final result = await _compressionService.compress(
        inputPath: inputPath,
        outputPath: outputPath,
        options: _options,
        pageCount: _documentInfo?.pageCount,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() => _compressionProgress = progress);
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResult = result;
        _outputPath = result.outputPath;
        _fileNameController.text = p.basename(result.outputPath);
      });
      try {
        await _revealFile(result.outputPath);
      } catch (error) {
        if (!mounted) {
          return;
        }
        setState(() => _errorMessage = '压缩完成，但打开文件夹失败：$error');
      }
    } on PdfCompressionException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = '压缩失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isCompressing = false;
          _compressionProgress = null;
        });
      }
    }
  }

  Future<void> _revealFile(String filePath) async {
    if (Platform.isMacOS) {
      await Process.run('open', <String>['-R', filePath]);
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>['/select,$filePath']);
    }
  }

  String _safeOutputFileName() {
    final text = _fileNameController.text.trim();
    if (text.isNotEmpty) {
      return ensurePdfExtension(text);
    }
    final inputPath = _inputFile?.path;
    return inputPath == null
        ? 'compressed.pdf'
        : p.basename(defaultOutputPath(inputPath));
  }

  void _setPreset(CompressionPreset preset) {
    setState(() {
      _preset = preset;
      _customQuality = preset.qualityValue;
      _useCustomQuality = false;
      _lastResult = null;
      _compressionProgress = null;
      _errorMessage = null;
      _invalidatePreview();
    });
  }

  void _setCustomQuality(double quality) {
    setState(() {
      _customQuality = quality.round();
      _useCustomQuality = true;
      _lastResult = null;
      _compressionProgress = null;
      _errorMessage = null;
      _invalidatePreview();
    });
  }

  void _setGrayscale(bool value) {
    setState(() {
      _grayscale = value;
      _lastResult = null;
      _compressionProgress = null;
      _invalidatePreview();
    });
  }

  void _setCompatibility(PdfCompatibility value) {
    setState(() {
      _compatibility = value;
      _lastResult = null;
      _compressionProgress = null;
      _invalidatePreview();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = _ShellState(
      page: _page,
      inputPath: _inputFile?.path,
      documentInfo: _documentInfo,
      isInspecting: _isInspecting,
      outputPath: _outputPath,
      estimate: _estimate,
      result: _lastResult,
      errorMessage: _errorMessage,
      compressionProgress: _compressionProgress,
      preset: _preset,
      useCustomQuality: _useCustomQuality,
      customQuality: _customQuality,
      grayscale: _grayscale,
      compatibility: _compatibility,
      previewTarget: _previewTarget,
      previewOutputPath: _previewOutputPath,
      hasFreshPreview: _hasFreshPreview,
      isPreparingPreview: _isPreparingPreview,
      isCompressing: _isCompressing,
      canCompress: _canCompress,
      settingsSummary: _settingsSummary,
    );

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _Sidebar(
              state: shell,
              onPageChanged: (page) => setState(() => _page = page),
            ),
            Expanded(
              child: _page == _AppPage.compress
                  ? _CompressPage(
                      state: shell,
                      fileNameController: _fileNameController,
                      onSelectPdf: _selectPdf,
                      onFileNameChanged: _updateOutputFileName,
                      onChooseSaveLocation: _chooseSaveLocation,
                      onPresetChanged: _setPreset,
                      onCustomQualityChanged: _setCustomQuality,
                      onGrayscaleChanged: _setGrayscale,
                      onCompatibilityChanged: _setCompatibility,
                      onCompress: _compress,
                      onOpenPreview: () {
                        setState(() {
                          _page = _AppPage.preview;
                          _previewTarget = _PreviewTarget.source;
                        });
                      },
                    )
                  : _PreviewPage(
                      state: shell,
                      onSelectPdf: _selectPdf,
                      onTargetChanged: (target) {
                        setState(() => _previewTarget = target);
                      },
                      onPreparePreview: _prepareQualityPreview,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellState {
  const _ShellState({
    required this.page,
    required this.inputPath,
    required this.documentInfo,
    required this.isInspecting,
    required this.outputPath,
    required this.estimate,
    required this.result,
    required this.errorMessage,
    required this.compressionProgress,
    required this.preset,
    required this.useCustomQuality,
    required this.customQuality,
    required this.grayscale,
    required this.compatibility,
    required this.previewTarget,
    required this.previewOutputPath,
    required this.hasFreshPreview,
    required this.isPreparingPreview,
    required this.isCompressing,
    required this.canCompress,
    required this.settingsSummary,
  });

  final _AppPage page;
  final String? inputPath;
  final PdfDocumentInfo? documentInfo;
  final bool isInspecting;
  final String? outputPath;
  final CompressionEstimate? estimate;
  final CompressionResult? result;
  final String? errorMessage;
  final CompressionProgress? compressionProgress;
  final CompressionPreset preset;
  final bool useCustomQuality;
  final int customQuality;
  final bool grayscale;
  final PdfCompatibility compatibility;
  final _PreviewTarget previewTarget;
  final String? previewOutputPath;
  final bool hasFreshPreview;
  final bool isPreparingPreview;
  final bool isCompressing;
  final bool canCompress;
  final String settingsSummary;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state, required this.onPageChanged});

  final _ShellState state;
  final ValueChanged<_AppPage> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      color: _rail,
      padding: const EdgeInsets.fromLTRB(16, 20, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  'assets/icon/app_icon_1024.png',
                  width: 32,
                  height: 32,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '文件工具',
                style: TextStyle(
                  color: Color(0xFFF5F7F3),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SideButton(
            icon: Icons.compress,
            label: '压缩',
            active: state.page == _AppPage.compress,
            onTap: () => onPageChanged(_AppPage.compress),
          ),
          const SizedBox(height: 6),
          _SideButton(
            icon: Icons.chrome_reader_mode_outlined,
            label: '预览',
            active: state.page == _AppPage.preview,
            onTap: () => onPageChanged(_AppPage.preview),
          ),
          const SizedBox(height: 18),
          const Divider(color: Color(0xFF30403A), height: 1),
          const SizedBox(height: 16),
          _SideButton(
            icon: Icons.image_outlined,
            label: '图片',
            disabled: true,
            onTap: () {},
          ),
          const SizedBox(height: 6),
          _SideButton(
            icon: Icons.more_horiz,
            label: '更多',
            disabled: true,
            onTap: () {},
          ),
          const Spacer(),
          if (state.documentInfo != null)
            _RailFileSummary(info: state.documentInfo!)
          else
            const Text(
              '本地处理\n不上载文件',
              style: TextStyle(
                color: Color(0xFFB9C5BF),
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? const Color(0xFF71807A)
        : active
        ? const Color(0xFFFFFFFF)
        : const Color(0xFFC6D0CB);
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF264B47) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (disabled)
              const Text(
                'soon',
                style: TextStyle(color: Color(0xFF71807A), fontSize: 10.5),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailFileSummary extends StatelessWidget {
  const _RailFileSummary({required this.info});

  final PdfDocumentInfo info;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(color: Color(0xFFC6D0CB), fontSize: 11.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF5F7F3),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text('${info.pageCountText} · ${info.sizeText}'),
        ],
      ),
    );
  }
}

class _CompressPage extends StatelessWidget {
  const _CompressPage({
    required this.state,
    required this.fileNameController,
    required this.onSelectPdf,
    required this.onFileNameChanged,
    required this.onChooseSaveLocation,
    required this.onPresetChanged,
    required this.onCustomQualityChanged,
    required this.onGrayscaleChanged,
    required this.onCompatibilityChanged,
    required this.onCompress,
    required this.onOpenPreview,
  });

  final _ShellState state;
  final TextEditingController fileNameController;
  final VoidCallback onSelectPdf;
  final ValueChanged<String> onFileNameChanged;
  final VoidCallback onChooseSaveLocation;
  final ValueChanged<CompressionPreset> onPresetChanged;
  final ValueChanged<double> onCustomQualityChanged;
  final ValueChanged<bool> onGrayscaleChanged;
  final ValueChanged<PdfCompatibility> onCompatibilityChanged;
  final VoidCallback onCompress;
  final VoidCallback onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            title: 'PDF 压缩',
            action: FilledButton.icon(
              onPressed: onSelectPdf,
              icon: const Icon(Icons.upload_file, size: 17),
              label: const Text('选择 PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: _PrimaryWorkSurface(
                    state: state,
                    fileNameController: fileNameController,
                    onSelectPdf: onSelectPdf,
                    onFileNameChanged: onFileNameChanged,
                    onChooseSaveLocation: onChooseSaveLocation,
                    onPresetChanged: onPresetChanged,
                    onCustomQualityChanged: onCustomQualityChanged,
                    onGrayscaleChanged: onGrayscaleChanged,
                    onCompatibilityChanged: onCompatibilityChanged,
                    onOpenPreview: onOpenPreview,
                  ),
                ),
                const SizedBox(width: 18),
                SizedBox(
                  width: 272,
                  child: _ResultColumn(
                    state: state,
                    onCompress: onCompress,
                    onOpenPreview: onOpenPreview,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _LicenseNotice(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 26,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Spacer(),
        action,
      ],
    );
  }
}

class _PrimaryWorkSurface extends StatelessWidget {
  const _PrimaryWorkSurface({
    required this.state,
    required this.fileNameController,
    required this.onSelectPdf,
    required this.onFileNameChanged,
    required this.onChooseSaveLocation,
    required this.onPresetChanged,
    required this.onCustomQualityChanged,
    required this.onGrayscaleChanged,
    required this.onCompatibilityChanged,
    required this.onOpenPreview,
  });

  final _ShellState state;
  final TextEditingController fileNameController;
  final VoidCallback onSelectPdf;
  final ValueChanged<String> onFileNameChanged;
  final VoidCallback onChooseSaveLocation;
  final ValueChanged<CompressionPreset> onPresetChanged;
  final ValueChanged<double> onCustomQualityChanged;
  final ValueChanged<bool> onGrayscaleChanged;
  final ValueChanged<PdfCompatibility> onCompatibilityChanged;
  final VoidCallback onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FileStrip(state: state, onSelectPdf: onSelectPdf),
          const SizedBox(height: 12),
          _TinyParams(info: state.documentInfo, isLoading: state.isInspecting),
          const SizedBox(height: 18),
          _OutputRow(
            controller: fileNameController,
            outputPath: state.outputPath,
            onChanged: onFileNameChanged,
            onChooseSaveLocation: onChooseSaveLocation,
          ),
          const SizedBox(height: 22),
          _QualityControls(
            state: state,
            onPresetChanged: onPresetChanged,
            onCustomQualityChanged: onCustomQualityChanged,
          ),
          const SizedBox(height: 18),
          _CompactOptions(
            state: state,
            onGrayscaleChanged: onGrayscaleChanged,
            onCompatibilityChanged: onCompatibilityChanged,
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: state.inputPath == null ? null : onOpenPreview,
              icon: const Icon(Icons.chrome_reader_mode_outlined, size: 17),
              label: const Text('打开预览'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileStrip extends StatelessWidget {
  const _FileStrip({required this.state, required this.onSelectPdf});

  final _ShellState state;
  final VoidCallback onSelectPdf;

  @override
  Widget build(BuildContext context) {
    final info = state.documentInfo;
    final path = state.inputPath;
    if (path == null) {
      return InkWell(
        onTap: onSelectPdf,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _line),
          ),
          child: const Row(
            children: [
              _PdfMark(),
              SizedBox(width: 14),
              Text(
                '选择 PDF',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              Icon(Icons.arrow_forward, color: _muted),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          const _PdfMark(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  path,
                  maxLines: 1,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (state.isInspecting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              info?.sizeText ?? '-',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onSelectPdf,
            icon: const Icon(Icons.swap_horiz, size: 18),
            tooltip: '更换',
            color: _accent,
          ),
        ],
      ),
    );
  }
}

class _PdfMark extends StatelessWidget {
  const _PdfMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.picture_as_pdf, color: _accent, size: 21),
    );
  }
}

class _TinyParams extends StatelessWidget {
  const _TinyParams({required this.info, required this.isLoading});

  final PdfDocumentInfo? info;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _MicroLine(text: '读取参数中');
    }
    if (info == null) {
      return const _MicroLine(text: '页数 / 尺寸 / 类型');
    }
    final resolvedInfo = info!;
    final items = [
      resolvedInfo.pageCountText,
      resolvedInfo.pageSizeText,
      resolvedInfo.documentKind,
      resolvedInfo.version == null ? 'PDF' : 'PDF ${resolvedInfo.version}',
      resolvedInfo.isEncrypted ? '加密' : '未加密',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) => _ParamChip(text: item)).toList(),
    );
  }
}

class _MicroLine extends StatelessWidget {
  const _MicroLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: _muted, fontSize: 12));
  }
}

class _ParamChip extends StatelessWidget {
  const _ParamChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFED),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OutputRow extends StatelessWidget {
  const _OutputRow({
    required this.controller,
    required this.outputPath,
    required this.onChanged,
    required this.onChooseSaveLocation,
  });

  final TextEditingController controller;
  final String? outputPath;
  final ValueChanged<String> onChanged;
  final VoidCallback onChooseSaveLocation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: const InputDecoration(labelText: '文件名'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: onChooseSaveLocation,
              icon: const Icon(Icons.folder_open, size: 19),
              tooltip: '保存位置',
              color: _accent,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          outputPath ?? '保存路径',
          maxLines: 1,
          style: const TextStyle(color: _muted, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _QualityControls extends StatelessWidget {
  const _QualityControls({
    required this.state,
    required this.onPresetChanged,
    required this.onCustomQualityChanged,
  });

  final _ShellState state;
  final ValueChanged<CompressionPreset> onPresetChanged;
  final ValueChanged<double> onCustomQualityChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: CompressionPreset.values.map((preset) {
            final active = !state.useCustomQuality && state.preset == preset;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: preset == CompressionPreset.values.last ? 0 : 8,
                ),
                child: _QualityButton(
                  label: preset.label,
                  active: active,
                  onTap: () => onPresetChanged(preset),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(
            color: state.useCustomQuality ? _surface : Colors.transparent,
            border: Border.all(color: state.useCustomQuality ? _accent : _line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    state.useCustomQuality ? '自定义' : state.preset.label,
                    style: TextStyle(
                      color: state.useCustomQuality ? _accent : _ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${state.customQuality}',
                    style: TextStyle(
                      color: state.useCustomQuality ? _accent : _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Slider(
                value: state.customQuality.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '${state.customQuality}',
                onChanged: onCustomQualityChanged,
                activeColor: _accent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? Colors.white : _ink,
        backgroundColor: active ? _accent : _surface,
        side: BorderSide(color: active ? _accent : _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _CompactOptions extends StatelessWidget {
  const _CompactOptions({
    required this.state,
    required this.onGrayscaleChanged,
    required this.onCompatibilityChanged,
  });

  final _ShellState state;
  final ValueChanged<bool> onGrayscaleChanged;
  final ValueChanged<PdfCompatibility> onCompatibilityChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilterChip(
          label: const Text('灰度'),
          selected: state.grayscale,
          onSelected: onGrayscaleChanged,
          selectedColor: _accentSoft,
          checkmarkColor: _accent,
        ),
        const SizedBox(width: 8),
        SegmentedButton<PdfCompatibility>(
          segments: PdfCompatibility.values.map((item) {
            return ButtonSegment(value: item, label: Text(item.value));
          }).toList(),
          selected: {state.compatibility},
          onSelectionChanged: (values) => onCompatibilityChanged(values.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ],
    );
  }
}

class _ResultColumn extends StatelessWidget {
  const _ResultColumn({
    required this.state,
    required this.onCompress,
    required this.onOpenPreview,
  });

  final _ShellState state;
  final VoidCallback onCompress;
  final VoidCallback onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final estimate = state.estimate;
    final result = state.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '预计',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                estimate == null ? '-' : formatBytes(estimate.outputBytes),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (estimate != null) ...[
                const SizedBox(height: 8),
                Text(
                  '约减少 ${(estimate.savedRatio * 100).clamp(0, 99).toStringAsFixed(0)}%',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: state.canCompress ? onCompress : null,
          icon: state.isCompressing
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow, size: 19),
          label: Text(state.isCompressing ? '压缩中' : '开始压缩'),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFD6DBD6),
            disabledForegroundColor: const Color(0xFF8A948E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
        if (state.isCompressing) ...[
          const SizedBox(height: 10),
          _CompressionProgressView(progress: state.compressionProgress),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: state.inputPath == null ? null : onOpenPreview,
          icon: const Icon(Icons.visibility_outlined, size: 17),
          label: const Text('预览'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          _StatusBox(
            color: const Color(0xFF067647),
            background: const Color(0xFFEFFAF4),
            icon: Icons.check_circle_outline,
            text:
                '${formatBytes(result.inputBytes)} -> ${formatBytes(result.outputBytes)}\n减少 ${formatBytes(result.savedBytes.clamp(0, result.inputBytes))}',
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 10),
          _StatusBox(
            color: _danger,
            background: const Color(0xFFFFF1F0),
            icon: Icons.error_outline,
            text: state.errorMessage!,
          ),
        ],
      ],
    );
  }
}

class _CompressionProgressView extends StatelessWidget {
  const _CompressionProgressView({required this.progress});

  final CompressionProgress? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress?.fraction;
    final text = progress?.displayText ?? '处理中';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: value,
            minHeight: 5,
            color: _accent,
            backgroundColor: const Color(0xFFE6ECE8),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    required this.state,
    required this.onSelectPdf,
    required this.onTargetChanged,
    required this.onPreparePreview,
  });

  final _ShellState state;
  final VoidCallback onSelectPdf;
  final ValueChanged<_PreviewTarget> onTargetChanged;
  final VoidCallback onPreparePreview;

  @override
  Widget build(BuildContext context) {
    final path = switch (state.previewTarget) {
      _PreviewTarget.source => state.inputPath,
      _PreviewTarget.compressed =>
        state.hasFreshPreview ? state.previewOutputPath : null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        children: [
          _PreviewToolbar(
            state: state,
            onSelectPdf: onSelectPdf,
            onTargetChanged: onTargetChanged,
            onPreparePreview: onPreparePreview,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE7EAE6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _line),
              ),
              clipBehavior: Clip.antiAlias,
              child: path == null
                  ? _PreviewEmpty(
                      state: state,
                      onPreparePreview: onPreparePreview,
                    )
                  : PdfViewer.file(
                      path,
                      key: ValueKey('${state.previewTarget.name}:$path'),
                      params: const PdfViewerParams(
                        textSelectionParams: PdfTextSelectionParams(
                          enabled: false,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewToolbar extends StatelessWidget {
  const _PreviewToolbar({
    required this.state,
    required this.onSelectPdf,
    required this.onTargetChanged,
    required this.onPreparePreview,
  });

  final _ShellState state;
  final VoidCallback onSelectPdf;
  final ValueChanged<_PreviewTarget> onTargetChanged;
  final VoidCallback onPreparePreview;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          '预览',
          style: TextStyle(
            color: _ink,
            fontSize: 26,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 18),
        SegmentedButton<_PreviewTarget>(
          segments: const [
            ButtonSegment(value: _PreviewTarget.source, label: Text('源文件')),
            ButtonSegment(
              value: _PreviewTarget.compressed,
              label: Text('压缩预览'),
            ),
          ],
          selected: {state.previewTarget},
          onSelectionChanged: (values) => onTargetChanged(values.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        if (state.previewTarget == _PreviewTarget.compressed) ...[
          const SizedBox(width: 10),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ParamChip(text: '使用：${state.settingsSummary}'),
                  if (!state.hasFreshPreview) ...[
                    const SizedBox(width: 6),
                    const _ParamChip(text: '需生成'),
                  ],
                ],
              ),
            ),
          ),
        ],
        const Spacer(),
        if (state.previewTarget == _PreviewTarget.compressed)
          OutlinedButton.icon(
            onPressed: state.inputPath == null || state.isPreparingPreview
                ? null
                : onPreparePreview,
            icon: state.isPreparingPreview
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high, size: 17),
            label: Text(state.isPreparingPreview ? '生成中' : '按当前设置生成'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: const BorderSide(color: _line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        const SizedBox(width: 8),
        IconButton.outlined(
          onPressed: onSelectPdf,
          icon: const Icon(Icons.upload_file, size: 18),
          tooltip: '选择 PDF',
          color: _accent,
        ),
      ],
    );
  }
}

class _PreviewEmpty extends StatelessWidget {
  const _PreviewEmpty({required this.state, required this.onPreparePreview});

  final _ShellState state;
  final VoidCallback onPreparePreview;

  @override
  Widget build(BuildContext context) {
    if (state.previewTarget == _PreviewTarget.compressed &&
        state.inputPath != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ParamChip(text: '使用：${state.settingsSummary}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.isPreparingPreview ? null : onPreparePreview,
              icon: state.isPreparingPreview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high, size: 17),
              label: Text(state.isPreparingPreview ? '生成中' : '按当前设置生成预览'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const Center(
      child: Text(
        '选择 PDF',
        style: TextStyle(
          color: _muted,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  const _StatusBox({
    required this.color,
    required this.background,
    required this.icon,
    required this.text,
  });

  final Color color;
  final Color background;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseNotice extends StatelessWidget {
  const _LicenseNotice();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Ghostscript 10.07.1 · 预计大小仅供参考 · 分发前确认 AGPL 或商业授权',
      style: TextStyle(color: Color(0xFF7A847F), fontSize: 11),
    );
  }
}
