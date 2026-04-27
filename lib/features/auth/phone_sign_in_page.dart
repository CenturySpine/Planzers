import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/auth/data/auth_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class PhoneSignInPage extends ConsumerStatefulWidget {
  const PhoneSignInPage({super.key, this.redirectAfterSignIn});

  static const String routePath = '/sign-in/phone';

  final String? redirectAfterSignIn;

  @override
  ConsumerState<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

class _PhoneSignInPageState extends ConsumerState<PhoneSignInPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;

  // Native: verificationId from Firebase codeSent callback
  String? _verificationId;
  int? _resendToken;

  // Web: confirm function from ConfirmationResult
  Future<UserCredential> Function(String)? _webConfirm;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _phoneNumber => _phoneController.text.trim();

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context)!;
    final phone = _phoneNumber;
    if (phone.isEmpty || !phone.startsWith('+')) {
      _showSnackBar(l10n.signInPhoneInvalidNumber);
      return;
    }
    setState(() => _isLoading = true);
    if (kIsWeb) {
      await _sendCodeWeb(phone);
    } else {
      _sendCodeNative(phone);
    }
  }

  Future<void> _sendCodeWeb(String phone) async {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.read(authRepositoryProvider).auth;
    try {
      // applicationVerifier is optional; Firebase handles reCAPTCHA internally.
      final result = await auth.signInWithPhoneNumber(phone);
      if (!mounted) return;
      _webConfirm = result.confirm;
      setState(() {
        _codeSent = true;
        _isLoading = false;
      });
      _showSnackBar(l10n.signInPhoneCodeSent);
    } catch (e) {
      debugPrint('Phone send error (web): $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar(_phoneSendErrorMessage(l10n, e));
      }
    }
  }

  void _sendCodeNative(String phone) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.read(authRepositoryProvider).auth;
    unawaited(
      auth
          .verifyPhoneNumber(
            phoneNumber: phone,
            forceResendingToken: _resendToken,
            verificationCompleted: (credential) async {
              // Auto sign-in via Android Play Integrity or silent SMS retrieval
              try {
                await auth.signInWithCredential(credential);
                if (mounted) _navigateAfterSignIn();
              } catch (e) {
                debugPrint('Auto phone sign-in error: $e');
                if (mounted) {
                  setState(() => _isLoading = false);
                  _showSnackBar(l10n.signInPhoneConfirmFailed);
                }
              }
            },
            verificationFailed: (e) {
              debugPrint(
                'Phone verification failed: ${e.code} - ${e.message}',
              );
              if (mounted) {
                setState(() => _isLoading = false);
                _showSnackBar(_phoneSendErrorMessage(l10n, e));
              }
            },
            codeSent: (verificationId, resendToken) {
              if (mounted) {
                setState(() {
                  _verificationId = verificationId;
                  _resendToken = resendToken;
                  _codeSent = true;
                  _isLoading = false;
                });
                _showSnackBar(l10n.signInPhoneCodeSent);
              }
            },
            codeAutoRetrievalTimeout: (verificationId) {
              if (mounted) setState(() => _verificationId = verificationId);
            },
          )
          .catchError((Object e) {
            debugPrint('verifyPhoneNumber error: $e');
            if (mounted) {
              setState(() => _isLoading = false);
              _showSnackBar(_phoneSendErrorMessage(l10n, e));
            }
          }),
    );
  }

  Future<void> _confirmCode() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _showSnackBar(l10n.signInPhoneInvalidCode);
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        await _webConfirm!(code);
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: code,
        );
        await ref
            .read(authRepositoryProvider)
            .auth
            .signInWithCredential(credential);
      }
      if (mounted) _navigateAfterSignIn();
    } on FirebaseAuthException catch (e) {
      debugPrint('Phone confirm error: ${e.code} - ${e.message}');
      if (mounted) {
        _showSnackBar(
          e.code == 'invalid-verification-code'
              ? l10n.signInPhoneInvalidCode
              : l10n.signInPhoneConfirmFailed,
        );
      }
    } catch (e) {
      debugPrint('Phone confirm error: $e');
      if (mounted) _showSnackBar(l10n.signInPhoneConfirmFailed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateAfterSignIn() {
    final redirect = widget.redirectAfterSignIn;
    if (redirect != null && redirect.trim().isNotEmpty) {
      context.go(redirect);
    } else {
      context.go('/trips');
    }
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _phoneSendErrorMessage(AppLocalizations l10n, Object error) {
    if (error is FirebaseAuthException) {
      if (error.code == 'too-many-requests') {
        return l10n.signInPhoneTooManyRequests;
      }
      if (error.code == 'invalid-phone-number') {
        return l10n.signInPhoneInvalidNumber;
      }
    }
    return l10n.signInPhoneSendFailed;
  }

  void _resetToPhoneStep() {
    setState(() {
      _codeSent = false;
      _verificationId = null;
      _webConfirm = null;
    });
    _codeController.clear();
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
              child: _codeSent ? _buildCodeStep(l10n) : _buildPhoneStep(l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.signInPhoneTitle,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          enabled: !_isLoading,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendCode(),
          decoration: InputDecoration(
            labelText: l10n.signInPhoneFieldLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isLoading ? null : _sendCode,
          child: _isLoading
              ? Text(l10n.signInLoading)
              : Text(l10n.signInPhoneSendCodeCta),
        ),
      ],
    );
  }

  Widget _buildCodeStep(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.signInPhoneCodeTitle,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _phoneNumber,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          enabled: !_isLoading,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          autofocus: true,
          onSubmitted: (_) => _confirmCode(),
          decoration: InputDecoration(
            labelText: l10n.signInPhoneCodeFieldLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isLoading ? null : _confirmCode,
          child: _isLoading
              ? Text(l10n.signInLoading)
              : Text(l10n.signInPhoneConfirmCta),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _isLoading ? null : _sendCode,
              child: Text(l10n.signInPhoneResendCode),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _isLoading ? null : _resetToPhoneStep,
              child: Text(l10n.signInPhoneChangeNumber),
            ),
          ],
        ),
      ],
    );
  }
}
