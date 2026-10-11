import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/customer_model.dart';
import '../dialogs/warehouse_dialog_shared.dart';
import '../viewmodels/module_viewmodels.dart';
import '../widgets/app_shell.dart';
import 'trading_company_activity_page.dart';

/// Customers section — sales partners used on orders / new sales.
class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final vm = CustomersViewModel();
        vm.pageSize = 200;
        return vm..load();
      },
      child: const _CustomersView(),
    );
  }
}

class _CustomersView extends StatefulWidget {
  const _CustomersView();

  @override
  State<_CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<_CustomersView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CustomerModel> _filtered(List<CustomerModel> items) {
    final q = _search.text.trim().toLowerCase();
    return items.where((c) {
      if (c.name.toLowerCase() == 'walk-in customer') return false;
      if (q.isEmpty) return true;
      final hay =
          '${c.name} ${c.phone ?? ''} ${c.email ?? ''} ${c.address ?? ''} ${c.notes ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _openActivity(CustomerModel c) {
    context.push(
      AppRoutes.tradingCompanyActivity,
      extra: TradingCompanyArgs(
        id: c.id,
        name: c.name,
        source: 'customer',
        phone: c.phone,
        address: c.address,
      ),
    );
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
    CustomersViewModel vm, {
    CustomerModel? customer,
  }) async {
    final isEdit = customer != null;
    final result = await showDialog<_CustomerFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _CustomerFormDialog(isEdit: isEdit, initial: customer),
    );
    if (result == null) return;
    if (result.name.isEmpty) {
      if (context.mounted) {
        GfToast.error(context, 'customers.nameRequired'.tr());
      }
      return;
    }

    final now = DateTime.now();
    final model = CustomerModel(
      id: customer?.id ?? 0,
      name: result.name,
      phone: result.phone,
      email: result.email,
      address: result.address,
      notes: result.notes,
      outstandingBalance: customer?.outstandingBalance ?? 0,
      totalPurchases: customer?.totalPurchases ?? 0,
      lastPurchaseAt: customer?.lastPurchaseAt,
      isArchived: customer?.isArchived ?? false,
      createdAt: customer?.createdAt ?? now,
      updatedAt: now,
    );
    final err = await vm.save(model, isNew: !isEdit);
    if (context.mounted) {
      err == null
          ? GfToast.success(
              context,
              isEdit ? 'customers.updated'.tr() : 'customers.added'.tr(),
            )
          : GfToast.error(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CustomersViewModel>();
    final customers = _filtered(vm.items);

    return PageScaffold(
      title: 'customers.title'.tr(),
      subtitle: 'customers.subtitle'.tr(),
      searchController: _search,
      searchHint: 'customers.searchHint'.tr(),
      onSearch: (_) => setState(() {}),
      actions: [
        GfPrimaryButton(
          label: 'customers.add'.tr(),
          icon: Icons.add,
          onPressed: () => _openForm(context, vm),
        ),
      ],
      body: vm.loading
          ? const GfPageLoader()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GfCountBox(
                    label: 'customers.tableTitle'.tr(),
                    count: customers.length,
                    icon: AppAssets.usersFilled,
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: GfDataTable(
                    title: 'customers.tableTitle'.tr(),
                    minWidth: gfTableMinWidth(context, preferred: 800),
                    columns: [
                      GfTableColumn(
                        label: 'customers.columns.name'.tr(),
                        flex: 3,
                      ),
                      GfTableColumn(
                        label: 'customers.columns.phone'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(
                        label: 'customers.columns.email'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(
                        label: 'customers.columns.outstanding'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(
                        label: 'customers.columns.totalPurchases'.tr(),
                        flex: 2,
                      ),
                      const GfTableColumn(label: '', width: 48),
                    ],
                    rowCount: customers.length,
                    total: customers.length,
                    clientSide: true,
                    itemLabel: 'common.records'.tr(),
                    empty: GfEmptyState(
                      title: 'customers.empty'.tr(),
                      subtitle: 'customers.emptyHint'.tr(),
                      compact: true,
                    ),
                    rowBuilder: (context, i) {
                      final c = customers[i];
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
                          Expanded(
                            flex: 2,
                            child: Text(
                              Formatters.money(c.outstandingBalance),
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              Formatters.money(c.totalPurchases),
                              style: AppTypography.body,
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              color: AppColors.modal,
                              onSelected: (v) async {
                                if (v == 'view') {
                                  _openActivity(c);
                                } else if (v == 'edit') {
                                  await _openForm(context, vm, customer: c);
                                } else if (v == 'delete') {
                                  final ok = await GfConfirmDialog.show(
                                    context,
                                    title: 'customers.deleteTitle'.tr(),
                                    message: 'customers.deleteMessage'.tr(
                                      namedArgs: {'name': c.name},
                                    ),
                                    confirmLabel: 'common.delete'.tr(),
                                    danger: true,
                                  );
                                  if (ok != true) return;
                                  final err = await vm.delete(c.id);
                                  if (context.mounted) {
                                    err == null
                                        ? GfToast.success(
                                            context,
                                            'customers.deleted'.tr(),
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
                                  label: 'customers.editMenu'.tr(),
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

class _CustomerFormResult {
  const _CustomerFormResult({
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

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({required this.isEdit, this.initial});

  final bool isEdit;
  final CustomerModel? initial;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
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
    Navigator.pop(
      context,
      _CustomerFormResult(
        name: _name.text.trim(),
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
      icon: Icons.person_outline_rounded,
      iconColor: AppColors.primary,
      title: widget.isEdit ? 'customers.edit'.tr() : 'customers.add'.tr(),
      subtitle: 'customers.subtitle'.tr(),
      primaryLabel: 'customers.save'.tr(),
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
            label: 'customers.name'.tr(),
            required: true,
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(controller: _phone, label: 'customers.phone'.tr()),
              GfTextField(controller: _email, label: 'customers.email'.tr()),
            ],
          ),
          const SizedBox(height: 14),
          GfTextField(controller: _address, label: 'customers.address'.tr()),
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
