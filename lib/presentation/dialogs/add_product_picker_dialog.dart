import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/category_model.dart';
import '../../data/models/currency_model.dart';
import '../../data/models/product_model.dart';
import '../widgets/order_detail_dialog_style.dart';

class AddProductPickResult {
  const AddProductPickResult({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.currencyId,
  });

  final ProductModel product;
  final double quantity;
  final double unitPrice;
  final int? currencyId;
}

class _PickDraft {
  _PickDraft({
    required this.quantity,
    required this.unitPrice,
    required this.priceCtrl,
    required this.qtyCtrl,
    this.currency,
  });

  double quantity;
  double unitPrice;
  final TextEditingController priceCtrl;
  final TextEditingController qtyCtrl;
  CurrencyModel? currency;

  void dispose() {
    priceCtrl.dispose();
    qtyCtrl.dispose();
  }
}

/// Multi-select product picker for orders — same UI as the purchase picker.
class AddProductPickerDialog extends StatefulWidget {
  const AddProductPickerDialog({
    super.key,
    this.products = const [],
    this.currencies = const [],
    this.defaultCurrency,
  });

  final List<ProductModel> products;
  final List<CurrencyModel> currencies;
  final CurrencyModel? defaultCurrency;

  static Future<List<AddProductPickResult>?> show(
    BuildContext context, {
    List<ProductModel> products = const [],
    List<CurrencyModel> currencies = const [],
    CurrencyModel? defaultCurrency,
  }) {
    return showDialog<List<AddProductPickResult>>(
      context: context,
      barrierColor: const Color(0x661E293B),
      builder: (_) => AddProductPickerDialog(
        products: products,
        currencies: currencies,
        defaultCurrency: defaultCurrency,
      ),
    );
  }

  @override
  State<AddProductPickerDialog> createState() => _AddProductPickerDialogState();
}

class _AddProductPickerDialogState extends State<AddProductPickerDialog> {
  final _search = TextEditingController();
  List<ProductModel> _products = const [];
  List<CategoryModel> _categories = const [];
  List<CurrencyModel> _currencies = const [];
  bool _loading = true;
  int? _categoryId;
  final Map<int, _PickDraft> _selected = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    for (final d in _selected.values) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    List<ProductModel> products = widget.products;
    if (products.isEmpty) {
      final result = await ServiceLocator.instance.products.query(
        const ProductQuery(pageSize: 500, sortBy: 'name', ascending: true),
      );
      products = result.when(
        success: (page) => page.items,
        failure: (_) => <ProductModel>[],
      );
    }

    List<CurrencyModel> currencies = widget.currencies;
    if (currencies.isEmpty) {
      final curs = await ServiceLocator.instance.lookups.getCurrencies();
      currencies = curs.when(
        success: (list) {
          final active = list.where((c) => c.isActive).toList();
          return active.isEmpty ? list : active;
        },
        failure: (_) => <CurrencyModel>[],
      );
    }

    final cats = await ServiceLocator.instance.lookups.getCategories();
    final categories = cats.when(
      success: (list) => list,
      failure: (_) => <CategoryModel>[],
    );

    if (!mounted) return;
    setState(() {
      _products = products;
      _categories = categories;
      _currencies = currencies;
      _loading = false;
    });
  }

  List<ProductModel> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _products.where((p) {
      if (_categoryId != null && p.categoryId != _categoryId) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.categoryName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  double _defaultPrice(ProductModel p) {
    if (p.sellingPrice > 0) return p.sellingPrice;
    return 0;
  }

  CurrencyModel? _currencyById(int? id) {
    if (id == null) return null;
    return _currencies.where((c) => c.id == id).firstOrNull;
  }

  CurrencyModel? _defaultCurrency(ProductModel p) {
    return _currencyById(p.currencyId) ??
        widget.defaultCurrency ??
        _currencies.where((c) => c.isBase).firstOrNull ??
        _currencies.firstOrNull;
  }

  void _toggle(ProductModel product) {
    setState(() {
      if (_selected.containsKey(product.id)) {
        _selected.remove(product.id)!.dispose();
      } else {
        final price = _defaultPrice(product);
        _selected[product.id] = _PickDraft(
          quantity: 1,
          unitPrice: price,
          priceCtrl: TextEditingController(
            text: price > 0 ? Formatters.number(price) : '',
          ),
          qtyCtrl: TextEditingController(text: '1'),
          currency: _defaultCurrency(product),
        );
      }
    });
  }

  void _confirm() {
    if (_selected.isEmpty) return;
    final out = <AddProductPickResult>[];
    for (final p in _products) {
      final draft = _selected[p.id];
      if (draft == null) continue;
      final price = Formatters.parse(draft.priceCtrl.text) ?? draft.unitPrice;
      final qty = Formatters.parse(draft.qtyCtrl.text) ?? draft.quantity;
      if (qty <= 0) continue;
      out.add(
        AddProductPickResult(
          product: p,
          quantity: qty,
          unitPrice: price < 0 ? 0 : price,
          currencyId: draft.currency?.id ?? p.currencyId,
        ),
      );
    }
    if (out.isEmpty) return;
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 720,
          maxHeight: OrderDetailDialogStyle.maxHeight,
        ),
        decoration: OrderDetailDialogStyle.container,
        padding: OrderDetailDialogStyle.padding,
        child: _loading
            ? const SizedBox(height: 280, child: Center(child: GfPageLoader()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onClose: () => Navigator.of(context).pop()),
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: OrderDetailDialogStyle.border,
                  ),
                  OrderDetailDialogStyle.sectionSpace,
                  _FilterRow(
                    search: _search,
                    categories: _categories,
                    categoryId: _categoryId,
                    onSearchChanged: (_) => setState(() {}),
                    onCategoryChanged: (id) => setState(() => _categoryId = id),
                  ),
                  OrderDetailDialogStyle.sectionSpace,
                  Expanded(
                    child: _ProductTable(
                      products: _filtered,
                      currencies: _currencies,
                      selected: _selected,
                      onToggle: _toggle,
                      onQtyChanged: (id, raw) {
                        final q = Formatters.parse(raw);
                        if (q == null) return;
                        setState(() => _selected[id]!.quantity = q);
                      },
                      onPriceChanged: (_) => setState(() {}),
                      onCurrencyChanged: (id, c) {
                        setState(() => _selected[id]!.currency = c);
                      },
                      currencyLabel: (c) => Formatters.currencyName(c.code),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: OrderDetailDialogStyle.border,
                  ),
                  const SizedBox(height: 12),
                  _Actions(
                    count: _selected.length,
                    onCancel: () => Navigator.of(context).pop(),
                    onConfirm: _selected.isEmpty ? null : _confirm,
                  ),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: OrderDetailDialogStyle.fieldHeight,
          height: OrderDetailDialogStyle.fieldHeight,
          decoration: BoxDecoration(
            color: OrderDetailDialogStyle.iconBg,
            borderRadius: OrderDetailDialogStyle.controlBorderRadius,
          ),
          child: Icon(
            Icons.add_box_outlined,
            color: OrderDetailDialogStyle.accent,
            size: 22,
          ),
        ),
        OrderDetailDialogStyle.rowGap,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'orders.addProduct'.tr(),
                style: AppTypography.sectionTitle.copyWith(
                  color: OrderDetailDialogStyle.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'orders.addProductSubtitle'.tr(),
                style: AppTypography.caption.copyWith(
                  color: OrderDetailDialogStyle.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: Icon(
            Icons.close_rounded,
            size: 20,
            color: OrderDetailDialogStyle.muted,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.search,
    required this.categories,
    required this.categoryId,
    required this.onSearchChanged,
    required this.onCategoryChanged,
  });

  final TextEditingController search;
  final List<CategoryModel> categories;
  final int? categoryId;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: OrderDetailDialogStyle.fieldHeight,
          child: GfDropdown<int?>(
            value: categoryId,
            height: OrderDetailDialogStyle.fieldHeight,
            items: <int?>[null, ...categories.map((c) => c.id)],
            labelBuilder: (id) {
              if (id == null) return 'orders.allCategories'.tr();
              return categories
                      .where((c) => c.id == id)
                      .map((c) => c.name)
                      .firstOrNull ??
                  'orders.allCategories'.tr();
            },
            onChanged: onCategoryChanged,
          ),
        ),
      ],
    );
  }
}

class _ProductTable extends StatelessWidget {
  const _ProductTable({
    required this.products,
    required this.currencies,
    required this.selected,
    required this.onToggle,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onCurrencyChanged,
    required this.currencyLabel,
  });

  final List<ProductModel> products;
  final List<CurrencyModel> currencies;
  final Map<int, _PickDraft> selected;
  final ValueChanged<ProductModel> onToggle;
  final void Function(int productId, String raw) onQtyChanged;
  final ValueChanged<String> onPriceChanged;
  final void Function(int productId, CurrencyModel? c) onCurrencyChanged;
  final String Function(CurrencyModel) currencyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OrderDetailDialogStyle.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: OrderDetailDialogStyle.tableHeaderBg,
            // Same end inset as the rows' scrollbar strip, so columns line up.
            padding: const EdgeInsetsDirectional.fromSTEB(
              10,
              10,
              10 + kGfScrollbarGutter,
              10,
            ),
            child: Row(
              children: [
                const SizedBox(width: 28),
                Expanded(flex: 3, child: _h('common.product'.tr())),
                SizedBox(
                  width: 88,
                  child: _h(
                    'inboundOutbound.unitPrice'.tr(),
                    align: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 86,
                  child: _h('sales.currency'.tr(), align: TextAlign.center),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 72,
                  child: _h('common.qty'.tr(), align: TextAlign.center),
                ),
              ],
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Text(
                      'common.noData'.tr(),
                      style: AppTypography.caption.copyWith(
                        color: OrderDetailDialogStyle.muted,
                      ),
                    ),
                  )
                : GfNoScrollbarGutter(
                    child: ListView.separated(
                    padding: const EdgeInsetsDirectional.only(
                      end: kGfScrollbarGutter,
                    ),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: OrderDetailDialogStyle.border,
                    ),
                    itemBuilder: (context, index) {
                      final p = products[index];
                      return _ProductRow(
                        product: p,
                        draft: selected[p.id],
                        currencies: currencies,
                        currencyLabel: currencyLabel,
                        onToggle: () => onToggle(p),
                        onQtyChanged: (raw) => onQtyChanged(p.id, raw),
                        onPriceChanged: onPriceChanged,
                        onCurrencyChanged: (c) => onCurrencyChanged(p.id, c),
                      );
                    },
                  ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _h(String text, {double? width, TextAlign align = TextAlign.start}) {
    final child = Text(
      text,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption.copyWith(
        color: OrderDetailDialogStyle.muted,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return child;
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.draft,
    required this.currencies,
    required this.currencyLabel,
    required this.onToggle,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onCurrencyChanged,
  });

  final ProductModel product;
  final _PickDraft? draft;
  final List<CurrencyModel> currencies;
  final String Function(CurrencyModel) currencyLabel;
  final VoidCallback onToggle;
  final ValueChanged<String> onQtyChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<CurrencyModel?> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    final selected = draft != null;
    final h = OrderDetailDialogStyle.inlineFieldHeight;

    return Material(
      color: selected
          ? OrderDetailDialogStyle.paleBlue
          : OrderDetailDialogStyle.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                activeColor: OrderDetailDialogStyle.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: InkWell(
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                onTap: onToggle,
                child: Row(
                  children: [
                    _Thumb(path: product.imagePath, size: 32),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMedium.copyWith(
                              color: OrderDetailDialogStyle.navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            product.sku,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              color: OrderDetailDialogStyle.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 88,
              height: h,
              child: selected
                  ? GfTextField(
                      controller: draft!.priceCtrl,
                      numberMode: true,
                      textAlign: TextAlign.center,
                      onChanged: onPriceChanged,
                    )
                  : _MutedCell(
                      Formatters.number(product.sellingPrice),
                      onTap: onToggle,
                    ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 86,
              height: h,
              child: selected
                  ? GfDropdown<CurrencyModel>(
                      value: draft!.currency,
                      items: currencies,
                      height: h,
                      hint: '—',
                      labelBuilder: currencyLabel,
                      onChanged: onCurrencyChanged,
                    )
                  : _MutedCell(
                      Formatters.currencyName(product.currencyCode),
                      onTap: onToggle,
                    ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 72,
              height: h,
              child: selected
                  ? GfTextField(
                      controller: draft!.qtyCtrl,
                      numberMode: true,
                      textAlign: TextAlign.center,
                      onChanged: onQtyChanged,
                    )
                  : _MutedCell('—', onTap: onToggle),
            ),
          ],
        ),
      ),
    );
  }
}

class _MutedCell extends StatelessWidget {
  const _MutedCell(this.text, {required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: onTap,
      borderRadius: OrderDetailDialogStyle.controlBorderRadius,
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(
            color: OrderDetailDialogStyle.muted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.count,
    required this.onCancel,
    required this.onConfirm,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'orders.productsSelected'.tr(namedArgs: {'count': '$count'}),
            style: AppTypography.caption.copyWith(
              color: OrderDetailDialogStyle.muted,
              fontSize: 11,
            ),
          ),
        ),
        SizedBox(
          height: OrderDetailDialogStyle.fieldHeight,
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: OrderDetailDialogStyle.navy,
              side: OrderDetailDialogStyle.borderSide,
              backgroundColor: OrderDetailDialogStyle.surface,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: OrderDetailDialogStyle.controlBorderRadius,
              ),
            ),
            child: Text('common.cancel'.tr()),
          ),
        ),
        OrderDetailDialogStyle.inlineGap,
        SizedBox(
          height: OrderDetailDialogStyle.fieldHeight,
          child: FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: OrderDetailDialogStyle.accent,
              disabledBackgroundColor:
                  OrderDetailDialogStyle.accent.withValues(
                alpha: 0.4,
              ),
              foregroundColor: OrderDetailDialogStyle.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: OrderDetailDialogStyle.controlBorderRadius,
              ),
            ),
            child: Text(
              'orders.addToInvoice'.tr(),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: OrderDetailDialogStyle.onAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    this.path,
    this.size = OrderDetailDialogStyle.inlineFieldHeight,
  });

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = (path ?? '').trim();
    Widget child = ColoredBox(
      color: OrderDetailDialogStyle.tableHeaderBg,
      child: Icon(
        Icons.image_outlined,
        size: size * 0.45,
        color: OrderDetailDialogStyle.muted,
      ),
    );
    if (p.isNotEmpty) {
      final file = File(p);
      if (file.existsSync()) {
        child = Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => child,
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: OrderDetailDialogStyle.controlBorderRadius,
        border: Border.all(
          color: OrderDetailDialogStyle.border,
          width: OrderDetailDialogStyle.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
