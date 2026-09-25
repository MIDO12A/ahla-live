import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final String latestVersion;
  final int buildNumber;
  final String apkUrl;
  final String notesAr;
  final String notesEn;
  final bool forceUpdate;
  final String currentVersion;
  final int currentBuild;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.buildNumber,
    required this.apkUrl,
    required this.notesAr,
    required this.notesEn,
    required this.forceUpdate,
    required this.currentVersion,
    required this.currentBuild,
  });

  String get notes => Platform.localeName.startsWith('ar') ? notesAr : notesEn;
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _docPath = 'app_config/app_update';
  static const _buildInfoUrl =
      'https://github.com/MIDO12A/ahla-live/releases/latest/download/build_info.json';
  static const _apkUrlArm64 =
      'https://github.com/MIDO12A/ahla-live/releases/latest/download/zero-app.apk';
  static const _apkUrlArm32 =
      'https://github.com/MIDO12A/ahla-live/releases/latest/download/zero-app-arm32.apk';
  static const _apkUrlX8664 =
      'https://github.com/MIDO12A/ahla-live/releases/latest/download/zero-app-x86_64.apk';
  static const _githubApiLatestUrl =
      'https://api.github.com/repos/MIDO12A/ahla-live/releases/latest';

  /// Picks the APK asset matching the device ABI (CI publishes split APKs).
  Future<String> apkUrlForDevice() async {
    try {
      final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      if (abis.contains('arm64-v8a')) return _apkUrlArm64;
      if (abis.contains('x86_64')) return _apkUrlX8664;
      if (abis.contains('armeabi-v7a')) return _apkUrlArm32;
    } catch (_) {}
    return _apkUrlArm64;
  }

  /// Checks for a published update. GitHub Releases is the primary source
  /// (no secrets needed - CI uploads build_info.json next to the APK on every
  /// push); the Firestore doc is kept as a legacy fallback.
  Future<AppUpdateInfo?> checkForUpdate({bool throwOnError = false}) async {
    final info = await PackageInfo.fromPlatform();
    try {
      final ghUpdate = await _checkGithub(info);
      if (ghUpdate != null) return ghUpdate;
      return await _checkFirestore(info);
    } catch (e) {
      if (throwOnError) rethrow;
      return null;
    }
  }

  Future<AppUpdateInfo?> _checkGithub(PackageInfo info) async {
    try {
      // 1. Try direct build_info.json from latest release
      final dio = Dio();
      Response<String>? res;
      try {
        res = await dio.get<String>(
          '$_buildInfoUrl?t=${DateTime.now().millisecondsSinceEpoch}',
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 500,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.119 Mobile Safari/537.36',
            },
          ),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}

      Map<String, dynamic>? d;
      if (res != null && res.statusCode == 200 && res.data != null) {
        try {
          d = jsonDecode(res.data!) as Map<String, dynamic>;
        } catch (_) {}
      }

      // 2. If direct build_info not found, try GitHub API releases
      if (d == null) {
        try {
          final apiRes = await dio.get<Map<String, dynamic>>(
            _githubApiLatestUrl,
            options: Options(
              validateStatus: (status) => status != null && status < 500,
              headers: {'Accept': 'application/vnd.github.v3+json'},
            ),
          ).timeout(const Duration(seconds: 8));

          if (apiRes.statusCode == 200 && apiRes.data != null) {
            final tagName = (apiRes.data!['tag_name'] ?? '').toString();
            final cleaned = tagName.replaceFirst('v', '');
            final parts = cleaned.split('+');
            final version = parts[0];
            final buildNum = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : _versionCode(version);
            if (version.isNotEmpty) {
              d = {'version': version, 'build_number': buildNum > 0 ? buildNum : 1};
            }
          }
        } catch (_) {}
      }

      if (d == null) return null;

      final latestVersion = (d['version'] ?? '').toString().trim();
      final latestBuild = int.tryParse('${d['build_number'] ?? ''}') ?? _versionCode(latestVersion);
      if (latestVersion.isEmpty) return null;

      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      if (!_isNewer(
        remoteVersion: latestVersion,
        remoteBuild: latestBuild,
        currentVersion: info.version,
        currentBuild: currentBuild,
      )) {
        return null;
      }
      return AppUpdateInfo(
        latestVersion: latestVersion,
        buildNumber: latestBuild,
        apkUrl: await apkUrlForDevice(),
        notesAr: 'تحديث جديد متاح يحتوي على أحدث الميزات والتحسينات',
        notesEn: 'New update available with latest features and enhancements',
        forceUpdate: false,
        currentVersion: info.version,
        currentBuild: currentBuild,
      );
    } catch (e) {
      debugPrint('GitHub update check failed: $e');
      return null;
    }
  }

  Future<AppUpdateInfo?> _checkFirestore(
    PackageInfo info, {
    bool throwOnError = false,
  }) async {
    try {
      final snap = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
          .doc(_docPath)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (!snap.exists) return null;
      final d = snap.data();
      if (d == null) return null;

      final latestVersion = (d['latest_version'] ?? '').toString().trim();
      final apkUrl = (d['apk_url'] ?? '').toString().trim();
      if (latestVersion.isEmpty || apkUrl.isEmpty) return null;

      final latestBuild = int.tryParse('${d['build_number'] ?? ''}') ?? 0;
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      if (!_isNewer(
        remoteVersion: latestVersion,
        remoteBuild: latestBuild,
        currentVersion: info.version,
        currentBuild: currentBuild,
      )) {
        return null;
      }

      return AppUpdateInfo(
        latestVersion: latestVersion,
        buildNumber: latestBuild,
        apkUrl: apkUrl,
        notesAr: (d['notes_ar'] ?? '').toString(),
        notesEn: (d['notes_en'] ?? '').toString(),
        forceUpdate: d['force_update'] == true,
        currentVersion: info.version,
        currentBuild: currentBuild,
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
      if (throwOnError) rethrow;
      return null;
    }
  }

  /// Strictly determines if an update should be offered.
  /// Prevents any accidental downgrade to an older version.
  bool _isNewer({
    required String remoteVersion,
    required int remoteBuild,
    required String currentVersion,
    required int currentBuild,
  }) {
    final remoteVer = _versionCode(remoteVersion);
    final currentVer = _versionCode(currentVersion);

    // If remote version is strictly older than installed version, NEVER update!
    if (remoteVer < currentVer) {
      return false;
    }

    // If remote version is strictly higher (e.g. 1.0.114 > 1.0.113), always update!
    if (remoteVer > currentVer) {
      return true;
    }

    // If versions are identical (e.g. 1.0.114 == 1.0.114), only update if remote build is strictly greater
    return remoteBuild > currentBuild;
  }

  /// '1.2.10' -> 102010 so versions compare numerically.
  int _versionCode(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 1000000 + parts[1] * 1000 + parts[2];
  }

  double downloadProgress = 0.0;
  int receivedBytes = 0;
  int totalBytes = 0;
  bool isDownloading = false;
  bool isDownloaded = false;
  String downloadedApkPath = '';
  String downloadError = '';

  final StreamController<void> _stateController = StreamController<void>.broadcast();
  Stream<void> get stateStream => _stateController.stream;

  CancelToken? _cancelToken;

  Future<void> startDownloadInBackground(String initialUrl) async {
    if (isDownloading) return;

    isDownloading = true;
    isDownloaded = false;
    downloadError = '';
    downloadProgress = 0.0;
    receivedBytes = 0;
    totalBytes = 0;
    _stateController.add(null);

    _cancelToken = CancelToken();

    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      }
      dir ??= await getTemporaryDirectory();

      final fileName = 'zero_update_${DateTime.now().millisecondsSinceEpoch}.apk';
      final savePath = '${dir.path}${Platform.pathSeparator}$fileName';

      // Candidate URLs in priority order
      final urls = <String>{
        initialUrl,
        'https://github.com/MIDO12A/ahla-live/releases/latest/download/zero-app.apk',
        'https://github.com/MIDO12A/ahla-live/releases/latest/download/app-arm64-v8a-release.apk',
        'https://github.com/MIDO12A/ahla-live/releases/download/latest/zero-app.apk',
      }.toList();

      bool success = false;
      dynamic lastError;

      for (final url in urls) {
        if (_cancelToken?.isCancelled ?? false) break;
        try {
          debugPrint('Attempting APK download from: $url');
          final dio = Dio();
          await dio.download(
            url,
            savePath,
            cancelToken: _cancelToken,
            onReceiveProgress: (received, total) {
              receivedBytes = received;
              totalBytes = total > 0 ? total : received;
              downloadProgress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
              _stateController.add(null);
            },
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: true,
              maxRedirects: 10,
              receiveTimeout: const Duration(minutes: 10),
              sendTimeout: const Duration(minutes: 2),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.119 Mobile Safari/537.36',
                'Accept': 'application/octet-stream, application/vnd.android.package-archive, */*',
              },
            ),
          );

          final file = File(savePath);
          if (await file.exists() && await file.length() > 1024 * 1024) {
            success = true;
            break;
          }
        } catch (err) {
          lastError = err;
          debugPrint('Download attempt failed for $url: $err');
          if (err is DioException && err.type == DioExceptionType.cancel) {
            isDownloading = false;
            isDownloaded = false;
            _stateController.add(null);
            return;
          }
        }
      }

      if (!success) {
        throw lastError ?? Exception('Failed to download valid APK');
      }

      isDownloading = false;
      isDownloaded = true;
      downloadedApkPath = savePath;
      _stateController.add(null);

      await installApk(savePath);
    } catch (e) {
      isDownloading = false;
      if (e is DioException && e.type == DioExceptionType.cancel) {
        isDownloaded = false;
        _stateController.add(null);
        return;
      }
      downloadError = 'تعذر تنزيل التحديث تلقائياً، يرجى إعادة المحاولة';
      _stateController.add(null);
    }
  }

  Future<void> installApk(String path) async {
    await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  }

  void cancelDownload() {
    _cancelToken?.cancel();
    _cancelToken = null;
    isDownloading = false;
    isDownloaded = false;
    downloadProgress = 0.0;
    _stateController.add(null);
  }
}
