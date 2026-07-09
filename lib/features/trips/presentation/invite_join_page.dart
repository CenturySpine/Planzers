import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/trips/data/invite_join_context.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/auth/data/display_name_length.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/trips/presentation/invite_join_widgets.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class InviteJoinPage extends ConsumerStatefulWidget {
  const InviteJoinPage({super.key, required this.tripId, required this.token});

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

  /// 0: choose name, 1: stay + options (only when [requiresParticipantChoice]).
  int _inviteFormStep = 0;
  bool _joinUsingCurrentProfile = false;
  String? _bypassParticipantName;
  bool _bypassUseProfileName = false;
  TripMemberStay? _stayDraft;
  TripMemberPhoneVisibility _phoneVisibilityDraft =
      TripMemberPhoneVisibility.nobody;
  bool _inviteCupidonEnabled = false;

  void _goToTripsList() {
    context.go('/trips');
  }

  bool _isBypassParticipantNameValid(String? name) =>
      isDisplayNameLengthValid(name ?? '');

  Future<String?> _loadMyProfileName() async {
    final snap = await ref
        .read(accountRepositoryProvider)
        .watchMyUserDocument()
        .first;
    return profileNameFromData(snap.data());
  }

  void _applyBypassNameChoice(
    TripParticipantNameDialogResult choice, {
    required String? profileName,
  }) {
    final displayName = resolveTripParticipantDisplayName(
      result: choice,
      profileName: profileName,
    );
    if (displayName == null) return;
    setState(() {
      _bypassParticipantName = displayName;
      _bypassUseProfileName = choice.useProfileName;
    });
  }

  /// Returns false if the user cancelled or the choice is invalid.
  Future<bool> _pickBypassParticipantName({
    String initialName = '',
    bool initialUseProfileName = false,
  }) async {
    final profileName = await _loadMyProfileName();
    if (!mounted) return false;

    final choice = await showDialog<TripParticipantNameDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => TripParticipantNameDialog(
        initialName: initialName,
        initialUseProfileName: initialUseProfileName,
        initialIsChild: false,
        isClaimed: true,
        profileName: profileName,
      ),
    );
    if (!mounted || choice == null) return false;

    _applyBypassNameChoice(choice, profileName: profileName);
    return _isBypassParticipantNameValid(_bypassParticipantName);
  }

  Future<void> _ensureBypassParticipantNameOnEntry() async {
    if (!_joinUsingCurrentProfile || !mounted) return;
    if (_isBypassParticipantNameValid(_bypassParticipantName)) return;

    final picked = await _pickBypassParticipantName();
    if (!mounted) return;
    if (!picked) {
      _goToTripsList();
    }
  }

  bool _canProceedFromCurrentStep() {
    if (_inviteFormStep == 0) {
      final id = _selectedPlaceholderId?.trim();
      return id != null && id.isNotEmpty;
    }
    if (_joinUsingCurrentProfile) {
      return _isBypassParticipantNameValid(_bypassParticipantName);
    }
    return true;
  }

  void _showJoinErrorSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String? _joinDisplayName(InviteJoinContext ctx) {
    if (_joinUsingCurrentProfile) {
      final name = _bypassParticipantName?.trim();
      return name != null && name.isNotEmpty ? name : null;
    }
    final id = _selectedPlaceholderId;
    if (id == null) return null;
    for (final option in ctx.participants) {
      if (option.id == id) return option.displayName;
    }
    return null;
  }

  String? _stepLabel(InviteJoinContext ctx) {
    if (!ctx.requiresParticipantChoice) return null;
    return AppLocalizations.of(
      context,
    )!.inviteJoinTripStepLabel(_inviteFormStep + 1, 2);
  }

  List<InviteJoinParticipantOption> _sortedPlaceholders(InviteJoinContext ctx) {
    final list = List<InviteJoinParticipantOption>.from(ctx.participants);
    list.sort(
      (a, b) => compareDisplayNamesForSort(a.displayName, b.displayName),
    );
    return list;
  }

  List<InviteJoinParticipantOption> _filteredPlaceholders(
    List<InviteJoinParticipantOption> sorted,
  ) {
    final q = _placeholderSearchController.text;
    return sorted
        .where((p) => displayNameMatchesNameSearch(p.displayName, q))
        .toList();
  }

  void _onPlaceholderSearchChanged(List<InviteJoinParticipantOption> sorted) {
    final filtered = _filteredPlaceholders(sorted);
    setState(() {
      final id = _selectedPlaceholderId;
      if (id != null && !filtered.any((p) => p.id == id)) {
        _selectedPlaceholderId = null;
      }
    });
  }

  Widget _placeholderChoiceTile({required InviteJoinParticipantOption option}) {
    final selected = _selectedPlaceholderId == option.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InviteJoinParticipantTile(
        displayName: option.displayName,
        selected: selected,
        enabled: !_joining,
        onTap: () => setState(() {
          _selectedPlaceholderId = option.id;
          final ctx = _context;
          if (ctx != null) {
            _stayDraft = _stayDraftForContext(ctx: ctx);
          }
        }),
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
        context.go('/sign-in?redirect=${Uri.encodeComponent(redirect)}');
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
    List<InviteJoinParticipantOption> sorted,
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

  TripMemberStay _stayDraftForContext({required InviteJoinContext ctx}) {
    return ctx.stayDraftForJoin(selectedParticipantId: _selectedPlaceholderId);
  }

  Future<void> _loadContextAndMaybeJoin() async {
    if (!mounted) return;
    setState(() {
      _loadingContext = true;
      _error = null;
    });
    try {
      final ctx = await ref
          .read(tripsRepositoryProvider)
          .getInviteJoinContext(tripId: widget.tripId, token: widget.token);
      if (!mounted) return;
      setState(() {
        _context = ctx;
        _phoneVisibilityDraft = TripMemberPhoneVisibility.nobody;
        _placeholderSearchController.clear();
        _joined = ctx.alreadyMember;
        if (ctx.requiresParticipantChoice && ctx.participants.isNotEmpty) {
          _inviteFormStep = 0;
          _joinUsingCurrentProfile = false;
          final sorted = _sortedPlaceholders(ctx);
          _suggestedPlaceholderId = _findSuggestedPlaceholderId(sorted);
          _selectedPlaceholderId = _suggestedPlaceholderId;
          _stayDraft = _stayDraftForContext(ctx: ctx);
        } else {
          _inviteFormStep = 1;
          _joinUsingCurrentProfile = true;
          _bypassParticipantName = null;
          _bypassUseProfileName = false;
          _suggestedPlaceholderId = null;
          _selectedPlaceholderId = null;
          _stayDraft = _stayDraftForContext(ctx: ctx);
        }
      });
      if (!ctx.alreadyMember && !ctx.requiresParticipantChoice) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_ensureBypassParticipantNameOnEntry());
        });
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

  Future<bool> _join({
    String? participantId,
    String? participantName,
    bool bypassParticipantChoice = false,
    bool useProfileName = false,
  }) async {
    if (_joining || _joined) return false;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(tripsRepositoryProvider)
          .joinTripWithInvite(
            tripId: widget.tripId,
            token: widget.token,
            participantId: participantId,
            participantName: participantName,
            bypassParticipantChoice: bypassParticipantChoice,
            useProfileName: useProfileName,
          );
      if (!mounted) return false;
      setState(() {
        _joined = true;
      });
      if (!result.alreadyMember) {
        await _persistCupidonPreferenceForTrip();
      }
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.inviteJoinedTrip)),
      );
      return !result.alreadyMember;
    } catch (e) {
      if (!mounted) return false;
      final message = _messageForError(context, e);
      setState(() {
        _error = message;
      });
      _showJoinErrorSnackBar(message);
      return false;
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
      await ref
          .read(cupidonRepositoryProvider)
          .setMyTripCupidonEnabled(
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

  Future<void> _continueWithCurrentProfile() async {
    final picked = await _pickBypassParticipantName();
    if (!mounted) return;
    if (!picked) return;

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
      _bypassParticipantName = null;
      _bypassUseProfileName = false;
      _error = null;
    });
  }

  Future<void> _completeInviteWithDetails() async {
    final ctx = _context;
    final stay = _stayDraft;
    final id = _selectedPlaceholderId?.trim();
    if (ctx == null || stay == null) return;
    if (!_joinUsingCurrentProfile && (id == null || id.isEmpty)) return;
    if (_joinUsingCurrentProfile &&
        !_isBypassParticipantNameValid(_bypassParticipantName)) {
      final message = AppLocalizations.of(
        context,
      )!.inviteBypassFirstNameRequired;
      setState(() => _error = message);
      _showJoinErrorSnackBar(message);
      return;
    }

    if (!ctx.isDayTrip) {
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
    }

    final joinedNow = await _join(
      participantId: _joinUsingCurrentProfile ? null : id,
      participantName: _joinUsingCurrentProfile
          ? _bypassParticipantName!.trim()
          : null,
      bypassParticipantChoice: _joinUsingCurrentProfile,
      useProfileName: _joinUsingCurrentProfile && _bypassUseProfileName,
    );
    if (!joinedNow || !mounted) return;

    try {
      final myParticipant = await ref
          .read(tripMembersRepositoryProvider)
          .watchMyParticipant(widget.tripId)
          .first;
      if (myParticipant != null) {
        final myPhoneNumber = ref.read(myPhoneNumberProvider).asData?.value;
        await ref
            .read(tripMembersRepositoryProvider)
            .updateParticipantProfile(
              tripId: widget.tripId,
              participantId: myParticipant.id,
              stay: ctx.isDayTrip ? null : stay,
              phoneVisibility: myPhoneNumber != null
                  ? _phoneVisibilityDraft
                  : null,
            );
      }
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
    final placeholderPick =
        _context != null && !_loadingContext && !_joining && !_joined;
    VoidCallback? onBack;
    if (placeholderPick &&
        _inviteFormStep == 1 &&
        (_context?.requiresParticipantChoice ?? false)) {
      onBack = _joining ? null : _backToNameStep;
    } else if (!_joined) {
      onBack = _loadingContext || _joining ? null : _goToTripsList;
    }

    return AppBar(
      backgroundColor: NeonPalette.scaffoldBackground,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 52,
      automaticallyImplyLeading: false,
      leading: onBack == null
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              color: NeonPalette.deep,
              onPressed: onBack,
            ),
      title: Text(
        l10n.inviteTitle,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: NeonPalette.deep,
        ),
      ),
    );
  }

  Widget _buildPlaceholderChoiceLayout(String tripTitle) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = _context!;
    final myPhoneNumber = ref.watch(myPhoneNumberProvider).asData?.value;
    final tripCupidonModeEnabled = ctx.cupidonModeEnabled;
    final sorted = _sortedPlaceholders(ctx);
    final filtered = _filteredPlaceholders(sorted);
    final joinName = _joinDisplayName(ctx);

    if (_inviteFormStep == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                InviteJoinHead(
                  title: l10n.inviteJoinTripHeadline,
                  tripName: tripTitle,
                  stepLabel: _stepLabel(ctx),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(
                    l10n.inviteChooseTravelerWarning,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      height: 1.45,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Text(
                    l10n.inviteWhoAreYouInTrip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: NeonPalette.deep,
                    ),
                  ),
                ),
                InviteJoinSearchField(
                  controller: _placeholderSearchController,
                  hintText: l10n.nameSearchLabel,
                  onChanged: (_) => _onPlaceholderSearchChanged(sorted),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            nameListSearchEmptyMessage(context),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              color: NeonPalette.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final option in filtered)
                              _placeholderChoiceTile(option: option),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                  child: Column(
                    children: [
                      Text(
                        l10n.inviteJoinProfileNotFoundShort,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                          color: NeonPalette.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _joining
                            ? null
                            : _continueWithCurrentProfile,
                        style: TextButton.styleFrom(
                          foregroundColor: NeonPalette.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(
                          Icons.person_add_alt_1_outlined,
                          size: 20,
                        ),
                        label: Text(
                          l10n.inviteJoinWithCurrentProfileAction,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: NeonPalette.error),
                    ),
                  ),
              ],
            ),
          ),
          InviteJoinDualCtaBar(
            secondaryLabel: l10n.commonCancel,
            primaryLabel: l10n.commonContinue,
            secondaryEnabled: !_joining,
            primaryEnabled: !_joining && _canProceedFromCurrentStep(),
            onSecondary: _goToTripsList,
            onPrimary: _continueFromNameStep,
            primaryIcon: Icons.arrow_forward,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              InviteJoinHead(
                title: l10n.inviteJoinThisTrip,
                tripName: tripTitle,
                stepLabel: ctx.requiresParticipantChoice
                    ? _stepLabel(ctx)
                    : null,
              ),
              InviteJoinInfoBanner(
                message: l10n.inviteOptionsEditableAfterJoinInfo,
              ),
              if (joinName != null) ...[
                TripNeonSectionHeader(
                  icon: Icons.person_outline,
                  label: l10n.inviteJoinNameSectionTitle,
                ),
                InviteJoinNameRow(
                  displayName: joinName,
                  editLabel: _joinUsingCurrentProfile
                      ? l10n.inviteBypassChangeName
                      : null,
                  onEdit: _joinUsingCurrentProfile
                      ? () async {
                          await _pickBypassParticipantName(
                            initialName: _bypassParticipantName ?? '',
                            initialUseProfileName: _bypassUseProfileName,
                          );
                        }
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              if (_stayDraft != null)
                TripMemberStayOptionsEditor(
                  mode: TripMemberStayOptionsEditorMode.draft,
                  tripStartDate: ctx.tripStartDate,
                  tripEndDate: ctx.tripEndDate,
                  showStayDates: !ctx.isDayTrip,
                  isCupidonModeEnabled: tripCupidonModeEnabled,
                  initialStay: _stayDraft!,
                  initialCupidonEnabled: _inviteCupidonEnabled,
                  initialPhoneVisibility: myPhoneNumber == null
                      ? null
                      : _phoneVisibilityDraft,
                  onDraftChanged: (draft) => setState(() {
                    _stayDraft = draft.stay;
                    _inviteCupidonEnabled = draft.cupidonEnabled;
                    _phoneVisibilityDraft =
                        draft.phoneVisibility ??
                        TripMemberPhoneVisibility.nobody;
                  }),
                  cupidonTitle: l10n.cupidonModeTitle,
                  phoneVisibilityTitle: l10n.tripPhoneVisibilityTitle,
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NeonPalette.error),
                  ),
                ),
            ],
          ),
        ),
        InviteJoinDualCtaBar(
          secondaryLabel: l10n.commonCancel,
          primaryLabel: l10n.commonConfirm,
          secondaryEnabled: !_joining,
          primaryEnabled: !_joining && _canProceedFromCurrentStep(),
          busy: _joining,
          onSecondary: _goToTripsList,
          onPrimary: _completeInviteWithDetails,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasInvalidParams =
        widget.tripId.trim().isEmpty || widget.token.trim().isEmpty;
    if (hasInvalidParams) {
      return Theme(
        data: Theme.of(
          context,
        ).copyWith(scaffoldBackgroundColor: NeonPalette.scaffoldBackground),
        child: Scaffold(
          backgroundColor: NeonPalette.scaffoldBackground,
          appBar: AppBar(
            backgroundColor: NeonPalette.scaffoldBackground,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: 52,
            title: Text(
              l10n.inviteTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: NeonPalette.deep,
              ),
            ),
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
                    style: const TextStyle(color: NeonPalette.text700),
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
        ),
      );
    }

    final tripTitle = _context?.tripTitle.trim() ?? '';
    final tripHeadline = tripTitle.isEmpty
        ? l10n.inviteJoinThisTrip
        : l10n.inviteJoinTripWithTitle(tripTitle);

    final placeholderPick =
        _context != null && !_loadingContext && !_joining && !_joined;

    final Widget bodyChild;
    if (placeholderPick) {
      bodyChild = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _buildPlaceholderChoiceLayout(tripTitle),
        ),
      );
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
                  InviteJoinLoadingStatus(message: l10n.inviteChecking),
                ] else if (_joining) ...[
                  InviteJoinLoadingStatus(
                    message: tripTitle.isEmpty
                        ? l10n.inviteJoiningInProgress
                        : l10n.inviteJoiningTripWithTitle(tripTitle),
                  ),
                ] else if (_joined) ...[
                  InviteJoinSuccessStatus(
                    title: l10n.inviteAccepted,
                    subtitle: l10n.inviteAcceptedSubtitle,
                    primaryLabel: l10n.inviteOpenTrip,
                    secondaryLabel: l10n.inviteSeeMyTrips,
                    onPrimary: () =>
                        context.go('/trips/${widget.tripId}/overview'),
                    onSecondary: _goToTripsList,
                  ),
                ] else if (_context != null &&
                    !_context!.requiresParticipantChoice &&
                    !_joined) ...[
                  Text(
                    tripHeadline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: NeonPalette.deep,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.inviteCouldNotFinalizeJoin,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: NeonPalette.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  InviteJoinDualCtaBar(
                    secondaryLabel: l10n.commonCancel,
                    primaryLabel: l10n.commonRetry,
                    secondaryEnabled: !_joining,
                    primaryEnabled: !_joining,
                    onSecondary: _goToTripsList,
                    onPrimary: () => _join(participantId: null),
                    primaryIcon: Icons.refresh,
                  ),
                ] else ...[
                  Icon(
                    Icons.group_add_outlined,
                    size: 52,
                    color: NeonPalette.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.inviteJoinATrip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: NeonPalette.deep,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.inviteOpenFailed,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: NeonPalette.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  InviteJoinDualCtaBar(
                    secondaryLabel: l10n.commonCancel,
                    primaryLabel: l10n.commonRetry,
                    secondaryEnabled: !_loadingContext,
                    primaryEnabled: !_loadingContext,
                    onSecondary: _goToTripsList,
                    onPrimary: _loadContextAndMaybeJoin,
                    primaryIcon: Icons.refresh,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Theme(
      data: Theme.of(
        context,
      ).copyWith(scaffoldBackgroundColor: NeonPalette.scaffoldBackground),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: _buildAppBar(),
        body: SafeArea(child: bodyChild),
      ),
    );
  }
}
