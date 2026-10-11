import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../di/service_locator.dart';
import '../widgets/gf_toast.dart';
import 'formatters.dart';

/// Plain-text share for trading companies (not PDF).
///
/// Layout order is fixed so readers always see the same sections:
/// 1) Our store header  2) Company profile  3) Optional notes
/// 4) Optional activity summary  5) Optional recent movements  6) Footer
abstract final class CompanyShareHelper {
  static const _rule = '────────────────────────';
  static const _thick = '════════════════════════';

  static Future<String> _setting(String key) async {
    final result = await ServiceLocator.instance.lookups.getSetting(key);
    return result.when(
      success: (v) => (v ?? '').trim(),
      failure: (_) => '',
    );
  }

  static void _line(StringBuffer b, String label, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return;
    b.writeln('$label: $v');
  }

  static void _section(StringBuffer b, String title) {
    b.writeln();
    b.writeln(_rule);
    b.writeln(title.toUpperCase());
    b.writeln(_rule);
  }

  /// Structured company card text for Share / copy.
  static Future<String> buildProfileText({
    required String companyName,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastActivity,
    CompanyShareActivitySummary? activity,
    List<CompanyShareMovementLine>? recentMovements,
  }) async {
    final storeName = await _setting('store_name');
    final storePhone = await _setting('store_phone');
    final storeEmail = await _setting('store_email');
    final storeAddress = await _setting('store_address');

    final b = StringBuffer();

    // 1) Store header
    b.writeln(_thick);
    b.writeln(
      storeName.isEmpty
          ? 'tradingCompanies.share.defaultStore'.tr()
          : storeName,
    );
    _line(b, 'common.phone'.tr(), storePhone);
    _line(b, 'common.email'.tr(), storeEmail);
    _line(b, 'common.address'.tr(), storeAddress);
    b.writeln(_thick);

    // 2) Company profile
    _section(b, 'tradingCompanies.share.companySection'.tr());
    _line(b, 'tradingCompanies.companyName'.tr(), companyName);
    _line(b, 'common.phone'.tr(), phone);
    _line(b, 'common.email'.tr(), email);
    _line(b, 'common.address'.tr(), address);
    if (isActive != null) {
      _line(
        b,
        'common.status'.tr(),
        isActive ? 'status.active'.tr() : 'status.inactive'.tr(),
      );
    }
    if (createdAt != null) {
      _line(b, 'tradingCompanies.share.registered'.tr(), Formatters.date(createdAt));
    }
    if (lastActivity != null) {
      _line(
        b,
        'tradingCompanies.lastTransaction'.tr(),
        Formatters.date(lastActivity),
      );
    }

    // 3) Notes
    final note = (notes ?? '').trim();
    if (note.isNotEmpty) {
      _section(b, 'tradingCompanies.share.notesSection'.tr());
      b.writeln(note);
    }

    // 4) Activity summary
    if (activity != null) {
      _section(b, 'tradingCompanies.share.summarySection'.tr());
      _line(b, 'tradingCompanies.share.period'.tr(), activity.periodLabel);
      if (activity.purchasesCount > 0) {
        b.writeln(
          'tradingCompanies.share.purchasesLine'.tr(
            namedArgs: {
              'count': '${activity.purchasesCount}',
              'qty': activity.purchasesQtyLabel,
              'value': activity.purchasesValueLabel,
            },
          ),
        );
      }
      if (activity.salesCount > 0) {
        b.writeln(
          'tradingCompanies.share.salesLine'.tr(
            namedArgs: {
              'count': '${activity.salesCount}',
              'qty': activity.salesQtyLabel,
              'value': activity.salesValueLabel,
            },
          ),
        );
      }
    }

    // 5) Recent invoices
    if (recentMovements != null && recentMovements.isNotEmpty) {
      _section(b, 'tradingCompanies.share.recentSection'.tr());
      for (var i = 0; i < recentMovements.length; i++) {
        final m = recentMovements[i];
        b.writeln(
          '${i + 1}. ${m.date} · ${m.type} · ${m.product} · ${m.quantity}',
        );
        if (m.price.isNotEmpty) {
          b.writeln('   ${'common.total'.tr()}: ${m.price}');
        }
      }
    }

    // 6) Footer
    b.writeln();
    b.writeln(_rule);
    b.writeln(
      'tradingCompanies.share.footer'.tr(
        namedArgs: {'date': Formatters.dateTime(DateTime.now())},
      ),
    );

    return b.toString().trimRight();
  }

  static Future<void> shareText(
    BuildContext context, {
    required String text,
    required String subject,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: subject,
          title: subject,
        ),
      );
      if (!context.mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        GfToast.success(context, 'tradingCompanies.copied'.tr());
        return;
      }
      if (result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed) {
        GfToast.success(context, 'tradingCompanies.shared'.tr());
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      GfToast.success(context, 'tradingCompanies.copied'.tr());
    }
  }
}

class CompanyShareActivitySummary {
  const CompanyShareActivitySummary({
    required this.periodLabel,
    required this.purchasesCount,
    required this.salesCount,
    required this.purchasesQtyLabel,
    required this.salesQtyLabel,
    required this.purchasesValueLabel,
    required this.salesValueLabel,
  });

  final String periodLabel;
  final int purchasesCount;
  final int salesCount;
  final String purchasesQtyLabel;
  final String salesQtyLabel;
  final String purchasesValueLabel;
  final String salesValueLabel;
}

class CompanyShareMovementLine {
  const CompanyShareMovementLine({
    required this.date,
    required this.type,
    required this.product,
    required this.quantity,
    this.price = '',
  });

  final String date;
  final String type;
  final String product;
  final String quantity;
  final String price;
}
