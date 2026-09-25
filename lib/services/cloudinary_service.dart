import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

enum CloudinaryResourceType { image, video, auto, raw }

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._();
  factory CloudinaryService() => _instance;
  CloudinaryService._();

  static const String _cloudName = 'r5kohqhd';
  static const String _apiKey = '183298827798548';
  static const String _apiSecret = String.fromEnvironment(
    'CLOUDINARY_API_SECRET',
    defaultValue: 'R9S7Ybk8tTTkVckWGAlgdwvppJw',
  );

  String _uploadUrl(CloudinaryResourceType type) {
    final t = type == CloudinaryResourceType.auto ? 'auto' : type.name;
    return 'https://api.cloudinary.com/v1_1/$_cloudName/$t/upload';
  }

  static int _timeOffset = 0;

  int _getCorrectedTimestamp() {
    return ((DateTime.now().millisecondsSinceEpoch + _timeOffset * 1000) / 1000).round();
  }

  Future<int> _syncTime() async {
    for (final url in [
      'https://api.cloudinary.com/v1_1/$_cloudName',
      'https://google.com',
    ]) {
      try {
        final response = await http.head(Uri.parse(url));
        final serverDate = response.headers['date'];
        if (serverDate != null) {
          final serverTime = HttpDate.parse(serverDate).millisecondsSinceEpoch;
          final localTime = DateTime.now().millisecondsSinceEpoch;
          _timeOffset = ((serverTime - localTime) / 1000).round();
          print('CloudinaryService: time synced, offset=$_timeOffset s (from $url)');
          break;
        }
      } catch (e) {
        print('CloudinaryService: time sync failed for $url: $e');
      }
    }
    return _getCorrectedTimestamp();
  }

  Future<String> upload(
    File file, {
    String? publicId,
    CloudinaryResourceType type = CloudinaryResourceType.auto,
  }) async {
    await _syncTime();
    return _doUpload(file, publicId: publicId, type: type, retriesLeft: 1);
  }

  Future<String> _doUpload(
    File file, {
    String? publicId,
    CloudinaryResourceType type = CloudinaryResourceType.auto,
    int retriesLeft = 0,
  }) async {
    final url = _uploadUrl(type);

    // 1. Try Unsigned Upload first (fastest, preset ahla_live is configured as unsigned)
    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.fields['upload_preset'] = 'ahla_live';
      if (publicId != null && publicId.isNotEmpty) {
        request.fields['public_id'] = publicId;
      }
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        if (secureUrl != null && secureUrl.isNotEmpty) {
          return secureUrl;
        }
      } else {
        print('Cloudinary unsigned upload response: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Cloudinary unsigned upload error: $e');
    }

    // 2. Fallback to Signed Upload with correct Cloudinary signature (without api_key in signature string)
    try {
      final timestamp = _getCorrectedTimestamp();
      final paramsToSign = <String, String>{
        'timestamp': timestamp.toString(),
      };
      if (publicId != null && publicId.isNotEmpty) {
        paramsToSign['public_id'] = publicId;
      }

      final signature = _generateSignature(paramsToSign);

      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.fields['api_key'] = _apiKey;
      request.fields['timestamp'] = timestamp.toString();
      request.fields['signature'] = signature;
      if (publicId != null && publicId.isNotEmpty) {
        request.fields['public_id'] = publicId;
      }
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        if (secureUrl != null && secureUrl.isNotEmpty) {
          return secureUrl;
        }
      }

      if (retriesLeft > 0 && response.body.contains('Stale request')) {
        await _syncTime();
        return _doUpload(file, publicId: publicId, type: type, retriesLeft: retriesLeft - 1);
      }

      throw Exception('Cloudinary upload failed: ${response.statusCode} ${response.body}');
    } catch (e) {
      if (retriesLeft > 0) {
        await _syncTime();
        return _doUpload(file, publicId: publicId, type: type, retriesLeft: retriesLeft - 1);
      }
      rethrow;
    }
  }

  Future<String> uploadImage(File file, {String? publicId}) {
    return upload(file, publicId: publicId, type: CloudinaryResourceType.image);
  }

  Future<String> uploadVideo(File file, {String? publicId}) {
    return upload(file, publicId: publicId, type: CloudinaryResourceType.video);
  }

  String _generateSignature(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final str = keys.map((k) => '$k=${params[k]}').join('&') + _apiSecret;
    return sha1.convert(utf8.encode(str)).toString();
  }
}
