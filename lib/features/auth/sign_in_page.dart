import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/core/intl/app_language.dart';
import 'package:planerz/core/intl/app_locale_provider.dart';
import 'package:planerz/features/about/presentation/about_page.dart';
import 'package:planerz/features/auth/data/auth_repository.dart';
import 'package:planerz/features/auth/email_link_sign_in_page.dart';
import 'package:planerz/features/auth/phone_sign_in_page.dart';
import 'package:planerz/features/legal/presentation/legal_information_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

const Color _googleSignInBorder = Color(0xFFDADCE0);
const Color _googleSignInText = Color(0xFF3C4043);

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({
    super.key,
    this.redirectAfterSignIn,
    this.emailLink,
  });

  final String? redirectAfterSignIn;
  final String? emailLink;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  bool _isLoading = false;
  static const double _legalLinkFontSize = 12;
  static const double _footerReservedHeight = 32;
  static const int _animatedLabelCount = 3;
  static const Duration _labelDisplayDuration = Duration(seconds: 3);
  static const Duration _labelTransitionDuration = Duration(milliseconds: 420);

  int _animatedLabelIndex = 0;
  Timer? _subtitleTimer;

  @override
  void initState() {
    super.initState();
    _scheduleSubtitleStep();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_completeEmailLinkSignInIfNeeded());
    });
  }

  @override
  void dispose() {
    _subtitleTimer?.cancel();
    super.dispose();
  }

  void _scheduleSubtitleStep() {
    if (_animatedLabelIndex >= _animatedLabelCount - 1) {
      return;
    }

    _subtitleTimer?.cancel();
    _subtitleTimer = Timer(_labelDisplayDuration, _advanceSubtitle);
  }

  void _advanceSubtitle() {
    if (!mounted || _animatedLabelIndex >= _animatedLabelCount - 1) {
      return;
    }

    setState(() {
      _animatedLabelIndex += 1;
    });
    _scheduleSubtitleStep();
  }

  double _labelWidth(
    BuildContext context,
    TextStyle style,
    String label,
  ) {
    final textScaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();

    return painter.width;
  }

  double _maxAnimatedLabelWidth(
    BuildContext context,
    TextStyle style,
    List<String> animatedLabels,
  ) {
    final textScaler = MediaQuery.textScalerOf(context);
    var maxWidth = 0.0;

    for (final label in animatedLabels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      maxWidth = math.max(maxWidth, painter.width);
    }

    return maxWidth;
  }

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

  Future<void> _completeEmailLinkSignInIfNeeded() async {
    final repo = ref.read(authRepositoryProvider);
    final emailLink = widget.emailLink ?? Uri.base.toString();
    if (!repo.isSignInWithEmailLink(emailLink)) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    final l10n = AppLocalizations.of(context)!;
    try {
      final email = await repo.consumePendingEmailLinkEmail();
      if (email == null || email.trim().isEmpty) {
        if (mounted) {
          _showInfoSnackBar(l10n.signInEmailLinkMissingEmail);
        }
        return;
      }
      await repo.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );
      if (mounted) {
        final redirect = widget.redirectAfterSignIn;
        if (redirect != null && redirect.trim().isNotEmpty) {
          context.go(redirect);
        } else {
          context.go('/trips');
        }
      }
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Email link sign-in completion error: ${e.code} - ${e.message ?? 'no message'}',
      );
      if (mounted) {
        _showInfoSnackBar(
          '${l10n.signInEmailLinkConfirmFailed} (${e.code})',
        );
      }
    } catch (e) {
      debugPrint('Email link sign-in completion error: $e');
      if (mounted) {
        _showInfoSnackBar(l10n.signInEmailLinkConfirmFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showInfoSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setLanguage(AppLanguage language) async {
    await ref.read(appLocalePreferenceProvider.notifier).setLanguage(language);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedLanguage = ref.watch(currentAppLanguageProvider);
    final animatedLabels = <String>[
      l10n.signInAnimatedLabelOutings,
      l10n.signInAnimatedLabelWeekends,
      l10n.signInAnimatedLabelTrips,
    ];
    final legalLinkColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final subtitleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.0,
      letterSpacing: 0.6,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final animatedLabelLineHeight =
        (subtitleStyle.fontSize ?? 18) * (subtitleStyle.height ?? 1.0);
    final currentAnimatedLabel = animatedLabels[_animatedLabelIndex];
    final isFinalAnimatedLabel =
        _animatedLabelIndex >= animatedLabels.length - 1;
    // During transitions we keep extra room to avoid clipping for long labels.
    // On the final label we collapse to the actual text width so the whole
    // subtitle recenters with the page title.
    final animatedLabelWidth = isFinalAnimatedLabel
        ? _labelWidth(context, subtitleStyle, currentAnimatedLabel) + 6
        : _maxAnimatedLabelWidth(context, subtitleStyle, animatedLabels) + 24;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0,
                        constraints.maxHeight - _footerReservedHeight,
                      ),
                    ),
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: _labelTransitionDuration,
                                curve: Curves.easeOut,
                                width: animatedLabelWidth,
                                height: animatedLabelLineHeight,
                                child: ClipRect(
                                  child: AnimatedSwitcher(
                                    duration: _labelTransitionDuration,
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    transitionBuilder: (child, animation) {
                                      final incomingKey = ValueKey<String>(
                                        currentAnimatedLabel,
                                      );
                                      final isIncoming =
                                          child.key == incomingKey;
                                      final curvedAnimation = CurvedAnimation(
                                        parent: isIncoming
                                            ? animation
                                            : ReverseAnimation(animation),
                                        curve: isIncoming
                                            ? Curves.easeOut
                                            : Curves.easeIn,
                                      );
                                      final offsetAnimation = Tween<Offset>(
                                        begin: isIncoming
                                            ? const Offset(0, 1)
                                            : Offset.zero,
                                        end: isIncoming
                                            ? Offset.zero
                                            : const Offset(0, -1),
                                      ).animate(curvedAnimation);

                                      return SlideTransition(
                                        position: offsetAnimation,
                                        child: child,
                                      );
                                    },
                                    child: Align(
                                      key: ValueKey<String>(
                                        currentAnimatedLabel,
                                      ),
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        currentAnimatedLabel,
                                        textAlign: TextAlign.right,
                                        style: subtitleStyle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.signInSubtitleStatic,
                                textAlign: TextAlign.center,
                                style: subtitleStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: SizedBox(
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton(
                                    onPressed:
                                        _isLoading ? null : _signInWithGoogle,
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: _googleSignInText,
                                      disabledForegroundColor: _googleSignInText
                                          .withValues(alpha: 0.55),
                                      side: const BorderSide(
                                        color: _googleSignInBorder,
                                        width: 1,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 28,
                                        vertical: 14,
                                      ),
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: _googleSignInText
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                l10n.signInLoading,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: _googleSignInText
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SvgPicture.asset(
                                                'assets/images/google_g.svg',
                                                width: 20,
                                                height: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                l10n.signInContinueWithGoogle,
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
                                  const SizedBox(height: 10),
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      OutlinedButton(
                                        onPressed: _isLoading
                                            ? null
                                            : () => context.push(
                                                  EmailLinkSignInPage.routePath,
                                                ),
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: _googleSignInText,
                                          disabledForegroundColor:
                                              _googleSignInText.withValues(
                                                alpha: 0.55,
                                              ),
                                          side: const BorderSide(
                                            color: _googleSignInBorder,
                                            width: 1,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 28,
                                            vertical: 14,
                                          ),
                                          minimumSize:
                                              const Size.fromHeight(50),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.mail_outline,
                                              size: 20,
                                              color: _googleSignInText,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              l10n.signInContinueWithEmailLink,
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
                                      Positioned(
                                        top: -6,
                                        right: -6,
                                        child: _buildAuthBetaPill(l10n),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      OutlinedButton(
                                        onPressed: _isLoading
                                            ? null
                                            : () {
                                                final redirect =
                                                    widget.redirectAfterSignIn;
                                                final route = (redirect !=
                                                            null &&
                                                        redirect
                                                            .trim()
                                                            .isNotEmpty)
                                                    ? Uri(
                                                        path: PhoneSignInPage
                                                            .routePath,
                                                        queryParameters: {
                                                          'redirect': redirect,
                                                        },
                                                      ).toString()
                                                    : PhoneSignInPage.routePath;
                                                context.push(route);
                                              },
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: _googleSignInText,
                                          disabledForegroundColor:
                                              _googleSignInText.withValues(
                                                alpha: 0.55,
                                              ),
                                          side: const BorderSide(
                                            color: _googleSignInBorder,
                                            width: 1,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 28,
                                            vertical: 14,
                                          ),
                                          minimumSize:
                                              const Size.fromHeight(50),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.phone_outlined,
                                              size: 20,
                                              color: _googleSignInText,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              l10n.signInContinueWithPhone,
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
                                      Positioned(
                                        top: -6,
                                        right: -6,
                                        child: _buildAuthBetaPill(l10n),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Material(
                                color: selectedLanguage == AppLanguage.frFr
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.75)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => _setLanguage(AppLanguage.frFr),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/images/flag_fr.svg',
                                      width: 18,
                                      height: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Material(
                                color: selectedLanguage == AppLanguage.enUs
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.75)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => _setLanguage(AppLanguage.enUs),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/images/flag_us.svg',
                                      width: 18,
                                      height: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () =>
                          context.push(LegalInformationPage.routePath),
                      style: TextButton.styleFrom(
                        foregroundColor: legalLinkColor,
                        textStyle: const TextStyle(
                          fontSize: _legalLinkFontSize,
                          fontWeight: FontWeight.w400,
                        ),
                        overlayColor: Colors.transparent,
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l10n.legalInfoTitle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '|',
                      style: TextStyle(
                        fontSize: _legalLinkFontSize,
                        fontWeight: FontWeight.w400,
                        color: legalLinkColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => context.push(AboutPage.routePath),
                      style: TextButton.styleFrom(
                        foregroundColor: legalLinkColor,
                        textStyle: const TextStyle(
                          fontSize: _legalLinkFontSize,
                          fontWeight: FontWeight.w400,
                        ),
                        overlayColor: Colors.transparent,
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l10n.aboutTitle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '|',
                      style: TextStyle(
                        fontSize: _legalLinkFontSize,
                        fontWeight: FontWeight.w400,
                        color: legalLinkColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.appCopyright,
                      style: TextStyle(
                        fontSize: _legalLinkFontSize,
                        fontWeight: FontWeight.w400,
                        color: legalLinkColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthBetaPill(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3C4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE9C46A)),
      ),
      child: Text(
        l10n.signInAuthBetaPill,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Color(0xFF7A5A00),
        ),
      ),
    );
  }
}
