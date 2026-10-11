import 'package:equatable/equatable.dart';

class ExpenseModel extends Equatable {
  const ExpenseModel({
    required this.id,
    required this.category,
    required this.amount,
    this.currencyId,
    this.currencyCode,
    this.exchangeRate = 1,
    this.payee,
    required this.expenseDate,
    this.note,
    this.receiptPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String category;
  final double amount;
  final int? currencyId;
  final String? currencyCode;
  final double exchangeRate;
  final String? payee;
  final DateTime expenseDate;
  final String? note;
  final String? receiptPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ExpenseModel.fromMap(Map<String, Object?> map) {
    return ExpenseModel(
      id: map['id'] as int,
      category: (map['category'] as String?) ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currencyId: map['currency_id'] as int?,
      currencyCode: map['currency_code'] as String?,
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1,
      payee: map['payee'] as String?,
      expenseDate: DateTime.parse(map['expense_date'] as String),
      note: map['note'] as String?,
      receiptPath: map['receipt_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id == 0 ? null : id,
        'category': category,
        'amount': amount,
        'currency_id': currencyId,
        'currency_code': currencyCode,
        'exchange_rate': exchangeRate,
        'payee': payee,
        'expense_date': expenseDate.toIso8601String(),
        'note': note,
        'receipt_path': receiptPath,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  ExpenseModel copyWith({
    int? id,
    String? category,
    double? amount,
    int? currencyId,
    String? currencyCode,
    double? exchangeRate,
    String? payee,
    DateTime? expenseDate,
    String? note,
    String? receiptPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      currencyId: currencyId ?? this.currencyId,
      currencyCode: currencyCode ?? this.currencyCode,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      payee: payee ?? this.payee,
      expenseDate: expenseDate ?? this.expenseDate,
      note: note ?? this.note,
      receiptPath: receiptPath ?? this.receiptPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, category, amount, expenseDate];
}

class ExpenseCategoryTotal extends Equatable {
  const ExpenseCategoryTotal({
    required this.category,
    required this.amount,
  });

  final String category;
  final double amount;

  @override
  List<Object?> get props => [category, amount];
}
