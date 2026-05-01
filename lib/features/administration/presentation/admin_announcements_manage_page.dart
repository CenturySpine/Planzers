import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/core/presentation/linkified_text.dart';
import 'package:planerz/features/administration/data/global_announcements_repository.dart';
import 'package:planerz/features/administration/domain/admin_announcement.dart';

class AdminAnnouncementsManagePage extends ConsumerStatefulWidget {
  const AdminAnnouncementsManagePage({super.key});

  static const String routePath = '/administration/announcements';

  @override
  ConsumerState<AdminAnnouncementsManagePage> createState() =>
      _AdminAnnouncementsManagePageState();
}

class _AdminAnnouncementsManagePageState
    extends ConsumerState<AdminAnnouncementsManagePage> {
  final TextEditingController _textController = TextEditingController();
  bool _isSubmitting = false;
  final Set<String> _deletingAnnouncementIds = <String>{};
  String? _editingAnnouncementId;

  bool get _isEditing => _editingAnnouncementId != null;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _createAnnouncement() async {
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(globalAnnouncementsRepositoryProvider)
          .sendAnnouncement(_textController.text);
      if (!mounted) {
        return;
      }
      _textController.clear();
      _showSnackBar('Annonce publiée.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Erreur: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _updateAnnouncement() async {
    final announcementId = _editingAnnouncementId;
    if (_isSubmitting || announcementId == null) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(globalAnnouncementsRepositoryProvider)
          .updateAnnouncement(announcementId, _textController.text);
      if (!mounted) {
        return;
      }
      _textController.clear();
      _editingAnnouncementId = null;
      _showSnackBar('Annonce mise à jour.');
      setState(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Erreur: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _deleteAnnouncement(AdminAnnouncement announcement) async {
    if (_deletingAnnouncementIds.contains(announcement.id)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette annonce ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _deletingAnnouncementIds.add(announcement.id));
    try {
      await ref
          .read(globalAnnouncementsRepositoryProvider)
          .deleteAnnouncement(announcement.id);
      if (!mounted) {
        return;
      }
      if (_editingAnnouncementId == announcement.id) {
        _editingAnnouncementId = null;
        _textController.clear();
      }
      _showSnackBar('Annonce supprimée.');
      setState(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Erreur: $error');
    } finally {
      if (mounted) {
        setState(() => _deletingAnnouncementIds.remove(announcement.id));
      }
    }
  }

  void _startEditingAnnouncement(AdminAnnouncement announcement) {
    _editingAnnouncementId = announcement.id;
    _textController.text = announcement.text;
    setState(() {});
  }

  void _cancelEditing() {
    _editingAnnouncementId = null;
    _textController.clear();
    setState(() {});
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toString();
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm', localeTag);
    final announcementsAsync = ref.watch(globalAnnouncementsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Annonces globales'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _textController,
                  minLines: 8,
                  maxLines: 12,
                  maxLength: GlobalAnnouncementsRepository.maxTextLength,
                  decoration: InputDecoration(
                    labelText: _isEditing
                        ? 'Modifier le message'
                        : 'Nouveau message',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    helperText:
                        'Format multilingue:\n[fr-FR]\\nBonjour...\\n\\n[en-US]\\nHello...',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : _isEditing
                              ? _updateAnnouncement
                              : _createAnnouncement,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_isEditing ? Icons.save : Icons.send),
                      label: Text(_isEditing ? 'Enregistrer' : 'Publier'),
                    ),
                    if (_isEditing) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _isSubmitting ? null : _cancelEditing,
                        child: const Text('Annuler'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: announcementsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Impossible de charger les annonces.\n$error',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (announcements) {
                if (announcements.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucune annonce globale pour le moment.'),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: announcements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final announcement = announcements[index];
                    final isDeleting = _deletingAnnouncementIds.contains(
                      announcement.id,
                    );
                    final isSelected = _editingAnnouncementId == announcement.id;
                    return Card(
                      color: isSelected
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    dateFormat.format(
                                      announcement.createdAt.toLocal(),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                if (announcement.wasEdited)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.edit,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Modifier',
                                  onPressed: _isSubmitting || isDeleting
                                      ? null
                                      : () => _startEditingAnnouncement(
                                            announcement,
                                          ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer',
                                  onPressed: _isSubmitting || isDeleting
                                      ? null
                                      : () => unawaited(
                                            _deleteAnnouncement(announcement),
                                          ),
                                  icon: isDeleting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          Icons.delete_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinkifiedText(text: announcement.text),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
