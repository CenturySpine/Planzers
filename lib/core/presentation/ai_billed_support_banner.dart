import 'package:flutter/material.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class AiBilledSupportBanner extends StatelessWidget {
  const AiBilledSupportBanner({super.key});

  Future<void> _openKofi(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri.parse('https://ko-fi.com/G2G31YCXGK');
    final didLaunch = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (didLaunch || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.linkOpenImpossible)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planerzColors = context.planerzColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: planerzColors.successContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.mealRecipeAiBilledWarning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: planerzColors.success,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openKofi(context),
            child: Image.network(
              'https://storage.ko-fi.com/cdn/kofi6.png?v=6',
              height: 36,
              fit: BoxFit.contain,
              semanticLabel: 'Buy Me a Coffee at ko-fi.com',
            ),
          ),
        ],
      ),
    );
  }
}
