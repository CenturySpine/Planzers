import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/auth_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class EmailLinkSignInPage extends ConsumerStatefulWidget {
  const EmailLinkSignInPage({super.key});

  static const String routePath = '/sign-in/email-link';

  @override
  ConsumerState<EmailLinkSignInPage> createState() =>
      _EmailLinkSignInPageState();
}

class _EmailLinkSignInPageState extends ConsumerState<EmailLinkSignInPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendEmailSignInLink() async {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      _showInfoSnackBar(l10n.signInEmailLinkInvalidEmail);
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      await ref.read(authRepositoryProvider).sendSignInLinkToEmail(email);
      if (!mounted) {
        return;
      }
      _showInfoSnackBar(l10n.signInEmailLinkSent);
    } on FirebaseAuthException catch (e) {
      debugPrint('Email link sign-in send error: ${e.message ?? e.code}');
      if (mounted) {
        _showInfoSnackBar(l10n.signInEmailLinkSendFailed);
      }
    } catch (e) {
      debugPrint('Email link sign-in send error: $e');
      if (mounted) {
        _showInfoSnackBar(l10n.signInEmailLinkSendFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isValidEmail(String value) {
    const pattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';
    return RegExp(pattern).hasMatch(value);
  }

  void _showInfoSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.signInSendEmailLinkCta,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _sendEmailSignInLink(),
                    decoration: InputDecoration(
                      labelText: l10n.signInEmailFieldLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isLoading ? null : _sendEmailSignInLink,
                    child: _isLoading
                        ? Text(l10n.signInLoading)
                        : Text(l10n.signInSendEmailLinkCta),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
