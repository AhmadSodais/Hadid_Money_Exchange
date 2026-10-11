import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/product_model.dart';
import '../dialogs/category_manage_dialog.dart';
import '../dialogs/product_form_dialog.dart';
import '../providers/auth_provider.dart';
import '../viewmodels/module_viewmodels.dart';
import '../widgets/app_shell.dart';

class WarehousePage extends StatelessWidget {
  const WarehousePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => InventoryViewModel()..load(),
      child: const _WarehouseView(),
    );
  }
}

class _WarehouseView extends StatefulWidget {
  const _WarehouseView();

  @override
  State<_WarehouseView> createState() => _WarehouseViewState();
}

class _WarehouseViewState extends State<_WarehouseView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InventoryViewModel>();
    final canSeeCost = context.watch<AuthProvider>().canViewPurchaseData;

    return PageScaffold(
      title: 'products.title'.tr(),
      subtitle: 'products.stockSubtitle'.tr(),
      searchController: _search,
      searchHint: 'products.stockSearchHint'.tr(),
      onSearch: vm.setSearch,
      actions: [
        GfSecondaryButton(
          label: 'products.categories.manage'.tr(),
          icon: Icons.category_outlined,
          onPressed: () async {
            final changed = await CategoryManageDialog.show(context);
            if (changed == true && context.mounted) {
              await vm.reloadCategories();
            }
          },
        ),
        GfSecondaryButton(
          label: 'warehouse.addProduct'.tr(),
          icon: Icons.add_box_outlined,
          onPressed: () => _openAddProduct(context, vm),
        ),
      ],
      body: vm.loading
          ? const GfPageLoader()
          : Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GfCountBox(
                    label: 'products.totalCount'.tr(),
                    count: vm.total,
                    icon: AppAssets.productFilled,
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: GfDataTable(
                    title: 'warehouse.stockTitle'.tr(),
                    minWidth: gfTableMinWidth(context, preferred: 900),
                    actions: [
                      SizedBox(
                        width: 180,
                        child: GfDropdown<int>(
                          hint: 'sales.all'.tr(),
                          items: [-1, ...vm.categories.map((c) => c.id)],
                          value: vm.categoryId ?? -1,
                          labelBuilder: (id) {
                            if (id == -1) return 'sales.all'.tr();
                            return vm.categories
                                    .where((c) => c.id == id)
                                    .firstOrNull
                                    ?.name ??
                                '$id';
                          },
                          prefixIcon: Icons.filter_list_rounded,
                          onChanged: (id) {
                            if (id == null) return;
                            vm.setCategoryFilter(id == -1 ? null : id);
                          },
                        ),
                      ),
                    ],
                    columns: [
                      GfTableColumn(label: 'warehouse.product'.tr(), flex: 3),
                      GfTableColumn(
                        label: 'products.columns.category'.tr(),
                        flex: 2,
                      ),
                      GfTableColumn(
                        label: 'warehouse.quantity'.tr(),
                        flex: 1,
                      ),
                      if (canSeeCost)
                        GfTableColumn(
                          label: 'products.columns.cost'.tr(),
                          flex: 1,
                        ),
                      GfTableColumn(
                        label: 'products.columns.price'.tr(),
                        flex: 1,
                      ),
                      GfTableColumn(
                        label: 'products.columns.status'.tr(),
                        flex: 1,
                      ),
                      const GfTableColumn(label: '', width: 48),
                    ],
                    rowCount: vm.items.length,
                    total: vm.total,
                    page: vm.page,
                    pageSize: vm.pageSize,
                    autoPageSize: true,
                    onPageSizeChanged: vm.setPageSize,
                    onPageChanged: vm.setPage,
                    itemLabel: 'common.records'.tr(),
                    empty: GfEmptyState(
                      title: 'warehouse.empty'.tr(),
                      subtitle: 'warehouse.emptyHint'.tr(),
                      compact: true,
                    ),
                    rowBuilder: (context, i) {
                      final p = vm.items[i];
                      return GfTableRow(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                _ProductThumb(path: p.imagePath),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        p.name,
                                        style: AppTypography.bodyMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        [
                                          if (p.sku.isNotEmpty) p.sku,
                                          if (p.brand != null &&
                                              p.brand!.isNotEmpty)
                                            p.brand!,
                                        ].join(' · '),
                                        style: AppTypography.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              p.categoryName ?? '—',
                              style: AppTypography.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              Formatters.number(p.currentStock),
                              style: AppTypography.body,
                            ),
                          ),
                          if (canSeeCost)
                            Expanded(
                              child: Text(
                                Formatters.money(
                                  p.costPrice,
                                  currency: p.costCurrencyCode ??
                                      p.currencyCode ??
                                      'AFN',
                                ),
                                style: AppTypography.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              Formatters.money(
                                p.sellingPrice,
                                currency: p.currencyCode ?? 'AFN',
                              ),
                              style: AppTypography.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(child: _StockStatusBadge(product: p)),
                          SizedBox(
                            width: 48,
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              color: AppColors.modal,
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  final saved = await ProductFormDialog.show(
                                    context,
                                    product: p,
                                  );
                                  if (saved == true) {
                                    await vm.load();
                                    if (context.mounted) {
                                      GfToast.success(
                                        context,
                                        'products.page.messages.updated'.tr(),
                                      );
                                    }
                                  }
                                } else if (action == 'delete') {
                                  final ok = await GfConfirmDialog.show(
                                    context,
                                    title: 'products.page.messages.deleteTitle'
                                        .tr(),
                                    message:
                                        'products.page.messages.deleteMessage'
                                            .tr(),
                                    confirmLabel: 'common.delete'.tr(),
                                    danger: true,
                                  );
                                  if (ok != true) return;
                                  final err = await vm.deleteProduct(p.id);
                                  if (context.mounted) {
                                    err == null
                                        ? GfToast.success(
                                            context,
                                            'products.page.messages.removed'
                                                .tr(),
                                          )
                                        : GfToast.error(context, err);
                                  }
                                }
                              },
                              itemBuilder: (_) => [
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

  Future<void> _openAddProduct(
    BuildContext context,
    InventoryViewModel vm,
  ) async {
    final saved = await ProductFormDialog.show(context);
    if (saved == true) {
      await vm.load();
    }
  }
}

class _StockStatusBadge extends StatelessWidget {
  const _StockStatusBadge({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (product.stockStatus) {
      ProductStockStatus.inStock => (
          'products.status.inStock'.tr(),
          AppColors.success,
        ),
      ProductStockStatus.lowStock => (
          'products.status.lowStock'.tr(),
          AppColors.warning,
        ),
      ProductStockStatus.outOfStock => (
          'products.status.outOfStock'.tr(),
          AppColors.error,
        ),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: GfStatusBadge(label: label, color: color, compact: true),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        path != null && path!.isNotEmpty && File(path!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 36,
        height: 36,
        child: hasImage
            ? Image.file(File(path!), fit: BoxFit.cover)
            : ColoredBox(
                color: AppColors.input,
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
      ),
    );
  }
}
