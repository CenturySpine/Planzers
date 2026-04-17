import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planzers/core/push/fcm_token_sync.dart';
import 'package:planzers/features/account/data/account_repository.dart';
import 'package:planzers/features/account/presentation/palette_picker_button.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  bool _didInitFromFirestore = false;
  bool _isSaving = false;
  bool _isEnablingPush = false;
  bool _isPhotoBusy = false;
  bool _isUpdatingAutoOpenCurrentTrip = false;

  Future<void> _pickAndUploadProfilePhoto(ImageSource source) async {
    if (_isPhotoBusy) return;
    final colorScheme = Theme.of(context).colorScheme;
    setState(() => _isPhotoBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked == null) {
        return;
      }
      if (!mounted) return;

      final screenSize = MediaQuery.sizeOf(context);
      final webCropWidth =
          ((screenSize.width - 140).clamp(260.0, 520.0)).round();
      final webCropHeight =
          ((screenSize.height - 320).clamp(220.0, 520.0)).round();

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recadrer la photo de profil',
            toolbarColor: colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: colorScheme.primary,
            dimmedLayerColor: Colors.black54,
            lockAspectRatio: true,
            initAspectRatio: CropAspectRatioPreset.square,
          ),
          IOSUiSettings(
            title: 'Recadrer la photo de profil',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
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
      if (cropped == null) {
        return;
      }

      final imagePath = cropped.path;
      final bytes = await XFile(imagePath).readAsBytes();
      final extMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(imagePath);
      final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
      await ref.read(accountRepositoryProvider).upsertMyProfilePhoto(
            bytes: bytes,
            fileExt: ext,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise a jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur photo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPhotoBusy = false);
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    if (_isPhotoBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
        content: const Text('La photo de profil sera retiree.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isPhotoBusy = true);
    try {
      await ref.read(accountRepositoryProvider).removeMyProfilePhoto();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil supprimee')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur suppression photo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPhotoBusy = false);
      }
    }
  }

  Widget _buildAvatar(String photoUrl, String email) {
    final fallback = CircleAvatar(
      radius: 42,
      child: Text(
        email.isNotEmpty ? email[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 24),
      ),
    );

    if (photoUrl.isEmpty) {
      return fallback;
    }

    return SizedBox(
      width: 84,
      height: 84,
      child: ClipOval(
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _accountNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateAccountName(_accountNameController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte mis a jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur mise a jour compte: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _enablePushNotifications() async {
    if (_isEnablingPush) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isEnablingPush = true);
    try {
      final success = await enablePushNotificationsFromUserAction(user);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Notifications activees.'
                : 'Impossible d activer les notifications.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isEnablingPush = false);
      }
    }
  }

  Future<void> _updateAutoOpenCurrentTripPreference(bool enabled) async {
    if (_isUpdatingAutoOpenCurrentTrip) return;
    setState(() => _isUpdatingAutoOpenCurrentTrip = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateAutoOpenCurrentTripOnLaunchPreference(enabled);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur mise à jour préférence: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAutoOpenCurrentTrip = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/sign-in');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon compte'),
        actions: const [
          PalettePickerButton(),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.read(accountRepositoryProvider).watchMyUserDocument(),
        builder: (
          BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() ?? const <String, dynamic>{};
          final account = (data['account'] as Map<String, dynamic>?) ?? const {};

          final email = (account['email'] as String?)?.trim().isNotEmpty == true
              ? (account['email'] as String).trim()
              : (data['email'] as String?)?.trim().isNotEmpty == true
                  ? (data['email'] as String).trim()
                  : (authUser.email ?? '').trim();
          final photoUrl = (account['photoUrl'] as String?)?.trim().isNotEmpty == true
              ? (account['photoUrl'] as String).trim()
              : (data['photoUrl'] as String?)?.trim().isNotEmpty == true
                  ? (data['photoUrl'] as String).trim()
                  : (authUser.photoURL ?? '').trim();
          final accountName = (account['name'] as String?)?.trim() ?? '';
          final autoOpenCurrentTripOnLaunch =
              autoOpenCurrentTripOnLaunchEnabledFromUserData(data);

          if (!_didInitFromFirestore) {
            _accountNameController.text = accountName;
            _didInitFromFirestore = true;
          }

          final effectiveName = accountName.isNotEmpty ? accountName : email;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.center,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildAvatar(photoUrl, email),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Material(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                        child: PopupMenuButton<String>(
                          tooltip: 'Actions photo de profil',
                          enabled: !_isPhotoBusy,
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'gallery') {
                              _pickAndUploadProfilePhoto(ImageSource.gallery);
                              return;
                            }
                            if (value == 'camera') {
                              _pickAndUploadProfilePhoto(ImageSource.camera);
                              return;
                            }
                            if (value == 'remove') {
                              _removeProfilePhoto();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'gallery',
                              child: Text('Choisir dans la galerie'),
                            ),
                            const PopupMenuItem(
                              value: 'camera',
                              child: Text('Prendre une photo'),
                            ),
                            if (photoUrl.isNotEmpty)
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Supprimer'),
                              ),
                          ],
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(
                              child: _isPhotoBusy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.8,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.photo_camera_outlined,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                email.isNotEmpty ? email : 'Email indisponible',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                effectiveName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              if (kIsWeb) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isEnablingPush ? null : _enablePushNotifications,
                    icon: _isEnablingPush
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active_outlined),
                    label: Text(
                      _isEnablingPush
                          ? 'Activation en cours...'
                          : 'Activer les notifications',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sur iPhone: installer l app sur l ecran d accueil, puis activer ici.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: autoOpenCurrentTripOnLaunch,
                      onChanged: _isUpdatingAutoOpenCurrentTrip
                          ? null
                          : _updateAutoOpenCurrentTripPreference,
                      title: const Text('Ouvrir automatiquement le voyage en cours'),
                      subtitle: const Text(
                        'Si un seul voyage est en cours aujourd\'hui, il s ouvre au lancement.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accountNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom du compte',
                        hintText: 'Ex: Alex',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().length > 60) {
                          return 'Maximum 60 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Si vide, le nom affiche sera votre email.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
