import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/sync_error_messages.dart';
import '../../core/sync/sync_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../core/widgets/widgets.dart';
import '../viewmodels/sync_viewmodel.dart';

enum _SyncFilter { all, pending, synced, failed, conflict }

/// Sync action shown beside the settings search field.
class SyncNowButton extends StatelessWidget {
  const SyncNowButton({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyncViewModel>();
    return GfPrimaryButton(
      label: 'sync.syncNow'.tr(),
      icon: Icons.cloud_upload_outlined,
      isLoading: vm.isBusy,
      onPressed: (!vm.isOnlineSyncEnabled || vm.isBusy)
          ? null
          : () => vm.syncNow(),
    );
  }
}

/// Sync status, queue history and retry tools, shown as a Settings section.
///
/// Needs a bounded height: the history table expands to fill the space left.
class SyncCenterPanel extends StatefulWidget {
  const SyncCenterPanel({super.key});

  @override
  State<SyncCenterPanel> createState() => _SyncCenterPanelState();
}

class _SyncCenterPanelState extends State<SyncCenterPanel> {
  _SyncFilter _filter = _SyncFilter.all;
  late final SyncViewModel _syncVm;

  @override
  void initState() {
    super.initState();
    _syncVm = context.read<SyncViewModel>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVm.attachView());
  }

  @override
  void dispose() {
    _syncVm.detachView();
    super.dispose();
  }

  List<SyncQueueItem> _filtered(SyncViewModel vm) {
    final rows = switch (_filter) {
      _SyncFilter.all => vm.history,
      _SyncFilter.pending => vm.history.where(
        (i) => i.status == SyncItemStatus.pending,
      ),
      _SyncFilter.synced => vm.history.where(
        (i) => i.status == SyncItemStatus.synced,
      ),
      _SyncFilter.failed => vm.failed,
      _SyncFilter.conflict => vm.conflicts,
    };
    return rows.toList();
  }

  String _entityLabel(String type) {
    switch (type) {
      case SyncEntityTypes.products:
        return 'sync.entity.products'.tr();
      case SyncEntityTypes.transactions:
        return 'sync.entity.transactions'.tr();
      case SyncEntityTypes.companyPayments:
        return 'sync.entity.companyPayments'.tr();
      case SyncEntityTypes.companies:
        return 'sync.entity.companies'.tr();
      case SyncEntityTypes.customers:
        return 'sync.entity.customers'.tr();
      case SyncEntityTypes.warehouses:
        return 'sync.entity.warehouses'.tr();
      case SyncEntityTypes.categories:
        return 'sync.entity.categories'.tr();
      case SyncEntityTypes.expenses:
        return 'sync.entity.expenses'.tr();
      case SyncEntityTypes.employees:
        return 'sync.entity.employees'.tr();
      case SyncEntityTypes.employeeWithdrawals:
        return 'sync.entity.employeeWithdrawals'.tr();
      case SyncEntityTypes.orders:
        return 'sync.entity.orders'.tr();
      case SyncEntityTypes.purchases:
        return 'sync.entity.purchases'.tr();
      default:
        return type;
    }
  }

  GfStatusVariant _statusVariant(SyncItemStatus status) => switch (status) {
    SyncItemStatus.synced => GfStatusVariant.completed,
    SyncItemStatus.pending => GfStatusVariant.pending,
    SyncItemStatus.failed ||
    SyncItemStatus.superseded => GfStatusVariant.cancelled,
    SyncItemStatus.conflict => GfStatusVariant.processing,
  };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyncViewModel>();
    final rows = _filtered(vm);

    return Column(
      children: [
        if (!vm.isOnlineSyncEnabled) ...[
          GfCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_outlined, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'sync.disabledHint'.tr(),
                    style: AppTypography.localize(
                      AppTypography.caption,
                      context: context,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (vm.message != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              vm.message!.tr(),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Expanded(
          child: GfDataTable(
            title: 'sync.history'.tr(),
            subtitle: _filter == _SyncFilter.conflict
                ? 'sync.conflictsHint'.tr()
                : null,
            minWidth: gfTableMinWidth(context, preferred: 760),
            tabs: GfScrollableRow(
              children: [
                _FilterChip(
                  label: '${'common.all'.tr()} (${vm.history.length})',
                  selected: _filter == _SyncFilter.all,
                  onTap: () => setState(() => _filter = _SyncFilter.all),
                ),
                _FilterChip(
                  label: '${'sync.pending'.tr()} (${vm.pendingCount})',
                  selected: _filter == _SyncFilter.pending,
                  onTap: () => setState(() => _filter = _SyncFilter.pending),
                ),
                _FilterChip(
                  label: '${'sync.synced'.tr()} (${vm.syncedCount})',
                  selected: _filter == _SyncFilter.synced,
                  onTap: () => setState(() => _filter = _SyncFilter.synced),
                ),
                _FilterChip(
                  label: '${'sync.status.failed'.tr()} (${vm.failedCount})',
                  selected: _filter == _SyncFilter.failed,
                  onTap: () => setState(() => _filter = _SyncFilter.failed),
                ),
                _FilterChip(
                  label: '${'sync.status.conflict'.tr()} (${vm.conflictCount})',
                  selected: _filter == _SyncFilter.conflict,
                  onTap: () => setState(() => _filter = _SyncFilter.conflict),
                ),
              ],
            ),
            actions: [
              if (vm.failed.isNotEmpty)
                GfSecondaryButton(
                  label: 'sync.retryAll'.tr(),
                  icon: Icons.refresh_rounded,
                  compact: true,
                  onPressed: vm.isBusy ? null : () => vm.retryAllFailed(),
                ),
            ],
            columns: [
              GfTableColumn(label: 'common.date'.tr(), flex: 2),
              GfTableColumn(label: 'sync.colType'.tr(), flex: 2),
              GfTableColumn(label: 'sync.colRecord'.tr(), flex: 2),
              GfTableColumn(label: 'sync.colOperation'.tr(), flex: 2),
              GfTableColumn(label: 'common.status'.tr(), flex: 2),
              const GfTableColumn(label: '', width: 48),
            ],
            rowCount: rows.length,
            total: rows.length,
            clientSide: true,
            itemLabel: 'common.records'.tr(),
            empty: GfEmptyState(
              title: 'sync.empty'.tr(),
              subtitle: 'sync.emptyHint'.tr(),
              compact: true,
            ),
            rowBuilder: (context, i) {
              final item = rows[i];
              return GfTableRow(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      ShamsiDates.formatDate(item.createdAt),
                      style: AppTypography.body,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _entityLabel(item.entityType),
                      style: AppTypography.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '#${item.entityId}',
                      style: AppTypography.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      item.operation.dbValue,
                      style: AppTypography.body,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: GfStatusBadge(
                        label: 'sync.status.${item.status.dbValue}'.tr(),
                        variant: _statusVariant(item.status),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: () {
                      final canRetry =
                          item.status == SyncItemStatus.failed ||
                          item.status == SyncItemStatus.pending;
                      final canKeep = item.status == SyncItemStatus.conflict;
                      final hasError =
                          item.lastError != null && item.lastError!.isNotEmpty;
                      if (!canRetry && !canKeep && !hasError) {
                        return const SizedBox.shrink();
                      }
                      return PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        color: AppColors.modal,
                        tooltip: 'common.actions'.tr(),
                        onSelected: (v) async {
                          if (v == 'retry') {
                            await vm.retryItem(item.id);
                          } else if (v == 'keepLocal') {
                            await vm.resolveKeepLocal(item);
                          }
                        },
                        itemBuilder: (_) => [
                          if (canRetry)
                            gfPopupMenuItem(
                              value: 'retry',
                              label: 'sync.retry'.tr(),
                            ),
                          if (canKeep)
                            gfPopupMenuItem(
                              value: 'keepLocal',
                              label: 'sync.keepLocal'.tr(),
                            ),
                          if (hasError)
                            PopupMenuItem(
                              enabled: false,
                              child: SizedBox(
                                width: 220,
                                child: Text(
                                  SyncErrorMessages.display(item.lastError),
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.error,
                                  ),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      );
                    }(),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
