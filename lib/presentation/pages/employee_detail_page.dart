import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../dialogs/warehouse_dialog_shared.dart' show DialogResponsiveRow;
import '../widgets/app_shell.dart';

enum _DetailTab { overview, receipts, withdrawals }

class EmployeeDetailPage extends StatefulWidget {
  const EmployeeDetailPage({super.key, required this.employeeId});

  final int employeeId;

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage> {
  DateFilterValue _dateFilter = DateFilterValue.today();
  _DetailTab _tab = _DetailTab.overview;
  EmployeeModel? _employee;
  List<StockMovementModel> _movements = const [];
  List<EmployeeWithdrawalModel> _withdrawals = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ServiceLocator.instance.employees;
    final emp = await repo.getById(
      widget.employeeId,
      from: _dateFilter.from,
      to: _dateFilter.to,
    );
    final moves = await repo.getMovements(
      widget.employeeId,
      from: _dateFilter.from,
      to: _dateFilter.to,
    );
    final withdrawals = await repo.getWithdrawals(widget.employeeId);
    if (!mounted) return;
    setState(() {
      _employee = emp.when(success: (v) => v, failure: (_) => null);
      _movements = moves.when(success: (v) => v, failure: (_) => const []);
      _withdrawals =
          withdrawals.when(success: (v) => v, failure: (_) => const []);
      _loading = false;
    });
  }

  Future<void> _addWithdrawal() async {
    final e = _employee;
    if (e == null) return;
    final result = await showDialog<_WithdrawalFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WithdrawalFormDialog(
        currency: e.salaryCurrency,
        remaining: e.remainingBalance,
      ),
    );
    if (result == null || !mounted) return;
    final now = DateTime.now();
    final save = await ServiceLocator.instance.employees.addWithdrawal(
      EmployeeWithdrawalModel(
        id: 0,
        employeeId: e.id,
        label: result.label,
        amount: result.amount,
        currency: result.currency,
        withdrawnAt: result.withdrawnAt,
        paymentMethod: result.paymentMethod,
        notes: result.notes,
        createdAt: now,
      ),
    );
    if (!mounted) return;
    save.when(
      success: (_) {
        GfToast.success(context, 'employees.withdrawalAdded'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _deleteWithdrawal(EmployeeWithdrawalModel w) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'employees.deleteWithdrawalTitle'.tr(),
      message: 'employees.deleteWithdrawalMessage'.tr(),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    final result =
        await ServiceLocator.instance.employees.deleteWithdrawal(w.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'employees.withdrawalDeleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _employee;
    final subtitle = e == null
        ? 'employees.detailSubtitle'.tr()
        : [
            if ((e.role ?? '').isNotEmpty) 'employees.roles.${e.role}'.tr(),
            if ((e.department ?? '').isNotEmpty) e.department!,
            'employees.detailSubtitle'.tr(),
          ].join(' · ');

    return PageScaffold(
      leading: Row(
        children: [
          GfIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'common.back'.tr(),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.employees);
              }
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e?.fullName ?? 'employees.title'.tr(),
                  style: AppTypography.localize(
                    AppTypography.pageTitle,
                    context: context,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.localize(
                    AppTypography.subtitle,
                    context: context,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      title: e?.fullName ?? 'employees.title'.tr(),
      actions: [
        GfDateFilter(
          value: _dateFilter,
          onChanged: (v) {
            setState(() => _dateFilter = v);
            _load();
          },
        ),
        if (_tab == _DetailTab.withdrawals)
          GfPrimaryButton(
            label: 'employees.addWithdrawal'.tr(),
            icon: Icons.add,
            onPressed: _addWithdrawal,
          ),
      ],
      body: _loading && e == null
          ? const GfPageLoader()
          : e == null
              ? GfEmptyState(
                  title: 'employees.notFound'.tr(),
                  subtitle: 'employees.notFoundHint'.tr(),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GfKpiGrid(
                      children: [
                        GfKpiCard(
                          title: 'employees.monthlySalary'.tr(),
                          value: Formatters.number(
                            e.baseSalary,
                            decimals: 0,
                          ),
                          icon: AppAssets.expenses,
                        ),
                        GfKpiCard(
                          title: 'employees.withdrawn'.tr(),
                          value: Formatters.number(
                            e.withdrawalTotal,
                            decimals: 0,
                          ),
                          icon: AppAssets.expenses,
                        ),
                        GfKpiCard(
                          title: 'employees.remaining'.tr(),
                          value: Formatters.number(
                            e.remainingBalance,
                            decimals: 0,
                          ),
                          icon: AppAssets.invoice,
                        ),
                        GfKpiCard(
                          title: 'employees.kpiReceipts'.tr(),
                          value: Formatters.number(
                            e.receiptTotal,
                            decimals: 0,
                          ),
                          icon: AppAssets.sales,
                        ),
                      ],
                    ),
                    SizedBox(height: gfSectionGap(context)),
                    _TabBar(
                      tab: _tab,
                      onChanged: (t) => setState(() => _tab = t),
                    ),
                    SizedBox(height: gfSectionGap(context)),
                    Expanded(
                      child: switch (_tab) {
                        _DetailTab.overview => _OverviewTab(
                            employee: e,
                            onAddWithdrawal: _addWithdrawal,
                          ),
                        _DetailTab.receipts => _ReceiptsTab(
                            movements: _movements,
                          ),
                        _DetailTab.withdrawals => _WithdrawalsTab(
                            withdrawals: _withdrawals,
                            onDelete: _deleteWithdrawal,
                            onAdd: _addWithdrawal,
                          ),
                      },
                    ),
                  ],
                ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab, required this.onChanged});

  final _DetailTab tab;
  final ValueChanged<_DetailTab> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(_DetailTab value, String label) {
      final selected = tab == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onChanged(value),
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        labelStyle: AppTypography.label.copyWith(
          color: selected ? AppColors.primary : AppColors.textMuted,
        ),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
        backgroundColor: AppColors.card,
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        chip(_DetailTab.overview, 'employees.tabOverview'.tr()),
        chip(_DetailTab.receipts, 'employees.tabReceipts'.tr()),
        chip(_DetailTab.withdrawals, 'employees.tabWithdrawals'.tr()),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.employee,
    required this.onAddWithdrawal,
  });

  final EmployeeModel employee;
  final VoidCallback onAddWithdrawal;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    return GfCard(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'employees.profile'.tr(),
                  style: AppTypography.sectionTitle,
                ),
              ),
              GfSecondaryButton(
                label: 'employees.addWithdrawal'.tr(),
                icon: Icons.outbox_outlined,
                compact: true,
                onPressed: onAddWithdrawal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow('employees.fullName'.tr(), e.fullName),
          _InfoRow('employees.code'.tr(), e.code ?? '—'),
          _InfoRow('common.phone'.tr(), e.phone ?? '—'),
          _InfoRow('common.email'.tr(), e.email ?? '—'),
          _InfoRow(
            'employees.role'.tr(),
            e.role == null || e.role!.isEmpty
                ? '—'
                : 'employees.roles.${e.role}'.tr(),
          ),
          _InfoRow('employees.department'.tr(), e.department ?? '—'),
          _InfoRow(
            'employees.hireDate'.tr(),
            e.hireDate == null ? '—' : ShamsiDates.formatDate(e.hireDate!),
          ),
          _InfoRow(
            'employees.monthlySalary'.tr(),
            e.baseSalary <= 0
                ? '—'
                : Formatters.money(
                    e.baseSalary,
                    currency: e.salaryCurrency,
                  ),
          ),
          _InfoRow(
            'employees.withdrawn'.tr(),
            Formatters.money(
              e.withdrawalTotal,
              currency: e.salaryCurrency,
            ),
          ),
          _InfoRow(
            'employees.remaining'.tr(),
            Formatters.money(
              e.remainingBalance,
              currency: e.salaryCurrency,
            ),
          ),
          _InfoRow('common.address'.tr(), e.address ?? '—'),
          _InfoRow('common.note'.tr(), e.notes ?? '—'),
          _InfoRow(
            'common.status'.tr(),
            e.isActive ? 'employees.active'.tr() : 'employees.inactive'.tr(),
          ),
          const SizedBox(height: 16),
          Text(
            'employees.performance'.tr(),
            style: AppTypography.sectionTitle,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            'employees.movements'.tr(),
            Formatters.number(e.movementCount),
          ),
          _InfoRow(
            'employees.inbound'.tr(),
            Formatters.number(e.inboundCount),
          ),
          _InfoRow(
            'employees.outbound'.tr(),
            Formatters.number(e.outboundCount),
          ),
          _InfoRow(
            'employees.receiptCount'.tr(),
            Formatters.number(e.receiptCount),
          ),
          _InfoRow(
            'employees.receiptTotal'.tr(),
            Formatters.number(e.receiptTotal, decimals: 0),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: AppTypography.caption),
          ),
          Expanded(
            child: Text(value, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ReceiptsTab extends StatelessWidget {
  const _ReceiptsTab({required this.movements});

  final List<StockMovementModel> movements;

  @override
  Widget build(BuildContext context) {
    return GfDataTable(
      title: 'employees.tabReceipts'.tr(),
      minWidth: gfTableMinWidth(context, preferred: 800),
      columns: [
        GfTableColumn(label: 'common.date'.tr(), flex: 2),
        GfTableColumn(label: 'common.product'.tr(), flex: 3),
        GfTableColumn(label: 'common.quantity'.tr(), flex: 1),
        GfTableColumn(label: 'common.total'.tr(), flex: 2),
        GfTableColumn(label: 'stockEntry.company'.tr(), flex: 2),
      ],
      rowCount: movements.length,
      total: movements.length,
      clientSide: true,
      itemLabel: 'common.records'.tr(),
      empty: GfEmptyState(
        title: 'employees.noReceipts'.tr(),
        subtitle: 'employees.noReceiptsHint'.tr(),
        compact: true,
      ),
      rowBuilder: (context, i) {
        final m = movements[i];
        final inbound = m.quantity >= 0;
        return GfTableRow(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                Formatters.dateTime(m.createdAt),
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                m.productName ?? '—',
                style: AppTypography.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(
                '${inbound ? '+' : ''}${Formatters.number(m.quantity)}',
                style: AppTypography.body.copyWith(
                  color: inbound ? AppColors.success : AppColors.error,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                m.lineTotal <= 0
                    ? '—'
                    : Formatters.number(m.lineTotal, decimals: 0),
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                m.partnerName ?? '—',
                style: AppTypography.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WithdrawalsTab extends StatelessWidget {
  const _WithdrawalsTab({
    required this.withdrawals,
    required this.onDelete,
    required this.onAdd,
  });

  final List<EmployeeWithdrawalModel> withdrawals;
  final ValueChanged<EmployeeWithdrawalModel> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return GfDataTable(
      title: 'employees.tabWithdrawals'.tr(),
      minWidth: gfTableMinWidth(context, preferred: 720),
      columns: [
        GfTableColumn(label: 'employees.withdrawnAt'.tr(), flex: 2),
        GfTableColumn(label: 'employees.withdrawalLabel'.tr(), flex: 2),
        GfTableColumn(label: 'employees.amount'.tr(), flex: 2),
        GfTableColumn(label: 'employees.paymentMethod'.tr(), flex: 2),
        const GfTableColumn(label: '', width: 48),
      ],
      rowCount: withdrawals.length,
      total: withdrawals.length,
      clientSide: true,
      itemLabel: 'common.records'.tr(),
      empty: GfEmptyState(
        title: 'employees.noWithdrawals'.tr(),
        subtitle: 'employees.noWithdrawalsHint'.tr(),
        compact: true,
        actionLabel: 'employees.addWithdrawal'.tr(),
        onAction: onAdd,
      ),
      rowBuilder: (context, i) {
        final w = withdrawals[i];
        return GfTableRow(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                Formatters.date(w.withdrawnAt),
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                w.label ?? '—',
                style: AppTypography.body,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Formatters.money(w.amount, currency: w.currency),
                style: AppTypography.bodyMedium,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                w.paymentMethod == null || w.paymentMethod!.isEmpty
                    ? '—'
                    : 'employees.methods.${w.paymentMethod}'.tr(),
                style: AppTypography.body,
              ),
            ),
            SizedBox(
              width: 48,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.error,
                onPressed: () => onDelete(w),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WithdrawalFormResult {
  const _WithdrawalFormResult({
    required this.amount,
    required this.currency,
    required this.withdrawnAt,
    this.label,
    this.paymentMethod,
    this.notes,
  });

  final double amount;
  final String currency;
  final DateTime withdrawnAt;
  final String? label;
  final String? paymentMethod;
  final String? notes;
}

class _WithdrawalFormDialog extends StatefulWidget {
  const _WithdrawalFormDialog({
    required this.currency,
    required this.remaining,
  });

  final String currency;
  final double remaining;

  @override
  State<_WithdrawalFormDialog> createState() => _WithdrawalFormDialogState();
}

class _WithdrawalFormDialogState extends State<_WithdrawalFormDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _label;
  late final TextEditingController _notes;
  DateTime _withdrawnAt = DateTime.now();
  String? _method = 'cash';

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _currency = TextEditingController(text: widget.currency);
    _label = TextEditingController();
    _notes = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.outbox_outlined,
      iconColor: AppColors.primary,
      title: 'employees.addWithdrawal'.tr(),
      subtitle: 'employees.withdrawalFormSubtitle'.tr(
        namedArgs: {
          'remaining': Formatters.money(
            widget.remaining,
            currency: widget.currency,
          ),
        },
      ),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onCancel: () => Navigator.pop(context),
      onPrimary: () {
        final amount = Formatters.parse(_amount.text) ?? 0;
        if (amount <= 0) return;
        Navigator.pop(
          context,
          _WithdrawalFormResult(
            amount: amount,
            currency: _currency.text.trim().isEmpty
                ? 'AFN'
                : _currency.text.trim(),
            withdrawnAt: _withdrawnAt,
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
            paymentMethod: _method,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ),
        );
      },
      maxWidth: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: _amount,
                label: 'employees.amount'.tr(),
                required: true,
                numberMode: true,
              ),
              GfDropdown<String>(
                label: 'employees.salaryCurrency'.tr(),
                items: const ['AFN', 'USD', 'EUR'],
                value: const ['AFN', 'USD', 'EUR']
                        .contains(_currency.text.trim().toUpperCase())
                    ? _currency.text.trim().toUpperCase()
                    : 'AFN',
                labelBuilder: Formatters.currencyName,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _currency.text = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              final picked = await ShamsiDates.pickDate(
                context,
                initial: _withdrawnAt,
              );
              if (picked != null) setState(() => _withdrawnAt = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'employees.withdrawnAt'.tr(),
                prefixIcon:
                    const Icon(Icons.calendar_today_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                ShamsiDates.formatDate(_withdrawnAt),
                style: AppTypography.body,
              ),
            ),
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: _label,
                label: 'employees.withdrawalLabel'.tr(),
                hint: 'employees.withdrawalLabelHint'.tr(),
              ),
              GfDropdown<String>(
                label: 'employees.paymentMethod'.tr(),
                items: const ['cash', 'bank', 'other'],
                value: _method,
                labelBuilder: (m) => 'employees.methods.$m'.tr(),
                onChanged: (v) => setState(() => _method = v),
              ),
            ],
          ),
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
