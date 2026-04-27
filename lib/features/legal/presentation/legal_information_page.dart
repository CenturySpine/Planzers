import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planerz/l10n/app_localizations.dart';

class LegalInformationPage extends StatelessWidget {
  const LegalInformationPage({super.key});

  static const String routePath = '/legal';
  static const String _mentionsAssetPath = 'legal/mentions_legales.txt';
  static const String _privacyAssetPath = 'legal/vie_privee_rgpd.txt';
  static const String _mentionsAssetPathEn = 'legal/mentions_legales_en.txt';
  static const String _privacyAssetPathEn = 'legal/vie_privee_rgpd_en.txt';

  Future<_LegalContent> _loadContent(Locale locale) async {
    final isEnglish = locale.languageCode == 'en';
    final mentionsPath = isEnglish ? _mentionsAssetPathEn : _mentionsAssetPath;
    final privacyPath = isEnglish ? _privacyAssetPathEn : _privacyAssetPath;
    final results = await Future.wait<String>([
      rootBundle.loadString(mentionsPath),
      rootBundle.loadString(privacyPath),
    ]);
    return _LegalContent(
      mentionsLegales: results[0],
      viePriveeRgpd: results[1],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.legalInfoTitle),
      ),
      body: FutureBuilder<_LegalContent>(
        future: _loadContent(Localizations.localeOf(context)),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.legalInfoLoadError,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final content = snapshot.data!;
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    tabs: [
                      Tab(text: l10n.legalMentionsTab),
                      Tab(text: l10n.legalPrivacyTab),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _LegalSectionContent(
                        title: l10n.legalMentionsTab,
                        body: content.mentionsLegales,
                      ),
                      _LegalSectionContent(
                        title: l10n.legalPrivacyTab,
                        body: content.viePriveeRgpd,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LegalContent {
  const _LegalContent({
    required this.mentionsLegales,
    required this.viePriveeRgpd,
  });

  final String mentionsLegales;
  final String viePriveeRgpd;
}

class _LegalSectionContent extends StatelessWidget {
  const _LegalSectionContent({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
