import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/trips/data/invite_join_context.dart';
import 'package:planerz/features/trips/data/trip_member_profile_repository.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/l10n/app_localizations.dart';

class InviteJoinPage extends ConsumerStatefulWidget {
  const InviteJoinPage({
    super.key,
    required this.tripId,
    required this.token,
  });

  final String tripId;
  final String token;

  @override
  ConsumerState<InviteJoinPage> createState() => _InviteJoinPageState();
}

class _InviteJoinPageState extends ConsumerState<InviteJoinPage> {
  static String _messageForError(BuildContext context, Object e) {
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return AppLocalizations.of(context)!.commonErrorWithDetails(e.toString());
  }

  bool _loadingContext = true;
  bool _joining = false;
  String? _error;
  bool _joined = false;
  InviteJoinContext? _context;
  String? _selectedPlaceholderId;
  String? _suggestedPlaceholderId;
  String? _currentUserEmailLocalPart;
  final TextEditingController _placeholderSearchController =
      TextEditingController();

  /// 0: choose name, 1: stay + options (only when [requiresPlaceholderChoice]).
  int _inviteFormStep = 0;
  bool _joinUsingCurrentProfile = false;
  TripMemberStay? _stayDraft;
  TripMemberPhoneVisibility _phoneVisibilityDraft =
      TripMemberPhoneVisibility.nobody;
  bool _inviteCupidonEnabled = false;

  void _goToTripsList() {
    context.go('/trips');
  }

  List<Color> _joinOptionAccentColors(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pz = context.planerzColors;
    return <Color>[
      cs.secondary,
      cs.tertiary,
      pz.warning,
    ];
  }

  List<InviteJoinPlaceholderOption> _sortedPlaceholders(
    InviteJoinContext ctx,
  ) {
    final list = List<InviteJoinPlaceholderOption>.from(ctx.placeholders);
    list.sort(
      (a, b) => compareDisplayNamesForSort(a.displayName, b.displayName),
    );
    return list;
  }

  List<InviteJoinPlaceholderOption> _filteredPlaceholders(
    List<InviteJoinPlaceholderOption> sorted,
  ) {
    final q = _placeholderSearchController.text;
    return sorted
        .where((p) => displayNameMatchesNameSearch(p.displayName, q))
        .toList();
  }

  void _onPlaceholderSearchChanged(
    List<InviteJoinPlaceholderOption> sorted,
  ) {
    final filtered = _filteredPlaceholders(sorted);
    setState(() {
      final id = _selectedPlaceholderId;
      if (id != null && !filtered.any((p) => p.id == id)) {
        _selectedPlaceholderId = null;
      }
    });
  }

  Widget _placeholderChoiceTile({
    required InviteJoinPlaceholderOption option,
    required int accentIndex,
    required bool isSuggested,
  }) {
    final accents = _joinOptionAccentColors(context);
    final accent = accents[accentIndex % accents.length];
    final selected = _selectedPlaceholderId == option.id;
    final borderWidth = selected ? 2.5 : 1.5;
    final fillOpacity = selected ? 0.2 : 0.1;
    final borderOpacity = selected ? 1.0 : 0.7;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: accent.withValues(alpha: fillOpacity),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: accent.withValues(alpha: borderOpacity),
            width: borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _joining
              ? null
              : () => setState(() {
                    _selectedPlaceholderId = option.id;
                  }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: accent,
                    size: 26,
                  )
                else if (isSuggested)
                  Icon(
                    Icons.auto_awesome,
                    color: accent,
                    size: 26,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _placeholderSearchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final redirect = Uri(
        path: '/join-with-code',
        queryParameters: <String, String>{
          'tripId': widget.tripId,
          'token': widget.token,
        },
      ).toString();
      if (mounted) {
        context.go(
          '/sign-in?redirect=${Uri.encodeComponent(redirect)}',
        );
      }
      return;
    }
    _currentUserEmailLocalPart = _extractEmailLocalPart(user.email);

    await _loadCupidonDefaultFromProfile();
    await _loadContextAndMaybeJoin();
  }

  String? _extractEmailLocalPart(String? email) {
    if (email == null) return null;
    final trimmed = email.trim();
    if (trimmed.isEmpty) return null;
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 0) return null;
    final localPart = trimmed.substring(0, atIndex).trim();
    if (localPart.isEmpty) return null;
    return localPart;
  }

  String? _findSuggestedPlaceholderId(
    List<InviteJoinPlaceholderOption> sorted,
  ) {
    final emailLocalPart = _currentUserEmailLocalPart;
    if (emailLocalPart == null || emailLocalPart.trim().isEmpty) return null;
    final match = findBestUiStringSimilarityMatch(
      source: emailLocalPart,
      candidates: sorted.map((option) => option.displayName).toList(),
      minimumScore: 0.5,
    );
    if (match == null) return null;
    return sorted[match.index].id;
  }

  Future<void> _loadCupidonDefaultFromProfile() async {
    try {
      final enabled = await ref
          .read(accountRepositoryProvider)
          .readCupidonEnabledByDefaultPreference();
      if (!mounted) return;
      setState(() => _inviteCupidonEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _loadContextAndMaybeJoin() async {
    if (!mounted) return;
    setState(() {
      _loadingContext = true;
      _error = null;
    });
    try {
      final ctx = await ref.read(tripsRepositoryProvider).getInviteJoinContext(
            tripId: widget.tripId,
            token: widget.token,
          );
      if (!mounted) return;
      setState(() {
        _context = ctx;
        _inviteFormStep = 0;
        _joinUsingCurrentProfile = false;
        _phoneVisibilityDraft = TripMemberPhoneVisibility.nobody;
        _placeholderSearchController.clear();
        if (ctx.requiresPlaceholderChoice && ctx.placeholders.isNotEmpty) {
          final sorted = _sortedPlaceholders(ctx);
          _suggestedPlaceholderId = _findSuggestedPlaceholderId(sorted);
          _selectedPlaceholderId = _suggestedPlaceholderId;
          _stayDraft = TripMemberStay.defaultForInviteContext(
            tripStartDate: ctx.tripStartDate,
            tripEndDate: ctx.tripEndDate,
          );
        } else {
          _suggestedPlaceholderId = null;
          _stayDraft = null;
        }
      });
      if (!ctx.requiresPlaceholderChoice) {
        await _join(placeholderMemberId: null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageForError(context, e);
      });
    } finally {
      if (mounted) {
        setState(() => _loadingContext = false);
      }
    }
  }

  Future<void> _join({
    String? placeholderMemberId,
    bool bypassPlaceholderChoice = false,
  }) async {
    if (_joining || _joined) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await ref.read(tripsRepositoryProvider).joinTripWithInvite(
            tripId: widget.tripId,
            token: widget.token,
            placeholderMemberId: placeholderMemberId,
            bypassPlaceholderChoice: bypassPlaceholderChoice,
          );
      if (!mounted) return;
      setState(() {
        _joined = true;
      });
      await _persistCupidonPreferenceForTrip();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.inviteJoinedTrip)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageForError(context, e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _joining = false;
        });
      }
    }
  }

  Future<void> _persistCupidonPreferenceForTrip() async {
    try {
      await ref.read(cupidonRepositoryProvider).setMyTripCupidonEnabled(
            tripId: widget.tripId,
            enabled: _inviteCupidonEnabled,
          );
    } catch (_) {}
  }

  void _continueFromNameStep() {
    final id = _selectedPlaceholderId?.trim();
    if (id == null || id.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context)!.inviteChooseTravelerError;
      });
      return;
    }
    setState(() {
      _error = null;
      _inviteFormStep = 1;
      _joinUsingCurrentProfile = false;
    });
  }

  void _continueWithCurrentProfile() {
    setState(() {
      _error = null;
      _inviteFormStep = 1;
      _joinUsingCurrentProfile = true;
    });
  }

  void _backToNameStep() {
    setState(() {
      _inviteFormStep = 0;
      _joinUsingCurrentProfile = false;
      _error = null;
    });
  }

  Future<void> _completeInviteWithDetails() async {
    final ctx = _context;
    final stay = _stayDraft;
    final id = _selectedPlaceholderId?.trim();
    if (ctx == null || stay == null) return;
    if (!_joinUsingCurrentProfile && (id == null || id.isEmpty)) return;

    if (!TripMemberStay.isChronological(stay)) {
      setState(() {
        _error = AppLocalizations.of(context)!.tripStayInvalidRange;
      });
      return;
    }
    if (!TripMemberStay.withinInviteDateBounds(
      stay: stay,
      tripStartDate: ctx.tripStartDate,
      tripEndDate: ctx.tripEndDate,
    )) {
      setState(() {
        _error = AppLocalizations.of(context)!.tripStayOutOfTripBounds;
      });
      return;
    }

    await _join(
      placeholderMemberId: _joinUsingCurrentProfile ? null : id,
      bypassPlaceholderChoice: _joinUsingCurrentProfile,
    );
    if (!_joined || !mounted) return;

    try {
      await ref.read(tripMemberProfileRepositoryProvider).upsertMyStay(
            tripId: widget.tripId,
            stay: stay,
          );
      final myPhoneNumber = ref.read(myPhoneNumberProvider).asData?.value;
      if (myPhoneNumber != null) {
        await ref.read(tripMemberProfileRepositoryProvider).setMyPhoneVisibility(
              tripId: widget.tripId,
              visibility: _phoneVisibilityDraft,
            );
      }
      await _persistCupidonPreferenceForTrip();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Voyage rejoint, mais préférences non enregistrées : '
              '${_messageForError(context, e)}',
            ),
          ),
        );
      }
    }
  }

  PreferredSizeWidget _buildAppBar() {
    final l10n = AppLocalizations.of(context)!;
    final showCancel = !_joined;
    final placeholderPick = _context?.requiresPlaceholderChoice == true &&
        !_loadingContext &&
        !_joining;
    return AppBar(
      title: Text(l10n.inviteTitle),
      actions: [
        if (showCancel && !placeholderPick)
          TextButton(
            onPressed: _loadingContext || _joining ? null : _goToTripsList,
            child: Text(l10n.commonCancel),
          ),
      ],
    );
  }

  Widget _buildPlaceholderChoiceLayout(String tripTitle) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = _context!;
    final myPhoneNumber = ref.watch(myPhoneNumberProvider).asData?.value;
    final sorted = _sortedPlaceholders(ctx);
    final filtered = _filteredPlaceholders(sorted);
    final stepTitle = _inviteFormStep == 0
        ? l10n.inviteJoinTripStepOne
        : l10n.inviteJoinTripStepTwo;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    stepTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (tripTitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '« $tripTitle »',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_inviteFormStep == 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.inviteChooseTravelerWarning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.inviteWhoAreYouInTrip,
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    NameListSearchTextField(
                      controller: _placeholderSearchController,
                      onChanged: (_) => _onPlaceholderSearchChanged(sorted),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                nameListSearchEmptyMessage(context),
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 4),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final option = filtered[index];
                                final accentIndex =
                                    sorted.indexWhere((e) => e.id == option.id);
                                return _placeholderChoiceTile(
                                  option: option,
                                  accentIndex:
                                      accentIndex >= 0 ? accentIndex : index,
                                  isSuggested:
                                      _suggestedPlaceholderId == option.id,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.inviteJoinWithCurrentProfileHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        onPressed: _joining ? null : _continueWithCurrentProfile,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: Text(l10n.inviteJoinWithCurrentProfileAction),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_stayDraft != null)
                              TripMemberStayOptionsEditor(
                                mode: TripMemberStayOptionsEditorMode.draft,
                                tripStartDate: ctx.tripStartDate,
                                tripEndDate: ctx.tripEndDate,
                                initialStay: _stayDraft!,
                                initialCupidonEnabled: _inviteCupidonEnabled,
                                initialPhoneVisibility:
                                    myPhoneNumber == null
                                        ? null
                                        : _phoneVisibilityDraft,
                                onDraftChanged: (draft) => setState(() {
                                  _stayDraft = draft.stay;
                                  _inviteCupidonEnabled = draft.cupidonEnabled;
                                  _phoneVisibilityDraft =
                                      draft.phoneVisibility ??
                                          TripMemberPhoneVisibility.nobody;
                                }),
                                cupidonTitle: l10n.cupidonEnableAction,
                                cupidonSubtitle: l10n.inviteCupidonSubtitle,
                                phoneVisibilityTitle:
                                    myPhoneNumber == null
                                        ? null
                                        : l10n.tripPhoneVisibilityTitle,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _joining ? null : _backToNameStep,
                        child: Text(l10n.inviteEditTravelerChoice),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _joining ? null : _goToTripsList,
                          child: Text(l10n.commonCancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed:
                              (_joining ||
                                      (_inviteFormStep == 0 &&
                                          (_selectedPlaceholderId == null ||
                                              _selectedPlaceholderId!
                                                  .trim()
                                                  .isEmpty)))
                                  ? null
                                  : (_inviteFormStep == 0
                                      ? _continueFromNameStep
                                      : _completeInviteWithDetails),
                          child: Text(
                            _inviteFormStep == 0
                                ? l10n.commonContinue
                                : l10n.commonConfirm,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasInvalidParams =
        widget.tripId.trim().isEmpty || widget.token.trim().isEmpty;
    if (hasInvalidParams) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.inviteTitle),
          actions: [
            TextButton(
              onPressed: _goToTripsList,
              child: Text(l10n.commonCancel),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.inviteInvalidLink,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _goToTripsList,
                  child: Text(l10n.inviteBackToTrips),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tripTitle = _context?.tripTitle.trim() ?? '';
    final tripHeadline = tripTitle.isEmpty
        ? l10n.inviteJoinThisTrip
        : l10n.inviteJoinTripWithTitle(tripTitle);

    final placeholderPick = _context != null &&
        _context!.requiresPlaceholderChoice &&
        !_loadingContext &&
        !_joining &&
        !_joined;

    final Widget bodyChild;
    if (placeholderPick) {
      bodyChild = _buildPlaceholderChoiceLayout(tripTitle);
    } else {
      bodyChild = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadingContext) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Text(
                    l10n.inviteChecking,
                    textAlign: TextAlign.center,
                  ),
                ] else if (_joining) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Text(
                    tripTitle.isEmpty
                        ? l10n.inviteJoiningInProgress
                        : l10n.inviteJoiningTripWithTitle(tripTitle),
                    textAlign: TextAlign.center,
                  ),
                ] else if (_joined) ...[
                  Icon(
                    Icons.check_circle,
                    color: context.planerzColors.success,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.inviteAccepted,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.inviteAcceptedSubtitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () =>
                        context.go('/trips/${widget.tripId}/overview'),
                    child: Text(l10n.inviteOpenTrip),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _goToTripsList,
                    child: Text(l10n.inviteSeeMyTrips),
                  ),
                ] else if (_context != null &&
                    !_context!.requiresPlaceholderChoice &&
                    !_joined) ...[
                  Text(
                    tripHeadline,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.inviteCouldNotFinalizeJoin,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _joining ? null : _goToTripsList,
                          child: Text(l10n.commonCancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _joining
                              ? null
                              : () => _join(placeholderMemberId: null),
                          child: Text(l10n.commonRetry),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Icon(
                    Icons.group_add_outlined,
                    size: 52,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.inviteJoinATrip,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.inviteOpenFailed,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loadingContext ? null : _goToTripsList,
                          child: Text(l10n.commonCancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed:
                              _loadingContext ? null : _loadContextAndMaybeJoin,
                          child: Text(l10n.commonRetry),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(child: bodyChild),
    );
  }
}
