import 'dart:math';

import '../transactions/financial_command.dart';

/// Identifier conventions used everywhere a record gets a code.
///
/// Every human-facing code is `PREFIX-NNNN`: an uppercase prefix naming the
/// kind of record, a hyphen, and its number zero-padded to four digits (the
/// number simply grows past 9999). The number of a customer, drawer, or their
/// ledger account is the row id; transaction numbers count per type.
///
/// | record            | example     |
/// |-------------------|-------------|
/// | customer          | `C-0012`    |
/// | cash drawer       | `D-0001`    |
/// | customer account  | `2100-0012` |
/// | cash account      | `1100-0001` |
/// | transaction       | `RCP-0042`  |
///
/// Machine keys (transaction uid, idempotency key) are [key]s: 12 characters
/// of Crockford base32.
abstract final class Ids {
  static const customerPrefix = 'C';
  static const drawerPrefix = 'D';
  static const cashAccountParent = '1100';
  static const customerAccountParent = '2100';

  static const keyLength = 12;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final _random = Random.secure();
  static final RegExp keyPattern = RegExp('^[$_alphabet]{$keyLength}\$');

  static String code(String prefix, int number) =>
      '$prefix-${number.toString().padLeft(4, '0')}';

  static String customer(int id) => code(customerPrefix, id);
  static String drawer(int id) => code(drawerPrefix, id);
  static String customerAccount(int customerId) => code(customerAccountParent, customerId);
  static String cashAccount(int drawerId) => code(cashAccountParent, drawerId);
  static String reference(TransactionType type, int number) => code(type.prefix, number);

  /// A random 60-bit key, e.g. `7K3M9Q2XA4BT`.
  static String key() =>
      String.fromCharCodes(List.generate(keyLength, (_) => _alphabet.codeUnitAt(_random.nextInt(32))));

  /// Idempotency key of the reversal half of an edit submitted with [key].
  static String editReversalKey(String key) => '$key-R';

  /// Idempotency keys of a reconciliation record's adjustments are this
  /// prefix followed by the attempt number.
  static String reconciliationKeyPrefix(int recordId) => 'REC-$recordId-';

  /// Prefix of the idempotency keys of one legacy-data import.
  static String legacyKeyPrefix(String sourceFingerprint) =>
      'LEG-${sourceFingerprint.substring(0, 8).toUpperCase()}';
}
