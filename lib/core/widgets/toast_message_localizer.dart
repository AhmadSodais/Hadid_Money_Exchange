import 'package:easy_localization/easy_localization.dart';

/// Resolves snackbar / toast text to the active app language.
///
/// Accepts:
/// - Already-translated UI strings (returned as-is)
/// - Translation keys like `errors.skuExists`
/// - Legacy hardcoded English failure sentences from repositories
abstract final class ToastMessageLocalizer {
  static final _keyPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]*$');

  static const _legacyEnglish = <String, String>{
    'Product not found.': 'errors.productNotFound',
    'Product not found': 'errors.productNotFound',
    'SKU already exists.': 'errors.skuExists',
    'SKU already exists. Choose a unique product code.': 'errors.skuExists',
    'Stock cannot go below zero.': 'errors.stockBelowZero',
    'Quantity cannot be zero.': 'errors.quantityZero',
    'Quantity must be positive.': 'errors.quantityPositive',
    'Cart is empty.': 'errors.cartEmpty',
    'Invoice number is required.': 'errors.invoiceRequired',
    'Invoice number already exists.': 'errors.invoiceExists',
    'Category name is required.': 'errors.categoryNameRequired',
    'Category already exists.': 'errors.categoryExists',
    'Category not found.': 'errors.categoryNotFound',
    'Warehouse name is required.': 'errors.warehouseNameRequired',
    'Warehouse not found.': 'errors.warehouseNotFound',
    'A warehouse with this name already exists.': 'errors.warehouseExists',
    'Customer name is required.': 'errors.customerNameRequired',
    'Customer not found.': 'errors.customerNotFound',
    'Supplier name is required.': 'errors.supplierNameRequired',
    'Supplier not found.': 'errors.supplierNotFound',
    'Order not found.': 'errors.orderNotFound',
    'Purchase not found.': 'errors.purchaseNotFound',
    'Expense not found': 'errors.expenseNotFound',
    'Employee not found.': 'errors.employeeNotFound',
    'Movement not found.': 'errors.movementNotFound',
    'Payment not found.': 'errors.paymentNotFound',
    'Payment amount must be greater than zero.': 'errors.paymentAmount',
    'Exchange rate must be positive.': 'errors.exchangeRate',
    'Currency not found.': 'errors.currencyNotFound',
    'Withdrawal record not found.': 'errors.withdrawalNotFound',
    'Image must be 5MB or smaller.': 'errors.imageTooLarge',
    'Please fix the highlighted fields.': 'errors.fixFixFields',
  };

  static String resolve(String? raw) {
    final message = (raw ?? '').trim();
    if (message.isEmpty) return 'errors.generic'.tr();

    if (_keyPattern.hasMatch(message)) {
      final translated = message.tr();
      if (translated != message) return translated;
    }

    final legacyKey = _legacyEnglish[message];
    if (legacyKey != null) return legacyKey.tr();

    if (message.startsWith('Not enough stock')) {
      return 'errors.notEnoughStock'.tr();
    }
    if (message.startsWith('Product not found')) {
      return 'errors.productNotFound'.tr();
    }
    if (message.startsWith('Failed to ') ||
        message.startsWith('SKU lookup') ||
        message.startsWith('SKU check') ||
        message.startsWith('Archive/restore failed') ||
        message.startsWith('Delete failed') ||
        message.startsWith('Stock adjustment failed') ||
        message.startsWith('POS search failed')) {
      return 'errors.operationFailed'.tr();
    }

    return message;
  }
}
