import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import '../models/daily_progress_entry.dart';
import '../models/daily_protocol.dart';
import 'murthy_crypto_service.dart';

/// Firestore access for the Murthy feature (daily protocols + daily
/// progress/summary). Every document is encrypted client-side before it's
/// written — see [MurthyCryptoService] — so raw Firestore reads only ever
/// turn up ciphertext.
///
/// Mirrors `daily_routine_sdk`'s own split: the native `cloud_firestore`
/// plugin has no Linux desktop implementation (and `main.dart` never calls
/// `Firebase.initializeApp()` there), so on Linux this talks to the
/// Firestore REST API directly instead, exactly like
/// `FirestoreRoutineRepositoryService` does for routine tasks.
class MurthyRepository {
  factory MurthyRepository({FirebaseFirestore? firestore, MurthyCryptoService? crypto}) {
    final cryptoService = crypto ?? MurthyCryptoService();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return MurthyRepository._(_RestMurthyBackend(), cryptoService);
    }
    return MurthyRepository._(_FirestoreMurthyBackend(firestore ?? FirebaseFirestore.instance), cryptoService);
  }

  MurthyRepository._(this._backend, this._crypto);

  final _MurthyBackend _backend;
  final MurthyCryptoService _crypto;

  Stream<List<DailyProtocol>> watchProtocols(String uid) {
    return _backend.watchProtocols(uid).asyncMap((docs) async {
      final protocols = await Future.wait(
        docs.map((doc) async {
          final json = await _crypto.decryptJson(doc.data);
          return DailyProtocol.fromJson(doc.id, json);
        }),
      );
      protocols.sort((a, b) {
        final aCreated = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aCreated.compareTo(bCreated);
      });
      return protocols;
    });
  }

  Future<void> upsertProtocol(String uid, DailyProtocol protocol) async {
    final encrypted = await _crypto.encryptJson(protocol.toJson());
    await _backend.upsertProtocol(uid, protocol.id, encrypted);
  }

  Future<void> deleteProtocol(String uid, String protocolId) {
    return _backend.deleteProtocol(uid, protocolId);
  }

  /// One-shot read, for callers (like the voice assistant) that just need a
  /// snapshot rather than a live stream.
  Future<List<DailyProtocol>> fetchProtocolsOnce(String uid) {
    return watchProtocols(uid).first;
  }

  Stream<DailyProgressEntry> watchProgress(String uid, String dateKey) {
    return _backend.watchProgress(uid, dateKey).asyncMap((data) async {
      if (data == null) return DailyProgressEntry(date: dateKey);
      final json = await _crypto.decryptJson(data);
      return DailyProgressEntry.fromJson(json);
    });
  }

  Future<void> upsertProgress(String uid, DailyProgressEntry entry) async {
    final encrypted = await _crypto.encryptJson(entry.toJson());
    await _backend.upsertProgress(uid, entry.date, encrypted);
  }
}

class _MurthyDoc {
  const _MurthyDoc(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

abstract class _MurthyBackend {
  Stream<List<_MurthyDoc>> watchProtocols(String uid);
  Future<void> upsertProtocol(String uid, String id, Map<String, dynamic> data);
  Future<void> deleteProtocol(String uid, String id);
  Stream<Map<String, dynamic>?> watchProgress(String uid, String dateKey);
  Future<void> upsertProgress(String uid, String dateKey, Map<String, dynamic> data);
}

class _FirestoreMurthyBackend implements _MurthyBackend {
  _FirestoreMurthyBackend(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _protocols(String uid) =>
      _firestore.collection('users').doc(uid).collection('murthyProtocols');

  DocumentReference<Map<String, dynamic>> _progressDoc(String uid, String dateKey) =>
      _firestore.collection('users').doc(uid).collection('murthyProgress').doc(dateKey);

  @override
  Stream<List<_MurthyDoc>> watchProtocols(String uid) {
    return _protocols(uid).snapshots().map(
      (snapshot) => snapshot.docs.map((d) => _MurthyDoc(d.id, d.data())).toList(),
    );
  }

  @override
  Future<void> upsertProtocol(String uid, String id, Map<String, dynamic> data) =>
      _protocols(uid).doc(id).set(data);

  @override
  Future<void> deleteProtocol(String uid, String id) => _protocols(uid).doc(id).delete();

  @override
  Stream<Map<String, dynamic>?> watchProgress(String uid, String dateKey) {
    return _progressDoc(uid, dateKey).snapshots().map((doc) => doc.data());
  }

  @override
  Future<void> upsertProgress(String uid, String dateKey, Map<String, dynamic> data) =>
      _progressDoc(uid, dateKey).set(data);
}

/// REST fallback for Linux desktop — see [MurthyRepository]'s doc comment.
/// Like `RestRoutineRepositoryService`, [watchProtocols]/[watchProgress]
/// poll rather than push (plain REST has no equivalent to Firestore's
/// gRPC/HTTP2 Listen API).
class _RestMurthyBackend implements _MurthyBackend {
  _RestMurthyBackend({http.Client? client, this.pollInterval = const Duration(seconds: 10)})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration pollInterval;

  final Map<String, StreamController<List<_MurthyDoc>>> _protocolControllers = {};
  final Map<String, Timer> _protocolTimers = {};

  final Map<String, StreamController<Map<String, dynamic>?>> _progressControllers = {};
  final Map<String, Timer> _progressTimers = {};

  String _protocolsUrl(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/murthyProtocols';

  String _progressDocUrl(String uid, String dateKey) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/murthyProgress/${Uri.encodeComponent(dateKey)}';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Stream<List<_MurthyDoc>> watchProtocols(String uid) {
    final existing = _protocolControllers[uid];
    if (existing != null) return existing.stream;

    late final StreamController<List<_MurthyDoc>> controller;
    controller = StreamController<List<_MurthyDoc>>.broadcast(
      onListen: () {
        _protocolTimers[uid] ??= Timer.periodic(pollInterval, (_) => _pollProtocols(uid));
        unawaited(_pollProtocols(uid));
      },
      onCancel: () {
        _protocolTimers.remove(uid)?.cancel();
        _protocolControllers.remove(uid);
      },
    );
    _protocolControllers[uid] = controller;
    return controller.stream;
  }

  Future<void> _pollProtocols(String uid) async {
    final controller = _protocolControllers[uid];
    if (controller == null || controller.isClosed) return;
    try {
      final response = await _client.get(Uri.parse(_protocolsUrl(uid)), headers: await _headers());
      if (response.statusCode != 200) {
        controller.addError(
          StateError('Firestore REST watchProtocols failed: ${response.statusCode} ${response.body}'),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      controller.add(
        docs.map((doc) {
          final map = doc as Map<String, dynamic>;
          final id = (map['name'] as String).split('/').last;
          return _MurthyDoc(id, decodeFirestoreFields(map));
        }).toList(),
      );
    } catch (e, stackTrace) {
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<void> upsertProtocol(String uid, String id, Map<String, dynamic> data) async {
    final response = await _client.patch(
      Uri.parse('${_protocolsUrl(uid)}/${Uri.encodeComponent(id)}'),
      headers: await _headers(),
      body: jsonEncode({'fields': encodeFirestoreFields(data)}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Firestore REST upsertProtocol failed: ${response.statusCode} ${response.body}');
    }
  }

  @override
  Future<void> deleteProtocol(String uid, String id) async {
    final response = await _client.delete(
      Uri.parse('${_protocolsUrl(uid)}/${Uri.encodeComponent(id)}'),
      headers: await _headers(),
    );
    if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
      throw StateError('Firestore REST deleteProtocol failed: ${response.statusCode} ${response.body}');
    }
  }

  @override
  Stream<Map<String, dynamic>?> watchProgress(String uid, String dateKey) {
    final key = '$uid/$dateKey';
    final existing = _progressControllers[key];
    if (existing != null) return existing.stream;

    late final StreamController<Map<String, dynamic>?> controller;
    controller = StreamController<Map<String, dynamic>?>.broadcast(
      onListen: () {
        _progressTimers[key] ??= Timer.periodic(pollInterval, (_) => _pollProgress(uid, dateKey));
        unawaited(_pollProgress(uid, dateKey));
      },
      onCancel: () {
        _progressTimers.remove(key)?.cancel();
        _progressControllers.remove(key);
      },
    );
    _progressControllers[key] = controller;
    return controller.stream;
  }

  Future<void> _pollProgress(String uid, String dateKey) async {
    final key = '$uid/$dateKey';
    final controller = _progressControllers[key];
    if (controller == null || controller.isClosed) return;
    try {
      final response = await _client.get(
        Uri.parse(_progressDocUrl(uid, dateKey)),
        headers: await _headers(),
      );
      if (response.statusCode == 404) {
        controller.add(null);
        return;
      }
      if (response.statusCode != 200) {
        controller.addError(
          StateError('Firestore REST watchProgress failed: ${response.statusCode} ${response.body}'),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      controller.add(decodeFirestoreFields(body));
    } catch (e, stackTrace) {
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<void> upsertProgress(String uid, String dateKey, Map<String, dynamic> data) async {
    final response = await _client.patch(
      Uri.parse(_progressDocUrl(uid, dateKey)),
      headers: await _headers(),
      body: jsonEncode({'fields': encodeFirestoreFields(data)}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Firestore REST upsertProgress failed: ${response.statusCode} ${response.body}');
    }
  }
}
