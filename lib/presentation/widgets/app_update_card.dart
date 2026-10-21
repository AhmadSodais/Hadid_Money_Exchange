import 'dart:async';
import 'dart:io';

import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/updater_controller.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import 'exchange_ui.dart';
import 'settings_kit.dart';

enum _CheckState { notChecked, upToDate, failed, available }

/// Settings → «به‌روزرسانی برنامه»: a manual check-for-update card.
///
/// The updater is deliberately *not* armed at startup: the controller is
/// created with a null archive URL, so the (offline-first) app never touches
/// the network on launch. Pressing «بررسی به‌روزرسانی» first runs a safe
/// check through [DesktopUpdater.versionCheck]; only when a newer release is
/// actually published in `app-archive.json` is the controller recreated with
/// the manifest URL, which makes [DesktopUpdateDirectCard] show the
/// download / restart card. Until the manifest is published with a higher
/// `shortVersion`, users see nothing — pushing code publishes no update.
class AppUpdateCard extends StatefulWidget {
  const AppUpdateCard({super.key, required this.padding});

  final double padding;

  @override
  State<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<AppUpdateCard> {
  static const _localization = DesktopUpdateLocalization(
    updateAvailableText: 'به‌روزرسانی موجود است',
    newVersionAvailableText: '{} {} آماده دانلود است',
    newVersionLongText:
        'نسخه جدید آماده دانلود است. با دکمه زیر دانلود آغاز می‌شود؛ '
        'این دانلود حدود {} مگابایت داده مصرف می‌کند.',
    restartText: 'راه‌اندازی مجدد برای به‌روزرسانی',
    warningTitleText: 'راه‌اندازی مجدد؟',
    restartWarningText:
        'برای کامل شدن نصب به‌روزرسانی، برنامه باید دوباره راه‌اندازی شود.\n'
        'تغییرات ذخیره‌نشده از دست می‌رود. اکنون دوباره راه‌اندازی شود؟',
    warningCancelText: 'فعلاً نه',
    warningConfirmText: 'راه‌اندازی مجدد',
    skipThisVersionText: 'رد کردن این نسخه',
    downloadText: 'دانلود به‌روزرسانی',
  );

  late DesktopUpdaterController _updater;
  bool _checking = false;
  _CheckState _state = _CheckState.notChecked;
  String? _foundVersion;
  String? _failureMessage;

  @override
  void initState() {
    super.initState();
    // Null URL: no automatic check. The controller is only armed with the
    // real manifest URL after a manual check finds a published update.
    _updater = DesktopUpdaterController(appArchiveUrl: null, localization: _localization)
      ..addListener(_onUpdaterChanged);
  }

  @override
  void dispose() {
    _updater.removeListener(_onUpdaterChanged);
    _updater.dispose();
    super.dispose();
  }

  void _onUpdaterChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final item = await DesktopUpdater().versionCheck(
        appArchiveUrl: AppConstants.updateManifestUrl,
      );
      if (!mounted) return;
      if (item == null) {
        setState(() => _state = _CheckState.upToDate);
        GfToast.success(context, 'برنامه به‌روز است؛ نسخه جدیدی منتشر نشده است.');
      } else {
        setState(() {
          _state = _CheckState.available;
          _foundVersion = item.version;
        });
        _armUpdater();
        GfToast.success(context, 'نسخه جدید ${item.version} یافت شد؛ از کارت زیر آن را دانلود کنید.');
      }
    } catch (e) {
      if (!mounted) return;
      // Diagnose the real cause instead of blaming every failure on the
      // network: a 404 means the manifest has not been published to the
      // repository yet; a socket failure is an actual connectivity problem.
      final text = e.toString();
      final message = switch (e) {
        _ when text.contains('HTTP 404') =>
          'فایل به‌روزرسانی هنوز در مخزن برنامه منتشر نشده است (app-archive.json یافت نشد).',
        _ when e is SocketException || text.contains('SocketException') || text.contains('Failed host lookup') =>
          'بررسی به‌روزرسانی انجام نشد؛ به اینترنت دسترسی نیست.',
        _ => 'بررسی به‌روزرسانی انجام نشد. دوباره تلاش کنید.',
      };
      setState(() {
        _state = _CheckState.failed;
        _failureMessage = message;
      });
      GfToast.error(context, message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Recreates the controller with the manifest URL so the package widget
  /// can drive download/restart. Constructing with a URL starts the
  /// package's own check immediately; that internal future has no error
  /// handler in this package version, so it runs in a guarded zone.
  void _armUpdater() {
    if (_updater.appArchiveUrl != null) return;
    DesktopUpdaterController? next;
    runZonedGuarded(
      () {
        next = DesktopUpdaterController(
          appArchiveUrl: Uri.parse(AppConstants.updateManifestUrl),
          localization: _localization,
        );
      },
      (error, stack) => debugPrint('desktop_updater check failed: $error'),
    );
    final created = next;
    if (created == null) return;
    _updater.removeListener(_onUpdaterChanged);
    _updater.dispose();
    _updater = created..addListener(_onUpdaterChanged);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      icon: Icons.system_update_alt_outlined,
      title: 'به‌روزرسانی برنامه',
      padding: widget.padding,
      footer: const SettingsFooterNote(
        'به‌روزرسانی فقط زمانی به شما پیشنهاد می‌شود که نسخه تازه‌ای رسماً منتشر شده باشد؛ '
        'تا آن زمان نتیجه بررسی «به‌روز است» خواهد بود. برای بررسی و دانلود، اتصال اینترنت لازم است.',
        warning: false,
      ),
      actions: [
        GfPrimaryButton(
          label: _checking ? 'در حال بررسی…' : 'بررسی به‌روزرسانی',
          icon: Icons.refresh_rounded,
          isLoading: _checking,
          onPressed: _checking ? null : _check,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsStatusLine(
            icon: Icons.verified_outlined,
            label: 'نسخه فعلی برنامه',
            value: '${AppConstants.appVersion}+${AppConstants.appBuildNumber}',
            ok: true,
          ),
          const SizedBox(height: 12),
          Text(
            'اگر نسخه تازه‌ای از برنامه منتشر شده باشد، پس از بررسی، کارت دانلود و نصب '
            'در همین بخش نمایش داده می‌شود و می‌توانید برنامه را از همین‌جا به‌روز کنید.',
            style: AppTypography.caption,
          ),
          if (_state == _CheckState.upToDate && !_updater.needUpdate) ...[
            const SizedBox(height: 12),
            const InfoBanner('برنامه به‌روز است و نسخه تازه‌ای منتشر نشده است.', tone: BannerTone.success),
          ],
          if (_state == _CheckState.failed) ...[
            const SizedBox(height: 12),
            InfoBanner(
              _failureMessage ?? 'بررسی به‌روزرسانی انجام نشد.',
              tone: BannerTone.warning,
            ),
          ],
          if (_state == _CheckState.available && !_updater.needUpdate) ...[
            const SizedBox(height: 12),
            InfoBanner(
              'نسخه جدید ${_foundVersion ?? ''} یافت شد؛ کارت دانلود در حال آماده‌سازی است…',
              tone: BannerTone.info,
            ),
          ],
          // Renders nothing until the controller reports a published update;
          // then shows the package's download / progress / restart card.
          DesktopUpdateDirectCard(
            controller: _updater,
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
