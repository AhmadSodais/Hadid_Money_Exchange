import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/shamsi_dates.dart';
import 'gf_button.dart';

/// Preset / custom periods for [GfDateFilter].
enum DateFilterPeriod {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  thisYear,
  custom,
}

/// Immutable value for the smart date filter (Shamsi calendar periods).
class DateFilterValue {
  const DateFilterValue({
    required this.period,
    required this.from,
    required this.to,
  });

  final DateFilterPeriod period;
  final DateTime from;
  final DateTime to;

  factory DateFilterValue.today([DateTime? now]) {
    final range = ShamsiDates.today(now);
    return DateFilterValue(
      period: DateFilterPeriod.today,
      from: range.$1,
      to: range.$2,
    );
  }

  factory DateFilterValue.yesterday([DateTime? now]) {
    final range = ShamsiDates.yesterday(now);
    return DateFilterValue(
      period: DateFilterPeriod.yesterday,
      from: range.$1,
      to: range.$2,
    );
  }

  factory DateFilterValue.thisWeek([DateTime? now]) {
    final range = ShamsiDates.thisWeek(now);
    return DateFilterValue(
      period: DateFilterPeriod.thisWeek,
      from: range.$1,
      to: range.$2,
    );
  }

  factory DateFilterValue.thisMonth([DateTime? now]) {
    final range = ShamsiDates.thisMonth(now);
    return DateFilterValue(
      period: DateFilterPeriod.thisMonth,
      from: range.$1,
      to: range.$2,
    );
  }

  factory DateFilterValue.thisYear([DateTime? now]) {
    final range = ShamsiDates.thisYear(now);
    return DateFilterValue(
      period: DateFilterPeriod.thisYear,
      from: range.$1,
      to: range.$2,
    );
  }

  factory DateFilterValue.custom({
    required DateTime from,
    required DateTime to,
  }) {
    final a = ShamsiDates.dateOnly(from);
    final b = ShamsiDates.dateOnly(to);
    final start = a.isBefore(b) ? a : b;
    final end = a.isBefore(b) ? b : a;
    return DateFilterValue(
      period: DateFilterPeriod.custom,
      from: start,
      to: ShamsiDates.endOfDay(end),
    );
  }

  bool contains(DateTime date) {
    final d = date.toLocal();
    return !d.isBefore(from) && !d.isAfter(to);
  }

  /// Annual (this year) views do not support PDF export.
  bool get supportsPdfExport => period != DateFilterPeriod.thisYear;

  /// Compact trigger label: preset name, or Shamsi date(s) for custom ranges.
  String get displayLabel {
    switch (period) {
      case DateFilterPeriod.today:
        return 'dateFilter.today'.tr();
      case DateFilterPeriod.yesterday:
        return 'dateFilter.yesterday'.tr();
      case DateFilterPeriod.thisWeek:
        return 'dateFilter.thisWeek'.tr();
      case DateFilterPeriod.thisMonth:
        return 'dateFilter.thisMonth'.tr();
      case DateFilterPeriod.thisYear:
        return 'dateFilter.thisYear'.tr();
      case DateFilterPeriod.custom:
        return ShamsiDates.formatRange(from, to);
    }
  }

  /// Period text for PDF / share copy — always Shamsi numbers (e.g. `1405/5/4`),
  /// never relative labels like "Today" or "Yesterday".
  String get exportPeriodLabel => ShamsiDates.formatRange(from, to);

  String subtitleFor(DateFilterPeriod p) {
    final v = switch (p) {
      DateFilterPeriod.today => DateFilterValue.today(),
      DateFilterPeriod.yesterday => DateFilterValue.yesterday(),
      DateFilterPeriod.thisWeek => DateFilterValue.thisWeek(),
      DateFilterPeriod.thisMonth => DateFilterValue.thisMonth(),
      DateFilterPeriod.thisYear => DateFilterValue.thisYear(),
      DateFilterPeriod.custom => this,
    };
    return ShamsiDates.formatRange(v.from, v.to);
  }
}

/// Compact smart date filter matching GlassFlow warehouse UI.
class GfDateFilter extends StatefulWidget {
  const GfDateFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 248,
  });

  final DateFilterValue value;
  final ValueChanged<DateFilterValue> onChanged;
  final double width;

  @override
  State<GfDateFilter> createState() => _GfDateFilterState();
}

class _GfDateFilterState extends State<GfDateFilter> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  bool _customMode = false;
  late DateTime _draftFrom;
  late DateTime _draftTo;

  @override
  void initState() {
    super.initState();
    _draftFrom = widget.value.from;
    _draftTo = widget.value.to;
  }

  @override
  void didUpdateWidget(covariant GfDateFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_customMode) {
      _draftFrom = widget.value.from;
      _draftTo = widget.value.to;
    }
  }

  void _toggle() {
    if (_portal.isShowing) {
      _close();
    } else {
      setState(() {
        _customMode = false;
        _draftFrom = widget.value.from;
        _draftTo = widget.value.to;
      });
      _portal.show();
      setState(() {});
    }
  }

  void _close() {
    _portal.hide();
    setState(() => _customMode = false);
  }

  void _selectPreset(DateFilterPeriod period) {
    final next = switch (period) {
      DateFilterPeriod.today => DateFilterValue.today(),
      DateFilterPeriod.yesterday => DateFilterValue.yesterday(),
      DateFilterPeriod.thisWeek => DateFilterValue.thisWeek(),
      DateFilterPeriod.thisMonth => DateFilterValue.thisMonth(),
      DateFilterPeriod.thisYear => DateFilterValue.thisYear(),
      DateFilterPeriod.custom => widget.value,
    };
    widget.onChanged(next);
    _close();
  }

  Future<void> _pickDraft({required bool isFrom}) async {
    final initial = isFrom ? _draftFrom : _draftTo;
    final picked = await ShamsiDates.pickDate(context, initial: initial);
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _draftFrom = picked;
        if (_draftTo.isBefore(_draftFrom)) _draftTo = _draftFrom;
      } else {
        _draftTo = picked;
        if (_draftFrom.isAfter(_draftTo)) _draftFrom = _draftTo;
      }
    });
  }

  void _applyCustom() {
    widget.onChanged(
      DateFilterValue.custom(from: _draftFrom, to: _draftTo),
    );
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final open = _portal.isShowing;
    final border = AppColors.primary.withValues(alpha: 0.28);
    // Filters sit in the page actions (trailing). Align the wider panel to the
    // trailing edge of the trigger so overflow grows inward, not off-screen.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final targetAnchor = isRtl ? Alignment.bottomLeft : Alignment.bottomRight;
    final followerAnchor = isRtl ? Alignment.topLeft : Alignment.topRight;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _close,
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: targetAnchor,
                followerAnchor: followerAnchor,
                offset: const Offset(0, 6),
                child: Material(
                  color: Colors.transparent,
                  elevation: 0,
                  child: _customMode
                      ? _CustomPanel(
                          from: _draftFrom,
                          to: _draftTo,
                          onPickFrom: () => _pickDraft(isFrom: true),
                          onPickTo: () => _pickDraft(isFrom: false),
                          onCancel: () =>
                              setState(() => _customMode = false),
                          onApply: _applyCustom,
                        )
                      : _MenuPanel(
                          value: widget.value,
                          onSelect: _selectPreset,
                          onCustom: () => setState(() {
                            _customMode = true;
                            _draftFrom = widget.value.from;
                            _draftTo = widget.value.to;
                          }),
                        ),
                ),
              ),
            ],
          );
        },
        child: SizedBox(
          width: widget.width,
          height: AppSpacing.controlHeight,
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        open && _customMode
                            ? 'dateFilter.customRange'.tr()
                            : widget.value.displayLabel,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.value,
    required this.onSelect,
    required this.onCustom,
  });

  final DateFilterValue value;
  final ValueChanged<DateFilterPeriod> onSelect;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final items = <(DateFilterPeriod, String, String)>[
      (
        DateFilterPeriod.today,
        'dateFilter.today'.tr(),
        value.subtitleFor(DateFilterPeriod.today),
      ),
      (
        DateFilterPeriod.yesterday,
        'dateFilter.yesterday'.tr(),
        value.subtitleFor(DateFilterPeriod.yesterday),
      ),
      (
        DateFilterPeriod.thisWeek,
        'dateFilter.thisWeek'.tr(),
        value.subtitleFor(DateFilterPeriod.thisWeek),
      ),
      (
        DateFilterPeriod.thisMonth,
        'dateFilter.thisMonth'.tr(),
        value.subtitleFor(DateFilterPeriod.thisMonth),
      ),
      (
        DateFilterPeriod.thisYear,
        'dateFilter.thisYear'.tr(),
        value.subtitleFor(DateFilterPeriod.thisYear),
      ),
    ];

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          for (final item in items)
            _MenuItem(
              icon: Icons.calendar_today_outlined,
              title: item.$2,
              subtitle: item.$3,
              selected: value.period == item.$1,
              onTap: () => onSelect(item.$1),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          _MenuItem(
            icon: Icons.tune_rounded,
            title: 'dateFilter.customRange'.tr(),
            subtitle: 'dateFilter.customHint'.tr(),
            selected: value.period == DateFilterPeriod.custom,
            onTap: onCustom,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodySemiBold.copyWith(
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomPanel extends StatelessWidget {
  const _CustomPanel({
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onCancel,
    required this.onApply,
  });

  final DateTime from;
  final DateTime to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'dateFilter.customRange'.tr(),
                style: AppTypography.bodySemiBold,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('dateFilter.from'.tr(), style: AppTypography.label),
          const SizedBox(height: 6),
          _DateBox(
            label: ShamsiDates.formatDate(from),
            onTap: onPickFrom,
          ),
          const SizedBox(height: 12),
          Text('dateFilter.to'.tr(), style: AppTypography.label),
          const SizedBox(height: 6),
          _DateBox(
            label: ShamsiDates.formatDate(to),
            onTap: onPickTo,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GfSecondaryButton(
                  label: 'common.cancel'.tr(),
                  compact: true,
                  onPressed: onCancel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GfPrimaryButton(
                  label: 'dateFilter.apply'.tr(),
                  compact: true,
                  onPressed: onApply,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.input,
      child: Container(
        height: AppSpacing.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: AppRadius.input,
          border: Border.all(color: AppColors.border),
          color: AppColors.input,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTypography.body),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
