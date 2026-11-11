import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// عميل HTTP آمن بفشل سريع (fail-fast) لكل طلبات Supabase REST.
///
/// يطبق timeout ثابت على كل الطلبات حتى لا يتجمد التطبيق عند ضعف الشبكة:
/// - GET / HEAD → 5 ثوانٍ
/// - POST / PUT / PATCH / DELETE → 10 ثوانٍ
///
/// عند انتهاء المهلة يرمي [TimeoutException] برسالة واضحة،
/// فتلتقطه كتل try/catch الموجودة في الخدمات وتُرجع خطأً للمستخدم
/// بدل الانتظار اللانهائي.
class SafeHttp {
  SafeHttp._();

  static const Duration _getTimeout = Duration(seconds: 5);
  static const Duration _writeTimeout = Duration(seconds: 10);

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) =>
      _send('GET', url, _getTimeout,
          () => http.get(url, headers: headers));

  static Future<http.Response> head(
    Uri url, {
    Map<String, String>? headers,
  }) =>
      _send('HEAD', url, _getTimeout,
          () => http.head(url, headers: headers));

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _send('POST', url, _writeTimeout,
          () => http.post(url, headers: headers, body: body, encoding: encoding));

  static Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _send('PATCH', url, _writeTimeout,
          () => http.patch(url, headers: headers, body: body, encoding: encoding));

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _send('PUT', url, _writeTimeout,
          () => http.put(url, headers: headers, body: body, encoding: encoding));

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _send('DELETE', url, _writeTimeout,
          () => http.delete(url, headers: headers, body: body, encoding: encoding));

  static Future<http.Response> _send(
    String method,
    Uri url,
    Duration timeout,
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      debugPrint('[SafeHttp] $method $url timed out after ${timeout.inSeconds}s');
      throw TimeoutException(
        'SafeHttp $method timed out after ${timeout.inSeconds}s: $url',
        timeout,
      );
    }
  }
}
