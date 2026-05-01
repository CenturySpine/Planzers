import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/core/presentation/linkified_text.dart';
import 'package:planerz/features/administration/data/global_announcements_repository.dart';
import 'package:planerz/features/administration/domain/admin_announcement.dart';
import 'package:planerz/features/administration/domain/admin_announcement_localized_text.dart';

class AdminAnnouncementsManagePage extends ConsumerStatefulWidget {
  const AdminAnnouncementsManagePage({super.key});

  static const String routePath = '/administration/announcements';

  @override
  ConsumerState<AdminAnnouncementsManagePage> createState() =>
      _AdminAnnouncementsManagePageState();
}

class _AdminAnnouncementsManagePageState
    extends ConsumerState<AdminAnnouncementsManagePage> {
  final TextEditingController _frFrTextController = TextEditingController();
  final TextEditingController _enUsTextController = TextEditingController();
  bool _isSubmitting = false;
  bool _isTranslating = false;
  bool _translateFrenchToEnglish = true;
  final Set<String> _deletingAnnouncementIds = <String>{};
  String? _editingAnnouncementId;

  bool get _isEditing => _editingAnnouncementId != null;

  static const int _maxBodyCharactersPerLocale =
      (GlobalAnnouncementsRepository.maxTextLength ~/ 2) - 24;

  @override
  void dispose() {
    _frFrTextController.dispose();
    _enUsTextController.dispose();
    super.dispose();
  }

  Future<void> _createAnnouncement() async {
    if (_isSubmitting) {
      return;
    }
    final assembledMultilingualText = assembleAdminAnnouncementMultilingualText(
      _frFrTextController.text,
      _enUsTextController.text,
    );
    if (_frFrTextController.text.trim().isEmpty &&
        _enUsTextController.text.trim().isEmpty) {
      _showSnackBar('Message vide.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(globalAnnouncementsRepositoryProvider)
          .sendAnnouncement(assembledMultilingualText);
      if (!mounted) {
        return;
      }
      _frFrTextController.clear();
      _enUsTextController.clear();
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
    final assembledMultilingualText = assembleAdminAnnouncementMultilingualText(
      _frFrTextController.text,
      _enUsTextController.text,
    );
    if (_frFrTextController.text.trim().isEmpty &&
        _enUsTextController.text.trim().isEmpty) {
      _showSnackBar('Message vide.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(globalAnnouncementsRepositoryProvider)
          .updateAnnouncement(
            announcementId,
            assembledMultilingualText,
          );
      if (!mounted) {
        return;
      }
      _frFrTextController.clear();
      _enUsTextController.clear();
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
        _frFrTextController.clear();
        _enUsTextController.clear();
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
    final splitBodies = splitAdminAnnouncementForEditing(announcement.text);
    _frFrTextController.text = splitBodies.frFr;
    _enUsTextController.text = splitBodies.enUs;
    setState(() {});
  }

  void _cancelEditing() {
    _editingAnnouncementId = null;
    _frFrTextController.clear();
    _enUsTextController.clear();
    setState(() {});
  }

  Future<void> _translateWithGoogleCloud() async {
    if (_isTranslating || _isSubmitting) {
      return;
    }

    final sourceText = _translateFrenchToEnglish
        ? _frFrTextController.text.trim()
        : _enUsTextController.text.trim();
    if (sourceText.isEmpty) {
      _showSnackBar('Rien à traduire dans la zone source.');
      return;
    }

    const sourceLanguageFrenchToEnglish = 'fr-FR';
    const targetLanguageFrenchToEnglish = 'en-US';
    const sourceLanguageEnglishToFrench = 'en-US';
    const targetLanguageEnglishToFrench = 'fr-FR';

    final sourceLanguageCode = _translateFrenchToEnglish
        ? sourceLanguageFrenchToEnglish
        : sourceLanguageEnglishToFrench;
    final targetLanguageCode = _translateFrenchToEnglish
        ? targetLanguageFrenchToEnglish
        : targetLanguageEnglishToFrench;

    setState(() => _isTranslating = true);
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: kFirebaseFunctionsRegion,
      ).httpsCallable('translateTextWithGoogleCloud');

      final callableResult = await callable.call(<String, dynamic>{
        'text': sourceText,
        'sourceLanguage': sourceLanguageCode,
        'targetLanguage': targetLanguageCode,
      });

      final responseData = callableResult.data;
      if (responseData is! Map) {
        if (!mounted) {
          return;
        }
        _showSnackBar('Réponse de traduction invalide.');
        return;
      }

      final translatedRaw = responseData['translatedText'];
      final translatedText =
          translatedRaw is String ? translatedRaw.trim() : '';

      if (!mounted) {
        return;
      }

      if (translatedText.isEmpty) {
        _showSnackBar('Traduction vide.');
        return;
      }

      setState(() {
        _enUsTextController.text = _translateFrenchToEnglish
            ? translatedText
            : _enUsTextController.text;
        _frFrTextController.text = _translateFrenchToEnglish
            ? _frFrTextController.text
            : translatedText;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Erreur: ${error.message ?? error.code}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Erreur: $error');
    } finally {
      if (mounted) {
        setState(() => _isTranslating = false);
      }
    }
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
                  controller: _frFrTextController,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: _maxBodyCharactersPerLocale,
                  decoration: const InputDecoration(
                    labelText: 'Message (fr-FR)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _isSubmitting || _isTranslating
                          ? null
                          : () => unawaited(_translateWithGoogleCloud()),
                      icon: _isTranslating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.translate_outlined),
                      label: const Text('Traduire'),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('FR → EN'),
                          tooltip: 'Français vers anglais',
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('EN → FR'),
                          tooltip: 'Anglais vers français',
                        ),
                      ],
                      selected: {_translateFrenchToEnglish},
                      onSelectionChanged: _isTranslating || _isSubmitting
                          ? null
                          : (selection) {
                              setState(() {
                                _translateFrenchToEnglish =
                                    selection.contains(true);
                              });
                            },
                      showSelectedIcon: false,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _enUsTextController,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: _maxBodyCharactersPerLocale,
                  decoration: const InputDecoration(
                    labelText: 'Message (en-US)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
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
                    final colorScheme = Theme.of(context).colorScheme;
                    final headerBackgroundColor = colorScheme.primaryContainer;
                    final headerForegroundColor = colorScheme.onPrimaryContainer;
                    return Card(
                      color: isSelected
                          ? colorScheme.secondaryContainer
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                            child: Material(
                              color: headerBackgroundColor,
                              borderRadius: BorderRadius.circular(10),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      dateFormat.format(
                                        announcement.createdAt.toLocal(),
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: headerForegroundColor,
                                          ),
                                    ),
                                    if (announcement.wasEdited) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.edit,
                                        size: 16,
                                        color: headerForegroundColor,
                                      ),
                                    ],
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Modifier',
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 20,
                                      style: IconButton.styleFrom(
                                        foregroundColor: headerForegroundColor,
                                      ),
                                      onPressed: _isSubmitting || isDeleting
                                          ? null
                                          : () => _startEditingAnnouncement(
                                                announcement,
                                              ),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Supprimer',
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 20,
                                      style: IconButton.styleFrom(
                                        foregroundColor: colorScheme.error,
                                      ),
                                      onPressed: _isSubmitting || isDeleting
                                          ? null
                                          : () => unawaited(
                                                _deleteAnnouncement(
                                                  announcement,
                                                ),
                                              ),
                                      icon: isDeleting
                                          ? SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: colorScheme.error,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_outline,
                                              size: 20,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: LinkifiedText(
                              text: resolveAdminAnnouncementText(
                                announcement.text,
                                Localizations.localeOf(context),
                              ),
                            ),
                          ),
                        ],
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
