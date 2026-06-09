import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_lifecycle_status.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/trip_entry_route.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripPreparationPage extends ConsumerStatefulWidget {
  const TripPreparationPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripPreparationPage> createState() =>
      _TripPreparationPageState();
}

class _TripPreparationPageState extends ConsumerState<TripPreparationPage> {
  bool _promoting = false;
  String? _errorMessage;

  Future<void> _promote() async {
    if (_promoting) return;
    setState(() {
      _promoting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(tripsRepositoryProvider).promoteTripToPlanned(
            tripId: widget.tripId,
          );
      if (!mounted) return;
      context.go(tripEntryPath(widget.tripId, TripLifecycleStatus.planned));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _promoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));

    return tripAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/trips'),
          ),
        ),
        body: Center(child: Text(error.toString())),
      ),
      data: (trip) {
        if (trip == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/trips');
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!trip.isInPreparation) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.go(tripEntryPath(widget.tripId, trip.lifecycleStatus));
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final titleForDisplay =
            trip.title.isEmpty ? l10n.tripLabelGeneric : trip.title;
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final currentRole = resolveTripPermissionRole(
          trip: trip,
          userId: myUid,
        );
        final canPromote = myUid != null &&
            trip.memberUserIds.contains(myUid) &&
            isTripRoleAllowed(
              currentRole: currentRole,
              minRole: trip.generalPermissions.editGeneralInfoMinRole,
            );

        return Scaffold(
          appBar: AppBar(
            title: Text(titleForDisplay),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/trips'),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  titleForDisplay,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (canPromote) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _promoting ? null : _promote,
                    child: _promoting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.tripPreparationPromoteAction),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
