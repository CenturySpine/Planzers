import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class PublicProfilePage extends ConsumerWidget {
  const PublicProfilePage({
    super.key,
    required this.userId,
    this.displayLabelHint = '',
  });

  final String userId;
  final String displayLabelHint;

  static const routePath = '/users/:userId/profile';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: ref
          .read(usersRepositoryProvider)
          .watchUsersDataByIds([userId]),
      builder: (context, snapshot) {
        final userData = snapshot.data?[userId];
        final account =
            (userData?['account'] as Map<String, dynamic>?) ?? const {};
        final accountName = (account['name'] as String?)?.trim() ?? '';
        final displayLabel =
            accountName.isNotEmpty ? accountName : displayLabelHint;
        final photoUrl = tripMemberStoredProfileBadgeUrl(userData);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              displayLabel.isNotEmpty ? displayLabel : l10n.publicProfileTitle,
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.maxWidth;
                      return _buildPhoto(
                        context: context,
                        photoUrl: photoUrl,
                        displayLabel: displayLabel,
                        size: size,
                      );
                    },
                  ),
                  if (displayLabel.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      displayLabel,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhoto({
    required BuildContext context,
    required String photoUrl,
    required String displayLabel,
    required double size,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        avatarInitialFromDisplayLabel(displayLabel),
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );

    if (photoUrl.isEmpty) return fallback;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}
