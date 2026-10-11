import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/gf_search_field.dart';

/// Shared keyboard intents for GlassFlow desktop UX.
class GfSaveIntent extends Intent {
  const GfSaveIntent();
}

class GfNewIntent extends Intent {
  const GfNewIntent();
}

class GfCancelIntent extends Intent {
  const GfCancelIntent();
}

class GfConfirmIntent extends Intent {
  const GfConfirmIntent();
}

class GfDeleteIntent extends Intent {
  const GfDeleteIntent();
}

/// Common shortcut maps.
abstract final class GfShortcuts {
  /// Arrow keys → directional focus within the nearest [FocusTraversalGroup].
  static final Map<ShortcutActivator, Intent> directionalFocus = {
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const DirectionalFocusIntent(TraversalDirection.down),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const DirectionalFocusIntent(TraversalDirection.up),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const DirectionalFocusIntent(TraversalDirection.right),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const DirectionalFocusIntent(TraversalDirection.left),
  };

  static final Map<ShortcutActivator, Intent> dialog = {
    const SingleActivator(LogicalKeyboardKey.escape): const GfCancelIntent(),
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        const GfSaveIntent(),
    const SingleActivator(LogicalKeyboardKey.enter, control: true):
        const GfSaveIntent(),
  };

  static final Map<ShortcutActivator, Intent> formPage = {
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        const GfSaveIntent(),
    const SingleActivator(LogicalKeyboardKey.keyN, control: true):
        const GfNewIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const GfCancelIntent(),
    const SingleActivator(LogicalKeyboardKey.delete): const GfDeleteIntent(),
  };

  static Map<ShortcutActivator, Intent> get searchFocus => gfSearchShortcuts();
}

/// Vertical list / menu / table-row keyboard navigation.
///
/// Maps arrow keys to [DirectionalFocusIntent] so focus moves among
/// geometrically adjacent focusable descendants of this group.
class GfArrowFocusGroup extends StatelessWidget {
  const GfArrowFocusGroup({
    super.key,
    required this.child,
    this.includeHorizontal = true,
    this.policy,
  });

  final Widget child;
  final bool includeHorizontal;
  final FocusTraversalPolicy? policy;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.arrowDown):
          const DirectionalFocusIntent(TraversalDirection.down),
      const SingleActivator(LogicalKeyboardKey.arrowUp):
          const DirectionalFocusIntent(TraversalDirection.up),
      if (includeHorizontal) ...{
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const DirectionalFocusIntent(TraversalDirection.right),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const DirectionalFocusIntent(TraversalDirection.left),
      },
    };

    return FocusTraversalGroup(
      policy: policy ?? WidgetOrderTraversalPolicy(),
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: DirectionalFocusAction(),
          },
          child: child,
        ),
      ),
    );
  }
}

/// Wraps dialog/page content with Escape / Ctrl+S / focus traversal.
class GfKeyboardScope extends StatelessWidget {
  const GfKeyboardScope({
    super.key,
    required this.child,
    this.onSave,
    this.onCancel,
    this.onNew,
    this.onDelete,
    this.onFocusSearch,
    this.autofocus = false,
    this.dialogMode = false,
  });

  final Widget child;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;
  final VoidCallback? onNew;
  final VoidCallback? onDelete;
  final VoidCallback? onFocusSearch;
  final bool autofocus;
  final bool dialogMode;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      ...GfShortcuts.formPage,
      if (dialogMode) ...GfShortcuts.dialog,
      ...GfShortcuts.searchFocus,
    };

    return FocusTraversalGroup(
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            GfSaveIntent: CallbackAction<GfSaveIntent>(
              onInvoke: (_) {
                onSave?.call();
                return null;
              },
            ),
            GfCancelIntent: CallbackAction<GfCancelIntent>(
              onInvoke: (_) {
                onCancel?.call();
                return null;
              },
            ),
            GfNewIntent: CallbackAction<GfNewIntent>(
              onInvoke: (_) {
                onNew?.call();
                return null;
              },
            ),
            GfDeleteIntent: CallbackAction<GfDeleteIntent>(
              onInvoke: (_) {
                onDelete?.call();
                return null;
              },
            ),
            GfSearchFocusIntent: CallbackAction<GfSearchFocusIntent>(
              onInvoke: (_) {
                onFocusSearch?.call();
                return null;
              },
            ),
          },
          child: _GfKeyboardHost(
            autofocus: autofocus,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Host that optionally moves focus to the first interactive descendant
/// without inserting a focus-stealing node into the Tab order.
class _GfKeyboardHost extends StatefulWidget {
  const _GfKeyboardHost({required this.child, required this.autofocus});

  final Widget child;
  final bool autofocus;

  @override
  State<_GfKeyboardHost> createState() => _GfKeyboardHostState();
}

class _GfKeyboardHostState extends State<_GfKeyboardHost> {
  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        gfFocusFirstIn(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Whether the primary focus is currently inside an editable text field.
bool gfFocusInTextInput([BuildContext? context]) {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null) return false;
  final ctx = primary.context;
  if (ctx == null) return false;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
      ctx.widget is EditableText;
}

/// Whether focus is in a multi-line text field (Enter should insert a newline).
bool gfFocusInMultilineTextInput() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null) return false;
  final ctx = primary.context;
  if (ctx == null) return false;
  final EditableText? editable = ctx.widget is EditableText
      ? ctx.widget as EditableText
      : ctx.findAncestorWidgetOfExactType<EditableText>();
  if (editable == null) return false;
  final max = editable.maxLines;
  return max == null || max > 1;
}

/// After the next frame, focus the first input of [context]: the editable
/// text field nearest the top (then the reading start) of the screen.
///
/// Dialogs often show a loader first, so this keeps checking until the form
/// is built (up to [wait]). It stops early when focus moves inside the scope
/// on its own (user click, Tab, or a field's autofocus). Only when no text
/// field ever appears does it fall back to the first focusable control.
void gfFocusFirstIn(
  BuildContext context, {
  Duration wait = const Duration(seconds: 3),
}) {
  final deadline = DateTime.now().add(wait);
  final startFocus = FocusManager.instance.primaryFocus;

  void attempt() {
    if (!context.mounted) return;
    final scope = FocusScope.of(context);
    final primary = FocusManager.instance.primaryFocus;
    final movedInside = primary != null &&
        primary != startFocus &&
        primary != scope &&
        primary.ancestors.contains(scope);
    if (movedInside) return;

    final target = _firstEditableIn(context, scope);
    if (target != null) {
      target.requestFocus();
      return;
    }
    if (DateTime.now().isBefore(deadline)) {
      Future<void>.delayed(const Duration(milliseconds: 60), attempt);
      return;
    }
    for (final node in scope.traversalDescendants) {
      if (node.canRequestFocus && !node.skipTraversal) {
        node.requestFocus();
        return;
      }
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
}

FocusNode? _firstEditableIn(BuildContext context, FocusScopeNode scope) {
  final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
  FocusNode? best;
  Rect? bestRect;
  for (final node in scope.traversalDescendants) {
    if (!node.canRequestFocus || node.skipTraversal) continue;
    final ctx = node.context;
    if (ctx == null) continue;
    final editable = ctx.widget is EditableText
        ? ctx.widget as EditableText
        : ctx.findAncestorWidgetOfExactType<EditableText>();
    if (editable == null || editable.readOnly) continue;
    final rect = node.rect;
    if (rect.isEmpty) continue;
    if (bestRect == null || _readsBefore(rect, bestRect, rtl)) {
      best = node;
      bestRect = rect;
    }
  }
  return best;
}

/// Top row first; within a row, the reading start (left in LTR, right in RTL).
bool _readsBefore(Rect a, Rect b, bool rtl) {
  if ((a.top - b.top).abs() > 4) return a.top < b.top;
  return rtl ? a.right > b.right : a.left < b.left;
}
