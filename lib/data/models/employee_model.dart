import 'package:equatable/equatable.dart';

/// Staff member used for warehouse operations and performance tracking.
class EmployeeModel extends Equatable {
  const EmployeeModel({
    required this.id,
    this.code,
    required this.fullName,
    this.phone,
    this.email,
    this.role,
    this.department,
    this.hireDate,
    this.baseSalary = 0,
    this.salaryCurrency = 'AFN',
    this.paymentCycle = 'monthly',
    this.bankAccount,
    this.address,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.movementCount = 0,
    this.receiptCount = 0,
    this.receiptTotal = 0,
    this.inboundCount = 0,
    this.outboundCount = 0,
    this.withdrawalTotal = 0,
  });

  final int id;
  final String? code;
  final String fullName;
  final String? phone;
  final String? email;
  final String? role;
  final String? department;
  final DateTime? hireDate;
  final double baseSalary;
  final String salaryCurrency;
  final String paymentCycle;
  final String? bankAccount;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Period performance (filled by list/detail stats queries).
  final int movementCount;
  final int receiptCount;
  final double receiptTotal;
  final int inboundCount;
  final int outboundCount;
  final double withdrawalTotal;

  /// Remaining balance against monthly salary after withdrawals.
  double get remainingBalance => baseSalary - withdrawalTotal;

  factory EmployeeModel.fromMap(Map<String, Object?> map) {
    DateTime? hire;
    final hireRaw = map['hire_date'] as String?;
    if (hireRaw != null && hireRaw.isNotEmpty) {
      hire = DateTime.tryParse(hireRaw);
    }
    return EmployeeModel(
      id: map['id'] as int,
      code: map['code'] as String?,
      fullName: map['full_name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      role: map['role'] as String?,
      department: map['department'] as String?,
      hireDate: hire,
      baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
      salaryCurrency: (map['salary_currency'] as String?) ?? 'AFN',
      paymentCycle: (map['payment_cycle'] as String?) ?? 'monthly',
      bankAccount: map['bank_account'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      movementCount: (map['movement_count'] as num?)?.toInt() ?? 0,
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      receiptTotal: (map['receipt_total'] as num?)?.toDouble() ?? 0,
      inboundCount: (map['inbound_count'] as num?)?.toInt() ?? 0,
      outboundCount: (map['outbound_count'] as num?)?.toInt() ?? 0,
      withdrawalTotal: (map['withdrawal_total'] as num?)?.toDouble() ??
          (map['salary_paid_total'] as num?)?.toDouble() ??
          0,
    );
  }

  Map<String, Object?> toInsertMap() => {
        'code': _emptyToNull(code),
        'full_name': fullName.trim(),
        'phone': _emptyToNull(phone),
        'email': _emptyToNull(email),
        'role': _emptyToNull(role),
        'department': _emptyToNull(department),
        'hire_date': hireDate?.toIso8601String(),
        'base_salary': baseSalary,
        'salary_currency': salaryCurrency.trim().isEmpty
            ? 'AFN'
            : salaryCurrency.trim(),
        'payment_cycle': paymentCycle.trim().isEmpty
            ? 'monthly'
            : paymentCycle.trim(),
        'bank_account': _emptyToNull(bankAccount),
        'address': _emptyToNull(address),
        'notes': _emptyToNull(notes),
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static String? _emptyToNull(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  EmployeeModel copyWith({
    int? id,
    String? code,
    String? fullName,
    String? phone,
    String? email,
    String? role,
    String? department,
    DateTime? hireDate,
    double? baseSalary,
    String? salaryCurrency,
    String? paymentCycle,
    String? bankAccount,
    String? address,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? movementCount,
    int? receiptCount,
    double? receiptTotal,
    int? inboundCount,
    int? outboundCount,
    double? withdrawalTotal,
  }) {
    return EmployeeModel(
      id: id ?? this.id,
      code: code ?? this.code,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      department: department ?? this.department,
      hireDate: hireDate ?? this.hireDate,
      baseSalary: baseSalary ?? this.baseSalary,
      salaryCurrency: salaryCurrency ?? this.salaryCurrency,
      paymentCycle: paymentCycle ?? this.paymentCycle,
      bankAccount: bankAccount ?? this.bankAccount,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      movementCount: movementCount ?? this.movementCount,
      receiptCount: receiptCount ?? this.receiptCount,
      receiptTotal: receiptTotal ?? this.receiptTotal,
      inboundCount: inboundCount ?? this.inboundCount,
      outboundCount: outboundCount ?? this.outboundCount,
      withdrawalTotal: withdrawalTotal ?? this.withdrawalTotal,
    );
  }

  @override
  List<Object?> get props => [id, fullName, role, isActive, updatedAt];
}

/// A withdrawal taken by an employee against their salary account.
///
/// Stored in `employee_salaries` (legacy table name).
class EmployeeWithdrawalModel extends Equatable {
  const EmployeeWithdrawalModel({
    required this.id,
    required this.employeeId,
    this.label,
    required this.amount,
    this.currency = 'AFN',
    required this.withdrawnAt,
    this.paymentMethod,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final int employeeId;
  final String? label;
  final double amount;
  final String currency;
  final DateTime withdrawnAt;
  final String? paymentMethod;
  final String? notes;
  final DateTime createdAt;

  factory EmployeeWithdrawalModel.fromMap(Map<String, Object?> map) {
    return EmployeeWithdrawalModel(
      id: map['id'] as int,
      employeeId: map['employee_id'] as int,
      label: map['period_label'] as String?,
      amount: (map['amount'] as num).toDouble(),
      currency: (map['currency'] as String?) ?? 'AFN',
      withdrawnAt: DateTime.parse(map['paid_at'] as String),
      paymentMethod: map['payment_method'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
        'employee_id': employeeId,
        'period_label':
            label?.trim().isEmpty == true ? null : label?.trim(),
        'amount': amount,
        'currency': currency.trim().isEmpty ? 'AFN' : currency.trim(),
        'paid_at': withdrawnAt.toIso8601String(),
        'payment_method': paymentMethod?.trim().isEmpty == true
            ? null
            : paymentMethod?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'created_at': createdAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [id, employeeId, amount, withdrawnAt];
}
