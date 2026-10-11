import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../../data/models/company_payment_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../presentation/dialogs/warehouse_dialog_shared.dart';
import '../constants/app_constants.dart';
import '../di/service_locator.dart';
import '../widgets/gf_toast.dart';
import 'formatters.dart';
import 'pdf_persian_text.dart';

/// Which movement direction(s) to include in an inbound/outbound PDF invoice.
enum PdfMovementExportKind { outbound, inbound, both }

/// GlassFlow PDF reports — layout matched to the shop invoice template
/// (navy header table, light-blue info / totals cards, 4-column contact footer).
abstract final class PdfReportHelper {
  static const int _maxRows = 400;
  /// Blank form lines when there are few (or no) data rows (outbound/inbound).
  static const int _minBlankRows = 15;

  /// Page margins — extra bottom room for the shop contact footer.
  static const pw.EdgeInsets _pageMargin =
      pw.EdgeInsets.fromLTRB(28, 24, 28, 28);

  // Template palette (from invoice mock).
  static final PdfColor _navy = PdfColor.fromInt(0xFF1B4F8C);
  static final PdfColor _navyDeep = PdfColor.fromInt(0xFF163A6B);
  static final PdfColor _softBlue = PdfColor.fromInt(0xFFE8F2FB);
  static final PdfColor _softBorder = PdfColor.fromInt(0xFF9BB8D9);
  static final PdfColor _ink = PdfColor.fromInt(0xFF1A2B3C);
  static final PdfColor _muted = PdfColor.fromInt(0xFF5A6B7C);
  static final PdfColor _white = PdfColors.white;
  static final PdfColor _grid = PdfColor.fromInt(0xFFB7CFE6);

  static Future<pw.Font> _regularFont() async {
    final data =
        await rootBundle.load('assets/fonts/pdf/NotoNaskhArabic-Regular.ttf');
    return pw.Font.ttf(data);
  }

  static Future<pw.Font> _boldFont() async {
    final data =
        await rootBundle.load('assets/fonts/pdf/NotoNaskhArabic-Bold.ttf');
    return pw.Font.ttf(data);
  }

  static Future<_StoreBrand> _storeBrand() async {
    final lookups = ServiceLocator.instance.lookups;
    Future<String> read(String key) async {
      final result = await lookups.getSetting(key);
      return result.when(
        success: (v) => (v ?? '').trim(),
        failure: (_) => '',
      );
    }

    final name = await read('store_name');
    final phone = await read('store_phone');
    final email = await read('store_email');
    final address = await read('store_address');
    final logoPath = await read('store_logo');
    pw.MemoryImage? logo;
    if (logoPath.isNotEmpty) {
      try {
        final file = File(logoPath);
        if (await file.exists()) {
          logo = pw.MemoryImage(await file.readAsBytes());
        }
      } catch (_) {}
    }
    return _StoreBrand(
      name: name.isEmpty ? AppConstants.appName : name,
      phone: phone.isEmpty ? null : phone,
      email: email.isEmpty ? null : email,
      address: address.isEmpty ? null : address,
      logo: logo,
    );
  }

  static String stamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
  }

  static String _moneyByCurrency(Iterable<StockMovementModel> rows) {
    final map = <String, double>{};
    for (final m in rows) {
      if (m.unitPrice == null) continue;
      final code = (m.currencyCode ?? '').trim().isEmpty
          ? AppConstants.defaultCurrencyCode
          : m.currencyCode!.trim();
      map[code] = (map[code] ?? 0) + m.lineTotal;
    }
    if (map.isEmpty) return '—';
    final parts = map.entries
        .where((e) => e.value > 0)
        .map((e) => Formatters.money(e.value, currency: e.key))
        .toList();
    return parts.isEmpty ? '—' : parts.join('  |  ');
  }

  static String _paidByCurrency(Iterable<StockMovementModel> rows) {
    final map = <String, double>{};
    for (final m in rows) {
      if (m.unitPrice == null || m.paidAmount <= 0) continue;
      final code = (m.currencyCode ?? '').trim().isEmpty
          ? AppConstants.defaultCurrencyCode
          : m.currencyCode!.trim();
      map[code] = (map[code] ?? 0) + m.paidAmount;
    }
    if (map.isEmpty) return '—';
    return map.entries
        .map((e) => Formatters.money(e.value, currency: e.key))
        .join('  |  ');
  }

  static String _outstandingByCurrency(Iterable<StockMovementModel> rows) {
    final map = <String, double>{};
    for (final m in rows) {
      if (m.unitPrice == null || m.outstanding <= 0) continue;
      final code = (m.currencyCode ?? '').trim().isEmpty
          ? AppConstants.defaultCurrencyCode
          : m.currencyCode!.trim();
      map[code] = (map[code] ?? 0) + m.outstanding;
    }
    if (map.isEmpty) return '—';
    return map.entries
        .map((e) => Formatters.money(e.value, currency: e.key))
        .join('  |  ');
  }

  static String _price(StockMovementModel m) {
    if (m.unitPrice == null) return '';
    final code = (m.currencyCode ?? '').trim().isEmpty
        ? AppConstants.defaultCurrencyCode
        : m.currencyCode!.trim();
    return Formatters.money(m.unitPrice!, currency: code);
  }

  static String _lineTotal(StockMovementModel m) {
    if (m.unitPrice == null) return '';
    final code = (m.currencyCode ?? '').trim().isEmpty
        ? AppConstants.defaultCurrencyCode
        : m.currencyCode!.trim();
    return Formatters.money(m.lineTotal, currency: code);
  }

  static String _short(String value, int max) {
    final t = value.trim();
    final chars = t.characters;
    if (chars.length <= max) return t;
    return '${chars.take(max - 1)}…';
  }

  static String _stockLabel(ProductStockStatus status) => switch (status) {
        ProductStockStatus.inStock => 'status.inStock'.tr(),
        ProductStockStatus.lowStock => 'status.lowStock'.tr(),
        ProductStockStatus.outOfStock => 'status.outOfStock'.tr(),
      };

  static String _dims(StockMovementModel m) {
    final parts = [
      if (m.lengthM != null) dimToDisplay(m.lengthM),
      if (m.widthM != null) dimToDisplay(m.widthM),
    ];
    if (parts.isEmpty) return '';
    return parts.join(' × ');
  }

  static String _area(StockMovementModel m) {
    if (m.areaM2 <= 0) return '';
    return Formatters.number(m.areaM2, decimals: 2);
  }

  static pw.Widget _txt(
    String text, {
    required pw.Font font,
    double fontSize = 10,
    PdfColor? color,
    pw.TextAlign align = pw.TextAlign.right,
    int? maxLines,
  }) {
    final shaped = PdfPersianText.shape(text);
    return pw.Text(
      shaped,
      textAlign: align,
      textDirection: pw.TextDirection.ltr,
      maxLines: maxLines,
      style: pw.TextStyle(
        font: font,
        fontSize: fontSize,
        color: color ?? _ink,
      ),
    );
  }

  // ─── Icons (simple vector marks matching the mock) ───────────────────────

  static pw.Widget _iconBox({
    required void Function(PdfGraphics canvas, PdfPoint size) paint,
    double size = 12,
  }) {
    return pw.SizedBox(
      width: size,
      height: size,
      child: pw.CustomPaint(
        size: PdfPoint(size, size),
        painter: paint,
      ),
    );
  }

  static void _prepStroke(PdfGraphics c) {
    c
      ..setStrokeColor(_navy)
      ..setLineWidth(1.1);
  }

  static void _strokePerson(PdfGraphics c, PdfPoint s) {
    _prepStroke(c);
    final cx = s.x * 0.5;
    final cy = s.y * 0.32;
    final r = s.x * 0.18;
    c.drawEllipse(cx, cy, r, r);
    c.strokePath();
    c.moveTo(s.x * 0.18, s.y * 0.92);
    c.lineTo(s.x * 0.18, s.y * 0.58);
    c.curveTo(
      s.x * 0.18,
      s.y * 0.48,
      s.x * 0.82,
      s.y * 0.48,
      s.x * 0.82,
      s.y * 0.58,
    );
    c.lineTo(s.x * 0.82, s.y * 0.92);
    c.strokePath();
  }

  static void _strokeCalendar(PdfGraphics c, PdfPoint s) {
    _prepStroke(c);
    c.drawRRect(s.x * 0.12, s.y * 0.22, s.x * 0.76, s.y * 0.66, 1.4, 1.4);
    c.strokePath();
    c.drawLine(s.x * 0.12, s.y * 0.42, s.x * 0.88, s.y * 0.42);
    c.strokePath();
    c.drawLine(s.x * 0.35, s.y * 0.10, s.x * 0.35, s.y * 0.30);
    c.strokePath();
    c.drawLine(s.x * 0.65, s.y * 0.10, s.x * 0.65, s.y * 0.30);
    c.strokePath();
  }

  static void _strokePhone(PdfGraphics c, PdfPoint s) {
    _prepStroke(c);
    c.drawRRect(s.x * 0.28, s.y * 0.08, s.x * 0.44, s.y * 0.84, 1.6, 1.6);
    c.strokePath();
    c.drawLine(s.x * 0.40, s.y * 0.78, s.x * 0.60, s.y * 0.78);
    c.strokePath();
  }

  static void _strokeMail(PdfGraphics c, PdfPoint s) {
    _prepStroke(c);
    c.drawRect(s.x * 0.08, s.y * 0.22, s.x * 0.84, s.y * 0.56);
    c.strokePath();
    c.drawLine(s.x * 0.08, s.y * 0.22, s.x * 0.50, s.y * 0.52);
    c.strokePath();
    c.drawLine(s.x * 0.92, s.y * 0.22, s.x * 0.50, s.y * 0.52);
    c.strokePath();
  }

  static void _strokePin(PdfGraphics c, PdfPoint s) {
    _prepStroke(c);
    c.drawEllipse(s.x * 0.50, s.y * 0.36, s.x * 0.28, s.y * 0.28);
    c.strokePath();
    c.drawEllipse(s.x * 0.50, s.y * 0.36, s.x * 0.10, s.y * 0.10);
    c.strokePath();
    c.drawLine(s.x * 0.50, s.y * 0.64, s.x * 0.50, s.y * 0.92);
    c.strokePath();
  }

  // ─── Shared chrome ───────────────────────────────────────────────────────

  static pw.Widget _shopTitle({
    required pw.Font bold,
    required _StoreBrand brand,
  }) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (brand.logo != null) ...[
          pw.Center(
            child: pw.Container(
              width: 48,
              height: 48,
              margin: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Image(brand.logo!, fit: pw.BoxFit.contain),
            ),
          ),
        ],
        pw.Center(
          child: _txt(
            brand.name,
            font: bold,
            fontSize: 18,
            color: _navy,
            align: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: 14),
      ],
    );
  }

  static void _strokeDoc(PdfGraphics c, PdfPoint s) {
    _prepStroke(c);
    c.drawRRect(s.x * 0.22, s.y * 0.08, s.x * 0.56, s.y * 0.84, 1.2, 1.2);
    c.strokePath();
    c.drawLine(s.x * 0.34, s.y * 0.32, s.x * 0.66, s.y * 0.32);
    c.strokePath();
    c.drawLine(s.x * 0.34, s.y * 0.50, s.x * 0.66, s.y * 0.50);
    c.strokePath();
    c.drawLine(s.x * 0.34, s.y * 0.68, s.x * 0.58, s.y * 0.68);
    c.strokePath();
  }

  static pw.Widget _infoBar({
    required pw.Font bold,
    required pw.Font regular,
    required String subject,
    required String periodLabel,
    String? companyName,
  }) {
    pw.Widget cell({
      required pw.Widget icon,
      required String label,
      required String value,
    }) {
      return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  _txt(label, font: regular, fontSize: 9, color: _navy),
                  pw.SizedBox(width: 6),
                  icon,
                ],
              ),
              pw.SizedBox(height: 4),
              _txt(value, font: bold, fontSize: 11, color: _ink),
            ],
          ),
        ),
      );
    }

    final company = (companyName ?? '').trim();
    final children = <pw.Widget>[
      cell(
        icon: _iconBox(paint: _strokeCalendar),
        label: 'pdfReport.dateLabel'.tr(),
        value: periodLabel,
      ),
      pw.Container(width: 0.8, height: 52, color: _softBorder),
      if (company.isNotEmpty) ...[
        cell(
          icon: _iconBox(paint: _strokePerson),
          label: 'pdfReport.companyName'.tr(),
          value: company,
        ),
        pw.Container(width: 0.8, height: 52, color: _softBorder),
      ],
      cell(
        icon: _iconBox(paint: _strokeDoc),
        label: 'pdfReport.subject'.tr(),
        value: subject,
      ),
    ];

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _softBlue,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _softBorder, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  static String subjectForKind(PdfMovementExportKind kind) => switch (kind) {
        PdfMovementExportKind.inbound => 'pdfReport.subjectInbound'.tr(),
        PdfMovementExportKind.outbound => 'pdfReport.subjectOutbound'.tr(),
        PdfMovementExportKind.both => 'pdfReport.subjectBoth'.tr(),
      };

  static pw.Widget _styledTable({
    required pw.Font bold,
    required pw.Font regular,
    required List<String> headers,
    required List<List<String>> dataRows,
    required List<double> widths,
    int minRows = _minBlankRows,
  }) {
    // Paint RTL: reverse so first logical column sits on the right.
    final orderedHeaders = headers.reversed.toList();
    final orderedWidths = widths.reversed.toList();
    final filled = <List<String>>[
      for (final row in dataRows) [...row.reversed],
    ];
    final target = dataRows.isEmpty
        ? minRows
        : (dataRows.length < minRows ? minRows : dataRows.length);
    while (filled.length < target) {
      final n = filled.length + 1;
      filled.add(
        List<String>.generate(
          orderedHeaders.length,
          (col) => col == orderedHeaders.length - 1 ? '$n' : '',
        ),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: orderedHeaders.map(PdfPersianText.shape).toList(),
      data: [
        for (final row in filled)
          [
            for (final c in row)
              c.trim().isEmpty ? ' ' : PdfPersianText.shape(c),
          ],
      ],
      headerStyle: pw.TextStyle(
        font: bold,
        fontSize: 9,
        color: _white,
      ),
      cellStyle: pw.TextStyle(font: regular, fontSize: 8, color: _ink),
      headerDecoration: pw.BoxDecoration(color: _navy),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      columnWidths: {
        for (var i = 0; i < orderedWidths.length; i++)
          i: pw.FlexColumnWidth(orderedWidths[i]),
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      border: pw.TableBorder.all(color: _grid, width: 0.55),
    );
  }

  static pw.Widget _contactFooter({
    required pw.Font bold,
    required pw.Font regular,
    required _StoreBrand brand,
  }) {
    pw.Widget cell({
      required void Function(PdfGraphics, PdfPoint) icon,
      required String value,
      required String label,
    }) {
      return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: _txt(
                      value.isEmpty ? '—' : value,
                      font: bold,
                      fontSize: 8,
                      color: _ink,
                      align: pw.TextAlign.center,
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  _iconBox(paint: icon, size: 11),
                ],
              ),
              pw.SizedBox(height: 2),
              _txt(
                label,
                font: regular,
                fontSize: 7,
                color: _muted,
                align: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(height: 1.2, color: _navyDeep),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Visual LTR order: address | email | phone | seller (RTL reading).
            cell(
              icon: _strokePin,
              value: brand.address ?? '',
              label: 'pdfReport.addressLabel'.tr(),
            ),
            pw.Container(width: 0.7, height: 32, color: _softBorder),
            cell(
              icon: _strokeMail,
              value: brand.email ?? '',
              label: 'pdfReport.emailLabel'.tr(),
            ),
            pw.Container(width: 0.7, height: 32, color: _softBorder),
            cell(
              icon: _strokePhone,
              value: brand.phone ?? '',
              label: 'pdfReport.phoneLabel'.tr(),
            ),
            pw.Container(width: 0.7, height: 32, color: _softBorder),
            cell(
              icon: _strokePerson,
              value: brand.name,
              label: 'pdfReport.sellerName'.tr(),
            ),
          ],
        ),
      ],
    );
  }

  /// Shop address / email / phone row — pinned to the bottom of every PDF page.
  static pw.Widget _pageFooter({
    required pw.Font bold,
    required pw.Font regular,
    required _StoreBrand brand,
  }) {
    return _contactFooter(bold: bold, regular: regular, brand: brand);
  }

  static String _companyOf(StockMovementModel m) {
    final n = (m.partnerName ?? '').trim();
    return n.isEmpty ? '—' : n;
  }

  static List<List<String>> _movementInvoiceRows(
    List<StockMovementModel> rows, {
    bool includeCompany = true,
  }) {
    return [
      for (var i = 0; i < rows.length; i++)
        () {
          final m = rows[i];
          final name = (m.productName ?? '').trim();
          final product = name.isEmpty ? '—' : name;
          final dims = _dims(m);
          final area = _area(m);
          final price = _price(m);
          final total = _lineTotal(m);
          return [
            '${i + 1}',
            _short(product, includeCompany ? 28 : 42),
            if (includeCompany) _short(_companyOf(m), 22),
            dims.isEmpty ? '—' : dims,
            Formatters.number(m.quantity.abs()),
            area.isEmpty ? '—' : area,
            price.isEmpty ? '—' : price,
            total.isEmpty ? '—' : total,
          ];
        }(),
    ];
  }

  static List<pw.Widget> _invoiceBody({
    required pw.Font bold,
    required pw.Font regular,
    required _StoreBrand brand,
    required String subject,
    required String periodLabel,
    required List<StockMovementModel> movements,
    String? companyName,
    bool includeCompanyColumn = true,
  }) {
    final sliced = movements.take(_maxRows).toList();

    final headers = <String>[
      'pdfReport.number'.tr(),
      'pdfReport.typeMaterial'.tr(),
      if (includeCompanyColumn) 'pdfReport.companyName'.tr(),
      'pdfReport.dimensions'.tr(),
      'pdfReport.qty'.tr(),
      'pdfReport.meterage'.tr(),
      'pdfReport.unitPrice'.tr(),
      'pdfReport.lineTotal'.tr(),
    ];
    final widths = includeCompanyColumn
        ? const [0.5, 1.8, 1.4, 1.0, 0.75, 0.85, 1.0, 1.1]
        : const [0.55, 2.4, 1.15, 0.85, 0.95, 1.1, 1.2];

    return [
      _shopTitle(bold: bold, brand: brand),
      _infoBar(
        bold: bold,
        regular: regular,
        subject: subject,
        periodLabel: periodLabel,
        companyName: companyName,
      ),
      pw.SizedBox(height: 12),
      _styledTable(
        bold: bold,
        regular: regular,
        headers: headers,
        widths: widths,
        minRows: _minBlankRows,
        dataRows: sliced.isEmpty
            ? const <List<String>>[]
            : _movementInvoiceRows(
                sliced,
                includeCompany: includeCompanyColumn,
              ),
      ),
      if (movements.length > _maxRows) ...[
        pw.SizedBox(height: 6),
        _txt(
          'pdfReport.truncated'.tr(
            namedArgs: {
              'shown': '$_maxRows',
              'total': '${movements.length}',
            },
          ),
          font: regular,
          fontSize: 8,
          color: _muted,
        ),
      ],
      pw.SizedBox(height: 8),
      _paymentSummaryBlock(
        bold: bold,
        regular: regular,
        grandTotal: _moneyByCurrency(sliced),
        paid: _paidByCurrency(sliced),
        remaining: _outstandingByCurrency(sliced),
      ),
    ];
  }

  /// Compact totals: Total / Paid / Balance in a short right-aligned strip.
  static pw.Widget _paymentSummaryBlock({
    required pw.Font bold,
    required pw.Font regular,
    required String grandTotal,
    required String paid,
    required String remaining,
  }) {
    pw.Widget line(String label, String value, {bool emphasize = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            _txt(
              value,
              font: emphasize ? bold : regular,
              fontSize: emphasize ? 9 : 8.5,
              color: _ink,
            ),
            pw.SizedBox(width: 8),
            pw.SizedBox(
              width: 56,
              child: _txt(
                label,
                font: regular,
                fontSize: 8,
                color: _muted,
                align: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Container(
        decoration: pw.BoxDecoration(
          color: _softBlue,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _softBorder, width: 0.6),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            line('common.total'.tr(), grandTotal, emphasize: true),
            line('common.paid'.tr(), paid),
            line('pdfReport.balance'.tr(), remaining, emphasize: true),
          ],
        ),
      ),
    );
  }

  // ─── Public builders ─────────────────────────────────────────────────────

  static Future<Uint8List> buildCompanyReport(
    BuildContext context, {
    required String companyName,
    String? companyPhone,
    String? companyAddress,
    required String periodLabel,
    required List<StockMovementModel> movements,
    PdfMovementExportKind kind = PdfMovementExportKind.both,
    String? purchaseSubject,
    String? salesSubject,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final store = await _storeBrand();
    final inboundSubject =
        purchaseSubject ?? 'pdfReport.subjectInbound'.tr();
    final outboundSubject =
        salesSubject ?? 'pdfReport.subjectOutbound'.tr();

    final doc = pw.Document();

    List<pw.Widget> bodyFor(
      List<StockMovementModel> rows, {
      required String subject,
    }) {
      return _invoiceBody(
        bold: bold,
        regular: regular,
        brand: store,
        subject: subject,
        periodLabel: periodLabel,
        companyName: companyName,
        movements: rows,
        includeCompanyColumn: false,
      );
    }

    void addSingle(List<StockMovementModel> rows, {required String subject}) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: _pageMargin,
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          footer: (_) => _pageFooter(
            bold: bold,
            regular: regular,
            brand: store,
          ),
          build: (_) => [
            ...bodyFor(rows, subject: subject),
          ],
        ),
      );
    }

    if (kind == PdfMovementExportKind.both) {
      final outbound = movements.where((m) => m.quantity < 0).toList();
      final inbound = movements.where((m) => m.quantity >= 0).toList();
      final sections = <(List<StockMovementModel>, String)>[
        if (outbound.isNotEmpty) (outbound, outboundSubject),
        if (inbound.isNotEmpty) (inbound, inboundSubject),
      ];
      if (sections.isEmpty) {
        addSingle(const [], subject: 'pdfReport.subjectCompanyLog'.tr());
      } else if (sections.length == 1) {
        addSingle(sections.first.$1, subject: sections.first.$2);
      } else {
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: _pageMargin,
            theme: pw.ThemeData.withFont(base: regular, bold: bold),
            footer: (_) => _pageFooter(
              bold: bold,
              regular: regular,
              brand: store,
            ),
            build: (_) => [
              ...bodyFor(sections[0].$1, subject: sections[0].$2),
              pw.SizedBox(height: 18),
              pw.Container(height: 1, color: _navy),
              pw.SizedBox(height: 18),
              ...bodyFor(sections[1].$1, subject: sections[1].$2),
            ],
          ),
        );
      }
    } else {
      final subject = kind == PdfMovementExportKind.inbound
          ? inboundSubject
          : outboundSubject;
      addSingle(movements, subject: subject);
    }

    return doc.save();
  }

  /// Clear account statement: balances by side + payment history.
  static Future<Uint8List> buildCompanyPaymentStatement(
    BuildContext context, {
    required String companyName,
    required List<CompanyPaymentModel> payments,
    required List<StockMovementModel> movements,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final store = await _storeBrand();

    Map<String, double> outstandingSide({required bool payable}) {
      final map = <String, double>{};
      for (final m in movements) {
        if (m.outstanding <= 0) continue;
        final isPayable = m.quantity >= 0;
        if (payable != isPayable) continue;
        final code = (m.currencyCode ?? '').trim().isEmpty
            ? AppConstants.defaultCurrencyCode
            : m.currencyCode!.trim();
        map[code] = (map[code] ?? 0) + m.outstanding;
      }
      return map;
    }

    final weOwe = outstandingSide(payable: true);
    final theyOwe = outstandingSide(payable: false);
    final sliced = payments.take(_maxRows).toList();

    String moneyMap(Map<String, double> map) {
      if (map.isEmpty) return '—';
      final parts = map.entries
          .where((e) => e.value > 0.0001)
          .map((e) => Formatters.money(e.value, currency: e.key))
          .toList();
      return parts.isEmpty ? '—' : parts.join('  |  ');
    }

    pw.Widget balanceCard({
      required String title,
      required String hint,
      required String amount,
      required PdfColor accent,
    }) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: _softBlue,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: _softBorder, width: 0.8),
          ),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _txt(title, font: bold, fontSize: 11, color: accent),
              pw.SizedBox(height: 4),
              _txt(hint, font: regular, fontSize: 8, color: _muted),
              pw.SizedBox(height: 8),
              _txt(amount, font: bold, fontSize: 12, color: _ink),
            ],
          ),
        ),
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: _pageMargin,
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          footer: (_) => _pageFooter(
            bold: bold,
            regular: regular,
            brand: store,
          ),
          build: (_) => [
          _shopTitle(bold: bold, brand: store),
          _infoBar(
            bold: bold,
            regular: regular,
            subject: 'pdfReport.subjectPaymentStatement'.tr(),
            periodLabel: Formatters.date(DateTime.now()),
            companyName: companyName,
          ),
          pw.SizedBox(height: 14),
          _txt(
            'pdfReport.accountBalances'.tr(),
            font: bold,
            fontSize: 11,
            color: _navy,
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              balanceCard(
                title: 'pdfReport.weOweThem'.tr(),
                hint: 'pdfReport.weOweThemHint'.tr(),
                amount: moneyMap(weOwe),
                accent: PdfColor.fromInt(0xFFB42318),
              ),
              pw.SizedBox(width: 10),
              balanceCard(
                title: 'pdfReport.theyOweUs'.tr(),
                hint: 'pdfReport.theyOweUsHint'.tr(),
                amount: moneyMap(theyOwe),
                accent: PdfColor.fromInt(0xFFB54708),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _txt(
            'pdfReport.paymentHistory'.tr(),
            font: bold,
            fontSize: 11,
            color: _navy,
          ),
          pw.SizedBox(height: 8),
          if (sliced.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 12),
              child: _txt(
                'pdfReport.noPayments'.tr(),
                font: regular,
                fontSize: 10,
                color: _muted,
                align: pw.TextAlign.center,
              ),
            )
          else
            _styledTable(
              bold: bold,
              regular: regular,
              headers: [
                'pdfReport.number'.tr(),
                'common.date'.tr(),
                'pdfReport.settlementType'.tr(),
                'pdfReport.amount'.tr(),
                'pdfReport.notes'.tr(),
              ],
              widths: const [0.45, 1.1, 1.8, 1.3, 2.2],
              minRows: 1,
              dataRows: [
                for (var i = 0; i < sliced.length; i++)
                  () {
                    final p = sliced[i];
                    final side =
                        p.settlementSide == PaymentSettlementSide.payable
                            ? 'pdfReport.settlementWePay'.tr()
                            : 'pdfReport.settlementTheyPay'.tr();
                    return [
                      '${i + 1}',
                      Formatters.date(p.paidAt),
                      side,
                      Formatters.money(p.amount, currency: p.currency),
                      _short((p.notes ?? '').trim().isEmpty ? '—' : p.notes!, 40),
                    ];
                  }(),
              ],
            ),
          if (payments.length > _maxRows) ...[
            pw.SizedBox(height: 6),
            _txt(
              'pdfReport.truncated'.tr(
                namedArgs: {
                  'shown': '$_maxRows',
                  'total': '${payments.length}',
                },
              ),
              font: regular,
              fontSize: 8,
              color: _muted,
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> buildMovementsReport(
    BuildContext context, {
    required String periodLabel,
    required String filterLabel,
    required List<StockMovementModel> movements,
    PdfMovementExportKind kind = PdfMovementExportKind.both,
  }) {
    return buildMovementsInvoice(
      context,
      periodLabel: periodLabel,
      kind: kind,
      movements: movements,
    );
  }

  /// Invoice PDF matching the shop template for inbound / outbound movements.
  ///
  /// [movements] should already be scoped by the caller for inbound/outbound.
  /// For [PdfMovementExportKind.both], this method splits into sections and
  /// only emits a section when that side has rows (avoids blank pages).
  static Future<Uint8List> buildMovementsInvoice(
    BuildContext context, {
    required String periodLabel,
    required PdfMovementExportKind kind,
    required List<StockMovementModel> movements,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final store = await _storeBrand();

    final doc = pw.Document();

    List<pw.Widget> bodyFor(
      List<StockMovementModel> rows, {
      required String subject,
    }) {
      return _invoiceBody(
        bold: bold,
        regular: regular,
        brand: store,
        subject: subject,
        periodLabel: periodLabel,
        movements: rows,
        includeCompanyColumn: true,
      );
    }

    void addSingle(List<StockMovementModel> rows, {required String subject}) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: _pageMargin,
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          footer: (_) => _pageFooter(
            bold: bold,
            regular: regular,
            brand: store,
          ),
          build: (_) => [
            ...bodyFor(rows, subject: subject),
          ],
        ),
      );
    }

    if (kind == PdfMovementExportKind.both) {
      final outbound = movements.where((m) => m.quantity < 0).toList();
      final inbound = movements.where((m) => m.quantity >= 0).toList();
      final sections = <(List<StockMovementModel>, String)>[
        if (outbound.isNotEmpty)
          (outbound, 'pdfReport.subjectOutbound'.tr()),
        if (inbound.isNotEmpty) (inbound, 'pdfReport.subjectInbound'.tr()),
      ];
      if (sections.isEmpty) {
        addSingle(const [], subject: subjectForKind(kind));
      } else if (sections.length == 1) {
        addSingle(sections.first.$1, subject: sections.first.$2);
      } else {
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: _pageMargin,
            theme: pw.ThemeData.withFont(base: regular, bold: bold),
            footer: (_) => _pageFooter(
              bold: bold,
              regular: regular,
              brand: store,
            ),
            build: (_) => [
              ...bodyFor(sections[0].$1, subject: sections[0].$2),
              pw.SizedBox(height: 18),
              pw.Container(height: 1, color: _navy),
              pw.SizedBox(height: 18),
              ...bodyFor(sections[1].$1, subject: sections[1].$2),
            ],
          ),
        );
      }
    } else {
      addSingle(movements, subject: subjectForKind(kind));
    }

    return doc.save();
  }

  static Future<Uint8List> buildWarehouseReport(
    BuildContext context, {
    required List<ProductModel> products,
    String? searchQuery,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final store = await _storeBrand();
    final sliced = products.take(_maxRows).toList();

    final rows = [
      for (var i = 0; i < sliced.length; i++)
        () {
          final p = sliced[i];
          final dims = [
            if (p.standardHeight != null) dimToDisplay(p.standardHeight),
            if (p.standardWidth != null) dimToDisplay(p.standardWidth),
          ].join(' × ');
          return [
            '${i + 1}',
            _short(p.name, 40),
            dims.isEmpty ? '—' : dims,
            Formatters.number(p.currentStock),
            Formatters.number(p.totalAreaM2, decimals: 2),
            _stockLabel(p.stockStatus),
          ];
        }(),
    ];

    final periodLabel = Formatters.date(DateTime.now());
    final subject = (searchQuery != null && searchQuery.trim().isNotEmpty)
        ? 'pdfReport.subjectItemList'.tr()
        : 'pdfReport.subjectWarehouseInventory'.tr();
    final subjectDetail = (searchQuery != null && searchQuery.trim().isNotEmpty)
        ? '${'pdfReport.subjectItemList'.tr()} — ${searchQuery.trim()}'
        : subject;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: _pageMargin,
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          footer: (_) => _pageFooter(
            bold: bold,
            regular: regular,
            brand: store,
          ),
          build: (_) => [
          _shopTitle(bold: bold, brand: store),
          _infoBar(
            bold: bold,
            regular: regular,
            subject: subjectDetail,
            periodLabel: periodLabel,
          ),
          pw.SizedBox(height: 12),
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 12),
              child: _txt(
                'pdfReport.noRows'.tr(),
                font: regular,
                fontSize: 10,
                color: _muted,
                align: pw.TextAlign.center,
              ),
            )
          else
            _styledTable(
              bold: bold,
              regular: regular,
              headers: [
                'pdfReport.number'.tr(),
                'pdfReport.typeMaterial'.tr(),
                'pdfReport.dimensions'.tr(),
                'pdfReport.qty'.tr(),
                'pdfReport.meterage'.tr(),
                'common.status'.tr(),
              ],
              widths: const [0.55, 2.5, 1.2, 0.9, 1.0, 1.1],
              dataRows: rows,
            ),
          ],
        ),
      );
    return doc.save();
  }

  /// Saves the PDF via a file dialog (no print).
  static Future<void> savePdf(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'pdfReport.saveTitle'.tr(),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        lockParentWindow: true,
        bytes: bytes,
      );
      if (path == null || path.isEmpty) return;
      final out = File(path.endsWith('.pdf') ? path : '$path.pdf');
      await out.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      GfToast.success(
        context,
        'pdfReport.saved'.tr(namedArgs: {'path': out.path}),
      );
    } catch (e) {
      if (!context.mounted) return;
      GfToast.error(context, e.toString());
    }
  }

  /// Writes the PDF to a temp file and opens the system print dialog
  /// (or the default PDF reader) — no save dialog.
  static Future<void> printPdf(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final safeName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
      final out = File('${dir.path}${Platform.pathSeparator}$safeName');
      await out.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      await openSystemPrintDialog(out.path);
    } catch (e) {
      if (!context.mounted) return;
      GfToast.error(context, e.toString());
    }
  }

  /// Opens the OS print dialog for a PDF. Falls back to opening the file.
  static Future<void> openSystemPrintDialog(String filePath) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            'Start-Process -FilePath ${jsonString(filePath)} -Verb Print',
          ],
          runInShell: false,
        );
        if (result.exitCode != 0) {
          await Process.start('cmd', ['/c', 'start', '', filePath]);
        }
      } else if (Platform.isMacOS) {
        await Process.start('lpr', [filePath]);
      } else {
        await Process.start('xdg-open', [filePath]);
      }
    } catch (_) {
      try {
        if (Platform.isWindows) {
          await Process.start('cmd', ['/c', 'start', '', filePath]);
        } else if (Platform.isMacOS) {
          await Process.start('open', [filePath]);
        } else {
          await Process.start('xdg-open', [filePath]);
        }
      } catch (_) {}
    }
  }

  static String jsonString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", "''");
    return "'$escaped'";
  }

  /// Kept for older call sites; forwards to [savePdf].
  static Future<void> shareOrSave(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    String? subject,
  }) =>
      savePdf(context, bytes: bytes, fileName: fileName);
}

class _StoreBrand {
  const _StoreBrand({
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.logo,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final pw.MemoryImage? logo;
}
