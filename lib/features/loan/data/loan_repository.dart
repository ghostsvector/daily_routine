import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import '../models/loan.dart';
import '../models/loan_payment.dart';

/// Firestore access for the Loan feature (loans + their payment ledgers).
///
/// Mirrors `MurthyRepository`'s split: native `cloud_firestore` has no Linux
/// desktop implementation, so on Linux this talks to the Firestore REST API
/// directly instead, exactly like `FirestoreRoutineRepositoryService` does.
class LoanRepository {
  factory LoanRepository({FirebaseFirestore? firestore}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return LoanRepository._(_RestLoanBackend());
    }
    return LoanRepository._(
      _FirestoreLoanBackend(firestore ?? FirebaseFirestore.instance),
    );
  }

  LoanRepository._(this._backend);

  final _LoanBackend _backend;

  Stream<List<Loan>> watchLoans(String uid) {
    return _backend.watchLoans(uid).map((docs) {
      final loans = docs.map((d) => Loan.fromJson(d.id, d.data)).toList();
      loans.sort((a, b) {
        final aCreated = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aCreated.compareTo(bCreated);
      });
      return loans;
    });
  }

  Future<void> upsertLoan(String uid, Loan loan) {
    return _backend.upsertLoan(uid, loan.id, loan.toJson());
  }

  Future<void> deleteLoan(String uid, String loanId) {
    return _backend.deleteLoan(uid, loanId);
  }

  Stream<List<LoanPayment>> watchPayments(String uid, String loanId) {
    return _backend.watchPayments(uid, loanId).map((docs) {
      final payments = docs
          .map((d) => LoanPayment.fromJson(d.id, d.data))
          .toList();
      payments.sort((a, b) => a.paidDate.compareTo(b.paidDate));
      return payments;
    });
  }

  Future<void> addPayment(String uid, LoanPayment payment) {
    return _backend.upsertPayment(
      uid,
      payment.loanId,
      payment.id,
      payment.toJson(),
    );
  }

  Future<void> deletePayment(String uid, String loanId, String paymentId) {
    return _backend.deletePayment(uid, loanId, paymentId);
  }
}

class _LoanDoc {
  const _LoanDoc(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

abstract class _LoanBackend {
  Stream<List<_LoanDoc>> watchLoans(String uid);
  Future<void> upsertLoan(String uid, String id, Map<String, dynamic> data);
  Future<void> deleteLoan(String uid, String id);
  Stream<List<_LoanDoc>> watchPayments(String uid, String loanId);
  Future<void> upsertPayment(
    String uid,
    String loanId,
    String paymentId,
    Map<String, dynamic> data,
  );
  Future<void> deletePayment(String uid, String loanId, String paymentId);
}

class _FirestoreLoanBackend implements _LoanBackend {
  _FirestoreLoanBackend(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _loans(String uid) =>
      _firestore.collection('users').doc(uid).collection('loans');

  CollectionReference<Map<String, dynamic>> _payments(
    String uid,
    String loanId,
  ) => _loans(uid).doc(loanId).collection('payments');

  @override
  Stream<List<_LoanDoc>> watchLoans(String uid) {
    return _loans(uid).snapshots().map(
      (snapshot) =>
          snapshot.docs.map((d) => _LoanDoc(d.id, d.data())).toList(),
    );
  }

  @override
  Future<void> upsertLoan(String uid, String id, Map<String, dynamic> data) =>
      _loans(uid).doc(id).set(data);

  @override
  Future<void> deleteLoan(String uid, String id) =>
      _loans(uid).doc(id).delete();

  @override
  Stream<List<_LoanDoc>> watchPayments(String uid, String loanId) {
    return _payments(uid, loanId).snapshots().map(
      (snapshot) =>
          snapshot.docs.map((d) => _LoanDoc(d.id, d.data())).toList(),
    );
  }

  @override
  Future<void> upsertPayment(
    String uid,
    String loanId,
    String paymentId,
    Map<String, dynamic> data,
  ) => _payments(uid, loanId).doc(paymentId).set(data);

  @override
  Future<void> deletePayment(String uid, String loanId, String paymentId) =>
      _payments(uid, loanId).doc(paymentId).delete();
}

/// REST fallback for Linux desktop — see [LoanRepository]'s doc comment.
/// Like `RestMurthyBackend`, watches poll rather than push (plain REST has
/// no equivalent to Firestore's gRPC/HTTP2 Listen API).
class _RestLoanBackend implements _LoanBackend {
  _RestLoanBackend({http.Client? client}) : _client = client ?? http.Client();

  static const pollInterval = Duration(seconds: 60);
  static const _logName = 'LoanRepository(REST)';

  final http.Client _client;

  final Map<String, StreamController<List<_LoanDoc>>> _loanControllers = {};
  final Map<String, Timer> _loanTimers = {};

  final Map<String, StreamController<List<_LoanDoc>>> _paymentControllers =
      {};
  final Map<String, Timer> _paymentTimers = {};

  String _loansUrl(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/loans';

  String _paymentsUrl(String uid, String loanId) =>
      '${_loansUrl(uid)}/${Uri.encodeComponent(loanId)}/payments';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Stream<List<_LoanDoc>> watchLoans(String uid) {
    final existing = _loanControllers[uid];
    if (existing != null) return existing.stream;

    late final StreamController<List<_LoanDoc>> controller;
    controller = StreamController<List<_LoanDoc>>.broadcast(
      onListen: () {
        _loanTimers[uid] ??= Timer.periodic(pollInterval, (_) => _pollLoans(uid));
        unawaited(_pollLoans(uid));
      },
      onCancel: () {
        _loanTimers.remove(uid)?.cancel();
        _loanControllers.remove(uid);
      },
    );
    _loanControllers[uid] = controller;
    return controller.stream;
  }

  Future<void> _pollLoans(String uid) async {
    final controller = _loanControllers[uid];
    if (controller == null || controller.isClosed) return;
    try {
      debugPrint('[$_logName] Polling users/$uid/loans');
      final response = await _client.get(
        Uri.parse(_loansUrl(uid)),
        headers: await _headers(),
      );
      if (response.statusCode != 200) {
        debugPrint('[$_logName] Poll failed: ${response.statusCode} ${response.body}');
        controller.addError(
          StateError(
            'Firestore REST watchLoans failed: ${response.statusCode} ${response.body}',
          ),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      controller.add(
        docs.map((doc) {
          final map = doc as Map<String, dynamic>;
          final id = (map['name'] as String).split('/').last;
          return _LoanDoc(id, decodeFirestoreFields(map));
        }).toList(),
      );
    } catch (e, stackTrace) {
      debugPrint('[$_logName] Poll threw: $e');
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<void> upsertLoan(
    String uid,
    String id,
    Map<String, dynamic> data,
  ) async {
    final response = await _client.patch(
      Uri.parse('${_loansUrl(uid)}/${Uri.encodeComponent(id)}'),
      headers: await _headers(),
      body: jsonEncode({'fields': encodeFirestoreFields(data)}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Firestore REST upsertLoan failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  @override
  Future<void> deleteLoan(String uid, String id) async {
    final response = await _client.delete(
      Uri.parse('${_loansUrl(uid)}/${Uri.encodeComponent(id)}'),
      headers: await _headers(),
    );
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throw StateError(
        'Firestore REST deleteLoan failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  @override
  Stream<List<_LoanDoc>> watchPayments(String uid, String loanId) {
    final key = '$uid/$loanId';
    final existing = _paymentControllers[key];
    if (existing != null) return existing.stream;

    late final StreamController<List<_LoanDoc>> controller;
    controller = StreamController<List<_LoanDoc>>.broadcast(
      onListen: () {
        _paymentTimers[key] ??= Timer.periodic(
          pollInterval,
          (_) => _pollPayments(uid, loanId),
        );
        unawaited(_pollPayments(uid, loanId));
      },
      onCancel: () {
        _paymentTimers.remove(key)?.cancel();
        _paymentControllers.remove(key);
      },
    );
    _paymentControllers[key] = controller;
    return controller.stream;
  }

  Future<void> _pollPayments(String uid, String loanId) async {
    final key = '$uid/$loanId';
    final controller = _paymentControllers[key];
    if (controller == null || controller.isClosed) return;
    try {
      debugPrint('[$_logName] Polling users/$uid/loans/$loanId/payments');
      final response = await _client.get(
        Uri.parse(_paymentsUrl(uid, loanId)),
        headers: await _headers(),
      );
      if (response.statusCode != 200) {
        debugPrint('[$_logName] Poll failed: ${response.statusCode} ${response.body}');
        controller.addError(
          StateError(
            'Firestore REST watchPayments failed: ${response.statusCode} ${response.body}',
          ),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      controller.add(
        docs.map((doc) {
          final map = doc as Map<String, dynamic>;
          final id = (map['name'] as String).split('/').last;
          return _LoanDoc(id, decodeFirestoreFields(map));
        }).toList(),
      );
    } catch (e, stackTrace) {
      debugPrint('[$_logName] Poll threw: $e');
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<void> upsertPayment(
    String uid,
    String loanId,
    String paymentId,
    Map<String, dynamic> data,
  ) async {
    final response = await _client.patch(
      Uri.parse(
        '${_paymentsUrl(uid, loanId)}/${Uri.encodeComponent(paymentId)}',
      ),
      headers: await _headers(),
      body: jsonEncode({'fields': encodeFirestoreFields(data)}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Firestore REST upsertPayment failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  @override
  Future<void> deletePayment(
    String uid,
    String loanId,
    String paymentId,
  ) async {
    final response = await _client.delete(
      Uri.parse(
        '${_paymentsUrl(uid, loanId)}/${Uri.encodeComponent(paymentId)}',
      ),
      headers: await _headers(),
    );
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throw StateError(
        'Firestore REST deletePayment failed: ${response.statusCode} ${response.body}',
      );
    }
  }
}
