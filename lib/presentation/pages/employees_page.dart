import 'package:easy_localization/easy_localization.dart' hide TextDirection;
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
import '../dialogs/warehouse_dialog_shared.dart' show DialogResponsiveRow;
import '../widgets/app_shell.dart';

const kEmployeeRoles = [
  'Cashier',
  'Warehouse',
  'Manager',
  'Driver',
  'Sales',
  'Accountant',
  'Other',
];

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  final _search = TextEditingController();
  DateFilterValue _dateFilter = DateFilterValue.today();
  List<EmployeeModel> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ServiceLocator.instance.employees.list(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      from: _dateFilter.from,
      to: _dateFilter.to,
      includeInactive: true,
    );
    if (!mounted) return;
    result.when(
      success: (list) => setState(() {
        _items = list;
        _loading = false;
      }),
      failure: (_) => setState(() {
        _items = const [];
        _loading = false;
      }),
    );
  }

  Future<void> _openForm({EmployeeModel? employee}) async {
    final isEdit = employee != null;
    final ok = await showDialog<_EmployeeFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EmployeeFormDialog(isEdit: isEdit, initial: employee),
    );
    if (ok == null || !mounted) return;

    final now = DateTime.now();
    final model = EmployeeModel(
      id: employee?.id ?? 0,
      code: ok.code,
      fullName: ok.fullName,
      phone: ok.phone,
      email: ok.email,
      role: ok.role,
      department: ok.department,
      hireDate: ok.hireDate,
      baseSalary: ok.baseSalary,
      salaryCurrency: ok.salaryCurrency,
      paymentCycle: 'monthly',
      bankAccount: employee?.bankAccount,
      address: ok.address,
      notes: ok.notes,
      isActive: ok.isActive,
      createdAt: employee?.createdAt ?? now,
      updatedAt: now,
    );
    final result = isEdit
        ? await ServiceLocator.instance.employees.update(model)
        : await ServiceLocator.instance.employees.create(model);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(
          context,
          isEdit ? 'employees.updated'.tr() : 'employees.added'.tr(),
        );
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _delete(EmployeeModel e) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'employees.deleteTitle'.tr(),
      message: 'employees.deleteMessage'.tr(namedArgs: {'name': e.fullName}),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    final result = await ServiceLocator.instance.employees.delete(e.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'employees.deleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _items.where((e) => e.isActive).length;
    final salary = _items.fold<double>(0, (s, e) => s + e.baseSalary);
    final withdrawn = _items.fold<double>(0, (s, e) => s + e.withdrawalTotal);

    return PageScaffold(
      title: 'employees.title'.tr(),
      subtitle: 'employees.subtitle'.tr(),
      searchController: _search,
      searchHint: 'employees.searchHint'.tr(),
      onSearch: (_) => _load(),
      actions: [
        GfDateFilter(
          value: _dateFilter,
          onChanged: (v) {
            setState(() => _dateFilter = v);
            _load();
          },
        ),
        GfPrimaryButton(
          label: 'employees.add'.tr(),
          icon: Icons.add,
          onPressed: () => _openForm(),
        ),
      ],
      body: _loading
          ? const GfPageLoader()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GfKpiGrid(
                  children: [
                    GfKpiCard(
                      title: 'employees.kpiTotal'.tr(),
                      value: Formatters.number(_items.length),
                      icon: AppAssets.users,
                    ),
                    GfKpiCard(
                      title: 'employees.kpiActive'.tr(),
                      value: Formatters.number(active),
                      icon: AppAssets.usersFilled,
                    ),
                    GfKpiCard(
                      title: 'employees.kpiPayroll'.tr(),
                      value: Formatters.number(salary, decimals: 0),
                      icon: AppAssets.expenses,
                    ),
                    GfKpiCard(
                      title: 'employees.kpiWithdrawn'.tr(),
                      value: Formatters.number(withdrawn, decimals: 0),
                      icon: AppAssets.expenses,
                    ),
                  ],
                ),
                SizedBox(height: gfSectionGap(context)),
                Expanded(
                  child: GfDataTable(
                    title: 'employees.tableTitle'.tr(),
                    minWidth: gfTableMinWidth(context, preferred: 960),
                    columns: [
                      GfTableColumn(label: 'employees.name'.tr(), flex: 3),
                      GfTableColumn(label: 'employees.role'.tr(), flex: 2),
                      GfTableColumn(label: 'employees.monthlySalary'.tr(), flex: 2),
                      GfTableColumn(label: 'employees.withdrawn'.tr(), flex: 2),
                      GfTableColumn(label: 'employees.remaining'.tr(), flex: 2),
                      GfTableColumn(label: 'common.status'.tr(), flex: 1),
                      const GfTableColumn(label: '', width: 48),
                    ],
                    rowCount: _items.length,
                    total: _items.length,
                    clientSide: true,
                    itemLabel: 'common.records'.tr(),
                    empty: GfEmptyState(
                      title: 'employees.empty'.tr(),
                      subtitle: 'employees.emptyHint'.tr(),
                      compact: true,
                    ),
                    rowBuilder: (context, i) {
                      final e = _items[i];
                      final contact = [
                        if ((e.code ?? '').isNotEmpty) e.code!,
                        if ((e.phone ?? '').isNotEmpty) e.phone!,
                      ].join(' · ');
                      final roleLine = [
                        if ((e.role ?? '').isNotEmpty)
                          'employees.roles.${e.role}'.tr(),
                        if ((e.department ?? '').isNotEmpty) e.department!,
                      ].join(' · ');
                      return GfTableRow(
                        onTap: () => context.push(
                          AppRoutes.employeeDetail,
                          extra: e.id,
                        ),
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  e.fullName,
                                  style: AppTypography.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (contact.isNotEmpty)
                                  Text(
                                    contact,
                                    style: AppTypography.caption,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              roleLine.isEmpty ? '—' : roleLine,
                              style: AppTypography.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              e.baseSalary <= 0
                                  ? '—'
                                  : Formatters.money(
                                      e.baseSalary,
                                      currency: e.salaryCurrency,
                                    ),
                              style: AppTypography.body,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              e.withdrawalTotal <= 0
                                  ? '—'
                                  : Formatters.money(
                                      e.withdrawalTotal,
                                      currency: e.salaryCurrency,
                                    ),
                              style: AppTypography.body.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              e.baseSalary <= 0 && e.withdrawalTotal <= 0
                                  ? '—'
                                  : Formatters.money(
                                      e.remainingBalance,
                                      currency: e.salaryCurrency,
                                    ),
                              style: AppTypography.body.copyWith(
                                color: e.remainingBalance >= 0
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: GfStatusBadge(
                                label: e.isActive
                                    ? 'employees.active'.tr()
                                    : 'employees.inactive'.tr(),
                                variant: e.isActive
                                    ? GfStatusVariant.completed
                                    : GfStatusVariant.cancelled,
                                compact: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              color: AppColors.modal,
                              onSelected: (v) {
                                if (v == 'view') {
                                  context.push(
                                    AppRoutes.employeeDetail,
                                    extra: e.id,
                                  );
                                } else if (v == 'edit') {
                                  _openForm(employee: e);
                                } else if (v == 'delete') {
                                  _delete(e);
                                }
                              },
                              itemBuilder: (_) => [
                                gfPopupMenuItem(
                                  value: 'view',
                                  label: 'employees.viewDetails'.tr(),
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

class _EmployeeFormResult {
  const _EmployeeFormResult({
    required this.fullName,
    this.code,
    this.phone,
    this.email,
    this.role,
    this.department,
    this.hireDate,
    required this.baseSalary,
    this.salaryCurrency = 'AFN',
    this.address,
    this.notes,
    this.isActive = true,
  });

  final String fullName;
  final String? code;
  final String? phone;
  final String? email;
  final String? role;
  final String? department;
  final DateTime? hireDate;
  final double baseSalary;
  final String salaryCurrency;
  final String? address;
  final String? notes;
  final bool isActive;
}

class _EmployeeFormDialog extends StatefulWidget {
  const _EmployeeFormDialog({required this.isEdit, this.initial});

  final bool isEdit;
  final EmployeeModel? initial;

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _department;
  late final TextEditingController _salary;
  late final TextEditingController _currency;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  String? _role;
  DateTime? _hireDate;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _name = TextEditingController(text: e?.fullName ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _department = TextEditingController(text: e?.department ?? '');
    _salary = TextEditingController(
      text: e == null || e.baseSalary <= 0
          ? ''
          : Formatters.number(e.baseSalary),
    );
    _currency = TextEditingController(text: e?.salaryCurrency ?? 'AFN');
    _address = TextEditingController(text: e?.address ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _role = e?.role;
    _hireDate = e?.hireDate;
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _phone.dispose();
    _email.dispose();
    _department.dispose();
    _salary.dispose();
    _currency.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickHireDate() async {
    final picked = await ShamsiDates.pickDate(
      context,
      initial: _hireDate ?? DateTime.now(),
    );
    if (picked != null) setState(() => _hireDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.badge_outlined,
      iconColor: AppColors.primary,
      title: widget.isEdit ? 'employees.edit'.tr() : 'employees.add'.tr(),
      subtitle: 'employees.formSubtitle'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onCancel: () => Navigator.pop(context),
      onPrimary: () {
        final n = _name.text.trim();
        final salary = Formatters.parse(_salary.text) ?? 0;
        if (n.isEmpty || salary <= 0) return;
        Navigator.pop(
          context,
          _EmployeeFormResult(
            fullName: n,
            code: _code.text.trim().isEmpty ? null : _code.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            role: _role,
            department: _department.text.trim().isEmpty
                ? null
                : _department.text.trim(),
            hireDate: _hireDate,
            baseSalary: salary,
            salaryCurrency: _currency.text.trim().isEmpty
                ? 'AFN'
                : _currency.text.trim(),
            address:
                _address.text.trim().isEmpty ? null : _address.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            isActive: _active,
          ),
        );
      },
      maxWidth: 560,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfTextField(
            controller: _name,
            label: 'employees.fullName'.tr(),
            required: true,
            prefixIcon: Icons.person_outline,
            autofocus: true,
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: _code,
                label: 'employees.code'.tr(),
                hint: 'employees.codeHint'.tr(),
              ),
              GfTextField(
                controller: _phone,
                label: 'common.phone'.tr(),
                prefixIcon: Icons.phone_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: _email,
                label: 'common.email'.tr(),
                prefixIcon: Icons.email_outlined,
              ),
              GfDropdown<String>(
                label: 'employees.role'.tr(),
                items: kEmployeeRoles,
                value: _role,
                hint: 'employees.selectRole'.tr(),
                labelBuilder: (r) => 'employees.roles.$r'.tr(),
                onChanged: (v) => setState(() => _role = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: _department,
                label: 'employees.department'.tr(),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'employees.hireDate'.tr(),
                    style: AppTypography.label,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: AppSpacing.controlHeight,
                    child: OutlinedButton.icon(
                      onPressed: _pickHireDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        _hireDate == null
                            ? '—'
                            : ShamsiDates.formatDate(_hireDate!),
                      ),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                controller: _salary,
                label: 'employees.monthlySalary'.tr(),
                required: true,
                numberMode: true,
                prefixIcon: Icons.payments_outlined,
                hint: 'employees.monthlySalaryHint'.tr(),
              ),
              GfDropdown<String>(
                label: 'employees.salaryCurrency'.tr(),
                items: const ['AFN', 'USD', 'EUR'],
                value: const ['AFN', 'USD', 'EUR'].contains(
                        _currency.text.trim().toUpperCase())
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
          GfTextField(
            controller: _address,
            label: 'common.address'.tr(),
            prefixIcon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 14),
          GfTextField(
            controller: _notes,
            label: 'common.note'.tr(),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'employees.active'.tr(),
              style: AppTypography.bodyMedium,
            ),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ],
      ),
    );
  }
}
