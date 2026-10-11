import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/warehouse_model.dart';
import '../widgets/app_shell.dart';

class WarehousesPage extends StatefulWidget {
  const WarehousesPage({super.key});

  @override
  State<WarehousesPage> createState() => _WarehousesPageState();
}

class _WarehousesPageState extends State<WarehousesPage> {
  final _search = TextEditingController();
  DateFilterValue _dateFilter = DateFilterValue.thisYear();
  List<WarehouseModel> _items = const [];
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
    final result = await ServiceLocator.instance.warehouses.list(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      from: _dateFilter.from,
      to: _dateFilter.to,
      includeInactive: false,
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

  Future<void> _openForm({WarehouseModel? warehouse}) async {
    final isEdit = warehouse != null;
    final ok = await showDialog<_WarehouseFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _WarehouseFormDialog(isEdit: isEdit, initial: warehouse),
    );
    if (ok == null || !mounted) return;

    final now = DateTime.now();
    final model = WarehouseModel(
      id: warehouse?.id ?? 0,
      name: ok.name,
      address: ok.address,
      notes: ok.notes,
      isActive: warehouse?.isActive ?? true,
      createdAt: warehouse?.createdAt ?? now,
      updatedAt: now,
    );
    final result = isEdit
        ? await ServiceLocator.instance.warehouses.update(model)
        : await ServiceLocator.instance.warehouses.create(model);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(
          context,
          isEdit ? 'warehouses.updated'.tr() : 'warehouses.added'.tr(),
        );
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _delete(WarehouseModel w) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'warehouses.deleteTitle'.tr(),
      message: 'warehouses.deleteMessage'.tr(namedArgs: {'name': w.name}),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    final result = await ServiceLocator.instance.warehouses.delete(w.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        GfToast.success(context, 'warehouses.deleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'warehouses.title'.tr(),
      subtitle: 'warehouses.subtitle'.tr(),
      searchController: _search,
      searchHint: 'warehouses.searchHint'.tr(),
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
          label: 'warehouses.add'.tr(),
          icon: Icons.add,
          onPressed: () => _openForm(),
        ),
      ],
      body: _loading
          ? const GfPageLoader()
          : GfDataTable(
              title: 'warehouses.tableTitle'.tr(),
              minWidth: gfTableMinWidth(context, preferred: 720),
              columns: [
                GfTableColumn(label: 'warehouses.name'.tr(), flex: 3),
                GfTableColumn(label: 'warehouses.products'.tr(), flex: 1),
                GfTableColumn(label: 'warehouses.stock'.tr(), flex: 1),
                GfTableColumn(label: 'warehouses.inbound'.tr(), flex: 2),
                GfTableColumn(label: 'warehouses.outbound'.tr(), flex: 2),
                const GfTableColumn(label: '', width: 48),
              ],
              rowCount: _items.length,
              total: _items.length,
              clientSide: true,
              itemLabel: 'common.records'.tr(),
              empty: GfEmptyState(
                title: 'warehouses.empty'.tr(),
                subtitle: 'warehouses.emptyHint'.tr(),
                compact: true,
              ),
              rowBuilder: (context, i) {
                final w = _items[i];
                return GfTableRow(
                  onTap: () =>
                      context.push(AppRoutes.warehouseDetail, extra: w.id),
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            w.name,
                            style: AppTypography.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (w.address != null && w.address!.isNotEmpty)
                            Text(
                              w.address!,
                              style: AppTypography.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        Formatters.number(w.productCount),
                        style: AppTypography.body,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        Formatters.number(w.stockQty),
                        style: AppTypography.body,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.number(w.inboundQty),
                        style: AppTypography.body.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.number(w.outboundQty),
                        style: AppTypography.body.copyWith(
                          color: AppColors.error,
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
                              AppRoutes.warehouseDetail,
                              extra: w.id,
                            );
                          } else if (v == 'edit') {
                            _openForm(warehouse: w);
                          } else if (v == 'delete') {
                            _delete(w);
                          }
                        },
                        itemBuilder: (_) => [
                          gfPopupMenuItem(
                            value: 'view',
                            label: 'warehouses.viewDetails'.tr(),
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
    );
  }
}

class _WarehouseFormResult {
  const _WarehouseFormResult({required this.name, this.address, this.notes});

  final String name;
  final String? address;
  final String? notes;
}

class _WarehouseFormDialog extends StatefulWidget {
  const _WarehouseFormDialog({required this.isEdit, this.initial});

  final bool isEdit;
  final WarehouseModel? initial;

  @override
  State<_WarehouseFormDialog> createState() => _WarehouseFormDialogState();
}

class _WarehouseFormDialogState extends State<_WarehouseFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final w = widget.initial;
    _name = TextEditingController(text: w?.name ?? '');
    _address = TextEditingController(text: w?.address ?? '');
    _notes = TextEditingController(text: w?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.warehouse_outlined,
      iconColor: AppColors.primary,
      title: widget.isEdit ? 'warehouses.edit'.tr() : 'warehouses.add'.tr(),
      subtitle: 'warehouses.formSubtitle'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onCancel: () => Navigator.pop(context),
      onPrimary: () {
        final n = _name.text.trim();
        if (n.isEmpty) return;
        Navigator.pop(
          context,
          _WarehouseFormResult(
            name: n,
            address: _address.text.trim().isEmpty
                ? null
                : _address.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ),
        );
      },
      maxWidth: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfTextField(
            controller: _name,
            label: 'warehouses.name'.tr(),
            required: true,
          ),
          const SizedBox(height: 14),
          GfTextField(
            controller: _address,
            label: 'warehouses.address'.tr(),
          ),
          const SizedBox(height: 14),
          GfTextField(
            controller: _notes,
            label: 'common.note'.tr(),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
