import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/carpool/data/trip_carpool.dart';
import 'package:planerz/features/carpool/data/trip_carpools_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_placeholder_member.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripCarpoolFormPage extends ConsumerStatefulWidget {
  const TripCarpoolFormPage({
    super.key,
    this.initialCarpool,
    this.startReadOnly = false,
  });

  final TripCarpool? initialCarpool;
  final bool startReadOnly;

  @override
  ConsumerState<TripCarpoolFormPage> createState() => _TripCarpoolFormPageState();
}

class _TripCarpoolFormPageState extends ConsumerState<TripCarpoolFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _meetingController;
  late final TextEditingController _transitController;
  late final TextEditingController _seatsController;
  DateTime? _departureAt;
  String? _driverUserId;
  final Set<String> _selectedParticipantIds = <String>{};
  bool _goesShopping = false;
  bool _saving = false;
  String? _defaultDriverUserId;
  bool _didInitDepartureFromTrip = false;
  bool _isReadOnly = false;

  bool get _isEdit => widget.initialCarpool != null;

  @override
  void initState() {
    super.initState();
    final currentUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final initial = widget.initialCarpool;
    _meetingController = TextEditingController(
      text: initial?.meetingPointAddress ?? '',
    );
    _transitController = TextEditingController(
      text: initial?.nearestTransitStop ?? '',
    );
    _seatsController = TextEditingController(
      text: (initial?.availableSeats ?? 4).toString(),
    );
    _departureAt = initial?.departureAt;
    _driverUserId = (initial?.driverUserId.trim().isNotEmpty == true)
        ? initial!.driverUserId.trim()
        : (currentUid.isNotEmpty ? currentUid : null);
    _defaultDriverUserId = _driverUserId;
    _selectedParticipantIds.addAll(initial?.assignedParticipantIds ?? const <String>[]);
    if (_driverUserId != null && _driverUserId!.isNotEmpty) {
      _selectedParticipantIds.add(_driverUserId!);
    }
    _goesShopping = initial?.goesShopping ?? false;
    _isReadOnly = _isEdit && widget.startReadOnly;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitDepartureFromTrip || _isEdit) return;
    final tripStart = TripScope.of(context).startDate;
    if (tripStart != null) {
      _departureAt = DateTime(tripStart.year, tripStart.month, tripStart.day, 18, 30);
    } else if (_departureAt == null) {
      final now = DateTime.now();
      _departureAt = DateTime(now.year, now.month, now.day, 18, 30);
    }
    _didInitDepartureFromTrip = true;
  }

  @override
  void dispose() {
    _meetingController.dispose();
    _transitController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  Future<void> _pickDepartureDateTime(BuildContext context) async {
    final base = _departureAt ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: AppLocalizations.of(context)!.commonDate,
    );
    if (pickedDate == null || !context.mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: AppLocalizations.of(context)!.tripCarpoolDepartureAtLabel,
    );
    if (pickedTime == null || !context.mounted) return;
    setState(() {
      _departureAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _save({
    required String tripId,
    required String myUid,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final departureAt = _departureAt;
    final driverUserId = _driverUserId?.trim() ?? '';
    if (departureAt == null || driverUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonRequired)),
      );
      return;
    }
    final seats = int.tryParse(_seatsController.text.trim()) ?? 0;
    if (seats < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripCarpoolSeatsInvalid)),
      );
      return;
    }
    final assignedIds = <String>{
      ..._selectedParticipantIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
      driverUserId,
    }.toList(growable: false);
    if (assignedIds.length > seats) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripCarpoolSeatsExceeded)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(tripCarpoolsRepositoryProvider).upsertTripCarpool(
            tripId: tripId,
            carpoolId: widget.initialCarpool?.id,
            driverUserId: driverUserId,
            meetingPointAddress: _meetingController.text,
            nearestTransitStop: _transitController.text,
            departureAt: departureAt,
            availableSeats: seats,
            assignedParticipantIds: assignedIds,
            goesShopping: _goesShopping,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? l10n.tripCarpoolUpdated : l10n.tripCarpoolCreated,
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteCarpool(String tripId) async {
    final l10n = AppLocalizations.of(context)!;
    final carpool = widget.initialCarpool;
    if (carpool == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tripCarpoolDeleteTitle),
        content: Text(l10n.tripCarpoolDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(tripCarpoolsRepositoryProvider).deleteTripCarpool(
            tripId: tripId,
            carpoolId: carpool.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripCarpoolDeleted)),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final carpoolsAsync = ref.watch(tripCarpoolsStreamProvider(trip.id));
    final canManageCarpoolData = _isEdit
        ? canManageCarpool(
            trip: trip,
            userId: myUid,
            carpoolCreatedByUserId: widget.initialCarpool?.createdByUserId,
          )
        : canProposeCarpoolForTrip(trip: trip, userId: myUid);
    final canAssign = _isEdit
        ? canAssignPassengersForCarpool(
            trip: trip,
            userId: myUid,
            carpoolCreatedByUserId: widget.initialCarpool?.createdByUserId,
          )
        : canManageCarpoolData;
    final canToggleShopping = _isEdit
        ? canMarkCarpoolGoesShopping(
            trip: trip,
            userId: myUid,
            carpoolCreatedByUserId: widget.initialCarpool?.createdByUserId,
          )
        : canManageCarpoolData;
    final canChangeDriver = canManageCarpoolData;
    final canEditExistingCarpool = _isEdit && canManageCarpoolData;
    final canUseEditControls = canManageCarpoolData && (!_isEdit || !_isReadOnly);

    final labelUserIds = <String>{
      for (final id in trip.memberIds)
        if (id.trim().isNotEmpty) id.trim(),
    }.toList(growable: false);
    final usersIdsKey = stableUsersIdsKey(labelUserIds);
    final usersAsync = ref.watch(usersDataByIdsKeyStreamProvider(usersIdsKey));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit ? l10n.tripCarpoolEditTitle : l10n.tripCarpoolCreateTitle,
        ),
        actions: [
          if (canEditExistingCarpool && _isReadOnly)
            IconButton(
              tooltip: l10n.commonEdit,
              onPressed: () => setState(() => _isReadOnly = false),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (canUseEditControls)
            IconButton(
              tooltip: l10n.commonSave,
              onPressed: !_saving ? () => _save(tripId: trip.id, myUid: myUid) : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
            ),
        ],
      ),
      body: usersAsync.when(
        data: (userDocs) {
          final memberLabels = tripMemberLabelsFromUserDocsById(
            userDocs,
            labelUserIds,
            tripMemberPublicLabels: trip.memberPublicLabels,
            currentUserId: myUid,
            emptyFallback: l10n.tripParticipantsTraveler,
          );
          final memberIds = trip.memberIds
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList(growable: false);
          final driverValue = _driverUserId?.trim();
          if (driverValue == null || !memberIds.contains(driverValue)) {
            if (memberIds.isNotEmpty) {
              _driverUserId = memberIds.first;
              _selectedParticipantIds.add(_driverUserId!);
            }
          }

          return carpoolsAsync.when(
            data: (carpools) {
              final assignmentByParticipant = <String, TripCarpool>{};
              for (final carpool in carpools) {
                if (_isEdit && carpool.id == widget.initialCarpool?.id) continue;
                for (final participantId in carpool.assignedParticipantIds) {
                  assignmentByParticipant[participantId] = carpool;
                }
              }
              final sortedParticipantIds = [...memberIds]
                ..sort((left, right) {
                  final leftAssigned = assignmentByParticipant.containsKey(left);
                  final rightAssigned = assignmentByParticipant.containsKey(right);
                  if (leftAssigned != rightAssigned) {
                    return leftAssigned ? 1 : -1;
                  }
                  final leftLabel = memberLabels[left] ?? l10n.tripParticipantsTraveler;
                  final rightLabel = memberLabels[right] ?? l10n.tripParticipantsTraveler;
                  return leftLabel.toLowerCase().compareTo(rightLabel.toLowerCase());
                });

              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    TextFormField(
                      controller: _meetingController,
                      readOnly: !canUseEditControls,
                      decoration: InputDecoration(
                        labelText: l10n.tripCarpoolMeetingPointLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _transitController,
                      readOnly: !canUseEditControls,
                      decoration: InputDecoration(
                        labelText: l10n.tripCarpoolNearestTransitStopLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: canUseEditControls
                          ? () => _pickDepartureDateTime(context)
                          : null,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.tripCarpoolDepartureAtLabel,
                          border: const OutlineInputBorder(),
                        ),
                        child: Text(
                          _departureAt == null
                              ? l10n.commonNotProvided
                              : '${MaterialLocalizations.of(context).formatMediumDate(_departureAt!)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_departureAt!), alwaysUse24HourFormat: true)}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownMenu<String>(
                      width: double.infinity,
                      initialSelection: _driverUserId,
                      enableSearch: true,
                      enableFilter: true,
                      label: Text(l10n.tripCarpoolDriverLabel),
                      dropdownMenuEntries: memberIds
                          .map(
                            (id) => DropdownMenuEntry<String>(
                              value: id,
                              label: memberLabels[id] ?? l10n.tripParticipantsTraveler,
                            ),
                          )
                          .toList(growable: false),
                      onSelected: canChangeDriver
                          && canUseEditControls
                          ? (value) {
                              if (value == null || value.trim().isEmpty) return;
                              setState(() {
                                final previousDriverId = _driverUserId?.trim() ?? '';
                                _driverUserId = value.trim();
                                if (previousDriverId.isNotEmpty &&
                                    previousDriverId != _driverUserId) {
                                  _selectedParticipantIds.remove(previousDriverId);
                                  if (_defaultDriverUserId == previousDriverId) {
                                    _defaultDriverUserId = null;
                                  }
                                }
                                _selectedParticipantIds.add(_driverUserId!);
                              });
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _seatsController,
                      readOnly: !canUseEditControls,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.tripCarpoolAvailableSeatsLabel,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final seats = int.tryParse((value ?? '').trim()) ?? 0;
                        if (seats < 1) return l10n.tripCarpoolSeatsInvalid;
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: _goesShopping,
                      onChanged: canToggleShopping && canUseEditControls
                          ? (value) => setState(() => _goesShopping = value)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.tripCarpoolGoesShoppingLabel),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.tripCarpoolPassengersTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final memberId in sortedParticipantIds)
                            CheckboxListTile(
                              value: _selectedParticipantIds.contains(memberId),
                              onChanged: canAssign && canUseEditControls
                                  ? (checked) {
                                      final seats = int.tryParse(
                                            _seatsController.text.trim(),
                                          ) ??
                                          0;
                                      final driverUserId = _driverUserId?.trim() ?? '';
                                      if (memberId == driverUserId && checked != true) {
                                        return;
                                      }
                                      if (checked == true &&
                                          !_selectedParticipantIds.contains(memberId) &&
                                          seats > 0 &&
                                          _selectedParticipantIds.length >= seats) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(l10n.tripCarpoolSeatsExceeded),
                                          ),
                                        );
                                        return;
                                      }
                                      setState(() {
                                        if (checked == true) {
                                          _selectedParticipantIds.add(memberId);
                                        } else {
                                          _selectedParticipantIds.remove(memberId);
                                        }
                                        if (driverUserId.isNotEmpty) {
                                          _selectedParticipantIds.add(driverUserId);
                                        }
                                      });
                                    }
                                  : null,
                              title: Text(
                                memberLabels[memberId] ?? l10n.tripParticipantsTraveler,
                              ),
                              subtitle: () {
                                final assignment = assignmentByParticipant[memberId];
                                if (assignment != null) {
                                  final assignmentDriver = memberLabels[assignment.driverUserId] ??
                                      l10n.tripParticipantsTraveler;
                                  return Text(
                                    l10n.tripCarpoolAlreadyAssignedTo(assignmentDriver),
                                  );
                                }
                                if (isTripPlaceholderMemberId(memberId)) {
                                  return Text(l10n.tripCarpoolTemporaryParticipantLabel);
                                }
                                return null;
                              }(),
                            ),
                        ],
                      ),
                    ),
                    if (_isEdit && canUseEditControls) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _deleteCarpool(trip.id),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.commonDelete),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.commonErrorWithDetails(error.toString())),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.commonErrorWithDetails(error.toString())),
          ),
        ),
      ),
    );
  }
}
