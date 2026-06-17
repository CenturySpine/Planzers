import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/auth/data/display_name_length.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/trip_create_creator_name_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_create_neon_palette.dart';
import 'package:planerz/features/trips/presentation/trip_date_range_picker_sheet.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_dialog.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripCreatePage extends ConsumerStatefulWidget {
  const TripCreatePage({super.key});

  static const String routePath = '/trips/new';

  @override
  ConsumerState<TripCreatePage> createState() => _TripCreatePageState();
}

class _TripCreatePageState extends ConsumerState<TripCreatePage> {
  late final TextEditingController _titleController;
  late final TextEditingController _destinationController;
  late final TextEditingController _descriptionController;
  late TripMemberStay _stay;
  DateTime? _singleDayDate;
  bool _isDayTrip = false;
  String? _profileName;
  String _customName = '';
  bool _useProfileName = false;
  String? _errorMessage;
  bool _saving = false;
  bool _isCoverBusy = false;
  Uint8List? _coverBytes;
  String? _coverExt;
  ImageProvider? _coverPreview;

  TripDateRangePickerStyle get _pickerStyle => TripDateRangePickerStyle(
        primary: TripCreateNeonPalette.primary,
        primarySoft: TripCreateNeonPalette.primarySoft,
        primaryTint: TripCreateNeonPalette.primaryTint,
        deep: TripCreateNeonPalette.deep,
        onSurfaceVariant: TripCreateNeonPalette.onSurfaceVariant,
        divider: TripCreateNeonPalette.divider,
        outline: TripCreateNeonPalette.outline,
        surface: TripCreateNeonPalette.surface,
        textSecondary: TripCreateNeonPalette.text700,
      );

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _destinationController = TextEditingController();
    _descriptionController = TextEditingController();
    _stay = TripMemberStay.defaultForNewTripEditor();
    _singleDayDate = DateUtils.dateOnly(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCreatorName());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _destinationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  TripParticipantNameDialogResult get _nameResult =>
      TripParticipantNameDialogResult(
        name: _customName,
        useProfileName: _useProfileName,
        isChild: false,
      );

  String? get _resolvedCreatorName => resolveTripParticipantDisplayName(
        result: _nameResult,
        profileName: _profileName,
      );

  bool get _isCreatorNameValid =>
      isDisplayNameLengthValid(_resolvedCreatorName ?? '');

  Future<void> _initCreatorName() async {
    _profileName = await _loadMyProfileName();
    if (!mounted) return;
    setState(() {
      if (isDisplayNameLengthValid(_profileName ?? '')) {
        _useProfileName = true;
      }
    });
  }

  Future<String?> _loadMyProfileName() async {
    final snap =
        await ref.read(accountRepositoryProvider).watchMyUserDocument().first;
    return profileNameFromData(snap.data());
  }

  Future<void> _pickCreatorName() async {
    _profileName ??= await _loadMyProfileName();
    if (!mounted) return;

    final choice = await showTripCreateCreatorNameDialog(
      context: context,
      initialCustomName: _customName,
      initialUseProfileName: _useProfileName,
      profileName: _profileName,
    );
    if (!mounted || choice == null) return;

    setState(() {
      _customName = choice.name;
      _useProfileName = choice.useProfileName;
      _errorMessage = null;
    });
  }

  Future<void> _pickCoverPhoto() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isCoverBusy || _saving) return;
    setState(() => _isCoverBusy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked == null || !mounted) return;

      final screenSize = MediaQuery.sizeOf(context);
      final webCropWidth =
          ((screenSize.width - 140).clamp(260.0, 900.0)).round();
      final webCropHeight =
          ((screenSize.height - 320).clamp(220.0, 700.0)).round();

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: l10n.tripOverviewCropBanner,
            toolbarColor: TripCreateNeonPalette.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: TripCreateNeonPalette.primary,
            dimmedLayerColor: Colors.black54,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
          ),
          IOSUiSettings(
            title: l10n.tripOverviewCropBanner,
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
          if (kIsWeb)
            WebUiSettings(
              context: context,
              presentStyle: WebPresentStyle.dialog,
              size: CropperSize(
                width: webCropWidth,
                height: webCropHeight,
              ),
            ),
        ],
      );
      if (cropped == null || !mounted) return;

      final bytes = await XFile(cropped.path).readAsBytes();
      final extMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(cropped.path);
      final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
      setState(() {
        _coverBytes = bytes;
        _coverExt = ext;
        _coverPreview = MemoryImage(bytes);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isCoverBusy = false);
    }
  }

  void _toggleDayTrip(bool enabled) {
    setState(() {
      _isDayTrip = enabled;
      _errorMessage = null;
      if (enabled) {
        final day = _singleDayDate ??
            TripMemberStay.parseDateKey(_stay.startDateKey) ??
            DateUtils.dateOnly(DateTime.now());
        _singleDayDate = day;
        _stay = _stay.copyWith(
          startDateKey: TripMemberStay.dateKeyFromDateTime(day),
          endDateKey: TripMemberStay.dateKeyFromDateTime(day),
        );
      } else {
        final start = TripMemberStay.parseDateKey(_stay.startDateKey) ??
            DateUtils.dateOnly(DateTime.now());
        var end = TripMemberStay.parseDateKey(_stay.endDateKey) ?? start;
        if (!end.isAfter(start)) {
          end = start.add(const Duration(days: 1));
        }
        _stay = _stay.copyWith(
          startDateKey: TripMemberStay.dateKeyFromDateTime(start),
          endDateKey: TripMemberStay.dateKeyFromDateTime(end),
        );
      }
    });
  }

  Future<void> _openDatePicker() async {
    if (_saving) return;
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1);
    final lastDate = DateTime(now.year + 2, 12, 31);

    if (_isDayTrip) {
      final initial = _singleDayDate ?? DateUtils.dateOnly(now);
      final result = await showTripDateRangePickerSheet(
        context: context,
        style: _pickerStyle,
        initialStart: initial,
        initialEnd: initial,
        single: true,
        firstDate: firstDate,
        lastDate: lastDate,
      );
      if (!mounted || result == null) return;
      setState(() {
        _singleDayDate = result.start;
        _errorMessage = null;
      });
      return;
    }

    final start = TripMemberStay.parseDateKey(_stay.startDateKey) ??
        DateUtils.dateOnly(now);
    final end = TripMemberStay.parseDateKey(_stay.endDateKey) ?? start;
    final result = await showTripDateRangePickerSheet(
      context: context,
      style: _pickerStyle,
      initialStart: start,
      initialEnd: end,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (!mounted || result == null) return;
    setState(() {
      _stay = _stay.copyWith(
        startDateKey: TripMemberStay.dateKeyFromDateTime(result.start),
        endDateKey: TripMemberStay.dateKeyFromDateTime(result.end),
      );
      _errorMessage = null;
    });
  }

  String _shortDateLabel(DateTime date) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('EEE d MMM', locale).format(date);
  }

  int _nightCount() {
    final start = TripMemberStay.parseDateKey(_stay.startDateKey);
    final end = TripMemberStay.parseDateKey(_stay.endDateKey);
    if (start == null || end == null) return 0;
    return end.difference(start).inDays;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final title = _titleController.text.trim();
    final destination = _destinationController.text.trim();
    final description = _descriptionController.text.trim();

    if (!_isCreatorNameValid) {
      await _pickCreatorName();
      if (!mounted) return;
    }
    final creatorName = _resolvedCreatorName?.trim() ?? '';

    if (_isDayTrip) {
      if (title.isEmpty || !_isCreatorNameValid) {
        setState(() => _errorMessage = l10n.tripsCreateValidationRequiredDayTrip);
        return;
      }
    } else {
      if (title.isEmpty || destination.isEmpty || !_isCreatorNameValid) {
        setState(() => _errorMessage = l10n.tripsCreateValidationRequired);
        return;
      }

      if (!TripMemberStay.isChronological(_stay)) {
        setState(() => _errorMessage = l10n.tripStayInvalidRange);
        return;
      }
    }

    DateTime? startDate;
    DateTime? endDate;
    if (_isDayTrip) {
      startDate = _singleDayDate;
      endDate = _singleDayDate;
    } else {
      startDate = TripMemberStay.parseDateKey(_stay.startDateKey);
      endDate = TripMemberStay.parseDateKey(_stay.endDateKey);
      if (startDate == null || endDate == null) {
        setState(() => _errorMessage = l10n.tripStayInvalidRange);
        return;
      }
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final tripId = await ref.read(tripsRepositoryProvider).createTrip(
            title: title,
            destination: _isDayTrip ? '' : destination,
            description: description,
            creatorName: creatorName,
            useProfileName: _useProfileName,
            startDate: startDate,
            endDate: endDate,
            tripStartDayPart: _isDayTrip ? null : _stay.startDayPart,
            tripEndDayPart: _isDayTrip ? null : _stay.endDayPart,
            isDayTrip: _isDayTrip,
          );

      if (_coverBytes != null && _coverExt != null) {
        await ref.read(tripsRepositoryProvider).upsertTripBannerImage(
              tripId: tripId,
              bytes: _coverBytes!,
              fileExt: _coverExt!,
            );
      }

      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: TripCreateNeonPalette.scaffoldBackground,
        splashColor: TripCreateNeonPalette.primary.withValues(alpha: 0.08),
        highlightColor: TripCreateNeonPalette.primary.withValues(alpha: 0.05),
      ),
      child: Scaffold(
        backgroundColor: TripCreateNeonPalette.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: TripCreateNeonPalette.scaffoldBackground,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 52,
          leading: IconButton(
            icon: const Icon(Icons.close),
            color: TripCreateNeonPalette.deep,
            onPressed: _saving ? null : () => context.pop(),
          ),
          title: Text(
            l10n.tripsCreateDialogTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: TripCreateNeonPalette.deep,
            ),
          ),
          centerTitle: false,
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  _CoverPhotoPicker(
                    preview: _coverPreview,
                    busy: _isCoverBusy,
                    onTap: _pickCoverPhoto,
                  ),
                  _FormSection(
                    child: _DayTripToggleCard(
                      value: _isDayTrip,
                      enabled: !_saving,
                      onChanged: _toggleDayTrip,
                    ),
                  ),
                  _FormSection(
                    child: _TripCreateLabel(
                      label: l10n.tripsTitleLabel,
                      required: true,
                      child: _TripCreateInputShell(
                        icon: Icons.luggage_outlined,
                        enabled: !_saving,
                        builder: (focusNode) => TextField(
                          controller: _titleController,
                          focusNode: focusNode,
                          enabled: !_saving,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(
                            fontSize: 15,
                            color: TripCreateNeonPalette.deep,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.tripCreateTitlePlaceholder,
                            hintStyle: const TextStyle(
                              color: TripCreateNeonPalette.outline,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  if (!_isDayTrip) ...[
                    _FormSection(
                      child: _TripCreateLabel(
                        label: l10n.tripsDestinationLabel,
                        child: _TripCreateInputShell(
                          icon: Icons.location_on_outlined,
                          enabled: !_saving,
                          builder: (focusNode) => TextField(
                            controller: _destinationController,
                            focusNode: focusNode,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(
                              fontSize: 15,
                              color: TripCreateNeonPalette.deep,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.tripCreateDestinationPlaceholder,
                              hintStyle: const TextStyle(
                                color: TripCreateNeonPalette.outline,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (_) {
                              if (_errorMessage != null) {
                                setState(() => _errorMessage = null);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_isDayTrip)
                    _FormSection(
                      child: _TripCreateLabel(
                        label: l10n.tripCreateDateLabel,
                        required: true,
                        child: _TripCreateDateCard(
                          kicker: l10n.tripCreateSingleDayFieldLabel,
                          kickerIcon: Icons.event_outlined,
                          value: _singleDayDate != null
                              ? _shortDateLabel(_singleDayDate!)
                              : l10n.commonNotProvided,
                          onTap: _openDatePicker,
                        ),
                      ),
                    )
                  else
                    _FormSection(
                      child: _TripCreateLabel(
                        label: l10n.tripCreateDatesLabel,
                        required: true,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _TripCreateDateCard(
                                    kicker: l10n.tripCreateDateStartLabel,
                                    kickerIcon: Icons.flight_takeoff,
                                    value: _shortDateLabel(
                                      TripMemberStay.parseDateKey(
                                            _stay.startDateKey,
                                          ) ??
                                          DateTime.now(),
                                    ),
                                    onTap: _openDatePicker,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TripCreateDateCard(
                                    kicker: l10n.tripCreateDateEndLabel,
                                    kickerIcon: Icons.flight_land,
                                    value: _shortDateLabel(
                                      TripMemberStay.parseDateKey(
                                            _stay.endDateKey,
                                          ) ??
                                          DateTime.now(),
                                    ),
                                    onTap: _openDatePicker,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.tripCreateNightsDays(
                                _nightCount(),
                                _nightCount() + 1,
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: TripCreateNeonPalette.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_isDayTrip) ...[
                    _FormSection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.tripCreateMealsSectionLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: TripCreateNeonPalette.text700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.tripCreateMealsHint,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: TripCreateNeonPalette.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _MealBoundCard(
                            dayLabel: l10n.tripCreateArrivalMealDay(
                              _shortDateLabel(
                                TripMemberStay.parseDateKey(
                                      _stay.startDateKey,
                                    ) ??
                                    DateTime.now(),
                              ),
                            ),
                            dayIcon: Icons.flight_takeoff,
                            question: l10n.tripCreateFirstMealQuestion,
                            selected: _stay.startDayPart,
                            onSelected: (part) {
                              setState(() {
                                _stay = _stay.copyWith(startDayPart: part);
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          _MealBoundCard(
                            dayLabel: l10n.tripCreateDepartureMealDay(
                              _shortDateLabel(
                                TripMemberStay.parseDateKey(_stay.endDateKey) ??
                                    DateTime.now(),
                              ),
                            ),
                            dayIcon: Icons.flight_land,
                            question: l10n.tripCreateLastMealQuestion,
                            selected: _stay.endDayPart,
                            onSelected: (part) {
                              setState(() {
                                _stay = _stay.copyWith(endDayPart: part);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  _FormSection(
                    child: _TripCreateLabel(
                      label: l10n.tripsCreateCreatorNameLabel,
                      child: TripCreateCreatorNameField(
                        displayName: _resolvedCreatorName,
                        useProfileName: _useProfileName,
                        enabled: !_saving,
                        onTap: _pickCreatorName,
                      ),
                    ),
                  ),
                  _FormSection(
                    child: _TripCreateLabel(
                      label: l10n.tripCreateDescriptionLabel,
                      child: _TripCreateInputShell(
                        multiline: true,
                        enabled: !_saving,
                        builder: (focusNode) => TextField(
                          controller: _descriptionController,
                          focusNode: focusNode,
                          enabled: !_saving,
                          minLines: 3,
                          maxLines: 6,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: TripCreateNeonPalette.deep,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.tripCreateDescriptionPlaceholder,
                            hintStyle: const TextStyle(
                              color: TripCreateNeonPalette.outline,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _CreateTripCtaBar(
              saving: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: child,
    );
  }
}

class _TripCreateLabel extends StatelessWidget {
  const _TripCreateLabel({
    required this.label,
    required this.child,
    this.required = false,
  });

  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text.rich(
            TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: TripCreateNeonPalette.text700,
                letterSpacing: 0.2,
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: '*',
                    style: TextStyle(color: TripCreateNeonPalette.accent),
                  ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _TripCreateInputShell extends StatefulWidget {
  const _TripCreateInputShell({
    this.icon,
    required this.builder,
    this.multiline = false,
    this.enabled = true,
  });

  final IconData? icon;
  final Widget Function(FocusNode focusNode) builder;
  final bool multiline;
  final bool enabled;

  @override
  State<_TripCreateInputShell> createState() => _TripCreateInputShellState();
}

class _TripCreateInputShellState extends State<_TripCreateInputShell> {
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.fromLTRB(
        14,
        widget.multiline ? 14 : 0,
        14,
        widget.multiline ? 14 : 0,
      ),
      constraints: BoxConstraints(
        minHeight: widget.multiline ? 64 : 52,
      ),
      alignment: widget.multiline ? Alignment.topLeft : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: TripCreateNeonPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused
              ? TripCreateNeonPalette.primary
              : TripCreateNeonPalette.divider,
          width: focused ? 2 : 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment:
            widget.multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: widget.multiline ? 2 : 0),
              child: Icon(
                widget.icon,
                size: 20,
                color: focused
                    ? TripCreateNeonPalette.primary
                    : TripCreateNeonPalette.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(child: widget.builder(_focusNode)),
        ],
      ),
    );
  }
}

class _CoverPhotoPicker extends StatelessWidget {
  const _CoverPhotoPicker({
    required this.preview,
    required this.busy,
    required this.onTap,
  });

  final ImageProvider? preview;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: preview == null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: TripCreateNeonPalette.coverGradient,
                    )
                  : null,
              image: preview != null
                  ? DecorationImage(image: preview!, fit: BoxFit.cover)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (preview != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black.withValues(alpha: 0.28),
                    ),
                    child: const SizedBox.expand(),
                  ),
                if (busy)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        child: const SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.tripCreateCoverPhotoLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        l10n.tripCreateCoverPhotoOptional,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayTripToggleCard extends StatelessWidget {
  const _DayTripToggleCard({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: value
          ? TripCreateNeonPalette.dayTripBackgroundActive
          : TripCreateNeonPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: value
              ? TripCreateNeonPalette.dayTripBorderActive
              : TripCreateNeonPalette.divider,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: value
                      ? TripCreateNeonPalette.dayTripIconBackgroundActive
                      : TripCreateNeonPalette.dayTripIconBackgroundRest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.wb_sunny_outlined,
                    size: 20,
                    color: value
                        ? TripCreateNeonPalette.primary
                        : TripCreateNeonPalette.dayTripIconColorRest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tripDayTripLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: TripCreateNeonPalette.deep,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.tripCreateDayTripSubtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: TripCreateNeonPalette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _NeonSwitch(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeonSwitch extends StatelessWidget {
  const _NeonSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: value
                ? TripCreateNeonPalette.primary
                : TripCreateNeonPalette.divider,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
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

class _TripCreateDateCard extends StatelessWidget {
  const _TripCreateDateCard({
    required this.kicker,
    required this.kickerIcon,
    required this.value,
    required this.onTap,
  });

  final String kicker;
  final IconData kickerIcon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TripCreateNeonPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: TripCreateNeonPalette.dateBorderSet,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    kickerIcon,
                    size: 14,
                    color: TripCreateNeonPalette.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    kicker,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: TripCreateNeonPalette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: TripCreateNeonPalette.deep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MealBoundCard extends StatelessWidget {
  const _MealBoundCard({
    required this.dayLabel,
    required this.dayIcon,
    required this.question,
    required this.selected,
    required this.onSelected,
  });

  final String dayLabel;
  final IconData dayIcon;
  final String question;
  final TripDayPart selected;
  final ValueChanged<TripDayPart> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = <(TripDayPart, String, IconData, IconData)>[
      (
        TripDayPart.morning,
        l10n.tripCreateMealBreakfast,
        Icons.bakery_dining_outlined,
        Icons.bakery_dining,
      ),
      (
        TripDayPart.midday,
        l10n.tripCreateMealLunch,
        Icons.lunch_dining_outlined,
        Icons.lunch_dining,
      ),
      (
        TripDayPart.evening,
        l10n.tripCreateMealDinner,
        Icons.dinner_dining_outlined,
        Icons.dinner_dining,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: TripCreateNeonPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: TripCreateNeonPalette.divider,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(dayIcon, size: 16, color: TripCreateNeonPalette.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dayLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: TripCreateNeonPalette.deep,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2, bottom: 10),
              child: Text(
                question,
                style: const TextStyle(
                  fontSize: 12,
                  color: TripCreateNeonPalette.onSurfaceVariant,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: TripCreateNeonPalette.segmentTrack,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    for (final option in options)
                      Expanded(
                        child: _MealSegmentOption(
                          label: option.$2,
                          icon: selected == option.$1 ? option.$4 : option.$3,
                          selected: selected == option.$1,
                          onTap: () => onSelected(option.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealSegmentOption extends StatelessWidget {
  const _MealSegmentOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? TripCreateNeonPalette.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      elevation: selected ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? TripCreateNeonPalette.primary
                    : TripCreateNeonPalette.onSurfaceVariant,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: selected
                      ? TripCreateNeonPalette.primary
                      : TripCreateNeonPalette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateTripCtaBar extends StatelessWidget {
  const _CreateTripCtaBar({
    required this.saving,
    required this.onPressed,
  });

  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TripCreateNeonPalette.scaffoldBackground,
        border: Border(top: BorderSide(color: TripCreateNeonPalette.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: saving ? null : [TripCreateNeonPalette.ctaShadow],
            ),
            child: FilledButton.icon(
              onPressed: saving ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: TripCreateNeonPalette.primary,
                disabledBackgroundColor:
                    TripCreateNeonPalette.primary.withValues(alpha: 0.5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 20),
              label: Text(
                l10n.tripsCreateAction,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
