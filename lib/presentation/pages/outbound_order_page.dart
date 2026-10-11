// ignore_for_file: unused_element

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pdf_report_helper.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/category_model.dart';
import '../../data/models/product_model.dart';
import '../viewmodels/outbound_cart_viewmodel.dart';
import '../viewmodels/stock_entry_viewmodel.dart';
import '../widgets/app_shell.dart';

/// Outbound Create / Edit Order page: product catalog + Current Order cart.
class OutboundOrderPage extends StatelessWidget {
  const OutboundOrderPage({super.key, this.editingOrderId});

  final int? editingOrderId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          OutboundCartViewModel(editingOrderId: editingOrderId)..load(),
      child: _OutboundOrderView(editingOrderId: editingOrderId),
    );
  }
}

class _OutboundOrderView extends StatefulWidget {
  const _OutboundOrderView({this.editingOrderId});

  final int? editingOrderId;

  @override
  State<_OutboundOrderView> createState() => _OutboundOrderViewState();
}

class _OutboundOrderViewState extends State<_OutboundOrderView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'outbound-search');
  final _pageFocus = FocusNode(debugLabel: 'outbound-page');
  final _amountReceived = TextEditingController();
  final _discount = TextEditingController();
  final _gridController = ScrollController();
  bool _paymentFieldsSeeded = false;

  /// Keyboard / click highlight in the product catalog (`-1` = none).
  /// ValueNotifier avoids rebuilding the search field on every arrow press.
  final ValueNotifier<int> _highlight = ValueNotifier<int>(-1);

  /// Product whose card is showing the red out-of-stock overlay.
  final ValueNotifier<int?> _outOfStockProductId = ValueNotifier<int?>(null);
  Timer? _outOfStockTimer;
  static const _outOfStockHold = Duration(milliseconds: 1400);

  /// Columns in the product [GridView] (kept in sync with layout).
  int _gridColumns = 1;

  /// Cross-axis width of each grid cell (for scroll math).
  double _gridCellWidth = 188;

  /// When true, arrow keys / Delete target cart lines instead of products.
  bool _cartNav = false;

  bool get _isEditing => widget.editingOrderId != null;

  @override
  void initState() {
    super.initState();
    _searchFocus.onKeyEvent = _onKeyEvent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _pageFocus.dispose();
    _amountReceived.dispose();
    _discount.dispose();
    _gridController.dispose();
    _highlight.dispose();
    _outOfStockTimer?.cancel();
    _outOfStockProductId.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final vm = context.read<OutboundCartViewModel>();
    vm.setSearch(value);
    _cartNav = false;
    _highlight.value = vm.products.isEmpty ? -1 : 0;
  }

  /// Two-dimensional focus move inside the product grid.
  ///
  /// [colDelta] is visual: +1 = right, −1 = left (adjusted for RTL).
  /// [rowDelta] keeps the same column: down from row0/col2 → row1/col2.
  void _moveGridHighlight({
    required int rowDelta,
    required int colDelta,
    required OutboundCartViewModel vm,
  }) {
    final count = vm.products.length;
    if (count == 0) {
      _highlight.value = -1;
      return;
    }

    final cols = _gridColumns.clamp(1, count);
    // Arrow keys are visual; in RTL the grid paints index 0 on the right.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final indexColDelta = rtl ? -colDelta : colDelta;

    _cartNav = false;
    final currentHighlight = _highlight.value;

    if (currentHighlight < 0) {
      _highlight.value = (rowDelta > 0 || colDelta > 0) ? 0 : count - 1;
      _ensureHighlightVisible();
      return;
    }

    final current = currentHighlight.clamp(0, count - 1);
    final row = current ~/ cols;
    final col = current % cols;
    final lastRow = (count - 1) ~/ cols;

    if (indexColDelta != 0) {
      final nextCol = col + indexColDelta;
      if (nextCol < 0 || nextCol >= cols) return;
      final next = row * cols + nextCol;
      if (next < count) {
        _highlight.value = next;
        _ensureHighlightVisible();
      }
      return;
    }

    if (rowDelta != 0) {
      final nextRow = row + rowDelta;
      if (nextRow < 0 || nextRow > lastRow) return;
      var next = nextRow * cols + col;
      // Last row may be shorter — land on last item in that column band.
      if (next >= count) {
        final lastRowStart = lastRow * cols;
        final preferred = lastRowStart + col;
        next = preferred < count ? preferred : count - 1;
      }
      _highlight.value = next;
      _ensureHighlightVisible();
    }
  }

  void _ensureHighlightVisible() {
    final index = _highlight.value;
    if (index < 0 || !_gridController.hasClients) return;
    final cols = _gridColumns.clamp(1, 99);
    final max = _gridController.position.maxScrollExtent;
    const mainAxisSpacing = 12.0;
    const aspectRatio = 0.72;
    final rowExtent = _gridCellWidth / aspectRatio + mainAxisSpacing;
    final row = index ~/ cols;
    final target = row * rowExtent;
    _gridController.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _addHighlighted(OutboundCartViewModel vm) {
    if (vm.products.isEmpty) return;
    final index = _highlight.value < 0 ? 0 : _highlight.value;
    _addProductAt(vm, index);
    // Keep existing search focus — do not re-request (avoids focus flicker).
  }

  /// Shared by click and Enter so both show the out-of-stock overlay.
  void _addProductAt(OutboundCartViewModel vm, int index) {
    final i = index.clamp(0, vm.products.length - 1);
    final product = vm.products[i];
    if (!vm.addProduct(product)) _flashOutOfStock(product.id);
    _cartNav = false;
    _highlight.value = i;
  }

  void _flashOutOfStock(int productId) {
    _outOfStockTimer?.cancel();
    _outOfStockProductId.value = productId;
    _outOfStockTimer = Timer(_outOfStockHold, () {
      if (mounted) _outOfStockProductId.value = null;
    });
  }

  void _moveCartFocus(int delta, OutboundCartViewModel vm) {
    if (vm.lines.isEmpty) return;
    _cartNav = true;
    final ids = vm.lines.map((l) => l.id).toList();
    final current = vm.focusedLineId;
    var index = current == null ? 0 : ids.indexOf(current);
    if (index < 0) index = 0;
    index = (index + delta).clamp(0, ids.length - 1);
    vm.focusLine(ids[index]);
  }

  void _deleteFocusedCartLine(OutboundCartViewModel vm) {
    final id = vm.focusedLineId;
    if (id == null) return;
    vm.removeLine(id);
    if (vm.lines.isEmpty) {
      _cartNav = false;
      if (!_searchFocus.hasFocus) {
        _searchFocus.requestFocus();
      }
    } else {
      vm.focusLine(vm.lines.first.id);
    }
  }

  /// Backspace: −1 on the focused (or most recent) cart line; removes at zero.
  void _decrementCartLine(OutboundCartViewModel vm) {
    final line = vm.lines
            .where((l) => l.id == vm.focusedLineId)
            .firstOrNull ??
        vm.lines.first;
    final next = line.quantity - 1;
    if (next > 0.0001) {
      vm.setLineQuantity(line.id, next);
      vm.focusLine(line.id);
      return;
    }
    vm.removeLine(line.id);
    if (vm.lines.isEmpty) {
      _cartNav = false;
      if (!_searchFocus.hasFocus) _searchFocus.requestFocus();
    } else {
      vm.focusLine(vm.lines.first.id);
    }
  }

  /// Same action as the cart's cancel button.
  void _cancelCurrentOrder() {
    if (_isEditing) {
      Navigator.of(context).maybePop(false);
      return;
    }
    _cancelOrder();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final vm = context.read<OutboundCartViewModel>();
    if (vm.loading || vm.saving) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final inText = gfFocusInTextInput();

    if (key == LogicalKeyboardKey.f1) {
      if (event is KeyDownEvent) _save(printAfter: false);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape &&
        (vm.lines.isNotEmpty || _isEditing)) {
      if (event is KeyDownEvent) _cancelCurrentOrder();
      return KeyEventResult.handled;
    }

    // Backspace edits text in other fields / a non-empty search box;
    // otherwise it decreases the cart line quantity.
    if (key == LogicalKeyboardKey.backspace) {
      final editingText = inText &&
          (!_searchFocus.hasFocus || _search.text.isNotEmpty);
      if (editingText || vm.lines.isEmpty) return KeyEventResult.ignored;
      _decrementCartLine(vm);
      return KeyEventResult.handled;
    }

    // Arrow navigation — product grid (↑↓←→) or cart (Ctrl+↑↓ / cart mode).
    // Never steal arrows from an active text field (avoids caret-run assert).
    if (key == LogicalKeyboardKey.arrowDown) {
      if (inText && !_searchFocus.hasFocus) {
        return KeyEventResult.ignored;
      }
      if (_cartNav ||
          (HardwareKeyboard.instance.isControlPressed && vm.lines.isNotEmpty)) {
        _moveCartFocus(1, vm);
        return KeyEventResult.handled;
      }
      if (inText && _searchFocus.hasFocus) {
        // Search is single-line; use ↓ for catalog navigation.
      }
      _moveGridHighlight(rowDelta: 1, colDelta: 0, vm: vm);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (inText && !_searchFocus.hasFocus) {
        return KeyEventResult.ignored;
      }
      if (_cartNav ||
          (HardwareKeyboard.instance.isControlPressed && vm.lines.isNotEmpty)) {
        _moveCartFocus(-1, vm);
        return KeyEventResult.handled;
      }
      _moveGridHighlight(rowDelta: -1, colDelta: 0, vm: vm);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_cartNav) return KeyEventResult.ignored;
      _moveGridHighlight(rowDelta: 0, colDelta: 1, vm: vm);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_cartNav) return KeyEventResult.ignored;
      _moveGridHighlight(rowDelta: 0, colDelta: -1, vm: vm);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isControlPressed) {
        _save(printAfter: false);
        return KeyEventResult.handled;
      }
      if (_cartNav && vm.focusedLineId != null) {
        final line = vm.lines
            .where((l) => l.id == vm.focusedLineId)
            .firstOrNull;
        if (line != null) {
          _editLine(line);
          return KeyEventResult.handled;
        }
      }
      // Enter from search / catalog: add or bump highlighted product.
      if (!inText || _searchFocus.hasFocus) {
        _addHighlighted(vm);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.delete) {
      if (_cartNav || vm.focusedLineId != null) {
        _deleteFocusedCartLine(vm);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_search.text.isNotEmpty) {
        _search.clear();
        _onSearchChanged('');
        return KeyEventResult.handled;
      }
      if (_highlight.value >= 0 || _cartNav) {
        _highlight.value = -1;
        _cartNav = false;
        vm.clearLineFocus();
        if (!_searchFocus.hasFocus) {
          _searchFocus.requestFocus();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // +/- quantity on focused cart line when not in a text field.
    if (!inText && vm.focusedLineId != null) {
      final line = vm.lines.where((l) => l.id == vm.focusedLineId).firstOrNull;
      if (line != null) {
        if (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.numpadAdd ||
            key == LogicalKeyboardKey.add) {
          vm.setLineQuantity(line.id, line.quantity + 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract) {
          vm.setLineQuantity(line.id, line.quantity - 1);
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  Future<bool> _confirmPartialIfNeeded(OutboundCartViewModel vm) async {
    if (vm.remaining <= 0.0001) return true;
    final ok = await GfConfirmDialog.show(
      context,
      title: 'sales.remainingTitle'.tr(),
      message: 'sales.remainingMessage'.tr(
        namedArgs: {
          'amount': Formatters.money(
            vm.remaining,
            currency: vm.orderCurrency?.code ?? 'AFN',
          ),
        },
      ),
      confirmLabel: 'common.confirm'.tr(),
    );
    return ok == true;
  }

  void _clearPaymentFields() {
    _amountReceived.clear();
    _discount.clear();
  }

  Future<void> _save({required bool printAfter}) async {
    final vm = context.read<OutboundCartViewModel>();
    if (vm.lines.isEmpty) {
      GfToast.error(context, 'sales.cartEmpty'.tr());
      return;
    }
    if (!await _confirmPartialIfNeeded(vm)) return;

    final err = await vm.save();
    if (!mounted) return;
    if (err != null) {
      GfToast.error(context, err);
      return;
    }

    GfToast.success(
      context,
      _isEditing ? 'orders.updated'.tr() : 'sales.saleSaved'.tr(),
    );
    if (printAfter) {
      final order = vm.lastSavedOrder;
      final bytes = await PdfReportHelper.buildMovementsInvoice(
        context,
        periodLabel: ShamsiDates.formatDate(order?.createdAt ?? DateTime.now()),
        kind: PdfMovementExportKind.outbound,
        movements: vm.buildInvoiceMovements(
          createdAt: order?.createdAt ?? DateTime.now(),
          order: order,
        ),
      );
      if (!mounted) return;
      await PdfReportHelper.printPdf(
        context,
        bytes: bytes,
        fileName: order != null
            ? 'glassflow_${order.invoiceNumber}_${PdfReportHelper.stamp()}.pdf'
            : 'glassflow_outbound_${PdfReportHelper.stamp()}.pdf',
      );
    }
    if (_isEditing) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    vm.clearCart();
    _clearPaymentFields();
  }

  Future<void> _cancelOrder() async {
    final vm = context.read<OutboundCartViewModel>();
    if (vm.lines.isEmpty) return;
    final ok = await GfConfirmDialog.show(
      context,
      title: 'sales.cancelTitle'.tr(),
      message: 'sales.cancelMessage'.tr(),
      confirmLabel: 'sales.clearOrder'.tr(),
      danger: true,
    );
    if (ok != true || !mounted) return;
    vm.clearCart();
    _clearPaymentFields();
    GfToast.success(context, 'sales.cartCleared'.tr());
  }

  Future<void> _editLine(OutboundCartLine line) async {
    final result = await showDialog<({double? qty, double? price})>(
      context: context,
      builder: (_) => _EditLineDialog(line: line),
    );
    if (result == null || !mounted) return;
    final qtyVal = result.qty;
    final priceVal = result.price;
    final vm = context.read<OutboundCartViewModel>();
    if (qtyVal != null && qtyVal > 0) {
      vm.setLineQuantity(line.id, qtyVal);
    }
    if (priceVal != null && priceVal >= 0) {
      vm.setLineUnitPrice(line.id, priceVal);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Select only values needed by the chrome so Enter / cart updates do not
    // rebuild the search field (which caused repeated focus flicker).
    final invoice = _isEditing
        ? context.select<OutboundCartViewModel, String?>(
            (vm) => vm.editingInvoiceNumber,
          )
        : null;

    return GfKeyboardScope(
      autofocus: false,
      onSave: () => _save(printAfter: false),
      onCancel: () {
        if (_search.text.isNotEmpty) {
          _search.clear();
          _onSearchChanged('');
          return;
        }
        if (_isEditing) {
          Navigator.of(context).maybePop();
        }
      },
      onDelete: () =>
          _deleteFocusedCartLine(context.read<OutboundCartViewModel>()),
      onFocusSearch: () {
        if (!_searchFocus.hasFocus) {
          _searchFocus.requestFocus();
        }
      },
      child: Focus(
        focusNode: _pageFocus,
        onKeyEvent: _onKeyEvent,
        child: PageScaffold(
          title: _isEditing ? 'sales.editTitle'.tr() : 'sales.title'.tr(),
          subtitle: _isEditing && invoice != null && invoice.isNotEmpty
              ? invoice
              : 'sales.subtitle'.tr(),
          searchController: _search,
          searchFocusNode: _searchFocus,
          searchHint: 'sales.searchHint'.tr(),
          onSearch: _onSearchChanged,
          headerExtra:
              Selector<OutboundCartViewModel, (List<CategoryModel>, int?)>(
                selector: (_, vm) => (vm.categories, vm.categoryId),
                builder: (context, data, _) {
                  final categories = data.$1;
                  final categoryId = data.$2;
                  return _CategoryChips(
                    categories: categories,
                    selectedId: categoryId,
                    onSelected: (id) {
                      context.read<OutboundCartViewModel>().setCategory(id);
                      _cartNav = false;
                      _highlight.value = 0;
                    },
                  );
                },
              ),
          body: Consumer<OutboundCartViewModel>(
            builder: (context, vm, _) {
              // Seed discount / amount fields once when editing.
              if (_isEditing &&
                  !vm.loading &&
                  !_paymentFieldsSeeded &&
                  (vm.discount > 0 || vm.applyCustomPayment)) {
                _paymentFieldsSeeded = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (vm.discount > 0) {
                    _discount.text = Formatters.number(vm.discount);
                  }
                  if (vm.applyCustomPayment && vm.amountReceived > 0) {
                    _amountReceived.text = Formatters.number(vm.amountReceived);
                  }
                });
              }

              if (!_isEditing &&
                  vm.lines.isEmpty &&
                  (_amountReceived.text.isNotEmpty ||
                      _discount.text.isNotEmpty)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _clearPaymentFields();
                });
              }

              final productCount = vm.products.length;
              if (_highlight.value >= productCount) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_highlight.value >= productCount) {
                    _highlight.value = productCount == 0
                        ? -1
                        : productCount - 1;
                  }
                });
              }

              if (vm.loading) return const GfPageLoader();

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        _highlight,
                        _outOfStockProductId,
                      ]),
                      builder: (context, _) {
                        return _CatalogPane(
                          vm: vm,
                          highlightIndex: _highlight.value,
                          outOfStockProductId: _outOfStockProductId.value,
                          gridController: _gridController,
                          onColumnsChanged: (cols, cellWidth) {
                            if (cols > 0) _gridColumns = cols;
                            if (cellWidth > 0) _gridCellWidth = cellWidth;
                          },
                          onProductActivated: (product, index) =>
                              _addProductAt(vm, index),
                          onHighlight: (index) {
                            _cartNav = false;
                            _highlight.value = index;
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.cardGap),
                  SizedBox(
                    width: 380,
                    child: _CurrentOrderPane(
                      vm: vm,
                      amountController: _amountReceived,
                      discountController: _discount,
                      onSave: () => _save(printAfter: false),
                      onSavePrint: () => _save(printAfter: true),
                      onCancel: _isEditing
                          ? () async {
                              if (mounted) {
                                Navigator.of(context).pop(false);
                              }
                            }
                          : _cancelOrder,
                      onEditLine: _editLine,
                      onSelectLine: (line) {
                        _cartNav = true;
                        vm.focusLine(line.id);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CatalogPane extends StatelessWidget {
  const _CatalogPane({
    required this.vm,
    required this.highlightIndex,
    required this.gridController,
    required this.onProductActivated,
    required this.onHighlight,
    required this.onColumnsChanged,
    this.outOfStockProductId,
  });

  final OutboundCartViewModel vm;
  final int highlightIndex;
  final int? outOfStockProductId;
  final ScrollController gridController;
  final void Function(ProductModel product, int index) onProductActivated;
  final ValueChanged<int> onHighlight;

  /// Reports (columnCount, cellWidth) so arrow math matches the painted grid.
  final void Function(int columns, double cellWidth) onColumnsChanged;

  /// Preferred max tile width — smaller than before so wider panes fit more cards.
  static const _maxCrossAxisExtent = 188.0;

  /// Never shrink cards below this width (keeps text/image readable).
  static const _minCrossAxisExtent = 148.0;

  static const _crossAxisSpacing = 12.0;
  static const _mainAxisSpacing = 12.0;
  static const _childAspectRatio = 0.72;
  static const _maxColumns = 8;

  /// Column count from available width: packs as many tiles as fit between
  /// [_minCrossAxisExtent] and [_maxCrossAxisExtent].
  static int columnsForWidth(double width) {
    if (!width.isFinite || width <= 0) return 1;
    // How many tiles fit at the minimum readable size?
    final byMin =
        (width + _crossAxisSpacing) / (_minCrossAxisExtent + _crossAxisSpacing);
    // How many at the preferred max size? (floor = fewer, larger tiles)
    final byMax =
        (width + _crossAxisSpacing) / (_maxCrossAxisExtent + _crossAxisSpacing);
    // Prefer filling space: use the higher column count from min-width packing,
    // but never less than what max-extent would allow (avoids oversized gaps).
    final cols = math.max(byMax.floor(), byMin.floor());
    return cols.clamp(1, _maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vm.error != null && vm.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              vm.error!,
              style: AppTypography.body.copyWith(color: AppColors.error),
            ),
          ),
        Expanded(
          child: vm.products.isEmpty
              ? GfEmptyState(
                  title: 'sales.noProducts'.tr(),
                  subtitle: 'sales.noProductsHint'.tr(),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth - kGfScrollbarGutter;
                    final cols = columnsForWidth(width);
                    final cellWidth =
                        (width - _crossAxisSpacing * (cols - 1)) / cols;
                    onColumnsChanged(cols, cellWidth);
                    // Fixed gutter instead of the automatic one, so
                    // [cellWidth] always matches the painted tiles.
                    return GfNoScrollbarGutter(
                      child: GridView.builder(
                        controller: gridController,
                        padding: const EdgeInsetsDirectional.only(
                          end: kGfScrollbarGutter,
                          bottom: 16,
                        ),
                        // Fixed count so navigation index math matches paint order.
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: _mainAxisSpacing,
                          crossAxisSpacing: _crossAxisSpacing,
                          childAspectRatio: _childAspectRatio,
                        ),
                        itemCount: vm.products.length,
                        itemBuilder: (context, i) {
                          final product = vm.products[i];
                          return _ProductCard(
                            product: product,
                            unavailable:
                                vm.limitToStock && product.currentStock < 1,
                            showOutOfStock: product.id == outOfStockProductId,
                            selected: i == highlightIndex,
                            onSelect: () => onHighlight(i),
                            onAdd: () => onProductActivated(vm.products[i], i),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryModel> categories;
  final int? selectedId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return GfArrowFocusGroup(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Chip(
              label: 'sales.all'.tr(),
              selected: selectedId == null,
              onTap: () => onSelected(null),
            ),
            for (final c in categories) ...[
              const SizedBox(width: 8),
              _Chip(
                label: c.name,
                selected: selectedId == c.id,
                onTap: () => onSelected(c.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) {
        if (mounted) setState(() => _focused = v);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Material(
        color: widget.selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _focused
                    ? AppColors.primary
                    : (widget.selected ? AppColors.primary : AppColors.border),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Text(
              widget.label,
              style: AppTypography.label.copyWith(
                color: widget.selected
                    ? AppColors.onPrimary
                    : AppColors.textPrimary,
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.onAdd,
    required this.onSelect,
    this.selected = false,
    this.unavailable = false,
    this.showOutOfStock = false,
  });

  final ProductModel product;
  final VoidCallback onAdd;
  final VoidCallback onSelect;
  final bool selected;

  /// Out of stock while sales are limited to stock — cannot be added.
  final bool unavailable;

  /// Red out-of-stock overlay (set briefly after a blocked add).
  final bool showOutOfStock;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  static const _outOfStockRed = Color(0xFFEF4444);

  bool _tapped = false;

  void _activate() => widget.onAdd();

  void _onTapDown(TapDownDetails details) {
    setState(() => _tapped = true);
    // Mouse / touchpad: focus this product on press, not on hover.
    widget.onSelect();
  }

  void _onTapCancel() {
    setState(() => _tapped = false);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _tapped = false);
    _activate();
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.product.currencyCode ?? 'AFN';
    final selected = widget.selected;
    final brand = (widget.product.brand ?? '').trim();
    final alert = widget.showOutOfStock;
    final accent = alert ? _outOfStockRed : AppColors.primary;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            _activate();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: AppRadius.card,
          border: Border.all(
            color: (selected || alert) ? accent : AppColors.border,
            width: (selected || alert) ? 2 : 1,
          ),
          boxShadow: (selected || alert)
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: alert ? 0.45 : 0.28),
                    blurRadius: alert ? 14 : 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.card,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: Stack(
              children: [
                SizedBox.expand(
                  child: _ProductImage(path: widget.product.imagePath),
                ),
                Container(
                  color: AppColors.primary.withAlpha(
                    ((selected ? 0.28 : 0.18) * 255).round(),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _tapped ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.ease,
                  child: Container(
                    color: (widget.unavailable
                            ? _outOfStockRed
                            : AppColors.primary)
                        .withAlpha((0.32 * 255).round()),
                  ),
                ),
                if (brand.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 24,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.92),
                          borderRadius: const BorderRadius.only(
                            bottomRight: Radius.circular(12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(1, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          brand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.card.withAlpha((0.88 * 255).round()),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.product.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Formatters.money(
                            widget.product.sellingPrice,
                            currency: currency,
                          ),
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: alert ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Container(
                      color: _outOfStockRed.withAlpha((0.62 * 255).round()),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.remove_shopping_cart_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'status.outOfStock'.tr(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySemiBold.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = (path ?? '').trim();
    if (p.isNotEmpty) {
      final file = File(p);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return ColoredBox(
      color: AppColors.input,
      child: Image.asset(
        AppAssets.appIcon,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.image_outlined,
            color: AppColors.textMuted,
            size: 36,
          ),
        ),
      ),
    );
  }
}

class _CurrentOrderPane extends StatefulWidget {
  const _CurrentOrderPane({
    required this.vm,
    required this.amountController,
    required this.discountController,
    required this.onSave,
    required this.onSavePrint,
    required this.onCancel,
    required this.onEditLine,
    this.onSelectLine,
  });

  final OutboundCartViewModel vm;
  final TextEditingController amountController;
  final TextEditingController discountController;
  final VoidCallback onSave;
  final VoidCallback onSavePrint;
  final VoidCallback onCancel;
  final ValueChanged<OutboundCartLine> onEditLine;
  final ValueChanged<OutboundCartLine>? onSelectLine;

  @override
  State<_CurrentOrderPane> createState() => _CurrentOrderPaneState();
}

class _CurrentOrderPaneState extends State<_CurrentOrderPane> {
  bool _paymentOpen = false;
  final _listController = ScrollController();
  int _seenFocusGeneration = 0;

  OutboundCartViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    if (vm.isEditing &&
        (vm.discount > 0 || vm.applyCustomPayment || vm.amountReceived > 0)) {
      _paymentOpen = true;
    }
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  void _scrollToFocusedLineIfNeeded() {
    final gen = vm.focusGeneration;
    if (gen == _seenFocusGeneration || vm.focusedLineId == null) return;
    _seenFocusGeneration = gen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listController.hasClients) return;
      _listController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _setPaymentOpen(bool open) {
    setState(() => _paymentOpen = open);
    if (!open) {
      widget.amountController.clear();
      widget.discountController.clear();
      vm.clearCustomPayment();
      vm.setDiscount(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyCode = vm.orderCurrency?.code ?? 'AFN';
    _scrollToFocusedLineIfNeeded();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'sales.currentOrder'.tr(),
                  style: AppTypography.localize(
                    AppTypography.sectionTitle,
                    context: context,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'sales.cancelOrder'.tr(),
                onPressed: vm.lines.isEmpty || vm.saving
                    ? null
                    : widget.onCancel,
                icon: const Icon(Icons.clear, size: 20),
                color: AppColors.error,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GfDropdown<TradingPartnerOption?>(
            label: 'sales.customer'.tr(),
            value: vm.selectedCompany,
            items: <TradingPartnerOption?>[null, ...vm.companies],
            labelBuilder: (c) => c?.name ?? 'sales.walkInCustomer'.tr(),
            onChanged: vm.selectCompany,
            prefixIcon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: vm.lines.isEmpty
                ? GfEmptyState(
                    title: 'sales.cartEmpty'.tr(),
                    subtitle: 'sales.cartEmptyHint'.tr(),
                    compact: true,
                  )
                : ListView.separated(
                    controller: _listController,
                    itemCount: vm.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final line = vm.lines[i];
                      return _CartLineTile(
                        line: line,
                        focused: line.id == vm.focusedLineId,
                        onEdit: () => widget.onEditLine(line),
                        onRemove: () => vm.removeLine(line.id),
                        onQtyChanged: (q) => vm.setLineQuantity(line.id, q),
                        onPriceChanged: (p) => vm.setLineUnitPrice(line.id, p),
                        onSelect: () => widget.onSelectLine?.call(line),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'sales.subtotalItems'.tr(
              namedArgs: {'count': '${vm.lines.length}'},
            ),
            value: Formatters.money(vm.subtotal, currency: currencyCode),
          ),
          if (vm.discount > 0) ...[
            const SizedBox(height: 4),
            _TotalRow(
              label: 'sales.discount'.tr(),
              value:
                  '- ${Formatters.money(vm.discount, currency: currencyCode)}',
            ),
          ],
          const SizedBox(height: 4),
          _TotalRow(
            label: 'sales.total'.tr(),
            value: Formatters.money(vm.total, currency: currencyCode),
            emphasize: true,
          ),
          const SizedBox(height: 6),
          Material(
            color: AppColors.input.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _setPaymentOpen(!_paymentOpen),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'sales.orderSummaryPayment'.tr(),
                        style: AppTypography.label.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    Icon(
                      _paymentOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_paymentOpen) ...[
            // const SizedBox(height: 8),
            // GfDropdown<CurrencyModel>(
            //   // hint: 'sales.currency'.tr(),
            //   // label: 'sales.currency'.tr(),
            //   value: vm.orderCurrency,
            //   items: vm.currencies,
            //   labelBuilder: (c) => Formatters.currencyName(c.code),
            //   onChanged: vm.selectOrderCurrency,
            // ),
            // const SizedBox(height: 8),
            GfTextField(
              hint: 'sales.discount'.tr(),
              controller: widget.discountController,
              // label: 'sales.discount'.tr(),
              numberMode: true,
              onChanged: (v) {
                final parsed = Formatters.parse(v);
                vm.setDiscount(parsed ?? 0);
                if ((v).trim().isEmpty) {
                  // keep discount 0
                }
              },
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GfTextField(
                  hint: 'sales.amountReceived'.tr(),
                  controller: widget.amountController,
                  // label: 'sales.amountReceived'.tr(),
                  numberMode: true,
                  onChanged: (v) {
                    final raw = v.trim();
                    if (raw.isEmpty) {
                      vm.clearCustomPayment();
                      return;
                    }
                    vm.setAmountReceived(Formatters.parse(raw) ?? 0);
                  },
                ),
                const SizedBox(height: 10),
                // InputDecorator(
                //   decoration: InputDecoration(
                //     labelText: 'sales.change'.tr(),
                //     isDense: false,
                //     filled: true,
                //     fillColor: AppColors.input,
                //     contentPadding: const EdgeInsets.symmetric(
                //       horizontal: 12,
                //       vertical: 14,
                //     ),
                //     border: OutlineInputBorder(borderRadius: AppRadius.input),
                //   ),
                //   child: Text(
                //     Formatters.money(vm.change, currency: currencyCode),
                //     style: AppTypography.bodyMedium.copyWith(
                //       color: AppColors.success,
                //     ),
                //   ),
                // ),
              ],
            ),
            if (vm.applyCustomPayment &&
                (vm.remaining > 0.0001 || vm.change > 0.0001)) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: AppRadius.input,
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Text(
                      vm.remaining > 0.0001
                          ? 'sales.remaining'.tr()
                          : 'sales.change'.tr(),
                      style: AppTypography.bodyMedium,
                    ),
                    const Spacer(),
                    Text(
                      Formatters.money(
                        vm.remaining > 0.0001 ? vm.remaining : vm.change,
                        currency: currencyCode,
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: vm.remaining > 0.0001
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (AppConstants.enablePrint) ...[
                Expanded(
                  flex: 2,
                  child: GfPrimaryButton(
                    label: 'sales.savePrint'.tr(),
                    icon: Icons.print_rounded,
                    expanded: true,
                    compact: true,
                    isLoading: vm.saving,
                    onPressed: vm.saving || vm.lines.isEmpty
                        ? null
                        : widget.onSavePrint,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GfSecondaryButton(
                    label: 'sales.save'.tr(),
                    icon: Icons.save_outlined,
                    expanded: true,
                    compact: true,
                    onPressed: vm.saving || vm.lines.isEmpty
                        ? null
                        : widget.onSave,
                  ),
                ),
              ] else
                Expanded(
                  child: GfPrimaryButton(
                    label: 'sales.save'.tr(),
                    icon: Icons.save_outlined,
                    expanded: true,
                    compact: true,
                    isLoading: vm.saving,
                    onPressed: vm.saving || vm.lines.isEmpty
                        ? null
                        : widget.onSave,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasize
                ? AppTypography.bodyMedium
                : AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ),
        Text(
          value,
          style: emphasize
              ? AppTypography.bodyMedium.copyWith(color: AppColors.primary)
              : AppTypography.bodyMedium,
        ),
      ],
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onEdit,
    required this.onRemove,
    required this.onQtyChanged,
    required this.onPriceChanged,
    this.onSelect,
    this.focused = false,
  });

  final OutboundCartLine line;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final ValueChanged<double> onQtyChanged;
  final ValueChanged<double> onPriceChanged;
  final VoidCallback? onSelect;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final dimsLabel = '';
    final String? remnantHint = null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: focused
            ? AppColors.primary.withValues(alpha: 0.10)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? AppColors.primary : AppColors.border,
          width: focused ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: _ProductImage(path: line.product.imagePath),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              line.product.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium.copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (dimsLabel.isNotEmpty)
                            Flexible(
                              child: Text(
                                dimsLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),

                          TextButton(
                            onPressed: onEdit,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsetsDirectional.only(
                                start: 8,
                                end: 8,
                              ),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              foregroundColor: AppColors.primary,
                              textStyle: AppTypography.caption.copyWith(
                                fontSize: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                                side: BorderSide(color: AppColors.primary),
                              ),
                            ),
                            child: Text('sales.editLine'.tr()),
                          ),
                        ],
                      ),
                      if (remnantHint != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          remnantHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.warning,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // _QtyBtn(
                //   icon: Icons.remove_rounded,
                //   onTap: () => onQtyChanged(line.quantity - 1),
                // ),
                _CartQtyField(
                  key: ValueKey('qty-${line.id}'),
                  quantity: line.quantity,
                  focused: focused,

                  onChanged: onQtyChanged,
                ),
                // _QtyBtn(
                //   icon: Icons.add_rounded,
                //   onTap: () => onQtyChanged(line.quantity + 1),
                // ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            // const SizedBox(height: 6),
            // Row(
            //   children: [
            //     Expanded(
            //       child: _CartLinePriceField(
            //         key: ValueKey('price-${line.id}'),
            //         unitPrice: line.unitPrice,
            //         onChanged: onPriceChanged,
            //       ),
            //     ),
            //     const SizedBox(width: 8),
            //     Text(
            //       Formatters.money(line.lineTotal, currency: line.currencyLabel),
            //       style: AppTypography.bodyMedium.copyWith(
            //         fontSize: 12,
            //         fontWeight: focused ? FontWeight.w700 : FontWeight.w600,
            //         color: focused ? AppColors.primary : AppColors.textPrimary,
            //       ),
            //     ),
            //   ],
            // ),
          ],
        ),
      ),
    );
  }
}

class _EditLineDialog extends StatefulWidget {
  const _EditLineDialog({required this.line});

  final OutboundCartLine line;

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late final TextEditingController _qty;
  late final TextEditingController _price;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    _qty = TextEditingController(text: Formatters.number(line.quantity));
    _price = TextEditingController(
      text: line.unitPrice <= 0 ? '' : Formatters.number(line.unitPrice),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  // Enter can reach both the field's onSubmitted and the shell's shortcut.
  void _close([({double? qty, double? price})? result]) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.edit_outlined,
      title: 'sales.editLine'.tr(),
      subtitle: widget.line.product.displayName,
      onCancel: _close,
      onPrimary: () => _close((
        qty: Formatters.parse(_qty.text),
        price: Formatters.parse(_price.text),
      )),
      primaryLabel: 'common.save'.tr(),
      maxWidth: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GfTextField(
            controller: _qty,
            label: 'common.quantity'.tr(),
            numberMode: true,
            prefixIcon: Icons.numbers_rounded,
          ),
          const SizedBox(height: 12),
          GfTextField(
            controller: _price,
            label: 'inboundOutbound.unitPrice'.tr(),
            numberMode: true,
            prefixIcon: Icons.payments_outlined,
          ),
        ],
      ),
    );
  }
}

class _CartLinePriceField extends StatefulWidget {
  const _CartLinePriceField({required this.unitPrice, required this.onChanged});

  final double unitPrice;
  final ValueChanged<double> onChanged;

  @override
  State<_CartLinePriceField> createState() => _CartLinePriceFieldState();
}

class _CartLinePriceFieldState extends State<_CartLinePriceField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  String _display(double value) =>
      value <= 0 ? '' : Formatters.number(value);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _display(widget.unitPrice));
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CartLinePriceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) return;
    final next = _display(widget.unitPrice);
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    final parsed = Formatters.parse(_controller.text) ?? 0;
    final normalized = _display(parsed);
    if (_controller.text != normalized) {
      _controller.text = normalized;
    }
    if ((parsed - widget.unitPrice).abs() > 0.0001) {
      widget.onChanged(parsed);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GfTextField(
      controller: _controller,
      focusNode: _focus,
      hint: 'inboundOutbound.unitPrice'.tr(),
      numberMode: true,
      onChanged: (v) {
        final parsed = Formatters.parse(v);
        if (parsed == null) {
          if (v.trim().isEmpty) widget.onChanged(0);
          return;
        }
        widget.onChanged(parsed);
      },
    );
  }
}

class _CartQtyField extends StatefulWidget {
  const _CartQtyField({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.focused = false,
  });

  final double quantity;
  final ValueChanged<double> onChanged;
  final bool focused;

  @override
  State<_CartQtyField> createState() => _CartQtyFieldState();
}

class _CartQtyFieldState extends State<_CartQtyField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.quantity));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CartQtyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity && !_focus.hasFocus) {
      final next = _format(widget.quantity);
      if (_controller.text != next) _controller.text = next;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _format(double value) => Formatters.number(value);

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    final parsed = Formatters.parse(_controller.text);
    if (parsed == null || parsed <= 0) {
      _controller.text = _format(widget.quantity);
      return;
    }
    if (_controller.text != _format(parsed)) {
      _controller.text = _format(parsed);
    }
    if ((parsed - widget.quantity).abs() > 0.0001) {
      widget.onChanged(parsed);
    }
  }

  void _commitTyped(String raw) {
    final parsed = Formatters.parse(raw);
    if (parsed == null || parsed <= 0) return;
    if ((parsed - widget.quantity).abs() > 0.0001) {
      widget.onChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: GfTextField(
        controller: _controller,
        focusNode: _focus,
        numberMode: true,
        textAlign: TextAlign.center,
        borderless: true,
        // inputFormatters: [
        //   FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}([,.]\d{0,3})?$')),
        // ],
        onChanged: _commitTyped,
        onSubmitted: _commitTyped,
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
          color: AppColors.input,
        ),
        child: Icon(icon, size: 14, color: AppColors.textPrimary),
      ),
    );
  }
}
