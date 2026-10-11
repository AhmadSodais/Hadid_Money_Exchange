import 'package:equatable/equatable.dart';

/// Who the settlement applies to.
///
/// - [payable]: we owe the company for purchases — we are paying them
/// - [receivable]: the company owes us for sales — they are paying us
enum PaymentSettlementSide { payable, receivable }

extension PaymentSettlementSideX on PaymentSettlementSide {
  String get dbValue => switch (this) {
        PaymentSettlementSide.payable => 'payable',
        PaymentSettlementSide.receivable => 'receivable',
      };

  static PaymentSettlementSide fromDb(String? value) {
    return value == 'receivable'
        ? PaymentSettlementSide.receivable
        : PaymentSettlementSide.payable;
  }
}

/// A recorded settlement against a trading company's account.
class CompanyPaymentModel extends Equatable {
  const CompanyPaymentModel({
    required this.id,
    required this.partnerType,
    required this.partnerId,
    this.partnerName,
    required this.amount,
    this.currency = 'AFN',
    required this.paidAt,
    this.paymentMethod,
    this.settlementSide = PaymentSettlementSide.payable,
    this.notes,
    this.isVoided = false,
    required this.createdAt,
  });

  final int id;
  final String partnerType; // supplier | customer
  final int partnerId;
  final String? partnerName;
  final double amount;
  final String currency;
  final DateTime paidAt;
  final String? paymentMethod;
  final PaymentSettlementSide settlementSide;
  final String? notes;
  final bool isVoided;
  final DateTime createdAt;

  factory CompanyPaymentModel.fromMap(Map<String, Object?> map) {
    return CompanyPaymentModel(
      id: map['id'] as int,
      partnerType: map['partner_type'] as String,
      partnerId: map['partner_id'] as int,
      partnerName: map['partner_name'] as String?,
      amount: (map['amount'] as num).toDouble(),
      currency: (map['currency'] as String?) ?? 'AFN',
      paidAt: DateTime.parse(map['paid_at'] as String),
      paymentMethod: map['payment_method'] as String?,
      settlementSide:
          PaymentSettlementSideX.fromDb(map['settlement_side'] as String?),
      notes: map['notes'] as String?,
      isVoided: ((map['is_voided'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
        'partner_type': partnerType,
        'partner_id': partnerId,
        'partner_name': partnerName,
        'amount': amount,
        'currency': currency.trim().isEmpty ? 'AFN' : currency.trim(),
        'paid_at': paidAt.toIso8601String(),
        'payment_method': paymentMethod?.trim().isEmpty == true
            ? null
            : paymentMethod?.trim(),
        'settlement_side': settlementSide.dbValue,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'is_voided': isVoided ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [id, partnerType, partnerId, amount, settlementSide, isVoided];
}
