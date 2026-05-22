import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/expenses/data/expense.dart';
import 'package:planerz/features/expenses/data/expense_group.dart';
import 'package:planerz/features/expenses/data/expense_group_summary.dart';
import 'package:planerz/features/expenses/data/expenses_ui_lock.dart';
import 'package:planerz/features/expenses/data/group_balance.dart';
import 'package:planerz/features/expenses/data/suggested_reimbursement.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Live expense posts for a trip, newest first.
final tripExpenseGroupsStreamProvider =
    StreamProvider.autoDispose.family<List<TripExpenseGroup>, String>(
        (ref, tripId) {
  return ref.watch(expensesRepositoryProvider).watchTripExpenseGroups(tripId);
});

/// Live list of expenses for a trip, newest first.
final tripExpensesStreamProvider =
    StreamProvider.autoDispose.family<List<TripExpense>, String>((ref, tripId) {
  return ref.watch(expensesRepositoryProvider).watchTripExpenses(tripId);
});

typedef ExpenseGroupScope = ({String tripId, String groupId});

final expenseGroupBalancesStreamProvider = StreamProvider.autoDispose
    .family<List<GroupBalance>, ExpenseGroupScope>((ref, scope) {
  return ref
      .watch(expensesRepositoryProvider)
      .watchGroupBalances(scope.tripId, scope.groupId);
});

final expenseGroupSuggestedReimbursementsStreamProvider =
    StreamProvider.autoDispose
        .family<List<SuggestedReimbursement>, ExpenseGroupScope>((ref, scope) {
  return ref.watch(expensesRepositoryProvider).watchGroupSuggestedReimbursements(
        scope.tripId,
        scope.groupId,
      );
});

final expenseGroupSummaryStreamProvider = StreamProvider.autoDispose
    .family<ExpenseGroupSummary?, ExpenseGroupScope>((ref, scope) {
  return ref
      .watch(expensesRepositoryProvider)
      .watchGroupExpenseSummary(scope.tripId, scope.groupId);
});

/// Live UI lock flag for trip expense editing controls.
final tripExpensesUiLockStreamProvider =
    StreamProvider.autoDispose.family<TripExpensesUiLock, String>((ref, tripId) {
  return ref.watch(expensesRepositoryProvider).watchExpensesUiLock(tripId);
});

class ExpensesRepository {
  ExpensesRepository({
    required this.firestore,
    required this.auth,
    FirebaseFunctions? functions,
  }) : _functions = functions ??
            FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion);

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> _expenseGroupsCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('expenseGroups');
  }

  CollectionReference<Map<String, dynamic>> _expensesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('expenses');
  }

  DocumentReference<Map<String, dynamic>> _expensesUiLockDoc(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('expenses_ui_locks')
        .doc(kTripExpensesUiLockDocId);
  }

  Stream<TripExpensesUiLock> watchExpensesUiLock(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(TripExpensesUiLock.defaults);
    }
    return _expensesUiLockDoc(cleanId).snapshots().map((snap) {
      if (!snap.exists) return TripExpensesUiLock.defaults;
      return TripExpensesUiLock.fromMap(snap.data() ?? const {});
    });
  }

  Future<void> setExpensesUiLocked({
    required String tripId,
    required bool locked,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    await _expensesUiLockDoc(cleanTripId).set(
      <String, dynamic>{
        'expensesLocked': locked,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      },
      SetOptions(merge: true),
    );
  }

  Future<Trip> _requireTrip(String tripId) async {
    final snap = await firestore.collection('trips').doc(tripId).get();
    if (!snap.exists) {
      throw StateError('Voyage introuvable');
    }
    final data = snap.data();
    if (data == null) {
      throw StateError('Voyage introuvable');
    }
    return Trip.fromMap(snap.id, data);
  }

  Future<String?> _resolveCurrentUserMemberId(
    String tripId,
    String userId,
  ) async {
    final snap = await firestore
        .collection('trips')
        .doc(tripId)
        .collection('participants')
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first.id;
  }

  void _ensureTripMemberExpenseRole({
    required Trip trip,
    required String userId,
    required TripPermissionRole minRole,
  }) {
    final callerRole = resolveTripPermissionRole(
      trip: trip,
      userId: userId,
    );
    final isMember = trip.memberUserIds.contains(userId);
    if (!isMember ||
        !isTripRoleAllowed(currentRole: callerRole, minRole: minRole)) {
      throw StateError('Droits insuffisants pour cette action');
    }
  }

  Stream<List<TripExpenseGroup>> watchTripExpenseGroups(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <TripExpenseGroup>[]);
    }

    return _expenseGroupsCol(cleanId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TripExpenseGroup.fromDoc).toList());
  }

  Stream<List<GroupBalance>> watchGroupBalances(String tripId, String groupId) {
    final cleanTripId = tripId.trim();
    final cleanGroupId = groupId.trim();
    if (cleanTripId.isEmpty || cleanGroupId.isEmpty) {
      return Stream.value(const <GroupBalance>[]);
    }
    return _expenseGroupsCol(cleanTripId)
        .doc(cleanGroupId)
        .collection('balances')
        .snapshots()
        .map((snap) => snap.docs.map(GroupBalance.fromDoc).toList());
  }

  Stream<List<SuggestedReimbursement>> watchGroupSuggestedReimbursements(
    String tripId,
    String groupId,
  ) {
    final cleanTripId = tripId.trim();
    final cleanGroupId = groupId.trim();
    if (cleanTripId.isEmpty || cleanGroupId.isEmpty) {
      return Stream.value(const <SuggestedReimbursement>[]);
    }
    return _expenseGroupsCol(cleanTripId)
        .doc(cleanGroupId)
        .collection('suggestedReimbursements')
        .snapshots()
        .map((snap) => snap.docs.map(SuggestedReimbursement.fromDoc).toList());
  }

  Stream<ExpenseGroupSummary?> watchGroupExpenseSummary(
    String tripId,
    String groupId,
  ) {
    final cleanTripId = tripId.trim();
    final cleanGroupId = groupId.trim();
    if (cleanTripId.isEmpty || cleanGroupId.isEmpty) {
      return Stream.value(null);
    }
    return _expenseGroupsCol(cleanTripId)
        .doc(cleanGroupId)
        .collection('summary')
        .doc('current')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return ExpenseGroupSummary.fromDoc(snap);
    });
  }

  Stream<List<TripExpense>> watchTripExpenses(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <TripExpense>[]);
    }

    return _expensesCol(cleanId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TripExpense.fromDoc).toList());
  }

  Future<void> addExpenseGroup({
    required String tripId,
    required String title,
    required List<String> visibleToMemberIds,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw StateError('Nom du poste obligatoire');
    }

    final visibleTo = visibleToMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (visibleTo.isEmpty) {
      throw StateError('Au moins une personne doit voir le poste');
    }

    final trip = await _requireTrip(cleanTripId);
    _ensureTripMemberExpenseRole(
      trip: trip,
      userId: user.uid,
      minRole: trip.expensesPermissions.createExpensePostMinRole,
    );

    await _expenseGroupsCol(cleanTripId).add({
      'title': cleanTitle,
      'visibleToMemberIds': visibleTo,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
    });
  }

  Future<void> updateExpenseGroup({
    required String tripId,
    required String groupId,
    required String title,
    required List<String> visibleToMemberIds,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanGroupId = groupId.trim();
    if (cleanTripId.isEmpty || cleanGroupId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw StateError('Nom du poste obligatoire');
    }

    final visibleTo = visibleToMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (visibleTo.isEmpty) {
      throw StateError('Au moins une personne doit voir le poste');
    }

    final trip = await _requireTrip(cleanTripId);
    final groupSnap = await _expenseGroupsCol(cleanTripId).doc(cleanGroupId).get();
    if (!groupSnap.exists) {
      throw StateError('Poste introuvable');
    }
    final existingGroup = TripExpenseGroup.fromDoc(groupSnap);
    final memberDocId = await _resolveCurrentUserMemberId(cleanTripId, user.uid);
    if (!existingGroup.isVisibleTo(memberDocId)) {
      throw StateError('Poste introuvable ou non visible');
    }
    _ensureTripMemberExpenseRole(
      trip: trip,
      userId: user.uid,
      minRole: trip.expensesPermissions.editExpensePostMinRole,
    );

    await _expenseGroupsCol(cleanTripId).doc(cleanGroupId).update({
      'title': cleanTitle,
      'visibleToMemberIds': visibleTo,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  Future<void> deleteExpenseGroup({
    required String tripId,
    required String groupId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanGroupId = groupId.trim();
    if (cleanTripId.isEmpty || cleanGroupId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final trip = await _requireTrip(cleanTripId);
    final groupSnap = await _expenseGroupsCol(cleanTripId).doc(cleanGroupId).get();
    if (!groupSnap.exists) {
      throw StateError('Poste introuvable');
    }
    final existingGroup = TripExpenseGroup.fromDoc(groupSnap);
    final memberDocId = await _resolveCurrentUserMemberId(cleanTripId, user.uid);
    if (!existingGroup.isVisibleTo(memberDocId)) {
      throw StateError('Poste introuvable ou non visible');
    }
    _ensureTripMemberExpenseRole(
      trip: trip,
      userId: user.uid,
      minRole: trip.expensesPermissions.deleteExpensePostMinRole,
    );

    final callable = _functions.httpsCallable('deleteExpenseGroup');
    await callable.call<Map<String, dynamic>>({
      'tripId': cleanTripId,
      'groupId': cleanGroupId,
    });
  }

  Future<String> markExpenseReimbursementPaid({
    required String tripId,
    required String groupId,
    required String fromParticipantId,
    required String toParticipantId,
    required double amount,
    required String currency,
  }) async {
    final callable = _functions.httpsCallable('markExpenseReimbursementPaid');
    final result = await callable.call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'groupId': groupId.trim(),
      'fromParticipantId': fromParticipantId.trim(),
      'toParticipantId': toParticipantId.trim(),
      'amount': amount,
      'currency': currency.trim().toUpperCase(),
    });
    final expenseId = result.data['expenseId']?.toString().trim() ?? '';
    if (expenseId.isEmpty) {
      throw StateError('Réponse serveur invalide');
    }
    return expenseId;
  }

  Future<void> unmarkExpenseReimbursementPaid({
    required String tripId,
    required String groupId,
    required String expenseId,
  }) async {
    final callable = _functions.httpsCallable('unmarkExpenseReimbursementPaid');
    await callable.call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'groupId': groupId.trim(),
      'expenseId': expenseId.trim(),
    });
  }

  Future<void> refreshExpenseGroupSettlement({
    required String tripId,
    required String groupId,
  }) async {
    final callable =
        _functions.httpsCallable('refreshExpenseGroupSettlement');
    await callable.call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'groupId': groupId.trim(),
    });
  }

  Future<void> addExpense({
    required String tripId,
    required String groupId,
    required String title,
    required double amount,
    required String currency,
    required String paidBy,
    required List<String> participantIds,
    required DateTime expenseDate,
    String category = 'other',
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final cleanGroupId = groupId.trim();
    if (cleanGroupId.isEmpty) {
      throw StateError('Poste invalide');
    }

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw StateError('Libelle obligatoire');
    }
    if (amount <= 0) {
      throw StateError('Montant invalide');
    }

    final cleanCurrency = currency.trim().toUpperCase();
    if (!kSupportedExpenseCurrencies.contains(cleanCurrency)) {
      throw StateError('Devise non supportee (EUR ou USD)');
    }

    final cleanPaidBy = paidBy.trim();
    if (cleanPaidBy.isEmpty) {
      throw StateError('Payeur invalide');
    }

    final participants = participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (participants.isEmpty) {
      throw StateError('Au moins un participant');
    }

    final draft = TripExpense(
      id: '',
      groupId: cleanGroupId,
      title: cleanTitle,
      amount: amount,
      currency: cleanCurrency,
      paidBy: cleanPaidBy,
      participantIds: participants,
      category: category,
      createdAt: DateTime.now(),
      expenseDate: DateTime(
        expenseDate.year,
        expenseDate.month,
        expenseDate.day,
      ),
      createdBy: user.uid,
      splitMode: ExpenseSplitMode.equal,
      participantShares: const {},
    );

    await _expensesCol(cleanTripId).add(
      draft.toCreateMap(
        paidBy: cleanPaidBy,
        createdBy: user.uid,
        groupId: cleanGroupId,
      ),
    );
  }

  Future<void> updateExpense({
    required String tripId,
    required String expenseId,
    required String title,
    required double amount,
    required String currency,
    required String paidBy,
    required List<String> participantIds,
    required DateTime expenseDate,
    String category = 'other',
    ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
    Map<String, double>? participantShares,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanExpenseId = expenseId.trim();
    if (cleanTripId.isEmpty || cleanExpenseId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw StateError('Libelle obligatoire');
    }
    if (amount <= 0) {
      throw StateError('Montant invalide');
    }

    final cleanCurrency = currency.trim().toUpperCase();
    if (!kSupportedExpenseCurrencies.contains(cleanCurrency)) {
      throw StateError('Devise non supportee (EUR ou USD)');
    }

    final cleanPaidBy = paidBy.trim();
    if (cleanPaidBy.isEmpty) {
      throw StateError('Payeur invalide');
    }

    final participants = participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (participants.isEmpty) {
      throw StateError('Au moins un participant');
    }

    final update = <String, dynamic>{
      'title': cleanTitle,
      'amount': amount,
      'currency': cleanCurrency,
      'paidBy': cleanPaidBy,
      'participantIds': participants,
      'category': category.trim().isEmpty ? 'other' : category.trim(),
      'expenseDate': Timestamp.fromDate(
        DateTime(expenseDate.year, expenseDate.month, expenseDate.day),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    };

    if (splitMode == ExpenseSplitMode.customAmounts) {
      update['splitMode'] = 'custom';
      update['participantShares'] = {
        for (final id in participants)
          id: (participantShares ?? const {})[id] ?? 0.0,
      };
    } else {
      update['splitMode'] = 'equal';
      update['participantShares'] = FieldValue.delete();
    }

    await _expensesCol(cleanTripId).doc(cleanExpenseId).update(update);
  }

  Future<void> deleteExpense({
    required String tripId,
    required String expenseId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanExpenseId = expenseId.trim();
    if (cleanTripId.isEmpty || cleanExpenseId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    await _expensesCol(cleanTripId).doc(cleanExpenseId).delete();
  }

}
