import 'package:equatable/equatable.dart';

class CurrencyModel extends Equatable {
  const CurrencyModel({
    required this.id,
    required this.code,
    required this.name,
    required this.symbol,
    required this.exchangeRate,
    this.isBase = false,
    this.isActive = true,
    required this.updatedAt,
  });

  final int id;
  final String code;
  final String name;
  final String symbol;
  final double exchangeRate;
  final bool isBase;
  final bool isActive;
  final DateTime updatedAt;

  factory CurrencyModel.fromMap(Map<String, Object?> map) {
    return CurrencyModel(
      id: map['id'] as int,
      code: map['code'] as String,
      name: map['name'] as String,
      symbol: map['symbol'] as String,
      exchangeRate: (map['exchange_rate'] as num).toDouble(),
      isBase: (map['is_base'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'symbol': symbol,
        'exchange_rate': exchangeRate,
        'is_base': isBase ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [id, code, exchangeRate, isBase];
}
