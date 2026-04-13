import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/app/theme/planzers_colors.dart';
import 'package:planzers/features/trips/data/invite_join_context.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';

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
  static String _messageForError(Object e) {
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return e.toString();
  }

  bool _loadingContext = true;
  bool _joining = false;
  String? _error;
  bool _joined = false;
  InviteJoinContext? _context;
  String? _selectedPlaceholderId;
  final TextEditingController _placeholderSearchController =
      TextEditingController();

  void _goToTripsList() {
    context.go('/trips');
  }

  List<Color> _joinOptionAccentColors(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pz = context.planzersColors;
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
      (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
    );
    return list;
  }

  List<InviteJoinPlaceholderOption> _filteredPlaceholders(
    List<InviteJoinPlaceholderOption> sorted,
  ) {
    final q = _placeholderSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return sorted;
    return sorted
        .where((p) => p.displayName.toLowerCase().contains(q))
        .toList();
  }

  void _onPlaceholderSearchChanged(
    List<InviteJoinPlaceholderOption> sorted,
  ) {
    final filtered = _filteredPlaceholders(sorted);
    setState(() {
      final id = _selectedPlaceholderId;
      if (id != null && !filtered.any((p) => p.id == id)) {
        _selectedPlaceholderId =
            filtered.isNotEmpty ? filtered.first.id : null;
      }
    });
  }

  Widget _placeholderChoiceTile({
    required InviteJoinPlaceholderOption option,
    required int accentIndex,
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
        path: '/invite',
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

    await _loadContextAndMaybeJoin();
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
        _placeholderSearchController.clear();
        if (ctx.requiresPlaceholderChoice && ctx.placeholders.isNotEmpty) {
          final sorted = _sortedPlaceholders(ctx);
          _selectedPlaceholderId = sorted.first.id;
        }
      });
      if (!ctx.requiresPlaceholderChoice) {
        await _join(placeholderMemberId: null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageForError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _loadingContext = false);
      }
    }
  }

  Future<void> _join({String? placeholderMemberId}) async {
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
          );
      if (!mounted) return;
      setState(() {
        _joined = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous avez rejoint le voyage')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageForError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _joining = false;
        });
      }
    }
  }

  Future<void> _confirmPlaceholderAndJoin() async {
    final ctx = _context;
    if (ctx == null || !ctx.requiresPlaceholderChoice) return;
    final id = _selectedPlaceholderId?.trim();
    if (id == null || id.isEmpty) {
      setState(() {
        _error = 'Choisis un voyageur sur la liste.';
      });
      return;
    }
    await _join(placeholderMemberId: id);
  }

  PreferredSizeWidget _buildAppBar() {
    final showCancel = !_joined;
    final placeholderPick = _context?.requiresPlaceholderChoice == true &&
        !_loadingContext &&
        !_joining;
    return AppBar(
      title: const Text('Invitation'),
      actions: [
        if (showCancel && !placeholderPick)
          TextButton(
            onPressed: _loadingContext || _joining ? null : _goToTripsList,
            child: const Text('Annuler'),
          ),
      ],
    );
  }

  Widget _buildPlaceholderChoiceLayout(String tripHeadline) {
    final ctx = _context!;
    final sorted = _sortedPlaceholders(ctx);
    final filtered = _filteredPlaceholders(sorted);

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
                    tripHeadline,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tu ne pourras faire ce choix qu’une seule fois pour ce voyage.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Qui es-tu dans ce voyage ?',
                    style: Theme.of(context).textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _placeholderSearchController,
                    decoration: InputDecoration(
                      labelText: 'Rechercher',
                      hintText: 'Filtrer par nom',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _placeholderSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Effacer',
                              onPressed: () {
                                _placeholderSearchController.clear();
                                _onPlaceholderSearchChanged(sorted);
                              },
                            )
                          : null,
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => _onPlaceholderSearchChanged(sorted),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun nom ne correspond.',
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
                                accentIndex: accentIndex >= 0 ? accentIndex : index,
                              );
                            },
                          ),
                  ),
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
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed:
                              _joining ? null : _confirmPlaceholderAndJoin,
                          child: const Text('Rejoindre le voyage'),
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
    final hasInvalidParams =
        widget.tripId.trim().isEmpty || widget.token.trim().isEmpty;
    if (hasInvalidParams) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Invitation'),
          actions: [
            TextButton(
              onPressed: _goToTripsList,
              child: const Text('Annuler'),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Lien d’invitation invalide.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _goToTripsList,
                  child: const Text('Retour aux voyages'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tripTitle = _context?.tripTitle.trim() ?? '';
    final tripHeadline = tripTitle.isEmpty
        ? 'Rejoindre ce voyage'
        : 'Rejoindre le voyage « $tripTitle »';

    final placeholderPick = _context != null &&
        _context!.requiresPlaceholderChoice &&
        !_loadingContext &&
        !_joining &&
        !_joined;

    final Widget bodyChild;
    if (placeholderPick) {
      bodyChild = _buildPlaceholderChoiceLayout(tripHeadline);
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
                  const Text(
                    'Vérification de l’invitation…',
                    textAlign: TextAlign.center,
                  ),
                ] else if (_joining) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Text(
                    tripTitle.isEmpty
                        ? 'Ajout au voyage en cours…'
                        : 'Ajout au voyage « $tripTitle » en cours…',
                    textAlign: TextAlign.center,
                  ),
                ] else if (_joined) ...[
                  Icon(
                    Icons.check_circle,
                    color: context.planzersColors.success,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Invitation acceptée',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tu fais partie du voyage. Les autres participants te verront avec ton compte.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () =>
                        context.go('/trips/${widget.tripId}/overview'),
                    child: const Text('Ouvrir le voyage'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _goToTripsList,
                    child: const Text('Voir mes voyages'),
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
                      'Nous n’avons pas pu finaliser ton entrée dans le voyage. '
                      'Vérifie ta connexion et réessaie, ou demande un nouveau lien à l’organisateur.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _joining
                                ? null
                                : () => _join(placeholderMemberId: null),
                            child: const Text('Réessayer'),
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
                      'Rejoindre un voyage',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Impossible d’ouvrir l’invitation pour le moment. '
                      'Vérifie ta connexion ou demande un nouveau lien à l’organisateur.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                            onPressed:
                                _loadingContext ? null : _goToTripsList,
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed:
                                _loadingContext ? null : _loadContextAndMaybeJoin,
                            child: const Text('Réessayer'),
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
