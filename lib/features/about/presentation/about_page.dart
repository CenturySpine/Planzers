import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  static const String routePath = '/about';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  int _memberIndex = 0;
  int _photoIndex = 0;
  late final PageController _carouselController;

  @override
  void initState() {
    super.initState();
    _carouselController = PageController();
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _openExternalUrl(BuildContext context, String value) async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri.parse(value.startsWith('http') ? value : 'https://$value');
    final didLaunch = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (didLaunch || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.linkOpenImpossible)),
    );
  }

  Future<void> _openEmail(BuildContext context, String email) async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri(scheme: 'mailto', path: email);
    final didLaunch = await launchUrl(uri);
    if (didLaunch || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.linkOpenImpossible)),
    );
  }

  List<_AboutMember> _members(AppLocalizations l10n) {
    final carouselSlides = <_AboutCarouselSlide>[
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_1.png',
        caption: l10n.aboutCarouselCaption1,
        focalAlignment: const Alignment(0.15, -0.05),
      ),
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_2.png',
        caption: l10n.aboutCarouselCaption2,
        focalAlignment: const Alignment(-0.35, -0.1),
      ),
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_3.png',
        caption: l10n.aboutCarouselCaption3,
        focalAlignment: const Alignment(0.35, -0.1),
      ),
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_4.png',
        caption: l10n.aboutCarouselCaption4,
        focalAlignment: Alignment.center,
      ),
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_5.png',
        caption: l10n.aboutCarouselCaption5,
        focalAlignment: Alignment.center,
      ),
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_6.png',
        caption: l10n.aboutCarouselCaption6,
        focalAlignment: const Alignment(-0.35, -0.05),
      ),
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_7.png',
        caption: l10n.aboutCarouselCaption7,
        linkLabel: l10n.aboutCarouselCaption7LinkLabel,
        linkUrl: 'https://www.etablicyclette.fr/',
        focalAlignment: Alignment.center,
      ),
      _AboutCarouselSlide(
        assetPath: 'assets/images/about_8.png',
        caption: l10n.aboutCarouselCaption8,
        focalAlignment: const Alignment(0.45, -0.1),
      ),
    ];

    return [
      _AboutMember(
        name: l10n.aboutMemberBrunoNameAndAge,
        role: l10n.aboutMemberBrunoRole,
        kofiUrl: 'https://ko-fi.com/brunochappe',
        photos: carouselSlides,
        bio: l10n.aboutIntroText,
        passions: [
          l10n.aboutPassionHiking,
          l10n.aboutPassionBachata,
          l10n.aboutPassionClimbing,
          l10n.aboutPassionRunning,
          l10n.aboutPassionCinema,
          l10n.aboutPassionSeries,
          l10n.aboutPassionGolf,
          l10n.aboutPassionCooking,
          l10n.aboutPassionBikeRepair,
          l10n.aboutPassionImprov,
          l10n.aboutPassionBoardGames,
        ],
        social: [
          _AboutSocialLink(
            icon: FontAwesomeIcons.facebook,
            label: 'Facebook',
            value: 'https://www.facebook.com/bruno.chappe',
          ),
          _AboutSocialLink(
            icon: FontAwesomeIcons.instagram,
            label: 'Instagram',
            value: 'https://www.instagram.com/centuryspine/',
          ),
          _AboutSocialLink(
            icon: FontAwesomeIcons.linkedin,
            label: 'LinkedIn',
            value: 'www.linkedin.com/in/bruno-chappe-669a5869',
          ),
          _AboutSocialLink(
            icon: FontAwesomeIcons.github,
            label: 'GitHub',
            value: 'https://github.com/CenturySpine',
          ),
        ],
        kofiRow: _AboutSocialLink(
          icon: FontAwesomeIcons.mugHot,
          label: 'Ko-fi',
          value: 'https://ko-fi.com/brunochappe',
        ),
        email: 'bruno.chappe@gmail.com',
        quotes: [l10n.aboutQuote1, l10n.aboutQuote2],
      ),
      _AboutMember(
        name: l10n.aboutMemberFlorentName,
        role: l10n.aboutMemberFlorentRole,
        social: const [
          _AboutSocialLink(
            icon: FontAwesomeIcons.facebook,
            label: 'Facebook',
          ),
          _AboutSocialLink(
            icon: FontAwesomeIcons.instagram,
            label: 'Instagram',
          ),
          _AboutSocialLink(
            icon: FontAwesomeIcons.linkedin,
            label: 'LinkedIn',
          ),
          _AboutSocialLink(
            icon: FontAwesomeIcons.github,
            label: 'GitHub',
          ),
        ],
      ),
    ];
  }

  void _goToMember(int index, int memberCount) {
    setState(() {
      _memberIndex = (index + memberCount) % memberCount;
      _photoIndex = 0;
    });
    if (_carouselController.hasClients) {
      _carouselController.jumpToPage(0);
    }
  }

  void _goToPhoto(int index, int photoCount) {
    if (photoCount == 0) {
      return;
    }
    final target = (index + photoCount) % photoCount;
    _carouselController.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openPhotoViewer(
    BuildContext context,
    List<_AboutCarouselSlide> slides,
    int initialIndex,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _AboutPhotoViewer(
          slides: slides,
          initialIndex: initialIndex,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final members = _members(l10n);
    final member = members[_memberIndex];
    final sectionTitleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: NeonPalette.deep,
          fontSize: 15,
        );

    return Scaffold(
      backgroundColor: NeonPalette.scaffoldBackground,
      appBar: AppBar(
        title: Text(l10n.aboutTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            decoration: BoxDecoration(
              color: NeonPalette.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MemberSwitcher(
                  member: member,
                  memberIndex: _memberIndex,
                  memberCount: members.length,
                  onPrevious: () => _goToMember(_memberIndex - 1, members.length),
                  onNext: () => _goToMember(_memberIndex + 1, members.length),
                  previousTooltip: l10n.aboutMemberPrevious,
                  nextTooltip: l10n.aboutMemberNext,
                ),
                if (member.kofiUrl != null) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: _KofiButton(
                      label: l10n.aboutBuyMeACoffee,
                      onTap: () => _openExternalUrl(context, member.kofiUrl!),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _PhotoSection(
                  member: member,
                  photoIndex: _photoIndex,
                  carouselController: _carouselController,
                  comingSoonLabel: l10n.aboutComingSoon,
                  photoComingSoonLabel: l10n.aboutPhotoComingSoon,
                  previousTooltip: l10n.aboutPhotoPrevious,
                  nextTooltip: l10n.aboutPhotoNext,
                  onPhotoChanged: (index) => setState(() => _photoIndex = index),
                  onGoToPhoto: (index) =>
                      _goToPhoto(index, member.photos.length),
                  onPhotoTap: (index) =>
                      _openPhotoViewer(context, member.photos, index),
                  onLinkTap: (url) => _openExternalUrl(context, url),
                ),
                const SizedBox(height: 18),
                Text(
                  member.bio ?? l10n.aboutComingSoon,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        fontSize: 14.5,
                        color: member.bio != null
                            ? NeonPalette.deep
                            : NeonPalette.outline,
                        fontStyle:
                            member.bio == null ? FontStyle.italic : FontStyle.normal,
                      ),
                ),
                const SizedBox(height: 18),
                Text(l10n.aboutPassionsTitle, style: sectionTitleStyle),
                const SizedBox(height: 12),
                if (member.passions != null)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: member.passions!
                        .map((label) => _PassionChip(label: label))
                        .toList(),
                  )
                else
                  _PassionChip(
                    label: l10n.aboutComingSoon,
                    placeholder: true,
                  ),
                const SizedBox(height: 18),
                Text(l10n.aboutNetworksTitle, style: sectionTitleStyle),
                const SizedBox(height: 6),
                ...member.social.map(
                  (link) => _NetworkTile(
                    icon: link.icon,
                    label: link.label,
                    value: link.value,
                    placeholder: l10n.aboutComingSoon,
                    onTap: link.value == null
                        ? null
                        : () => _openExternalUrl(context, link.value!),
                  ),
                ),
                if (member.kofiRow != null)
                  _NetworkTile(
                    icon: member.kofiRow!.icon,
                    label: member.kofiRow!.label,
                    value: member.kofiRow!.value,
                    onTap: () =>
                        _openExternalUrl(context, member.kofiRow!.value!),
                  ),
                const SizedBox(height: 18),
                Text(l10n.aboutContactTitle, style: sectionTitleStyle),
                const SizedBox(height: 6),
                if (member.email != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openEmail(context, member.email!),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const _RowIcon(icon: Icons.mail_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              member.email!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const _RowIcon(icon: Icons.mail_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.aboutComingSoon,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: NeonPalette.outline,
                                      fontStyle: FontStyle.italic,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                Text(l10n.aboutQuotesTitle, style: sectionTitleStyle),
                const SizedBox(height: 10),
                if (member.quotes != null)
                  ...member.quotes!.map(
                    (quote) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        quote,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: NeonPalette.text700,
                              height: 1.55,
                              fontSize: 13.5,
                            ),
                      ),
                    ),
                  )
                else
                  Text(
                    l10n.aboutComingSoon,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: NeonPalette.outline,
                          fontSize: 13.5,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberSwitcher extends StatelessWidget {
  const _MemberSwitcher({
    required this.member,
    required this.memberIndex,
    required this.memberCount,
    required this.onPrevious,
    required this.onNext,
    required this.previousTooltip,
    required this.nextTooltip,
  });

  final _AboutMember member;
  final int memberIndex;
  final int memberCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String previousTooltip;
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _NavCircleButton(
              tooltip: previousTooltip,
              icon: Icons.chevron_left,
              onPressed: onPrevious,
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    member.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: NeonPalette.deep,
                          fontSize: 18,
                          letterSpacing: -0.1,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    member.role,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: NeonPalette.primary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            _NavCircleButton(
              tooltip: nextTooltip,
              icon: Icons.chevron_right,
              onPressed: onNext,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(memberCount, (index) {
            final isActive = index == memberIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 16 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isActive ? NeonPalette.primary : NeonPalette.divider,
                borderRadius: BorderRadius.circular(9999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _NavCircleButton extends StatelessWidget {
  const _NavCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 22,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize, color: NeonPalette.primary),
      style: IconButton.styleFrom(
        minimumSize: Size(size, size),
        maximumSize: Size(size, size),
        backgroundColor: NeonPalette.surfaceHighest,
        shape: const CircleBorder(),
      ),
    );
  }
}

class _KofiButton extends StatelessWidget {
  const _KofiButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.accent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(9999),
      child: InkWell(
        borderRadius: BorderRadius.circular(9999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_cafe, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.member,
    required this.photoIndex,
    required this.carouselController,
    required this.comingSoonLabel,
    required this.photoComingSoonLabel,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.onPhotoChanged,
    required this.onGoToPhoto,
    required this.onPhotoTap,
    required this.onLinkTap,
  });

  final _AboutMember member;
  final int photoIndex;
  final PageController carouselController;
  final String comingSoonLabel;
  final String photoComingSoonLabel;
  final String previousTooltip;
  final String nextTooltip;
  final ValueChanged<int> onPhotoChanged;
  final ValueChanged<int> onGoToPhoto;
  final ValueChanged<int> onPhotoTap;
  final ValueChanged<String> onLinkTap;

  @override
  Widget build(BuildContext context) {
    final photos = member.photos;
    if (photos.isEmpty) {
      return Column(
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: NeonPalette.surfaceHighest,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      size: 30,
                      color: NeonPalette.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      photoComingSoonLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NeonPalette.outline,
                            letterSpacing: 0.3,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            comingSoonLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NeonPalette.outline,
                  fontStyle: FontStyle.italic,
                  fontSize: 12.5,
                ),
          ),
        ],
      );
    }

    final currentSlide = photos[photoIndex];
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final desiredWidth = kIsWeb ? 420.0 : maxWidth;
            final carouselWidth = desiredWidth.clamp(240.0, maxWidth);

            return Center(
              child: SizedBox(
                width: carouselWidth,
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: PageView.builder(
                      controller: carouselController,
                      itemCount: photos.length,
                      onPageChanged: onPhotoChanged,
                      itemBuilder: (context, index) {
                        final slide = photos[index];
                        return GestureDetector(
                          onTap: () => onPhotoTap(index),
                          child: Image.asset(
                            slide.assetPath,
                            fit: BoxFit.cover,
                            alignment: slide.focalAlignment,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          currentSlide.caption,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: NeonPalette.onSurfaceVariant,
                fontSize: 12.5,
              ),
        ),
        if (currentSlide.linkLabel != null && currentSlide.linkUrl != null) ...[
          const SizedBox(height: 4),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onLinkTap(currentSlide.linkUrl!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  currentSlide.linkLabel!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                        fontSize: 12.5,
                      ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NavCircleButton(
              tooltip: previousTooltip,
              icon: Icons.chevron_left,
              size: 30,
              iconSize: 18,
              onPressed: () => onGoToPhoto(photoIndex - 1),
            ),
            const SizedBox(width: 14),
            Text(
              '${photoIndex + 1}/${photos.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: NeonPalette.text700,
                    fontSize: 13,
                  ),
            ),
            const SizedBox(width: 14),
            _NavCircleButton(
              tooltip: nextTooltip,
              icon: Icons.chevron_right,
              size: 30,
              iconSize: 18,
              onPressed: () => onGoToPhoto(photoIndex + 1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: List.generate(photos.length, (index) {
            final isActive = index == photoIndex;
            return GestureDetector(
              onTap: () => onGoToPhoto(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive ? NeonPalette.accent : NeonPalette.divider,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _PassionChip extends StatelessWidget {
  const _PassionChip({required this.label, this.placeholder = false});

  final String label;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: NeonPalette.divider,
          width: 1.5,
          style: BorderStyle.solid,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: placeholder ? NeonPalette.outline : NeonPalette.deep,
              fontStyle: placeholder ? FontStyle.italic : FontStyle.normal,
            ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(
        color: NeonPalette.surfaceHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: NeonPalette.text700),
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.placeholder,
  });

  final FaIconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: hasValue ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: NeonPalette.surfaceHighest,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: FaIcon(icon, size: 18, color: NeonPalette.text700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: NeonPalette.deep,
                          fontSize: 14,
                        ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    hasValue ? value! : placeholder ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: hasValue
                              ? Theme.of(context).colorScheme.primary
                              : NeonPalette.outline,
                          fontStyle:
                              hasValue ? FontStyle.normal : FontStyle.italic,
                          fontSize: 12.5,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutMember {
  const _AboutMember({
    required this.name,
    required this.role,
    this.kofiUrl,
    this.photos = const [],
    this.bio,
    this.passions,
    required this.social,
    this.kofiRow,
    this.email,
    this.quotes,
  });

  final String name;
  final String role;
  final String? kofiUrl;
  final List<_AboutCarouselSlide> photos;
  final String? bio;
  final List<String>? passions;
  final List<_AboutSocialLink> social;
  final _AboutSocialLink? kofiRow;
  final String? email;
  final List<String>? quotes;
}

class _AboutSocialLink {
  const _AboutSocialLink({
    required this.icon,
    required this.label,
    this.value,
  });

  final FaIconData icon;
  final String label;
  final String? value;
}

class _AboutCarouselSlide {
  const _AboutCarouselSlide({
    required this.assetPath,
    required this.caption,
    this.linkLabel,
    this.linkUrl,
    this.focalAlignment = Alignment.center,
  });

  final String assetPath;
  final String caption;
  final String? linkLabel;
  final String? linkUrl;
  final Alignment focalAlignment;
}

class _AboutPhotoViewer extends StatefulWidget {
  const _AboutPhotoViewer({
    required this.slides,
    required this.initialIndex,
  });

  final List<_AboutCarouselSlide> slides;
  final int initialIndex;

  @override
  State<_AboutPhotoViewer> createState() => _AboutPhotoViewerState();
}

class _AboutPhotoViewerState extends State<_AboutPhotoViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSlide = widget.slides[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.slides.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final slide = widget.slides[index];
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.asset(
                        slide.assetPath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                currentSlide.caption,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
