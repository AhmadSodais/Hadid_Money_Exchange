import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/supplier_model.dart';
import '../dialogs/warehouse_dialog_shared.dart';
import '../viewmodels/module_viewmodels.dart';
import '../widgets/app_shell.dart';
import 'trading_company_activity_page.dart';

class _TradingCompany {
  const _TradingCompany({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.lastActivity,
    this.createdAt,
  });

  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final DateTime? lastActivity;
  final DateTime? createdAt;

  TradingCompanyArgs toArgs() => TradingCompanyArgs(
        id: id,
        name: name,
        source: 'supplier',
        phone: phone,
        address: address,
      );
}

/// Trading companies (suppliers) — used for purchases only.
class TradingCompaniesPage extends StatelessWidget {
  const TradingCompaniesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final vm = SuppliersViewModel();
        vm.pageSize = 200;
        return vm..load();
      },
      child: const _TradingCompaniesView(),
    );
  }
}

class _TradingCompaniesView extends StatefulWidget {
  const _TradingCompaniesView();

  @override
  State<_TradingCompaniesView> createState() => _TradingCompaniesViewState();
}

class _TradingCompaniesViewState extends State<_TradingCompaniesView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_TradingCompany> _buildCompanies(List<SupplierModel> suppliers) {
    final q = _search.text.trim().toLowerCase();
    final list = <_TradingCompany>[
      for (final s in suppliers)
        _TradingCompany(
          id: s.id,
          name: s.name,
          phone: s.phone,
          email: s.email,
          address: s.address,
          notes: s.notes,
          lastActivity: s.updatedAt,
          createdAt: s.createdAt,
        ),
    ];

    list.sort((a, b) {
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bAt.compareTo(aAt);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
    if (q.isEmpty) return list;
    return list.where((c) {
      final hay =
          '${c.name} ${c.phone ?? ''} ${c.email ?? ''} ${c.address ?? ''} ${c.notes ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _openActivity(_TradingCompany company) {
    context.push(AppRoutes.tradingCompanyActivity, extra: company.toArgs());
  }

  Widget _detailCell(String? value, {int flex = 2}) {
    final text = (value ?? '').trim();
    return Expanded(
      flex: flex,
      child: Text(
        text.isEmpty ? '—' : text,
        style: AppTypography.body.copyWith(
          color: text.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    SuppliersViewModel suppliersVm, {
    _TradingCompany? company,
  }) async {
    final isEdit = company != null;
    final result = await showDialog<_CompanyFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CompanyFormDialog(isEdit: isEdit, initial: company),
    );
    if (result == null) return;
    if (result.name.isEmpty) {
      if (context.mounted) {
        GfToast.error(context, 'common.nameRequired'.tr());
      }
      return;
    }

    final now = DateTime.now();
    final existing = isEdit
        ? suppliersVm.items.where((e) => e.id == company.id).firstOrNull
        : null;
    final model = SupplierModel(
      id: existing?.id ?? 0,
      name: result.name,
      phone: result.phone,
      email: result.email,
      address: result.address,
      notes: result.notes,
      isArchived: existing?.isArchived ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final err = await suppliersVm.save(model, isNew: !isEdit);

    if (context.mounted) {
      err == null
          ? GfToast.success(
              context,
              isEdit
                  ? 'tradingCompanies.updated'.tr()
                  : 'tradingCompanies.added'.tr(),
            )
          : GfToast.error(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliersVm = context.watch<SuppliersViewModel>();
    final companies = _buildCompanies(suppliersVm.items);

    return PageScaffold(
      title: 'tradingCompanies.title'.tr(),
      subtitle: 'tradingCompanies.subtitle'.tr(),
      searchController: _search,
      searchHint: 'tradingCompanies.searchHint'.tr(),
      onSearch: (_) => setState(() {}),
      actions: [
        GfPrimaryButton(
          label: 'tradingCompanies.addCompany'.tr(),
          icon: Icons.add,
          onPressed: () => _openForm(context, suppliersVm),
        ),
      ],
      body: suppliersVm.loading
          ? const GfPageLoader()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GfCountBox(
                    label: 'tradingCompanies.totalCompanies'.tr(),
                    count: companies.length,
                    icon: AppAssets.suppliersFilled,
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: GfDataTable(
                    title: 'tradingCompanies.tableTitle'.tr(),
                    minWidth: gfTableMinWidth(context, preferred: 720),
                    columns: [
                      GfTableColumn(
                        label: 'tradingCompanies.companyName'.tr(),
                        flex: 3,
                      ),
                      GfTableColumn(label: 'common.phone'.tr(), flex: 2),
                      GfTableColumn(label: 'common.email'.tr(), flex: 2),
                      GfTableColumn(label: 'common.address'.tr(), flex: 3),
                      const GfTableColumn(label: '', width: 48),
                    ],
                    rowCount: companies.length,
                    total: companies.length,
                    clientSide: true,
                    itemLabel: 'common.records'.tr(),
                    empty: GfEmptyState(
                      title: 'tradingCompanies.empty'.tr(),
                      subtitle: 'tradingCompanies.emptyHint'.tr(),
                      compact: true,
                    ),
                    rowBuilder: (context, i) {
                      final c = companies[i];
                      return GfTableRow(
                        onTap: () => _openActivity(c),
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              c.name,
                              style: AppTypography.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _detailCell(c.phone),
                          _detailCell(c.email),
                          _detailCell(c.address, flex: 3),
                          SizedBox(
                            width: 48,
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              color: AppColors.modal,
                              onSelected: (v) async {
                                if (v == 'view') {
                                  _openActivity(c);
                                } else if (v == 'edit') {
                                  await _openForm(
                                    context,
                                    suppliersVm,
                                    company: c,
                                  );
                                } else if (v == 'delete') {
                                  final ok = await GfConfirmDialog.show(
                                    context,
                                    title: 'tradingCompanies.deleteTitle'.tr(),
                                    message:
                                        'tradingCompanies.deleteMessage'.tr(
                                      namedArgs: {'name': c.name},
                                    ),
                                    confirmLabel: 'common.delete'.tr(),
                                    danger: true,
                                  );
                                  if (ok != true) return;
                                  final err = await suppliersVm.delete(c.id);
                                  if (context.mounted) {
                                    err == null
                                        ? GfToast.success(
                                            context,
                                            'tradingCompanies.deleted'.tr(),
                                          )
                                        : GfToast.error(context, err);
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                gfPopupMenuItem(
                                  value: 'view',
                                  label: 'common.view'.tr(),
                                ),
                                gfPopupMenuItem(
                                  value: 'edit',
                                  label: 'common.edit'.tr(),
                                ),
                                gfPopupMenuItem(
                                  value: 'delete',
                                  label: 'common.delete'.tr(),
                                  danger: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _CompanyFormResult {
  const _CompanyFormResult({
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
}

class _CompanyFormDialog extends StatefulWidget {
  const _CompanyFormDialog({required this.isEdit, this.initial});

  final bool isEdit;
  final _TradingCompany? initial;

  @override
  State<_CompanyFormDialog> createState() => _CompanyFormDialogState();
}

class _CompanyFormDialogState extends State<_CompanyFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    Navigator.pop(
      context,
      _CompanyFormResult(
        name: name,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.apartment_outlined,
      iconColor: AppColors.primary,
      title: widget.isEdit
          ? 'tradingCompanies.editCompany'.tr()
          : 'tradingCompanies.addCompany'.tr(),
      subtitle: 'tradingCompanies.formSubtitle'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onCancel: () => Navigator.pop(context),
      onPrimary: _save,
      maxWidth: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfTextField(
            controller: _name,
            label: 'tradingCompanies.companyName'.tr(),
            required: true,
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(controller: _phone, label: 'common.phone'.tr()),
              GfTextField(controller: _email, label: 'common.email'.tr()),
            ],
          ),
          const SizedBox(height: 14),
          GfTextField(controller: _address, label: 'common.address'.tr()),
          const SizedBox(height: 14),
          GfTextField(
            controller: _notes,
            label: 'common.note'.tr(),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
