import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/expenses/data/expense.dart';
import 'package:planzers/features/expenses/data/expense_group.dart';
import 'package:planzers/features/expenses/domain/expense_settlement.dart';

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

class ExpensesRepository {
  ExpensesRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _expenseGroupsCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('expenseGroups');
  }

  CollectionReference<Map<String, dynamic>> _expensesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('expenses');
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

    final groupRef = _expenseGroupsCol(cleanTripId).doc(cleanGroupId);
    final expensesSnap = await _expensesCol(cleanTripId)
        .where('groupId', isEqualTo: cleanGroupId)
        .get();

    final batch = firestore.batch();
    for (final doc in expensesSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(groupRef);
    await batch.commit();
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
