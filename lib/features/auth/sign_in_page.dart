import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/auth/data/auth_repository.dart';
import 'package:planerz/features/legal/presentation/legal_information_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                              child: OutlinedButton(
                                onPressed:
                                    _isLoading ? null : _signInWithGoogle,
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color:
                                                  _googleSignInText.withValues(
                                                alpha: 0.7,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            l10n.signInLoading,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color:
                                                  _googleSignInText.withValues(
                                                alpha: 0.7,
                                              ),
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
                            ),
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
                    Text(
                      '© 2026 Bruno Chappe',
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
}
