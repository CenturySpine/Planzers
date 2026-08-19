import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/account/presentation/connected_external_providers_page.dart';
import 'package:planerz/features/oauth/data/external_connection_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Landing page for `/external/callback` — where an external ecosystem
/// provider (e.g. Ridgegear) redirects the browser back to after its own
/// consent screen. No decision UI here (consent already happened on the
/// provider's side); this page only completes the exchange and reports the
/// outcome.
class ExternalConnectionCallbackPage extends ConsumerStatefulWidget {
  const ExternalConnectionCallbackPage({
    super.key,
    required this.code,
    required this.state,
    required this.error,
  });

  static const String routePath = '/external/callback';

  final String code;
  final String state;
  final String error;

  @override
  ConsumerState<ExternalConnectionCallbackPage> createState() =>
      _ExternalConnectionCallbackPageState();
}

enum _CallbackStatus { loading, success, error }

class _ExternalConnectionCallbackPageState
    extends ConsumerState<ExternalConnectionCallbackPage> {
  _CallbackStatus _status = _CallbackStatus.loading;
  String? _errorDetails;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    if (widget.error.isNotEmpty) {
      setState(() => _status = _CallbackStatus.error);
      return;
    }
    if (widget.code.isEmpty || widget.state.isEmpty) {
      setState(() => _status = _CallbackStatus.error);
      return;
    }

    try {
      // No providerId here: the provider's redirect only ever carries back
      // `code` and `state` (standard OAuth2) — `state` alone already
      // identifies the pending connection server-side.
      await ref.read(externalConnectionRepositoryProvider).completeConnection(
            code: widget.code,
            state: widget.state,
          );
      if (!mounted) return;
      setState(() => _status = _CallbackStatus.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _CallbackStatus.error;
        _errorDetails = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: AppBar(title: Text(l10n.externalConnectionCallbackTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (_status) {
                _CallbackStatus.loading => const CircularProgressIndicator(),
                _CallbackStatus.success => _CallbackResult(
                    icon: Icons.check_circle_outline,
                    iconColor: Colors.green,
                    message: l10n.externalConnectionCallbackSuccess,
                    onDone: () =>
                        context.go(ConnectedExternalProvidersPage.routePath),
                    doneLabel: l10n.externalConnectionCallbackBackToList,
                  ),
                _CallbackStatus.error => _CallbackResult(
                    icon: Icons.error_outline,
                    iconColor: Theme.of(context).colorScheme.error,
                    message: widget.error.isNotEmpty
                        ? l10n.externalConnectionCallbackDenied
                        : _errorDetails != null
                            ? l10n.commonErrorWithDetails(_errorDetails!)
                            : l10n.externalConnectionCallbackError,
                    onDone: () =>
                        context.go(ConnectedExternalProvidersPage.routePath),
                    doneLabel: l10n.externalConnectionCallbackBackToList,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CallbackResult extends StatelessWidget {
  const _CallbackResult({
    required this.icon,
    required this.iconColor,
    required this.message,
    required this.onDone,
    required this.doneLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String message;
  final VoidCallback onDone;
  final String doneLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: iconColor),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: Text(doneLabel)),
      ],
    );
  }
}
