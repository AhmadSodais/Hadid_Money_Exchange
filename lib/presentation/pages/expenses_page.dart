import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/expense_model.dart';
import '../dialogs/warehouse_dialog_shared.dart' show DialogResponsiveRow;
import '../widgets/app_shell.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _search = TextEditingController();
  DateFilterValue _dateFilter = DateFilterValue.thisMonth();
  List<ExpenseModel> _items = const [];
  List<ExpenseCategoryTotal> _monthCats = const [];
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
    final repo = ServiceLocator.instance.expenses;
    final listResult = await repo.list(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      from: _dateFilter.from,
      to: _dateFilter.to,
    );
    final month = ShamsiDates.thisMonth(DateTime.now());
    final catsResult = await repo.totalsByCategory(
      from: month.$1,
      to: month.$2,
    );
    if (!mounted) return;
    listResult.when(
      success: (list) => setState(() {
        _items = list;
        _loading = false;
      }),
      failure: (f) {
        setState(() {
          _items = const [];
          _loading = false;
        });
        GfToast.error(context, f.message);
      },
    );
    catsResult.when(
      success: (cats) => setState(() => _monthCats = cats),
      failure: (_) {},
    );
  }

  Future<void> _openForm({ExpenseModel? expense}) async {
    final saved = await _ExpenseFormDialog.show(context, initial: expense);
    if (saved == null || !mounted) return;

    final repo = ServiceLocator.instance.expenses;
    final result = expense == null
        ? await repo.create(saved)
        : await repo.update(saved.copyWith(id: expense.id));
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(
          context,
          expense == null ? 'expenses.recorded'.tr() : 'common.save'.tr(),
        );
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _delete(ExpenseModel e) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'expenses.deleteTitle'.tr(),
      message: 'expenses.deleteMessage'.tr(),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    final result = await ServiceLocator.instance.expenses.delete(e.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'expenses.delete'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (s, e) => s + e.amount);

    return PageScaffold(
      title: 'expenses.title'.tr(),
      subtitle: 'expenses.subtitle'.tr(),
      searchController: _search,
      searchHint: 'expenses.searchHint'.tr(),
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
          label: 'expenses.newExpense'.tr(),
          icon: Icons.add_rounded,
          onPressed: () => _openForm(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfKpiGrid(
            children: [
              GfKpiCard(
                title: 'expenses.tableTitle'.tr(),
                value: Formatters.money(total),
                icon: AppAssets.expenses,
              ),
              GfKpiCard(
                title: 'expenses.thisMonth'.tr(),
                value: Formatters.money(
                  _monthCats.fold<double>(0, (s, c) => s + c.amount),
                ),
                icon: AppAssets.expensesFilled,
              ),
            ],
          ),
          // SizedBox(height: gfSectionGap(context)),
          // if (_monthCats.isNotEmpty) ...[
          // SizedBox(
          //   height: 40,
          //   child: ListView.separated(
          //     scrollDirection: Axis.horizontal,
          //     itemCount: _monthCats.length,
          //     separatorBuilder: (_, __) => const SizedBox(width: 8),
          //     itemBuilder: (context, i) {
          //       final c = _monthCats[i];
          //       return Container(
          //         padding: const EdgeInsets.symmetric(
          //           horizontal: 12,
          //           vertical: 8,
          //         ),
          //         decoration: BoxDecoration(
          //           color: AppColors.surface,
          //           borderRadius: BorderRadius.circular(8),
          //           border: Border.all(color: AppColors.border),
          //         ),
          //         child: Row(
          //           children: [
          //             // Text(
          //             //   c.category,
          //             //   style: AppTypography.caption.copyWith(
          //             //     fontWeight: FontWeight.w600,
          //             //   ),
          //             // ),
          //             // const SizedBox(width: 8),
          //             // Text(
          //             //   Formatters.money(c.amount),
          //             //   style: AppTypography.caption.copyWith(
          //             //     color: AppColors.textMuted,
          //             //   ),
          //             // ),
          //           ],
          //         ),
          //       );
          //     },
          //   ),
          // ),
          // ],
          SizedBox(height: gfSectionGap(context)),

          Expanded(
            child: GfDataTable(
              title: 'expenses.tableTitle'.tr(),
              isLoading: _loading,
              minWidth: gfTableMinWidth(context, preferred: 900),
              columns: [
                GfTableColumn(label: 'expenses.columns.title'.tr(), flex: 2),
                GfTableColumn(label: 'expenses.columns.payee'.tr(), flex: 2),
                GfTableColumn(label: 'expenses.columns.amount'.tr(), flex: 2),
                GfTableColumn(label: 'expenses.columns.date'.tr(), flex: 2),
                GfTableColumn(label: 'expenses.columns.note'.tr(), flex: 2),
                const GfTableColumn(label: '', width: 88),
              ],
              rowCount: _items.length,
              total: _items.length,
              clientSide: true,
              itemLabel: 'common.records'.tr(),
              empty: GfEmptyState(
                title: 'expenses.empty'.tr(),
                subtitle: 'expenses.emptyHint'.tr(),
                actionLabel: 'expenses.addExpense'.tr(),
                onAction: () => _openForm(),
                compact: true,
              ),
              rowBuilder: (context, index) {
                final e = _items[index];
                final currency = e.currencyCode ?? 'AFN';
                return GfTableRow(
                  onTap: () => _openForm(expense: e),
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        e.category,
                        style: AppTypography.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        e.payee?.trim().isNotEmpty == true ? e.payee! : '—',
                        style: AppTypography.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.money(e.amount, currency: currency),
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.date(e.expenseDate),
                        style: AppTypography.body,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        e.note?.trim().isNotEmpty == true ? e.note! : '—',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 88,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'common.edit'.tr(),
                            onPressed: () => _openForm(expense: e),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: 'common.delete'.tr(),
                            onPressed: () => _delete(e),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.error,
                            ),
                            visualDensity: VisualDensity.compact,
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

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({this.initial});

  final ExpenseModel? initial;

  static Future<ExpenseModel?> show(
    BuildContext context, {
    ExpenseModel? initial,
  }) {
    return showDialog<ExpenseModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExpenseFormDialog(initial: initial),
    );
  }

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  late final TextEditingController _note;
  late final TextEditingController _title;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _amount = TextEditingController(
      text: i == null || i.amount <= 0 ? '' : Formatters.number(i.amount),
    );
    _payee = TextEditingController(text: i?.payee ?? '');
    _note = TextEditingController(text: i?.note ?? '');
    _title = TextEditingController(text: i?.category ?? '');
    _date = i?.expenseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = Formatters.parse(_amount.text) ?? 0;
    final title = _title.text.trim();
    if (title.isEmpty || amount <= 0) {
      GfToast.error(context, 'expenses.validation'.tr());
      return;
    }
    final now = DateTime.now();
    final initial = widget.initial;
    Navigator.pop(
      context,
      ExpenseModel(
        id: initial?.id ?? 0,
        category: title,
        amount: amount,
        currencyId: initial?.currencyId,
        currencyCode: AppConstants.defaultCurrencyCode,
        exchangeRate: 1,
        payee: _payee.text.trim().isEmpty ? null : _payee.text.trim(),
        expenseDate: _date,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        createdAt: initial?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.payments_outlined,
      title: widget.initial == null
          ? 'expenses.formTitle'.tr()
          : 'common.edit'.tr(),
      subtitle: 'expenses.subtitle'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onCancel: () => Navigator.pop(context),
      onPrimary: _submit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogResponsiveRow(
            children: [
              GfTextField(
                label: 'expenses.titleLabel'.tr(),
                hint: 'expenses.titleHint'.tr(),
                required: true,
                controller: _title,
              ),
              GfTextField(
                label: 'expenses.amount'.tr(),
                required: true,
                controller: _amount,
                numberMode: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DatePickerField(
            label: 'expenses.date'.tr(),
            value: _date,
            onPick: () async {
              final picked = await ShamsiDates.pickDate(
                context,
                initial: _date,
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 10),
          GfTextField(label: 'expenses.payee'.tr(), controller: _payee),
          const SizedBox(height: 10),
          GfTextField(
            label: 'expenses.note'.tr(),
            controller: _note,
            minLines: 1,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: AppSpacing.controlHeight,
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(Formatters.date(value)),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ],
    );
  }
}
