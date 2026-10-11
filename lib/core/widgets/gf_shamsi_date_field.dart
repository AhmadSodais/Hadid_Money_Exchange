import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/app_calendar.dart';
import '../utils/shamsi_dates.dart';
import 'gf_scroll_behavior.dart';

/// Material-style Solar (Shamsi / Jalali) date picker dialog.
///
/// Mirrors Flutter's [showDatePicker] calendar UX: header, month navigation,
/// day grid (شنبه→جمعه), year grid toggle, Cancel / OK — built from scratch
/// for the Solar Hijri calendar with ~100 years past/future by default.
class GfShamsiDatePicker {
  GfShamsiDatePicker._();

  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initial,
    int? minYear,
    int? maxYear,
    String? title,
  }) {
    final now = Jalali.now();
    final first = Jalali(minYear ?? now.year - 100, 1, 1);
    final lastYear = maxYear ?? now.year + 100;
    final last = Jalali(lastYear, 12, Jalali(lastYear, 12, 1).monthLength);
    var selected = ShamsiDates.of(initial ?? DateTime.now());
    if (selected.toDateTime().isBefore(first.toDateTime())) selected = first;
    if (selected.toDateTime().isAfter(last.toDateTime())) selected = last;

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => _ShamsiDatePickerDialog(
        initialDate: selected,
        firstDate: first,
        lastDate: last,
        currentDate: now,
        helpText: title ?? 'common.selectDate'.tr(),
      ),
    );
  }
}

enum _PickerMode { day, year }

class _ShamsiDatePickerDialog extends StatefulWidget {
  const _ShamsiDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.helpText,
  });

  final Jalali initialDate;
  final Jalali firstDate;
  final Jalali lastDate;
  final Jalali currentDate;
  final String helpText;

  @override
  State<_ShamsiDatePickerDialog> createState() =>
      _ShamsiDatePickerDialogState();
}

class _ShamsiDatePickerDialogState extends State<_ShamsiDatePickerDialog> {
  late Jalali _selected;
  late Jalali _displayedMonth;
  _PickerMode _mode = _PickerMode.day;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _displayedMonth = Jalali(_selected.year, _selected.month, 1);
    _pageController = PageController(initialPage: _monthIndex(_displayedMonth));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _totalMonths {
    return (widget.lastDate.year - widget.firstDate.year) * 12 +
        widget.lastDate.month -
        widget.firstDate.month +
        1;
  }

  int _monthIndex(Jalali month) {
    return (month.year - widget.firstDate.year) * 12 +
        month.month -
        widget.firstDate.month;
  }

  Jalali _monthAt(int index) {
    final total = widget.firstDate.month - 1 + index;
    final year = widget.firstDate.year + total ~/ 12;
    final month = total % 12 + 1;
    return Jalali(year, month, 1);
  }

  bool get _canGoPrev => _monthIndex(_displayedMonth) > 0;
  bool get _canGoNext => _monthIndex(_displayedMonth) < _totalMonths - 1;

  void _goPrev() {
    if (!_canGoPrev) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _goNext() {
    if (!_canGoNext) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _displayedMonth = _monthAt(index));
  }

  void _selectDay(Jalali day) {
    setState(() {
      _selected = day;
      if (_selected.year != _displayedMonth.year ||
          _selected.month != _displayedMonth.month) {
        _displayedMonth = Jalali(_selected.year, _selected.month, 1);
        _pageController.jumpToPage(_monthIndex(_displayedMonth));
      }
    });
  }

  void _selectYear(int year) {
    final clampedDay = _selected.day.clamp(
      1,
      Jalali(year, _displayedMonth.month, 1).monthLength,
    );
    setState(() {
      _displayedMonth = Jalali(year, _displayedMonth.month, 1);
      _selected = Jalali(year, _displayedMonth.month, clampedDay);
      _mode = _PickerMode.day;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_monthIndex(_displayedMonth));
      }
    });
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _PickerMode.day ? _PickerMode.year : _PickerMode.day;
    });
  }

  void _confirm() => Navigator.of(context).pop(_selected.toDateTime());

  String get _headerDateLabel {
    final wd = ShamsiDates.weekdayNames[_selected.weekDay - 1];
    final month = ShamsiDates.monthNames[_selected.month - 1];
    return '$wd، ${_selected.day} $month';
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.3,
    );

    return Dialog(
      backgroundColor: AppColors.modal,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScale),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PickerHeader(
                helpText: widget.helpText,
                selectedLabel: _headerDateLabel,
                yearLabel: '${_selected.year}',
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _mode == _PickerMode.day
                        ? KeyedSubtree(
                            key: const ValueKey('day'),
                            child: _DayModeView(
                              displayedMonth: _displayedMonth,
                              selected: _selected,
                              currentDate: widget.currentDate,
                              firstDate: widget.firstDate,
                              lastDate: widget.lastDate,
                              totalMonths: _totalMonths,
                              pageController: _pageController,
                              canGoPrev: _canGoPrev,
                              canGoNext: _canGoNext,
                              onPrev: _goPrev,
                              onNext: _goNext,
                              onPageChanged: _onPageChanged,
                              onSelectDay: _selectDay,
                              onToggleYear: _toggleMode,
                              monthAt: _monthAt,
                            ),
                          )
                        : KeyedSubtree(
                            key: const ValueKey('year'),
                            child: _YearModeView(
                              firstYear: widget.firstDate.year,
                              lastYear: widget.lastDate.year,
                              selectedYear: _selected.year,
                              currentYear: widget.currentDate.year,
                              onSelectYear: _selectYear,
                              onToggleDay: _toggleMode,
                              displayedMonthLabel:
                                  '${ShamsiDates.monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                            ),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'common.cancel'.tr(),
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _confirm,
                      child: Text(
                        'common.confirm'.tr(),
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Material date-picker header band (help text + large selected date).
class _PickerHeader extends StatelessWidget {
  const _PickerHeader({
    required this.helpText,
    required this.selectedLabel,
    required this.yearLabel,
  });

  final String helpText;
  final String selectedLabel;
  final String yearLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              helpText,
              style: AppTypography.caption.copyWith(
                color: AppColors.onPrimary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              yearLabel,
              style: AppTypography.body.copyWith(
                color: AppColors.onPrimary.withValues(alpha: 0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              selectedLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sectionTitle.copyWith(
                color: AppColors.onPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w400,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayModeView extends StatelessWidget {
  const _DayModeView({
    required this.displayedMonth,
    required this.selected,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.totalMonths,
    required this.pageController,
    required this.canGoPrev,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    required this.onPageChanged,
    required this.onSelectDay,
    required this.onToggleYear,
    required this.monthAt,
  });

  final Jalali displayedMonth;
  final Jalali selected;
  final Jalali currentDate;
  final Jalali firstDate;
  final Jalali lastDate;
  final int totalMonths;
  final PageController pageController;
  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<Jalali> onSelectDay;
  final VoidCallback onToggleYear;
  final Jalali Function(int index) monthAt;

  @override
  Widget build(BuildContext context) {
    final monthLabel =
        '${ShamsiDates.monthNames[displayedMonth.month - 1]} ${displayedMonth.year}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MonthControls(
          label: monthLabel,
          yearMode: false,
          canGoPrev: canGoPrev,
          canGoNext: canGoNext,
          onPrev: onPrev,
          onNext: onNext,
          onToggleMode: onToggleYear,
        ),
        const SizedBox(height: 4),
        const _WeekdayHeader(),
        SizedBox(
          height: 6 * 42,
          child: PageView.builder(
            controller: pageController,
            onPageChanged: onPageChanged,
            itemCount: totalMonths,
            itemBuilder: (context, index) {
              final month = monthAt(index);
              return _MonthDayGrid(
                displayedMonth: month,
                selected: selected,
                currentDate: currentDate,
                firstDate: firstDate,
                lastDate: lastDate,
                onSelectDay: onSelectDay,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _YearModeView extends StatefulWidget {
  const _YearModeView({
    required this.firstYear,
    required this.lastYear,
    required this.selectedYear,
    required this.currentYear,
    required this.onSelectYear,
    required this.onToggleDay,
    required this.displayedMonthLabel,
  });

  final int firstYear;
  final int lastYear;
  final int selectedYear;
  final int currentYear;
  final ValueChanged<int> onSelectYear;
  final VoidCallback onToggleDay;
  final String displayedMonthLabel;

  @override
  State<_YearModeView> createState() => _YearModeViewState();
}

class _YearModeViewState extends State<_YearModeView> {
  late final ScrollController _controller;

  static const _itemExtent = 56.0;
  static const _columns = 3;

  @override
  void initState() {
    super.initState();
    final index = widget.selectedYear - widget.firstYear;
    final row = index ~/ _columns;
    final offset = (row * _itemExtent) - (_itemExtent * 2);
    _controller = ScrollController(
      initialScrollOffset: offset.clamp(0, double.infinity),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final years = [
      for (var y = widget.firstYear; y <= widget.lastYear; y++) y,
    ];

    return Column(
      children: [
        _MonthControls(
          label: widget.displayedMonthLabel,
          yearMode: true,
          canGoPrev: false,
          canGoNext: false,
          onPrev: () {},
          onNext: () {},
          onToggleMode: widget.onToggleDay,
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 6 * 42,
          child: GfNoScrollbarGutter(
            child: GridView.builder(
              controller: _controller,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                mainAxisExtent: _itemExtent,
                crossAxisSpacing: 8,
                mainAxisSpacing: 4,
              ),
              itemCount: years.length,
              itemBuilder: (context, i) {
                final year = years[i];
                final selected = year == widget.selectedYear;
                final isCurrent = year == widget.currentYear;
                return _YearCell(
                  year: year,
                  selected: selected,
                  isCurrent: isCurrent,
                  onTap: () => widget.onSelectYear(year),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthControls extends StatelessWidget {
  const _MonthControls({
    required this.label,
    required this.yearMode,
    required this.canGoPrev,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    required this.onToggleMode,
  });

  final String label;
  final bool yearMode;
  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Flexible(
            child: InkWell(
              onTap: onToggleMode,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySemiBold.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      yearMode
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!yearMode) ...[
            IconButton(
              tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
              onPressed: canGoPrev ? onPrev : null,
              icon: Icon(
                Icons.chevron_left_rounded,
                color: canGoPrev ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
              onPressed: canGoNext ? onNext : null,
              icon: Icon(
                Icons.chevron_right_rounded,
                color: canGoNext ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  /// Short Persian weekday labels (شنبه … جمعه).
  static const _labels = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          for (final label in _labels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthDayGrid extends StatelessWidget {
  const _MonthDayGrid({
    required this.displayedMonth,
    required this.selected,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.onSelectDay,
  });

  final Jalali displayedMonth;
  final Jalali selected;
  final Jalali currentDate;
  final Jalali firstDate;
  final Jalali lastDate;
  final ValueChanged<Jalali> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = displayedMonth.monthLength;
    // Jalali.weekDay: 1 = Saturday … 7 = Friday → offset 0…6 for Saturday-first grid.
    final firstWeekday = Jalali(
      displayedMonth.year,
      displayedMonth.month,
      1,
    ).weekDay;
    final leading = firstWeekday - 1;
    final itemCount = leading + daysInMonth;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 42,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < leading) return const SizedBox.shrink();
        final day = index - leading + 1;
        final date = Jalali(displayedMonth.year, displayedMonth.month, day);
        final dt = date.toDateTime();
        final enabled = !dt.isBefore(firstDate.toDateTime()) &&
            !dt.isAfter(lastDate.toDateTime());
        final isSelected = date.year == selected.year &&
            date.month == selected.month &&
            date.day == selected.day;
        final isToday = date.year == currentDate.year &&
            date.month == currentDate.month &&
            date.day == currentDate.day;

        return _DayCell(
          day: day,
          selected: isSelected,
          isToday: isToday,
          enabled: enabled,
          onTap: enabled ? () => onSelectDay(date) : null,
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final bool isToday;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color fg = enabled ? AppColors.textPrimary : AppColors.textMuted;
    Border? border;

    if (selected) {
      bg = AppColors.primary;
      fg = AppColors.onPrimary;
    } else if (isToday) {
      border = Border.all(color: AppColors.primary, width: 1.2);
      fg = AppColors.primary;
    }

    return Center(
      child: Material(
        color: bg ?? Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: border,
            ),
            child: Text(
              '$day',
              style: AppTypography.body.copyWith(
                color: fg,
                fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YearCell extends StatelessWidget {
  const _YearCell({
    required this.year,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  final int year;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color fg = AppColors.textPrimary;
    Border? border;

    if (selected) {
      bg = AppColors.primary;
      fg = AppColors.onPrimary;
    } else if (isCurrent) {
      border = Border.all(color: AppColors.primary, width: 1.2);
      fg = AppColors.primary;
    }

    return Center(
      child: Material(
        color: bg ?? Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 72,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: border,
            ),
            child: Text(
              '$year',
              style: AppTypography.bodySemiBold.copyWith(
                color: fg,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Form field that displays and picks a date using the active [AppCalendar].
class GfShamsiDateField extends StatelessWidget {
  const GfShamsiDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.required = false,
    this.clearable = true,
    this.minYear,
    this.maxYear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? hint;
  final bool required;
  final bool clearable;
  final int? minYear;
  final int? maxYear;

  @override
  Widget build(BuildContext context) {
    final display = value == null
        ? (hint ?? 'common.selectDate'.tr())
        : AppCalendar.formatDate(value!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: AppTypography.label,
            children: [
              if (required)
                TextSpan(
                  text: ' *',
                  style: AppTypography.label.copyWith(color: AppColors.error),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: AppSpacing.controlHeight,
          child: OutlinedButton(
            onPressed: () async {
              final picked = await AppCalendar.pickDate(
                context,
                initial: value,
                title: label,
              );
              if (picked != null) onChanged(picked);
            },
            style: OutlinedButton.styleFrom(
              alignment: AlignmentDirectional.centerStart,
              foregroundColor:
                  value == null ? AppColors.textMuted : AppColors.textPrimary,
              side: BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    display,
                    style: AppTypography.body.copyWith(
                      color: value == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (clearable && value != null)
                  InkWell(
                    onTap: () => onChanged(null),
                    child: Icon(
                      Icons.clear,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
