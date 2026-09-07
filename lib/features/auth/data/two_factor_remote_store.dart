import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

/// Firestore access for the encrypted 2FA sync record at
/// `users/{uid}/meta/twoFactor` — already covered by the existing
/// `meta/{docId}` security rule (owner-only read/write), no rules change
/// needed. One-shot get/set/delete only; unlike Murthy's data this never
/// needs a live stream, since [TwoFactorService] checks it only at
/// enrollment/import time and verifies codes against the local copy.
///
/// Mirrors the SDK's native/REST split: `cloud_firestore` has no Linux
/// desktop implementation, so Linux talks to the Firestore REST API
/// directly, same as `MurthyRepository`.
class TwoFactorRemoteStore {
  factory TwoFactorRemoteStore({FirebaseFirestore? firestore, http.Client? client}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return TwoFactorRemoteStore._(_RestBackend(client: client));
    }
    return TwoFactorRemoteStore._(_FirestoreBackend(firestore ?? FirebaseFirestore.instance));
  }

  TwoFactorRemoteStore._(this._backend);

  final _TwoFactorRemoteBackend _backend;

  Future<Map<String, dynamic>?> read(String uid) => _backend.read(uid);
  Future<void> write(String uid, Map<String, dynamic> data) => _backend.write(uid, data);
  Future<void> delete(String uid) => _backend.delete(uid);
}

abstract class _TwoFactorRemoteBackend {
  Future<Map<String, dynamic>?> read(String uid);
  Future<void> write(String uid, Map<String, dynamic> data);
  Future<void> delete(String uid);
}

class _FirestoreBackend implements _TwoFactorRemoteBackend {
  _FirestoreBackend(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid).collection('meta').doc('twoFactor');

  @override
  Future<Map<String, dynamic>?> read(String uid) async => (await _doc(uid).get()).data();

  @override
  Future<void> write(String uid, Map<String, dynamic> data) => _doc(uid).set(data);

  @override
  Future<void> delete(String uid) => _doc(uid).delete();
}

class _RestBackend implements _TwoFactorRemoteBackend {
  _RestBackend({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String _url(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/meta/twoFactor';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  @override
  Future<Map<String, dynamic>?> read(String uid) async {
    final response = await _client.get(Uri.parse(_url(uid)), headers: await _headers());
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError(
        'Firestore REST read twoFactor failed: ${response.statusCode} ${response.body}',
      );
    }
    return decodeFirestoreFields(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<void> write(String uid, Map<String, dynamic> data) async {
    final response = await _client.patch(
      Uri.parse(_url(uid)),
      headers: await _headers(),
      body: jsonEncode({'fields': encodeFirestoreFields(data)}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Firestore REST write twoFactor failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  @override
  Future<void> delete(String uid) async {
    final response = await _client.delete(Uri.parse(_url(uid)), headers: await _headers());
    if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
      throw StateError(
        'Firestore REST delete twoFactor failed: ${response.statusCode} ${response.body}',
      );
    }
  }
}
