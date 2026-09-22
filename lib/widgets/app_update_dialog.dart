import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/update_service.dart';
import '../../config/r.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, required this.info});

  final AppUpdateInfo info;

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      barrierColor: Colors.black54,
      builder: (_) => PopScope(
        canPop: !info.forceUpdate,
        child: AppUpdateDialog(info: info),
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

enum _UpdatePhase { idle, downloading, downloaded, installing, error }

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  StreamSubscription? _sub;

  _UpdatePhase get _phase {
    final s = UpdateService.instance;
    if (s.isDownloading) return _UpdatePhase.downloading;
    if (s.isDownloaded) return _UpdatePhase.downloaded;
    if (s.downloadError.isNotEmpty) return _UpdatePhase.error;
    return _UpdatePhase.idle;
  }

  double get _progress => UpdateService.instance.downloadProgress;
  int get _received => UpdateService.instance.receivedBytes;
  int get _total => UpdateService.instance.totalBytes;
  String get _error => UpdateService.instance.downloadError;
  String get _apkPath => UpdateService.instance.downloadedApkPath;

  bool get _force => widget.info.forceUpdate;

  String get _phaseText {
    final ph = _phase;
    switch (ph) {
      case _UpdatePhase.downloading:
        return 'جاري تنزيل التحديث... ${(_progress * 100).toStringAsFixed(0)}%'
            '  (${_mb(_received)} / ${_mb(_total)} ميجابايت)';
      case _UpdatePhase.downloaded:
        return 'تم التنزيل — اضغط للتثبيت';
      case _UpdatePhase.installing:
        return 'جاري بدء التثبيت...';
      case _UpdatePhase.error:
        return _error;
      case _UpdatePhase.idle:
        return '';
    }
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _sub = UpdateService.instance.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    // بدء التنزيل تلقائياً في الخلفية فور ظهور نافذة التحديث
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!UpdateService.instance.isDownloading && !UpdateService.instance.isDownloaded) {
        _startDownload();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startDownload() {
    UpdateService.instance.startDownloadInBackground(widget.info.apkUrl);
  }

  void _install() {
    if (_apkPath.isNotEmpty) {
      UpdateService.instance.installApk(_apkPath);
    } else {
      _startDownload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App Logo instead of download icon
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: R.image(
                R.splashImgLogo,
                width: 76,
                height: 76,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'تحديث جديد متاح',
              style: TextStyle(
                color: Color(0xFF16151A),
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'الإصدار ${widget.info.latestVersion}'
              '  (${widget.info.currentVersion} ← ${widget.info.latestVersion})',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (widget.info.notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.notes,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.6),
                  ),
                ),
              ),
            ],
            if (_phase != _UpdatePhase.idle && _phase != _UpdatePhase.error) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: _phase == _UpdatePhase.downloading ? _progress : null,
                  minHeight: 8,
                  backgroundColor: Colors.black.withOpacity(0.06),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD54F)), // Gold color bar
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _phaseText,
                style: const TextStyle(color: Colors.black54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
            if (_phase == _UpdatePhase.error) ...[
              const SizedBox(height: 14),
              Text(
                _phaseText,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                if (!_force)
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.black54),
                      child: const Text('لاحقاً'),
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _phase == _UpdatePhase.downloading || _phase == _UpdatePhase.installing
                        ? null
                        : (_phase == _UpdatePhase.downloaded ? _install : _startDownload),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB300), // Gold button
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFFFB300).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                    ),
                    child: Text(
                      switch (_phase) {
                        _UpdatePhase.downloading => 'جاري التنزيل...',
                        _UpdatePhase.downloaded || _UpdatePhase.installing => 'تثبيت',
                        _ => 'تحديث الآن',
                      },
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            if (_force && _phase == _UpdatePhase.idle) ...[
              const SizedBox(height: 10),
              const Text(
                'هذا الإصدار إلزامي ويجب التحديث للمتابعة',
                style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
