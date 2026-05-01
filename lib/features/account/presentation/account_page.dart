import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planerz/core/intl/app_language.dart';
import 'package:planerz/core/intl/app_locale_provider.dart';
import 'package:planerz/core/push/fcm_token_sync.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/account/presentation/account_allergens_page.dart';
import 'package:planerz/features/account/presentation/palette_picker_button.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/l10n/app_localizations.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _accountNameController = TextEditingController();
  final _accountEmailController = TextEditingController();
  final _phoneCountryCodeController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _accountNameFieldKey = GlobalKey<FormFieldState<String>>();
  final _accountEmailFieldKey = GlobalKey<FormFieldState<String>>();
  final _phoneCountryCodeFieldKey = GlobalKey<FormFieldState<String>>();
  final _phoneNumberFieldKey = GlobalKey<FormFieldState<String>>();
  bool _didInitFromFirestore = false;
  bool _didRequestPhotoSync = false;
  bool _isEditingName = false;
  bool _isEditingEmail = false;
  bool _isEditingPhone = false;
  bool _isSavingName = false;
  bool _isSavingEmail = false;
  bool _isSavingPhone = false;
  bool _isEnablingPush = false;
  bool _isPhotoBusy = false;
  bool _isUpdatingLanguage = false;

  @override
  void initState() {
    super.initState();
    if (!_didRequestPhotoSync) {
      _didRequestPhotoSync = true;
      Future<void>.microtask(() async {
        await ref
            .read(accountRepositoryProvider)
            .syncMyGoogleProfilePhotoToStorage();
      });
    }
  }

  Future<void> _pickAndUploadProfilePhoto(ImageSource source) async {
    final l10n = AppLocalizations.of(context)!;
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
            toolbarTitle: l10n.accountCropProfilePhotoTitle,
            toolbarColor: colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: colorScheme.primary,
            dimmedLayerColor: Colors.black54,
            lockAspectRatio: true,
            initAspectRatio: CropAspectRatioPreset.square,
          ),
          IOSUiSettings(
            title: l10n.accountCropProfilePhotoTitle,
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
        SnackBar(content: Text(l10n.accountPhotoUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isPhotoBusy = false);
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isPhotoBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.accountRemovePhotoDialogTitle),
        content: Text(l10n.accountRemovePhotoDialogBody),
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
    if (confirmed != true) return;

    setState(() => _isPhotoBusy = true);
    try {
      await ref.read(accountRepositoryProvider).removeMyProfilePhoto();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoDeleteError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isPhotoBusy = false);
      }
    }
  }

  Widget _buildAvatar(String photoUrl, String displayLabel) {
    final fallback = CircleAvatar(
      radius: 42,
      child: Text(
        avatarInitialFromDisplayLabel(displayLabel),
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
    _accountEmailController.dispose();
    _phoneCountryCodeController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSavingName) return;
    final nameField = _accountNameFieldKey.currentState;
    if (nameField == null || !nameField.validate()) return;

    setState(() => _isSavingName = true);
    try {
      await ref.read(accountRepositoryProvider).updateAccountName(
            _accountNameController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountUpdated)),
      );
      setState(() => _isEditingName = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountUpdateError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingName = false);
      }
    }
  }

  Future<void> _savePhone() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSavingPhone) return;
    final countryField = _phoneCountryCodeFieldKey.currentState;
    final numberField = _phoneNumberFieldKey.currentState;
    if (countryField == null || numberField == null) return;
    final validCountry = countryField.validate();
    final validNumber = numberField.validate();
    if (!validCountry || !validNumber) return;

    setState(() => _isSavingPhone = true);
    try {
      await ref.read(accountRepositoryProvider).updateAccountPhone(
            phoneCountryCode: _phoneCountryCodeController.text,
            phoneNumber: _phoneNumberController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountUpdated)),
      );
      setState(() => _isEditingPhone = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountUpdateError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingPhone = false);
      }
    }
  }

  Future<void> _saveEmail() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSavingEmail) return;
    final emailField = _accountEmailFieldKey.currentState;
    if (emailField == null || !emailField.validate()) return;

    setState(() => _isSavingEmail = true);
    try {
      await ref.read(accountRepositoryProvider).updateAccountEmail(
            _accountEmailController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountUpdated)),
      );
      setState(() => _isEditingEmail = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountUpdateError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingEmail = false);
      }
    }
  }

  bool _isValidEmail(String value) {
    const pattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';
    return RegExp(pattern).hasMatch(value);
  }

  Widget _buildReadOnlyField({
    required BuildContext context,
    required IconData leadingIcon,
    required String value,
    required VoidCallback onEdit,
  }) {
    final resolvedValue = value.trim().isEmpty ? '—' : value.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          leadingIcon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            resolvedValue,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: AppLocalizations.of(context)!.commonEdit,
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }

  Widget _buildCompactCancelButton({
    required bool isSaving,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: isSaving ? null : onPressed,
      tooltip: tooltip,
      icon: const Icon(Icons.undo_rounded),
    );
  }

  Widget _buildEditActions({
    required bool isSaving,
    required VoidCallback onSave,
    required VoidCallback onCancel,
    required String saveTooltip,
    required String cancelTooltip,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactSaveButton(
          isSaving: isSaving,
          onPressed: onSave,
          tooltip: saveTooltip,
        ),
        _buildCompactCancelButton(
          isSaving: isSaving,
          onPressed: onCancel,
          tooltip: cancelTooltip,
        ),
      ],
    );
  }

  Widget _buildCompactSaveButton({
    required bool isSaving,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: isSaving ? null : onPressed,
      tooltip: tooltip,
      icon: isSaving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check),
    );
  }

  Future<void> _enablePushNotifications() async {
    final l10n = AppLocalizations.of(context)!;
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
                ? l10n.accountNotificationsEnabled
                : l10n.accountNotificationsEnableError,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isEnablingPush = false);
      }
    }
  }

  Future<void> _updatePreferredLanguage(AppLanguage language) async {
    if (_isUpdatingLanguage) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isUpdatingLanguage = true);
    try {
      await ref
          .read(appLocalePreferenceProvider.notifier)
          .setLanguage(language);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.accountLanguageUpdated),
            duration: const Duration(milliseconds: 1100),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingLanguage = false);
      }
    }
  }

  void _openAllergensPage(Map<String, dynamic> userData) {
    final initial = foodAllergenCatalogIdsFromUserData(userData);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AccountAllergensPage(initialCatalogIds: initial),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentLanguage = ref.watch(currentAppLanguageProvider);
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
        title: Text(l10n.accountTitle),
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
          final account =
              (data['account'] as Map<String, dynamic>?) ?? const {};

          final email = (account['email'] as String?)?.trim().isNotEmpty == true
              ? (account['email'] as String).trim()
              : (data['email'] as String?)?.trim().isNotEmpty == true
                  ? (data['email'] as String).trim()
                  : (authUser.email ?? '').trim();
          final photoUrl =
              (account['photoUrl'] as String?)?.trim().isNotEmpty == true
                  ? (account['photoUrl'] as String).trim()
                  : (data['photoUrl'] as String?)?.trim().isNotEmpty == true
                      ? (data['photoUrl'] as String).trim()
                      : '';
          final accountName = (account['name'] as String?)?.trim() ?? '';
          final phoneCountryCode =
              (account['phoneCountryCode'] as String?)?.trim() ?? '';
          final phoneNumber = (account['phoneNumber'] as String?)?.trim() ?? '';
          final phoneDisplay = [
            phoneCountryCode,
            phoneNumber,
          ].where((part) => part.trim().isNotEmpty).join(' ');
          final displayLabel = accountName.isNotEmpty
              ? accountName
              : (authUser.displayName ?? '').trim().isNotEmpty
                  ? (authUser.displayName ?? '').trim()
                  : displayLabelFromEmail(email);

          if (!_didInitFromFirestore) {
            _accountNameController.text = accountName;
            _accountEmailController.text = email;
            _phoneCountryCodeController.text = phoneCountryCode;
            _phoneNumberController.text = phoneNumber;
            _didInitFromFirestore = true;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.center,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildAvatar(photoUrl, displayLabel),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Material(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                        child: PopupMenuButton<String>(
                          tooltip: l10n.accountPhotoActionsTooltip,
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
                            PopupMenuItem(
                              value: 'gallery',
                              child: Text(l10n.accountChooseFromGallery),
                            ),
                            PopupMenuItem(
                              value: 'camera',
                              child: Text(l10n.accountTakePhoto),
                            ),
                            if (photoUrl.isNotEmpty)
                              PopupMenuItem(
                                value: 'remove',
                                child: Text(l10n.commonDelete),
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
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isEditingEmail)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: _accountEmailFieldKey,
                            controller: _accountEmailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: l10n.signInEmailFieldLabel,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final trimmed = (value ?? '').trim();
                              if (trimmed.isEmpty) {
                                return l10n.accountEmailUnavailable;
                              }
                              if (!_isValidEmail(trimmed)) {
                                return l10n.signInEmailLinkInvalidEmail;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildEditActions(
                          isSaving: _isSavingEmail,
                          onSave: _saveEmail,
                          onCancel: () => setState(() {
                            _accountEmailController.text = email;
                            _isEditingEmail = false;
                          }),
                          saveTooltip: l10n.signInEmailFieldLabel,
                          cancelTooltip: l10n.commonCancel,
                        ),
                      ],
                    )
                  else
                    _buildReadOnlyField(
                      context: context,
                      leadingIcon: Icons.alternate_email_rounded,
                      value: email,
                      onEdit: () {
                        setState(() {
                          _accountEmailController.text = email;
                          _isEditingEmail = true;
                          _isEditingName = false;
                          _isEditingPhone = false;
                        });
                      },
                    ),
                  const SizedBox(height: 12),
                  if (_isEditingName)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: _accountNameFieldKey,
                            controller: _accountNameController,
                            decoration: InputDecoration(
                              labelText: l10n.accountNameLabel,
                              hintText: l10n.accountNameHint,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().length > 60) {
                                return l10n.accountNameMaxLength;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildEditActions(
                          isSaving: _isSavingName,
                          onSave: _saveName,
                          onCancel: () => setState(() {
                            _accountNameController.text = accountName;
                            _isEditingName = false;
                          }),
                          saveTooltip: l10n.accountSaveNameTooltip,
                          cancelTooltip: l10n.commonCancel,
                        ),
                      ],
                    )
                  else
                    _buildReadOnlyField(
                      context: context,
                      leadingIcon: Icons.person_outline_rounded,
                      value: accountName,
                      onEdit: () {
                        setState(() {
                          _accountNameController.text = accountName;
                          _isEditingName = true;
                          _isEditingEmail = false;
                          _isEditingPhone = false;
                        });
                      },
                    ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.accountNameFallbackHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_isEditingPhone)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 108,
                          child: TextFormField(
                            key: _phoneCountryCodeFieldKey,
                            controller: _phoneCountryCodeController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: l10n.accountPhoneCountryCodeLabel,
                              hintText: l10n.accountPhoneCountryCodeHint,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (_) {
                              final countryCode =
                                  _phoneCountryCodeController.text.trim();
                              final phoneNumber =
                                  _phoneNumberController.text.trim();
                              final hasAnyPhonePart = countryCode.isNotEmpty ||
                                  phoneNumber.isNotEmpty;
                              if (!hasAnyPhonePart) {
                                return null;
                              }
                              if (countryCode.isEmpty &&
                                  RegExp(r'^\+[0-9 ]{6,20}$')
                                      .hasMatch(phoneNumber)) {
                                return null;
                              }
                              if (countryCode.isEmpty) {
                                return l10n.accountPhoneCountryCodeRequired;
                              }
                              if (!RegExp(r'^\+[0-9]{1,4}$')
                                  .hasMatch(countryCode)) {
                                return l10n.accountPhoneCountryCodeInvalid;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: _phoneNumberFieldKey,
                            controller: _phoneNumberController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: l10n.accountPhoneNumberLabel,
                              hintText: l10n.accountPhoneNumberHint,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (_) {
                              final countryCode =
                                  _phoneCountryCodeController.text.trim();
                              final phoneNumber =
                                  _phoneNumberController.text.trim();
                              final hasAnyPhonePart = countryCode.isNotEmpty ||
                                  phoneNumber.isNotEmpty;
                              if (!hasAnyPhonePart) {
                                return null;
                              }
                              if (countryCode.isEmpty &&
                                  RegExp(r'^\+[0-9 ]{6,20}$')
                                      .hasMatch(phoneNumber)) {
                                return null;
                              }
                              if (phoneNumber.isEmpty) {
                                return l10n.accountPhoneNumberRequired;
                              }
                              if (!RegExp(r'^[0-9 ]{4,20}$')
                                  .hasMatch(phoneNumber)) {
                                return l10n.accountPhoneNumberInvalid;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildEditActions(
                          isSaving: _isSavingPhone,
                          onSave: _savePhone,
                          onCancel: () => setState(() {
                            _phoneCountryCodeController.text = phoneCountryCode;
                            _phoneNumberController.text = phoneNumber;
                            _isEditingPhone = false;
                          }),
                          saveTooltip: l10n.accountSavePhoneTooltip,
                          cancelTooltip: l10n.commonCancel,
                        ),
                      ],
                    )
                  else
                    _buildReadOnlyField(
                      context: context,
                      leadingIcon: Icons.phone_outlined,
                      value: phoneDisplay,
                      onEdit: () {
                        setState(() {
                          _phoneCountryCodeController.text = phoneCountryCode;
                          _phoneNumberController.text = phoneNumber;
                          _isEditingPhone = true;
                          _isEditingEmail = false;
                          _isEditingName = false;
                        });
                      },
                    ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.accountPhonePrivacyHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.accountFoodAllergens),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openAllergensPage(data),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.accountCupidonSpace),
                subtitle: Text(l10n.accountCupidonHistory),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/account/cupidon'),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.accountPreferencesSectionTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.accountColorPalette),
                trailing: const PalettePickerButton(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.accountLanguageTitle),
                subtitle: Text(l10n.accountLanguageSubtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: currentLanguage == AppLanguage.frFr
                          ? Theme.of(
                              context,
                            )
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.75)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _isUpdatingLanguage
                            ? null
                            : () => _updatePreferredLanguage(AppLanguage.frFr),
                        child: Tooltip(
                          message: l10n.languageFrench,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            child: SvgPicture.asset(
                              'assets/images/flag_fr.svg',
                              width: 18,
                              height: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Material(
                      color: currentLanguage == AppLanguage.enUs
                          ? Theme.of(
                              context,
                            )
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.75)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _isUpdatingLanguage
                            ? null
                            : () => _updatePreferredLanguage(AppLanguage.enUs),
                        child: Tooltip(
                          message: l10n.languageEnglishUs,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            child: SvgPicture.asset(
                              'assets/images/flag_us.svg',
                              width: 18,
                              height: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        _isEnablingPush ? null : _enablePushNotifications,
                    icon: _isEnablingPush
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active_outlined),
                    label: Text(
                      _isEnablingPush
                          ? l10n.accountEnabling
                          : l10n.accountEnableNotifications,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.accountWebPushHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
