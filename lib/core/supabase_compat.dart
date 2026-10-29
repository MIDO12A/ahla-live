import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../services/supabase_auth_service.dart';
import '../services/supabase_data_service.dart';
import '../services/cloudinary_service.dart';

/// Singleton mirroring `Supabase.instance`.
class Supabase {
  static final Supabase instance = Supabase._();
  Supabase._();
  final SupabaseClient client = SupabaseClient();
}

/// Client exposing a subset of the Supabase API backed purely by Supabase REST API + PostgREST.
class SupabaseClient {
  final AuthClient auth = AuthClient();

  SupabaseQueryBuilder from(String table) => SupabaseQueryBuilder(table);

  /// Postgres RPC -> Supabase HTTP REST endpoint /rest/v1/rpc/$fn
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    if (fn == 'delete_user_account') {
      final uid = auth.currentUser?.id ?? params?['uid']?.toString();
      if (uid != null) {
        try {
          await SupabaseDataService().deleteUser(uid);
        } catch (_) {}
      }
      try {
        await SupabaseAuthService().signOut();
      } catch (_) {}
      return <String, dynamic>{'status': 'ok'};
    }

    try {
      final url = Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/rpc/$fn');
      final res = await http.post(
        url,
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(params ?? {}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) return null;
        try {
          return jsonDecode(res.body);
        } catch (_) {
          return res.body;
        }
      } else {
        debugPrint('[SupabaseClient.rpc] $fn HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[SupabaseClient.rpc] $fn error: $e');
    }
    return null;
  }

  RealtimeChannel channel(String topic) => RealtimeChannel(topic);

  void removeChannel(RealtimeChannel channel) {
    channel.dispose();
  }

  StorageClient get storage => StorageClient();
}

/// Storage backed by Cloudinary (mirrors Supabase storage API).
class StorageClient {
  StorageBucket from(String bucket) => StorageBucket(bucket);
}

class StorageBucket {
  final String bucket;
  StorageBucket(this.bucket);

  static final Map<String, String> _uploadedUrls = {};

  Future<String> upload(
    String path,
    dynamic file, {
    FileOptions? fileOptions,
  }) async {
    final File localFile;
    if (file is File) {
      localFile = file;
    } else if (file is Uint8List) {
      final tmp = File(
        '${Directory.systemTemp.path}/$bucket/${path.replaceAll('/', '_')}',
      );
      await tmp.create(recursive: true);
      await tmp.writeAsBytes(file, flush: true);
      localFile = tmp;
    } else {
      throw StateError('Unsupported upload type: ${file.runtimeType}');
    }
    final url = await CloudinaryService().upload(localFile);
    _uploadedUrls[path] = url;
    return path;
  }

  Future<String> uploadBinary(
    String path,
    Uint8List data, {
    FileOptions? fileOptions,
  }) async {
    return upload(path, data, fileOptions: fileOptions);
  }

  String getPublicUrl(String path) {
    final url = _uploadedUrls[path];
    if (url != null && url.isNotEmpty) return url;
    return 'https://res.cloudinary.com/r5kohqhd/image/upload/$path';
  }
}

class FileOptions {
  final bool upsert;
  final String? contentType;
  const FileOptions({this.upsert = false, this.contentType});
}

/// Realtime-channel shim backed by Supabase polling.
class RealtimeChannel {
  final String topic;
  RealtimeChannel(this.topic);

  PostgresChangeEvent? _event;
  String? _table;
  String? _column;
  dynamic _value;
  bool _negated = false;
  void Function(PostgresChangePayload)? _callback;
  Timer? _pollTimer;

  RealtimeChannel onPostgresChanges({
    PostgresChangeEvent event = PostgresChangeEvent.all,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    void Function(PostgresChangePayload)? callback,
  }) {
    _event = event;
    _table = table;
    _column = filter?.column;
    _value = filter?.value;
    _negated = filter?.type == PostgresChangeFilterType.neq;
    _callback = callback;
    return this;
  }

  RealtimeChannel subscribe() {
    return this;
  }

  void unsubscribe() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() => unsubscribe();
}

class PostgresChangeFilter {
  final PostgresChangeFilterType type;
  final String? column;
  final dynamic value;
  const PostgresChangeFilter({
    this.type = PostgresChangeFilterType.eq,
    this.column,
    this.value,
  });
}

enum PostgresChangeFilterType { eq, neq }

enum PostgresChangeEvent { all, insert, update, delete }

class PostgresChangePayload {
  final Map<String, dynamic> newRecord;
  final Map<String, dynamic> oldRecord;
  const PostgresChangePayload(this.newRecord, {this.oldRecord = const {}});
}

/// Auth client backed by SupabaseAuthService.
class AuthClient {
  UserCompat? get currentUser {
    final supa = SupabaseAuthService().currentUser;
    if (supa != null && supa.uid.isNotEmpty) {
      return UserCompat.fromSupa(supa);
    }
    return null;
  }

  Session? get currentSession {
    final supa = SupabaseAuthService().currentUser;
    if (supa != null && supa.uid.isNotEmpty) {
      final uc = UserCompat.fromSupa(supa);
      return Session(uc, uc.id);
    }
    return null;
  }

  Future<AuthResponse> signInAnonymously() async {
    return AuthResponse(currentUser);
  }

  Future<void> signOut() async {
    await SupabaseAuthService().signOut();
  }
}

class Session {
  final UserCompat user;
  final String? accessToken;
  Session(this.user, this.accessToken);
}

class UserCompat {
  final String id;
  final String? email;
  final String? phone;
  final Map<String, dynamic>? userMetadata;
  String get uid => id;

  UserCompat({
    required this.id,
    this.email,
    this.phone,
    this.userMetadata,
  });

  UserCompat.fromSupa(AppAuthUser supa)
      : id = supa.uid,
        email = supa.email,
        phone = supa.phoneNumber,
        userMetadata = const <String, dynamic>{};
}

class AuthResponse {
  final UserCompat? user;
  AuthResponse(this.user);
}

/// Supabase REST API Query Builder (PostgREST HTTP client).
enum _QOp { select, insert, update, delete, upsert }

class SupabaseQueryBuilder implements Future<List<Map<String, dynamic>>> {
  final String _table;
  final List<(String, String, dynamic)> _wheres = [];
  final List<List<(String, String, dynamic)>> _orGroups = [];
  final List<String> _orRawStrings = [];
  String? _orderCol;
  bool _orderAsc = true;
  int? _limit;
  int? _rangeStart;
  int? _rangeEnd;
  _QOp _op = _QOp.select;
  dynamic _payload;

  SupabaseQueryBuilder(this._table);

  SupabaseQueryBuilder select([String columns = '*']) => this;

  SupabaseQueryBuilder eq(String column, dynamic value) {
    _wheres.add((column, 'eq', value));
    return this;
  }

  SupabaseQueryBuilder neq(String column, dynamic value) {
    _wheres.add((column, 'neq', value));
    return this;
  }

  SupabaseQueryBuilder gt(String column, dynamic value) {
    _wheres.add((column, 'gt', value));
    return this;
  }

  SupabaseQueryBuilder gte(String column, dynamic value) {
    _wheres.add((column, 'gte', value));
    return this;
  }

  SupabaseQueryBuilder lt(String column, dynamic value) {
    _wheres.add((column, 'lt', value));
    return this;
  }

  SupabaseQueryBuilder lte(String column, dynamic value) {
    _wheres.add((column, 'lte', value));
    return this;
  }

  SupabaseQueryBuilder inFilter(String column, List<dynamic> values) {
    _wheres.add((column, 'in', values));
    return this;
  }

  SupabaseQueryBuilder in_(String column, List<dynamic> values) => inFilter(column, values);

  SupabaseQueryBuilder like(String column, String pattern) {
    _wheres.add((column, 'like', pattern));
    return this;
  }

  SupabaseQueryBuilder ilike(String column, String pattern) {
    _wheres.add((column, 'ilike', pattern));
    return this;
  }

  SupabaseQueryBuilder isFilter(String column, dynamic value) {
    _wheres.add((column, 'is', value));
    return this;
  }

  SupabaseQueryBuilder not(String column, String operator, dynamic value) {
    _wheres.add((column, 'not.$operator', value));
    return this;
  }

  Stream<List<Map<String, dynamic>>> stream({required List<String> primaryKey}) {
    return Stream.fromFuture(_execute());
  }

  SupabaseQueryBuilder order(String column, {bool ascending = true}) {
    _orderCol = column;
    _orderAsc = ascending;
    return this;
  }

  SupabaseQueryBuilder limit(int count) {
    _limit = count;
    return this;
  }

  SupabaseQueryBuilder range(int from, int to) {
    _rangeStart = from;
    _rangeEnd = to;
    return this;
  }

  SupabaseQueryBuilder or(String filters) {
    if (filters.trim().isNotEmpty) {
      _orRawStrings.add(filters.trim());
    }
    final groups = filters.split(',');
    final parsed = <(String, String, dynamic)>[];
    for (final raw in groups) {
      final parts = raw.split('.');
      if (parts.length >= 3) {
        parsed.add((parts[0].trim(), parts[1].trim(), parts.sublist(2).join('.').trim()));
      }
    }
    if (parsed.isNotEmpty) _orGroups.add(parsed);
    return this;
  }

  SupabaseQueryBuilder insert(dynamic payload) {
    _op = _QOp.insert;
    _payload = payload;
    return this;
  }

  SupabaseQueryBuilder upsert(dynamic payload) {
    _op = _QOp.upsert;
    _payload = payload;
    return this;
  }

  SupabaseQueryBuilder update(Map<String, dynamic> payload) {
    _op = _QOp.update;
    _payload = payload;
    return this;
  }

  SupabaseQueryBuilder delete() {
    _op = _QOp.delete;
    return this;
  }

  Future<Map<String, dynamic>?> maybeSingle() async {
    final list = await _execute();
    return list.isEmpty ? null : list.first;
  }

  Future<Map<String, dynamic>> single() async {
    final list = await _execute();
    if (list.isEmpty) {
      throw StateError('single() returned no rows in table "$_table"');
    }
    return list.first;
  }

  Future<List<Map<String, dynamic>>> _execute() async {
    final baseUrl = SupabaseConfig.projectUrl;
    final headers = {
      'apikey': SupabaseConfig.anonKey,
      'Authorization': 'Bearer ' + SupabaseConfig.anonKey,
      'Content-Type': 'application/json',
    };

    switch (_op) {
      case _QOp.select:
        final queryParams = <String>['select=*'];
        for (final item in _wheres) {
          final col = item.$1;
          final op = item.$2;
          final val = item.$3;
          switch (op) {
            case 'neq':
              queryParams.add('$col=neq.$val');
              break;
            case 'gt':
              queryParams.add('$col=gt.$val');
              break;
            case 'gte':
              queryParams.add('$col=gte.$val');
              break;
            case 'lt':
              queryParams.add('$col=lt.$val');
              break;
            case 'lte':
              queryParams.add('$col=lte.$val');
              break;
            case 'in':
              final inStr = (val as List).map((v) => '"$v"').join(',');
              queryParams.add('$col=in.($inStr)');
              break;
            case 'like':
              queryParams.add('$col=like.$val');
              break;
            case 'ilike':
              queryParams.add('$col=ilike.$val');
              break;
            case 'is':
              queryParams.add('$col=is.$val');
              break;
            case 'eq':
              queryParams.add('$col=eq.$val');
              break;
            default:
              if (op.startsWith('not.')) {
                queryParams.add('$col=$op.$val');
              } else {
                queryParams.add('$col=eq.$val');
              }
          }
        }

        for (final raw in _orRawStrings) {
          queryParams.add('or=($raw)');
        }

        if (_orderCol != null) {
          queryParams.add('order=$_orderCol.${_orderAsc ? 'asc' : 'desc'}');
        }
        if (_limit != null) {
          queryParams.add('limit=$_limit');
        }
        if (_rangeStart != null && _rangeEnd != null) {
          queryParams.add('offset=$_rangeStart');
          queryParams.add('limit=${_rangeEnd! - _rangeStart! + 1}');
        }

        final uri = Uri.parse('$baseUrl/rest/v1/$_table?${queryParams.join('&')}');
        final res = await http.get(uri, headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        }
        return [];

      case _QOp.insert:
        headers['Prefer'] = 'return=representation';
        final uri = Uri.parse('$baseUrl/rest/v1/$_table');
        final res = await http.post(uri, headers: headers, body: jsonEncode(_payload));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        }
        return [];

      case _QOp.upsert:
        headers['Prefer'] = 'resolution=merge-duplicates,return=representation';
        final uri = Uri.parse('$baseUrl/rest/v1/$_table');
        final res = await http.post(uri, headers: headers, body: jsonEncode(_payload));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        }
        return [];

      case _QOp.update:
        headers['Prefer'] = 'return=representation';
        final queryParams = <String>[];
        for (final item in _wheres) {
          queryParams.add('${item.$1}=eq.${item.$3}');
        }
        final uri = Uri.parse('$baseUrl/rest/v1/$_table?${queryParams.join('&')}');
        final res = await http.patch(uri, headers: headers, body: jsonEncode(_payload));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        }
        return [];

      case _QOp.delete:
        final queryParams = <String>[];
        for (final item in _wheres) {
          queryParams.add('${item.$1}=eq.${item.$3}');
        }
        final uri = Uri.parse('$baseUrl/rest/v1/$_table?${queryParams.join('&')}');
        await http.delete(uri, headers: headers);
        return [];
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() => _execute().asStream();

  @override
  Future<List<Map<String, dynamic>>> catchError(Function onError, {bool Function(Object error)? test}) =>
      _execute().catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) =>
      _execute().then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> timeout(Duration timeLimit, {FutureOr<List<Map<String, dynamic>>> Function()? onTimeout}) =>
      _execute().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(FutureOr<void> Function() action) =>
      _execute().whenComplete(action);
}
