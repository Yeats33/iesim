import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class LpaScannerPage extends StatefulWidget {
  const LpaScannerPage({super.key});

  @override
  State<LpaScannerPage> createState() => _LpaScannerPageState();
}

class _LpaScannerPageState extends State<LpaScannerPage> {
  late final MobileScannerController _controller;
  bool _returning = false;
  bool _analyzingImage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoZoom: true,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_returning) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.trim().isEmpty) continue;
      if (LpaActivation.tryParse(value) == null) {
        if (mounted) setState(() => _error = '识别到了二维码，但它不是有效的 LPA 激活码');
        continue;
      }
      _returning = true;
      unawaited(_controller.stop());
      Navigator.pop(context, value);
      return;
    }
  }

  Future<void> _analyzeImage() async {
    if (_returning || _analyzingImage) return;
    const images = XTypeGroup(
      label: '二维码图片',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
      mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: const [images]);
    if (file == null || !mounted) return;
    setState(() {
      _analyzingImage = true;
      _error = null;
    });
    try {
      final capture = await _controller.analyzeImage(file.path);
      if (!mounted) return;
      if (capture == null || capture.barcodes.isEmpty) {
        setState(() => _error = '图片中没有识别到二维码');
        return;
      }
      _onDetect(capture);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取这张图片，请换一张清晰的二维码截图');
    } finally {
      if (mounted) setState(() => _analyzingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描 eSIM 二维码'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: '从图片识别',
            onPressed: _analyzingImage ? null : _analyzeImage,
            icon: _analyzingImage
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image_search_rounded),
          ),
          IconButton(
            tooltip: '开关闪光灯',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on_rounded),
          ),
          IconButton(
            tooltip: '切换摄像头',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: .62,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: .64),
                  ],
                  stops: const [.58, 1],
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 3),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error ?? '将 LPA:1\$… 二维码放入框内，识别后会先显示预览。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _error == null
                            ? Colors.white
                            : scheme.errorContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _analyzingImage ? null : _analyzeImage,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('从相册或截图识别'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
