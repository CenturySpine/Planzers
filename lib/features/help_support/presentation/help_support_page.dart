import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/about/presentation/about_page.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  static const String routePath = '/help-support';

  Future<void> _openUrl(BuildContext context, Uri uri) async {
    final l10n = AppLocalizations.of(context)!;
    final didLaunch = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!didLaunch && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4);
    final sectionTitleStyle = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(fontWeight: FontWeight.w700);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.helpSupportTitle),
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
                  Text(l10n.helpSupportIntro, style: bodyStyle),
                  const SizedBox(height: 20),
                  Text(l10n.helpSupportContactIntro, style: sectionTitleStyle),
                  const SizedBox(height: 12),
                  _ContactTile(
                    icon: Icons.bug_report_outlined,
                    label: l10n.helpSupportGithubLabel,
                    onTap: () => _openUrl(
                      context,
                      Uri.parse('https://github.com/CenturySpine/Planzers/issues'),
                    ),
                  ),
                  _ContactTile(
                    icon: Icons.email_outlined,
                    label: l10n.helpSupportEmailLabel,
                    sublabel: 'century.spine@gmail.com',
                    onTap: () => _openUrl(
                      context,
                      Uri(scheme: 'mailto', path: 'century.spine@gmail.com'),
                    ),
                  ),
                  _ContactTile(
                    icon: Icons.person_outline,
                    label: l10n.helpSupportAboutLinkLabel,
                    onTap: () => context.push(AboutPage.routePath),
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sublabel,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
