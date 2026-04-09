import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/expenses/data/expense.dart';
import 'package:planzers/features/expenses/domain/expense_settlement.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Live list of expenses for a trip, newest first.
final tripExpensesStreamProvider = StreamProvider.autoDispose
    .family<List<TripExpense>, String>((ref, tripId) {
  return ref.watch(expensesRepositoryProvider).watchTripExpenses(tripId);
});

class ExpensesRepository {
  ExpensesRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _expensesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('expenses');
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

  Future<void> addExpense({
    required String tripId,
    required String title,
    required double amount,
    required String currency,
    required String paidBy,
    required List<String> participantIds,
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
      title: cleanTitle,
      amount: amount,
      currency: cleanCurrency,
      paidBy: cleanPaidBy,
      participantIds: participants,
      category: category,
      createdAt: DateTime.now(),
      createdBy: user.uid,
    );

    await _expensesCol(cleanTripId).add(
      draft.toCreateMap(paidBy: cleanPaidBy, createdBy: user.uid),
    );
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
