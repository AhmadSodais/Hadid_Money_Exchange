import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../application/customer_service.dart';
import '../../application/read_models.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/security/permissions.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> with RevisionReload {
  final _search = TextEditingController();
  bool _includeInactive = false;
  bool _loading = true;
  List<CustomerRecord> _customers = const [];
  Map<int, Map<String, int>> _positions = const {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final s = session.services;
    final list = await s.customers
        .search(_search.text, includeInactive: _includeInactive, includeWalkIn: true, limit: 500);
    final positions = await s.queries.allCustomerPositions();
    if (!mounted) return;
    setState(() {
      _customers = list;
      _positions = positions;
      _loading = false;
    });
  }

  void _openStatement(CustomerRecord c) => context.go('${AppRoutes.customerStatement}?id=${c.id}');

  Future<void> _onAction(String action, CustomerRecord c) async {
    final s = context.read<AppSession>();
    switch (action) {
      case 'statement':
        _openStatement(c);
      case 'edit':
        await CustomerEditDialog.show(context, existing: c);
      case 'toggle':
        if (c.isActive) {
          final ok = await GfConfirmDialog.show(
            context,
            title: 'غیرفعال کردن مشتری',
            message: '«${c.name}» غیرفعال می‌شود و در جستجوی معاملات نمایش داده نمی‌شود. '
                'حساب‌ها و سوابق او حفظ می‌شوند.',
            confirmLabel: 'غیرفعال کردن',
            cancelLabel: 'انصراف',
            danger: true,
          );
          if (!ok || !mounted) return;
        }
        if (!mounted) return;
        await runAction(
          context,
          () => s.services.customers.setActive(c.id, !c.isActive, s.actor),
          success: c.isActive ? 'مشتری غیرفعال شد.' : 'مشتری فعال شد.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canManage = s.can(Permissions.customersManage);
    return PageScaffold(
      title: 'مشتریان',
      subtitle: 'مثبت = صرافی به مشتری بدهکار است (طلب مشتری) — منفی = مشتری به صرافی بدهکار است',
      searchController: _search,
      searchHint: 'نام، شماره تماس، کد یا شماره مشتری',
      onSearch: (_) => reload(),
      actions: [
        if (canManage)
          GfPrimaryButton(
            label: 'مشتری جدید',
            icon: Icons.person_add_alt,
            onPressed: () => CustomerEditDialog.show(context),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GfCountBox(label: 'تعداد مشتریان', count: _customers.length, icon: AppAssets.customerFilled),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      GfFilterChip(
                        label: 'مشتریان فعال',
                        selected: !_includeInactive,
                        onTap: () {
                          setState(() => _includeInactive = false);
                          reload();
                        },
                      ),
                      const SizedBox(width: 8),
                      GfFilterChip(
                        label: 'همه (با غیرفعال‌ها)',
                        selected: _includeInactive,
                        onTap: () {
                          setState(() => _includeInactive = true);
                          reload();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: LedgerTable(
              title: 'فهرست مشتریان',
              isLoading: _loading,
              minWidth: 1000,
              itemLabel: 'مشتری',
              emptyText: 'مشتری یافت نشد.',
              emptyHint: canManage ? 'برای شروع، «مشتری جدید» را بزنید.' : null,
              columns: const [
                LedgerColumn('کد', width: 100),
                LedgerColumn('نام', flex: 3),
                LedgerColumn('شماره تماس', flex: 2),
                LedgerColumn('حساب‌ها', flex: 5),
                LedgerColumn('وضعیت', width: 90),
                LedgerColumn('', width: LedgerRowMenu.width),
              ],
              rows: [
                for (final c in _customers)
                  [
                    Text(c.code, style: AppTypography.caption),
                    Text(c.name, style: AppTypography.bodyMedium),
                    Text(c.phone ?? '—', textDirection: TextDirection.ltr, style: AppTypography.body),
                    _PositionsCell(positions: _positions[c.id] ?? const {}, session: s),
                    Text(
                      c.isWalkIn
                          ? 'متفرقه'
                          : (c.isActive ? 'فعال' : (c.status == 'anonymized' ? 'بی‌نام‌شده' : 'غیرفعال')),
                      style: AppTypography.caption.copyWith(
                        color: c.isActive ? AppColors.success : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    LedgerRowMenu(
                      onSelected: (a) => _onAction(a, c),
                      items: [
                        gfPopupMenuItem(value: 'statement', label: 'صورت‌حساب'),
                        if (canManage && !c.isWalkIn && c.status != 'anonymized') ...[
                          gfPopupMenuItem(value: 'edit', label: 'ویرایش'),
                          gfPopupMenuItem(
                            value: 'toggle',
                            label: c.isActive ? 'غیرفعال کردن' : 'فعال کردن',
                            danger: c.isActive,
                          ),
                        ],
                      ],
                    ),
                  ],
              ],
              onTapRow: (i) => _openStatement(_customers[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionsCell extends StatelessWidget {
  const _PositionsCell({required this.positions, required this.session});

  final Map<String, int> positions;
  final AppSession session;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) return Text('تسویه', style: AppTypography.caption);
    final codes = positions.keys.toList()
      ..sort((a, b) => (session.currency(a)?.sortOrder ?? 99).compareTo(session.currency(b)?.sortOrder ?? 99));
    String line(String code) =>
        '${session.currency(code)?.nameFa ?? code}: ${MoneyFormat.amount(positions[code]!, session.currency(code))}';
    return Tooltip(
      message: codes.map(line).join('\n'),
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < codes.length; i++) ...[
              if (i > 0) const TextSpan(text: '   '),
              TextSpan(
                text: line(codes[i]),
                style: TextStyle(color: positions[codes[i]]! > 0 ? AppColors.success : AppColors.error),
              ),
            ],
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class CustomerEditDialog extends StatefulWidget {
  const CustomerEditDialog({super.key, this.existing});

  final CustomerRecord? existing;

  static Future<void> show(BuildContext context, {CustomerRecord? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: CustomerEditDialog(existing: existing),
      ),
    );
  }

  @override
  State<CustomerEditDialog> createState() => _CustomerEditDialogState();
}

class _CustomerEditDialogState extends State<CustomerEditDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _idDoc = TextEditingController(text: widget.existing?.idDocument);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _idDoc, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<AppSession>();
    final input = CustomerInput(
      name: _name.text,
      phone: _phone.text,
      idDocument: _idDoc.text,
      address: _address.text,
      notes: _notes.text,
    );
    setState(() => _saving = true);
    final existing = widget.existing;
    final result = await runAction<Object>(
      context,
      () async => existing == null
          ? await s.services.customers.create(input, s.actor)
          : await s.services.customers.update(existing.id, input, s.actor),
      success: existing == null ? 'مشتری ثبت شد.' : 'مشخصات مشتری ذخیره شد.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return GfDialogShell(
      icon: existing == null ? Icons.person_add_alt : Icons.edit_outlined,
      iconColor: AppColors.primary,
      title: existing == null ? 'مشتری جدید' : 'ویرایش مشتری',
      subtitle: existing == null
          ? 'برای مشتری در هر ارز حساب جداگانه ساخته می‌شود.'
          : 'کد مشتری: ${existing.code}',
      cancelLabel: 'انصراف',
      onCancel: () => Navigator.of(context).pop(),
      primaryLabel: 'ذخیره',
      primaryIcon: Icons.save_outlined,
      onPrimary: _save,
      saving: _saving,
      maxWidth: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfTextField(label: 'نام کامل', controller: _name, required: true, autofocus: true),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(label: 'شماره تماس', controller: _phone, keyboardType: TextInputType.phone),
              GfTextField(label: 'شماره تذکره / پاسپورت', controller: _idDoc),
            ],
          ),
          const SizedBox(height: 14),
          GfTextField(label: 'آدرس', controller: _address),
          const SizedBox(height: 14),
          GfTextField(label: 'یادداشت', controller: _notes, minLines: 2, maxLines: 3),
          if (existing == null) ...[
            const SizedBox(height: 14),
            const DialogInfoBanner(
              message: 'کد مشتری به‌صورت خودکار ساخته می‌شود و قابل تغییر نیست.',
            ),
          ],
        ],
      ),
    );
  }
}
