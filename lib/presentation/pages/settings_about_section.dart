part of 'settings_page.dart';

String _aboutText(String key) => 'settings.aboutCompany.$key'.tr();

abstract final class _HadidBrand {
  static const logoAsset = 'assets/images/hadid_logo.jpg';
  static const phones = ['0792348941', '0770745869'];

  static const navy = Color(0xFF0B2A3F);
  static const navyDeep = Color(0xFF06182A);
  static const mint = Color(0xFF8EF0C4);
  static const cyan = Color(0xFF27D3DD);
  static const peach = Color(0xFFF6C9A0);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mint, cyan],
  );

  static const darkGradient = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [navy, navyDeep],
  );

  /// Brand accent that stays readable on the current card surface.
  static Color get accent => AppColors.isLight ? const Color(0xFF0E8C99) : cyan;

  static TextStyle get paragraph =>
      AppTypography.body.copyWith(color: AppColors.textSecondary, height: 1.95);
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.metrics});

  final SettingsMetrics metrics;

  static const _services = <(IconData, String)>[
    (Icons.calculate_outlined, '۰۱'),
    (Icons.dashboard_customize_outlined, '۰۲'),
    (Icons.code_rounded, '۰۳'),
    (Icons.devices_other_outlined, '۰۴'),
    (Icons.support_agent_rounded, '۰۵'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 860;
        final gap = metrics.gap;
        final serviceColumns = width >= 1100 ? 3 : (width >= 640 ? 2 : 1);

        final sections = <Widget>[
          _AboutHero(wide: wide),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.currency_exchange_rounded,
            title: _aboutText('appTitle'),
            child: _AboutParagraphs(texts: [_aboutText('app1'), _aboutText('app2')]),
          ),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.apartment_rounded,
            title: _aboutText('introTitle'),
            child: _AboutParagraphs(
              texts: [
                _aboutText('intro1'),
                _aboutText('intro2'),
                _aboutText('intro3'),
              ],
            ),
          ),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.design_services_outlined,
            title: _aboutText('servicesTitle'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_aboutText('servicesIntro'), style: _HadidBrand.paragraph),
                const SizedBox(height: 16),
                _AboutGrid(
                  columns: serviceColumns,
                  spacing: metrics.fieldGap,
                  children: [
                    for (var i = 0; i < _services.length; i++)
                      _ServiceTile(
                        icon: _services[i].$1,
                        number: _services[i].$2,
                        title: _aboutText('service${i + 1}Title'),
                        body: _aboutText('service${i + 1}Body'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _AboutGrid(
            columns: wide ? 2 : 1,
            spacing: gap,
            children: [
              _HighlightCard(
                metrics: metrics,
                icon: Icons.visibility_outlined,
                title: _aboutText('visionTitle'),
                body: _aboutText('visionBody'),
              ),
              _HighlightCard(
                metrics: metrics,
                icon: Icons.flag_outlined,
                title: _aboutText('missionTitle'),
                body: _aboutText('missionBody'),
              ),
            ],
          ),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.verified_outlined,
            title: _aboutText('whyTitle'),
            child: _AboutGrid(
              columns: width >= 640 ? 2 : 1,
              spacing: metrics.fieldGap * 0.75,
              children: [
                for (var i = 1; i <= 6; i++)
                  _CheckItem(text: _aboutText('why$i')),
              ],
            ),
          ),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.handshake_outlined,
            title: _aboutText('commitmentTitle'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _aboutText('commitment1'),
                  style: _HadidBrand.paragraph,
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 16),
                _QuoteHighlight(text: _aboutText('commitment2')),
              ],
            ),
          ),
          _AboutContact(wide: wide),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'settings.aboutCompany.footer'.tr(
                namedArgs: {
                  'app': AppConstants.appName,
                  'version': AppConstants.appVersion,
                },
              ),
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              _FadeSlideIn(index: i, child: sections[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Staggered entrance; [index] delays each block slightly after the previous.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = index * 70;
    final total = 420 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
    );
  }
}

/// Equal-height rows; a shorter last row stretches its items to fill.
class _AboutGrid extends StatelessWidget {
  const _AboutGrid({
    required this.columns,
    required this.spacing,
    required this.children,
  });

  final int columns;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final rowItems = children.sublist(
        i,
        (i + columns).clamp(0, children.length),
      );
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < rowItems.length; j++) ...[
                if (j > 0) SizedBox(width: spacing),
                Expanded(child: rowItems[j]),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color, this.alpha = 0.25});

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 22.0;
    final paint = Paint()..color = color;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => oldDelegate.color != color;
}

/// Dark brand canvas shared by the hero and contact blocks.
class _BrandBackdrop extends StatelessWidget {
  const _BrandBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: _HadidBrand.darkGradient,
        borderRadius: AppRadius.card,
        boxShadow: [
          BoxShadow(
            color: _HadidBrand.navyDeep.withValues(
              alpha: AppColors.isLight ? 0.22 : 0.5,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          const PositionedDirectional(
            top: -90,
            end: -70,
            child: _GlowOrb(size: 300, color: _HadidBrand.cyan, alpha: 0.28),
          ),
          const PositionedDirectional(
            bottom: -120,
            start: -60,
            child: _GlowOrb(size: 280, color: _HadidBrand.mint, alpha: 0.18),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DotGridPainter(Colors.white.withValues(alpha: 0.05)),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _HadidBrand.mint,
                    _HadidBrand.cyan,
                    _HadidBrand.peach,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _HadidLogo extends StatelessWidget {
  const _HadidLogo({required this.size, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: _HadidBrand.mint.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: _HadidBrand.cyan.withValues(alpha: 0.35),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1.5),
        child: Image.asset(
          _HadidBrand.logoAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _GradientIconBadge extends StatelessWidget {
  const _GradientIconBadge({required this.icon, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: _HadidBrand.gradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: _HadidBrand.cyan.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.52, color: _HadidBrand.navy),
    );
  }
}

class _AboutHero extends StatelessWidget {
  const _AboutHero({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;

    final info = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            gradient: _HadidBrand.gradient,
            borderRadius: AppRadius.pill,
          ),
          child: Text(
            _aboutText('badge'),
            style: AppTypography.caption.copyWith(
              color: _HadidBrand.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _aboutText('name'),
          textAlign: textAlign,
          style: AppTypography.display.copyWith(
            color: Colors.white,
            fontSize: wide ? 28 : 22,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _aboutText('nameEn'),
          textAlign: textAlign,
          textDirection: TextDirection.ltr,
          style: AppTypography.bodyMedium.copyWith(
            fontFamily: AppFontFamily.inter,
            color: _HadidBrand.mint.withValues(alpha: 0.9),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: AppRadius.pill,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: _HadidBrand.peach,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _aboutText('tagline'),
                  style: AppTypography.bodySemiBold.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            _HeroStat(
              icon: Icons.workspace_premium_outlined,
              title: _aboutText('statExperienceTitle'),
              caption: _aboutText('statExperienceCaption'),
            ),
            _HeroStat(
              icon: Icons.groups_2_outlined,
              title: _aboutText('statTeamTitle'),
              caption: _aboutText('statTeamCaption'),
            ),
            _HeroStat(
              icon: Icons.auto_fix_high_outlined,
              title: _aboutText('statCustomTitle'),
              caption: _aboutText('statCustomCaption'),
            ),
          ],
        ),
      ],
    );

    return _BrandBackdrop(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? 36 : 22,
          wide ? 36 : 26,
          wide ? 36 : 22,
          wide ? 38 : 28,
        ),
        child: wide
            ? Row(
                children: [
                  const _HadidLogo(size: 156),
                  const SizedBox(width: 32),
                  Expanded(child: info),
                ],
              )
            : Column(
                children: [
                  const _HadidLogo(size: 112),
                  const SizedBox(height: 22),
                  info,
                ],
              ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GradientIconBadge(icon: icon, size: 34),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodySemiBold.copyWith(
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
              Text(
                caption,
                style: AppTypography.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({
    required this.metrics,
    required this.icon,
    required this.title,
    required this.child,
  });

  final SettingsMetrics metrics;
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(metrics.cardPadding + 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AboutHeading(icon: icon, title: title),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _AboutHeading extends StatelessWidget {
  const _AboutHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GradientIconBadge(icon: icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.sectionTitle),
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 3,
                decoration: const BoxDecoration(
                  gradient: _HadidBrand.gradient,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Renders `**bold**` segments of a translated string.
class _RichParagraph extends StatelessWidget {
  const _RichParagraph({
    required this.text,
    required this.style,
    this.boldColor,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final Color? boldColor;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final bold = style.copyWith(
      fontWeight: FontWeight.w700,
      color: boldColor ?? AppColors.textPrimary,
    );
    final parts = text.split('**');
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].isNotEmpty)
              TextSpan(text: parts[i], style: i.isOdd ? bold : null),
        ],
      ),
      textAlign: textAlign,
    );
  }
}

class _AboutParagraphs extends StatelessWidget {
  const _AboutParagraphs({required this.texts});

  final List<String> texts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < texts.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _RichParagraph(
            text: texts[i],
            style: _HadidBrand.paragraph,
            boldColor: _HadidBrand.accent,
            textAlign: TextAlign.justify,
          ),
        ],
      ],
    );
  }
}

class _ServiceTile extends StatefulWidget {
  const _ServiceTile({
    required this.icon,
    required this.number,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String number;
  final String title;
  final String body;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = _HadidBrand.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadius.card,
          border: Border.all(
            color: _hover ? accent.withValues(alpha: 0.55) : AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: _hover ? 0.16 : 0),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _GradientIconBadge(icon: widget.icon, size: 42),
                const Spacer(),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: AppTypography.display.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: accent.withValues(alpha: _hover ? 0.55 : 0.22),
                  ),
                  child: Text(widget.number),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: AppTypography.bodySemiBold.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              widget.body,
              style: AppTypography.subtitle.copyWith(height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.metrics,
    required this.icon,
    required this.title,
    required this.body,
  });

  final SettingsMetrics metrics;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final accent = _HadidBrand.accent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: 0.12), AppColors.card),
            AppColors.card,
          ],
        ),
        borderRadius: AppRadius.card,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -18,
            bottom: -24,
            child: Icon(icon, size: 128, color: accent.withValues(alpha: 0.07)),
          ),
          Padding(
            padding: EdgeInsets.all(metrics.cardPadding + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboutHeading(icon: icon, title: title),
                const SizedBox(height: 16),
                Text(
                  body,
                  style: _HadidBrand.paragraph,
                  textAlign: TextAlign.justify,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  const _CheckItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              gradient: _HadidBrand.gradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 16,
              color: _HadidBrand.navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _RichParagraph(
              text: text,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.75,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteHighlight extends StatelessWidget {
  const _QuoteHighlight({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = _HadidBrand.accent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_HadidBrand.mint, _HadidBrand.cyan],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded, size: 30, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RichParagraph(
                        text: text,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          height: 1.9,
                        ),
                        boldColor: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutContact extends StatelessWidget {
  const _AboutContact({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return _BrandBackdrop(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? 32 : 20,
          wide ? 28 : 22,
          wide ? 32 : 20,
          wide ? 30 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _GradientIconBadge(icon: Icons.phone_in_talk_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _aboutText('contactTitle'),
                    style: AppTypography.sectionTitle.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _aboutText('contactBody'),
              style: AppTypography.body.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.9,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _aboutText('phonesLabel'),
              style: AppTypography.label.copyWith(
                color: _HadidBrand.mint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final phone in _HadidBrand.phones)
                  _PhoneChip(phone: phone),
              ],
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
            const SizedBox(height: 18),
            Row(
              children: [
                const _HadidLogo(size: 44, glow: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _aboutText('name'),
                        style: AppTypography.bodySemiBold.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _aboutText('slogan'),
                        style: AppTypography.caption.copyWith(
                          color: _HadidBrand.peach,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneChip extends StatelessWidget {
  const _PhoneChip({required this.phone});

  final String phone;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (context.mounted) GfToast.success(context, _aboutText('phoneCopied'));
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _aboutText('copyPhone'),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _copy(context),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    gradient: _HadidBrand.gradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_rounded,
                    size: 18,
                    color: _HadidBrand.navy,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: AppTypography.bodySemiBold.copyWith(
                    fontFamily: AppFontFamily.inter,
                    color: Colors.white,
                    fontSize: 17,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

