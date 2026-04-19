import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/auth/data/auth_repository.dart';

const Color _googleSignInBorder = Color(0xFFDADCE0);
const Color _googleSignInText = Color(0xFF3C4043);

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({
    super.key,
    this.redirectAfterSignIn,
  });

  final String? redirectAfterSignIn;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      if (mounted) {
        final redirect = widget.redirectAfterSignIn;
        if (redirect != null && redirect.trim().isNotEmpty) {
          context.go(redirect);
        } else {
          context.go('/trips');
        }
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign-in error: ${e.message ?? e.code}');
    } catch (e) {
      debugPrint('Google sign-in error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/app_icon.png',
                      width: 120,
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'PLANERZ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'WE ENTRE AMIS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        letterSpacing: 0.6,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 40),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _googleSignInText,
                            disabledForegroundColor:
                                _googleSignInText.withValues(alpha: 0.55),
                            side: const BorderSide(
                              color: _googleSignInBorder,
                              width: 1,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isLoading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _googleSignInText.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Connexion...',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: _googleSignInText.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SvgPicture.asset(
                                      'assets/images/google_g.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Continuer avec Google',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: _googleSignInText,
                                        letterSpacing: 0.15,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
