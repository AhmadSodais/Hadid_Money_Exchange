import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/category_model.dart';

/// Manage product categories (add / edit / delete) from the Products page.
class CategoryManageDialog extends StatefulWidget {
  const CategoryManageDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CategoryManageDialog(),
    );
  }

  @override
  State<CategoryManageDialog> createState() => _CategoryManageDialogState();
}

class _CategoryManageDialogState extends State<CategoryManageDialog> {
  List<CategoryModel> _items = const [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ServiceLocator.instance.lookups.getCategories();
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

  Future<void> _openForm({CategoryModel? category}) async {
    final isEdit = category != null;
    final result = await showDialog<_CategoryFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(
        isEdit: isEdit,
        initialName: category?.name ?? '',
      ),
    );
    if (result == null || !mounted) return;

    final repo = ServiceLocator.instance.lookups;
    final save = isEdit
        ? await repo.updateCategory(category.id, result.name)
        : await repo.createCategory(result.name);
    if (!mounted) return;
    save.when(
      success: (_) {
        _changed = true;
        GfToast.success(
          context,
          isEdit
              ? 'products.categories.updated'.tr()
              : 'products.categories.added'.tr(),
        );
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  Future<void> _delete(CategoryModel category) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'products.categories.deleteTitle'.tr(),
      message: 'products.categories.deleteMessage'
          .tr(namedArgs: {'name': category.name}),
      confirmLabel: 'common.delete'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    final result =
        await ServiceLocator.instance.lookups.deleteCategory(category.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        _changed = true;
        GfToast.success(context, 'products.categories.deleted'.tr());
        _load();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.category_outlined,
      iconColor: AppColors.primary,
      title: 'products.categories.title'.tr(),
      subtitle: 'products.categories.manageSubtitle'.tr(),
      cancelLabel: 'common.close'.tr(),
      onCancel: () => Navigator.pop(context, _changed),
      fixedHeight: true,
      maxHeight: 520,
      headerAction: GfPrimaryButton(
        label: 'products.categories.add'.tr(),
        icon: Icons.add,
        compact: true,
        onPressed: _loading ? null : () => _openForm(),
      ),
      body: _loading
          ? const SizedBox(height: 200, child: GfPageLoader())
          : _items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: GfEmptyState(
                    title: 'products.categories.empty'.tr(),
                    subtitle: 'products.categories.emptyHint'.tr(),
                    compact: true,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: AppColors.divider),
                      _CategoryTile(
                        index: i,
                        category: _items[i],
                        onEdit: _openForm,
                        onDelete: _delete,
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.index,
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final CategoryModel category;
  final void Function({CategoryModel? category}) onEdit;
  final ValueChanged<CategoryModel> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${index + 1}. ${category.name}',
        style: AppTypography.bodyMedium,
      ),
      trailing: PopupMenuButton<String>(
        position: PopupMenuPosition.under,
        color: AppColors.modal,
        onSelected: (v) {
          if (v == 'edit') {
            onEdit(category: category);
          } else if (v == 'delete') {
            onDelete(category);
          }
        },
        itemBuilder: (_) => [
          gfPopupMenuItem(value: 'edit', label: 'common.edit'.tr()),
          gfPopupMenuItem(
            value: 'delete',
            label: 'common.delete'.tr(),
            danger: true,
          ),
        ],
      ),
    );
  }
}

class _CategoryFormResult {
  const _CategoryFormResult({required this.name});
  final String name;
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.isEdit,
    required this.initialName,
  });

  final bool isEdit;
  final String initialName;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.category_outlined,
      iconColor: AppColors.primary,
      title: widget.isEdit
          ? 'products.categories.edit'.tr()
          : 'products.categories.add'.tr(),
      subtitle: 'products.categories.formSubtitle'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      onPrimary: () {
        final n = _name.text.trim();
        if (n.isEmpty) return;
        Navigator.pop(context, _CategoryFormResult(name: n));
      },
      onCancel: () => Navigator.pop(context),
      maxWidth: 400,
      maxHeight: 420,
      body: GfTextField(
        controller: _name,
        label: 'products.categories.name'.tr(),
        required: true,
        autofocus: true,
      ),
    );
  }
}
