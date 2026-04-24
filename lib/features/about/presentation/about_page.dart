import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  static const String routePath = '/about';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final PageController _carouselController;
  int _currentCarouselIndex = 0;

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

  Future<void> _openEmail(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri(scheme: 'mailto', path: 'bruno.chappe@gmail.com');
    final didLaunch = await launchUrl(uri);
    if (didLaunch || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.linkOpenImpossible)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
    final currentSlide = carouselSlides[_currentCarouselIndex];
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final sectionTitleStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);

    void goToSlide(int index) {
      _carouselController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }

    Future<void> openPhotoViewer(int initialIndex) async {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _AboutPhotoViewer(
            slides: carouselSlides,
            initialIndex: initialIndex,
          ),
          fullscreenDialog: true,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aboutTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(l10n.aboutFullNameAndAge, style: titleStyle),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () =>
                          _openExternalUrl(context, 'https://ko-fi.com/G2G31YCXGK'),
                      child: Image.network(
                        'https://storage.ko-fi.com/cdn/kofi6.png?v=6',
                        height: 36,
                        fit: BoxFit.contain,
                        semanticLabel: 'Buy Me a Coffee at ko-fi.com',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final maxAvailable = constraints.maxWidth;
                      final desiredSize = kIsWeb ? 420.0 : 280.0;
                      final carouselSize = desiredSize.clamp(
                        240.0,
                        maxAvailable,
                      );

                      return Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: carouselSize,
                            height: carouselSize,
                            child: PageView.builder(
                              controller: _carouselController,
                              itemCount: carouselSlides.length,
                              onPageChanged: (value) {
                                setState(() => _currentCarouselIndex = value);
                              },
                              itemBuilder: (context, index) {
                                final slide = carouselSlides[index];
                                return GestureDetector(
                                  onTap: () => openPhotoViewer(index),
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
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: kIsWeb ? 420 : 280,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSlide.caption,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (currentSlide.linkLabel != null &&
                              currentSlide.linkUrl != null) ...[
                            const SizedBox(height: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () =>
                                  _openExternalUrl(context, currentSlide.linkUrl!),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  currentSlide.linkLabel!,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Photo précédente',
                        onPressed: _currentCarouselIndex == 0
                            ? null
                            : () => goToSlide(_currentCarouselIndex - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_currentCarouselIndex + 1}/${carouselSlides.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Photo suivante',
                        onPressed: _currentCarouselIndex >= carouselSlides.length - 1
                            ? null
                            : () => goToSlide(_currentCarouselIndex + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      carouselSlides.length,
                      (index) => GestureDetector(
                        onTap: () => goToSlide(index),
                        child: Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: index == _currentCarouselIndex
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(height: 10),
                  Text(
                    l10n.aboutIntroText,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.aboutPassionsTitle, style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PassionChip(label: l10n.aboutPassionHiking),
                      _PassionChip(label: l10n.aboutPassionBachata),
                      _PassionChip(label: l10n.aboutPassionClimbing),
                      _PassionChip(label: l10n.aboutPassionRunning),
                      _PassionChip(label: l10n.aboutPassionCinema),
                      _PassionChip(label: l10n.aboutPassionSeries),
                      _PassionChip(label: l10n.aboutPassionGolf),
                      _PassionChip(label: l10n.aboutPassionCooking),
                      _PassionChip(label: l10n.aboutPassionBikeRepair),
                      _PassionChip(label: l10n.aboutPassionImprov),
                      _PassionChip(label: l10n.aboutPassionBoardGames),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.aboutNetworksTitle, style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  _NetworkTile(
                    icon: FontAwesomeIcons.facebook,
                    label: 'Facebook',
                    value: 'https://www.facebook.com/bruno.chappe',
                    onTap: () => _openExternalUrl(
                      context,
                      'https://www.facebook.com/bruno.chappe',
                    ),
                  ),
                  _NetworkTile(
                    icon: FontAwesomeIcons.instagram,
                    label: 'Instagram',
                    value: 'https://www.instagram.com/centuryspine/',
                    onTap: () => _openExternalUrl(
                      context,
                      'https://www.instagram.com/centuryspine/',
                    ),
                  ),
                  _NetworkTile(
                    icon: FontAwesomeIcons.linkedin,
                    label: 'LinkedIn',
                    value: 'www.linkedin.com/in/bruno-chappe-669a5869',
                    onTap: () => _openExternalUrl(
                      context,
                      'www.linkedin.com/in/bruno-chappe-669a5869',
                    ),
                  ),
                  _NetworkTile(
                    icon: FontAwesomeIcons.github,
                    label: 'GitHub',
                    value: 'https://github.com/CenturySpine',
                    onTap: () => _openExternalUrl(
                      context,
                      'https://github.com/CenturySpine',
                    ),
                  ),
                  _NetworkTile(
                    icon: FontAwesomeIcons.mugHot,
                    label: 'Ko-fi',
                    value: 'https://ko-fi.com/brunochappe',
                    onTap: () =>
                        _openExternalUrl(context, 'https://ko-fi.com/brunochappe'),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.aboutContactTitle, style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openEmail(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'bruno.chappe@gmail.com',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.aboutQuotesTitle, style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  Text(
                    '"Tout le malheur des hommes vient d\'une seule chose, qui est de ne pas savoir demeurer en repos dans une chambre" (Pascal)',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '"L\'apparence n\'est rien ; c\'est au fond du cœur qu\'est la plaie" (Euripide)',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassionChip extends StatelessWidget {
  const _PassionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FaIcon(icon, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
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
