import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/oauth/data/oauth_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Consent screen for Planerz's OAuth authorization endpoint
/// (`/oauth/authorize`). A third-party app (e.g. Ridgegear) redirects the
/// user's browser here with `client_id`, `redirect_uri`, `scope` and
/// `state`; on "Autoriser" we hand back a single-use code by navigating the
/// browser to `redirect_uri`.
class OAuthAuthorizePage extends ConsumerStatefulWidget {
  const OAuthAuthorizePage({
    super.key,
    required this.clientId,
    required this.redirectUri,
    required this.scope,
    required this.state,
  });

  static const String routePath = '/oauth/authorize';

  final String clientId;
  final String redirectUri;
  final String scope;
  final String state;

  @override
  ConsumerState<OAuthAuthorizePage> createState() =>
      _OAuthAuthorizePageState();
}

class _OAuthAuthorizePageState extends ConsumerState<OAuthAuthorizePage> {
  bool _loading = true;
  bool _deciding = false;
  String? _loadError;
  OAuthClientPublicInfo? _client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  String get _currentFullPath {
    final params = <String, String>{
      'client_id': widget.clientId,
      'redirect_uri': widget.redirectUri,
      if (widget.scope.isNotEmpty) 'scope': widget.scope,
      if (widget.state.isNotEmpty) 'state': widget.state,
    };
    return Uri(
      path: OAuthAuthorizePage.routePath,
      queryParameters: params,
    ).toString();
  }

  Future<void> _init() async {
    if (FirebaseAuth.instance.currentUser == null) {
      context.go(
        Uri(
          path: '/sign-in',
          queryParameters: {'redirect': _currentFullPath},
        ).toString(),
      );
      return;
    }

    if (widget.clientId.isEmpty || widget.redirectUri.isEmpty) {
      setState(() {
        _loading = false;
        _loadError = 'invalid_request';
      });
      return;
    }

    try {
      final info = await ref
          .read(oauthRepositoryProvider)
          .getClientPublicInfo(widget.clientId);
      if (!info.redirectUris.contains(widget.redirectUri)) {
        setState(() {
          _loading = false;
          _loadError = 'invalid_redirect_uri';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _client = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _navigateBrowserTo(String url) async {
    if (url.isEmpty) return;
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self',
    );
  }

  Future<void> _authorize() async {
    if (_deciding) return;
    setState(() => _deciding = true);
    try {
      final redirectUrl = await ref.read(oauthRepositoryProvider).authorize(
            clientId: widget.clientId,
            redirectUri: widget.redirectUri,
            scope: widget.scope,
            state: widget.state,
          );
      if (!mounted) return;
      await _navigateBrowserTo(redirectUrl);
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.oauthAuthorizeError(e.toString()))),
      );
      setState(() => _deciding = false);
    }
  }

  Future<void> _deny() async {
    if (_deciding) return;
    setState(() => _deciding = true);
    final url = Uri.parse(widget.redirectUri).replace(
      queryParameters: {
        ...Uri.parse(widget.redirectUri).queryParameters,
        'error': 'access_denied',
        if (widget.state.isNotEmpty) 'state': widget.state,
      },
    );
    await _navigateBrowserTo(url.toString());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: AppBar(title: Text(l10n.oauthAuthorizeTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? _ErrorCard(message: l10n.oauthAuthorizeLoadError)
                      : _ConsentCard(
                          client: _client!,
                          scope: widget.scope,
                          deciding: _deciding,
                          onAuthorize: _authorize,
                          onDeny: _deny,
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.client,
    required this.scope,
    required this.deciding,
    required this.onAuthorize,
    required this.onDeny,
  });

  final OAuthClientPublicInfo client;
  final String scope;
  final bool deciding;
  final VoidCallback onAuthorize;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _AppIconBadge(
                  assetPath: 'assets/images/app_icon.png',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.sync_alt_rounded),
                ),
                _AppIconBadge(networkUrl: client.iconUrl),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              l10n.oauthAuthorizeHeadline(client.displayName),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _scopeDescription(l10n, scope),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: deciding ? null : onDeny,
                    child: Text(l10n.oauthAuthorizeDeny),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: deciding ? null : onAuthorize,
                    child: deciding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.oauthAuthorizeAllow),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _scopeDescription(AppLocalizations l10n, String scope) {
    if (scope.split(' ').contains('trips.read')) {
      return l10n.oauthScopeTripsRead;
    }
    return scope;
  }
}

class _AppIconBadge extends StatelessWidget {
  const _AppIconBadge({this.assetPath, this.networkUrl});

  final String? assetPath;
  final String? networkUrl;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: assetPath != null
            ? Image.asset(assetPath!, fit: BoxFit.cover)
            : (networkUrl != null && networkUrl!.isNotEmpty)
                ? Image.network(
                    networkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _FallbackAppIcon(),
                  )
                : const _FallbackAppIcon(),
      ),
    );
  }
}

class _FallbackAppIcon extends StatelessWidget {
  const _FallbackAppIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.apps_rounded),
    );
  }
}
