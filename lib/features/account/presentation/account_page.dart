import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/core/intl/app_language.dart';
import 'package:planerz/core/intl/app_locale_provider.dart';
import 'package:planerz/core/push/fcm_token_sync.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/account/presentation/account_allergens_page.dart';
import 'package:planerz/features/account/presentation/account_page_ui.dart';
import 'package:planerz/features/auth/data/display_name_length.dart';
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

  static const InputDecoration _inlineFieldDecoration = InputDecoration(
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
  );

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

  Future<void> _removeProfilePhoto({
    required String photoUrl,
    required String displayLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (_isPhotoBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (ctx) => AccountRemovePhotoDialog(
        title: l10n.accountRemovePhotoDialogTitle,
        body: l10n.accountRemovePhotoDialogBody,
        cancelLabel: l10n.commonCancel,
        deleteLabel: l10n.commonDelete,
        photoUrl: photoUrl,
        displayLabel: displayLabel,
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

  Future<void> _showPhotoSheet({
    required String photoUrl,
    required String displayLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (_isPhotoBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (sheetContext) {
        return AccountPhotoBottomSheet(
          title: l10n.accountPhotoSheetTitle,
          galleryLabel: l10n.accountChooseFromGallery,
          cameraLabel: l10n.accountTakePhoto,
          deleteLabel: l10n.commonDelete,
          showDelete: photoUrl.isNotEmpty,
          onGallery: () {
            Navigator.of(sheetContext).pop();
            _pickAndUploadProfilePhoto(ImageSource.gallery);
          },
          onCamera: () {
            Navigator.of(sheetContext).pop();
            _pickAndUploadProfilePhoto(ImageSource.camera);
          },
          onDelete: () {
            Navigator.of(sheetContext).pop();
            _removeProfilePhoto(
              photoUrl: photoUrl,
              displayLabel: displayLabel,
            );
          },
        );
      },
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
    if (nameField == null || !nameField.validate()) {
      setState(() {});
      return;
    }

    setState(() => _isSavingName = true);
    try {
      await ref.read(accountRepositoryProvider).updateAccountName(
            _accountNameController.text.trim(),
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
    if (!validCountry || !validNumber) {
      setState(() {});
      return;
    }

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
    if (emailField == null || !emailField.validate()) {
      setState(() {});
      return;
    }

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

  void _startEditingEmail(String email) {
    setState(() {
      _accountEmailController.text = email;
      _isEditingEmail = true;
      _isEditingName = false;
      _isEditingPhone = false;
    });
  }

  void _startEditingName(String accountName) {
    setState(() {
      _accountNameController.text = accountName;
      _isEditingName = true;
      _isEditingEmail = false;
      _isEditingPhone = false;
    });
  }

  void _startEditingPhone({
    required String phoneCountryCode,
    required String phoneNumber,
  }) {
    setState(() {
      _phoneCountryCodeController.text = phoneCountryCode;
      _phoneNumberController.text = phoneNumber;
      _isEditingPhone = true;
      _isEditingEmail = false;
      _isEditingName = false;
    });
  }

  Widget _buildEmailRow({
    required AppLocalizations l10n,
    required String email,
  }) {
    if (_isEditingEmail) {
      final emailError = _accountEmailFieldKey.currentState?.errorText;
      return AccountEditWrap(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AccountInputShell(
                    icon: Icons.alternate_email_rounded,
                    hasError: emailError != null,
                    child: TextFormField(
                      key: _accountEmailFieldKey,
                      controller: _accountEmailController,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 15,
                        color: NeonPalette.deep,
                      ),
                      decoration: _inlineFieldDecoration,
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
                ),
                const SizedBox(width: 8),
                AccountEditActions(
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
            ),
            if (emailError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 6),
                child: Text(
                  emailError,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFBA1A1A),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return AccountInfoRow(
      icon: Icons.alternate_email_rounded,
      label: l10n.accountEmailAddressLabel,
      value: email,
      editTooltip: l10n.commonEdit,
      onEdit: () => _startEditingEmail(email),
    );
  }

  Widget _buildNameRow({
    required AppLocalizations l10n,
    required String accountName,
  }) {
    if (_isEditingName) {
      return AccountEditWrap(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AccountInputShell(
                    icon: Icons.badge_outlined,
                    child: TextFormField(
                      key: _accountNameFieldKey,
                      controller: _accountNameController,
                      autofocus: true,
                      maxLength: kDisplayNameMaxLength,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      buildCounter: (
                        context, {
                        required currentLength,
                        required isFocused,
                        required maxLength,
                      }) =>
                          null,
                      style: const TextStyle(
                        fontSize: 15,
                        color: NeonPalette.deep,
                      ),
                      decoration: _inlineFieldDecoration.copyWith(
                        hintText: l10n.accountNameHint,
                        hintStyle: const TextStyle(
                          color: NeonPalette.outline,
                        ),
                      ),
                      validator: (value) {
                        if (!isDisplayNameLengthValid(value ?? '')) {
                          return l10n.inviteBypassFirstNameInvalid;
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AccountEditActions(
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
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_accountNameController.text.length}/$kDisplayNameMaxLength',
                  style: const TextStyle(
                    fontSize: 11,
                    color: NeonPalette.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AccountInfoRow(
      icon: Icons.badge_outlined,
      label: l10n.accountNameLabel,
      value: accountName,
      editTooltip: l10n.commonEdit,
      onEdit: () => _startEditingName(accountName),
    );
  }

  Widget _buildPhoneRow({
    required AppLocalizations l10n,
    required String phoneCountryCode,
    required String phoneNumber,
    required String phoneDisplay,
  }) {
    if (_isEditingPhone) {
      return AccountEditWrap(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 92,
                  child: AccountInputShell(
                    icon: Icons.add,
                    child: TextFormField(
                      key: _phoneCountryCodeFieldKey,
                      controller: _phoneCountryCodeController,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        fontSize: 15,
                        color: NeonPalette.deep,
                      ),
                      decoration: _inlineFieldDecoration.copyWith(
                        hintText: l10n.accountPhoneCountryCodeHint,
                        hintStyle: const TextStyle(
                          color: NeonPalette.outline,
                        ),
                      ),
                      validator: (_) {
                        final countryCode =
                            _phoneCountryCodeController.text.trim();
                        final phoneNumberValue =
                            _phoneNumberController.text.trim();
                        final hasAnyPhonePart = countryCode.isNotEmpty ||
                            phoneNumberValue.isNotEmpty;
                        if (!hasAnyPhonePart) {
                          return null;
                        }
                        if (countryCode.isEmpty &&
                            RegExp(r'^\+[0-9 ]{6,20}$')
                                .hasMatch(phoneNumberValue)) {
                          return null;
                        }
                        if (countryCode.isEmpty) {
                          return l10n.accountPhoneCountryCodeRequired;
                        }
                        if (!RegExp(r'^\+[0-9]{1,4}$').hasMatch(countryCode)) {
                          return l10n.accountPhoneCountryCodeInvalid;
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AccountInputShell(
                    icon: Icons.phone_outlined,
                    child: TextFormField(
                      key: _phoneNumberFieldKey,
                      controller: _phoneNumberController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        fontSize: 15,
                        color: NeonPalette.deep,
                      ),
                      decoration: _inlineFieldDecoration.copyWith(
                        hintText: l10n.accountPhoneNumberHint,
                        hintStyle: const TextStyle(
                          color: NeonPalette.outline,
                        ),
                      ),
                      validator: (_) {
                        final countryCode =
                            _phoneCountryCodeController.text.trim();
                        final phoneNumberValue =
                            _phoneNumberController.text.trim();
                        final hasAnyPhonePart = countryCode.isNotEmpty ||
                            phoneNumberValue.isNotEmpty;
                        if (!hasAnyPhonePart) {
                          return null;
                        }
                        if (countryCode.isEmpty &&
                            RegExp(r'^\+[0-9 ]{6,20}$')
                                .hasMatch(phoneNumberValue)) {
                          return null;
                        }
                        if (phoneNumberValue.isEmpty) {
                          return l10n.accountPhoneNumberRequired;
                        }
                        if (!RegExp(r'^[0-9 ]{4,20}$')
                            .hasMatch(phoneNumberValue)) {
                          return l10n.accountPhoneNumberInvalid;
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: AccountEditActions(
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
            ),
          ],
        ),
      );
    }

    return AccountInfoRow(
      icon: Icons.phone_outlined,
      label: l10n.accountPhoneNumberLabel,
      value: phoneDisplay,
      editTooltip: l10n.commonEdit,
      onEdit: () => _startEditingPhone(
        phoneCountryCode: phoneCountryCode,
        phoneNumber: phoneNumber,
      ),
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

  String _languageSubtitle(AppLanguage language, AppLocalizations l10n) {
    return switch (language) {
      AppLanguage.frFr => l10n.languageFrench,
      AppLanguage.enUs => l10n.languageEnglishUs,
    };
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

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: AppBar(
          title: Text(l10n.accountTitle),
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: NeonPalette.deep,
            height: 28 / 20,
          ),
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
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                AccountProfileHeader(
                  photoUrl: photoUrl,
                  displayLabel: displayLabel,
                  email: email,
                  isPhotoBusy: _isPhotoBusy,
                  cameraTooltip: l10n.accountPhotoActionsTooltip,
                  onCameraTap: () => _showPhotoSheet(
                    photoUrl: photoUrl,
                    displayLabel: displayLabel,
                  ),
                ),
                AccountSectionHeader(
                  label: l10n.accountPersonalInfoSectionTitle,
                ),
                AccountCard(
                  child: Column(
                    children: [
                      _buildEmailRow(l10n: l10n, email: email),
                      const AccountCardDivider(),
                      _buildNameRow(l10n: l10n, accountName: accountName),
                      const AccountCardDivider(),
                      _buildPhoneRow(
                        l10n: l10n,
                        phoneCountryCode: phoneCountryCode,
                        phoneNumber: phoneNumber,
                        phoneDisplay: phoneDisplay,
                      ),
                    ],
                  ),
                ),
                AccountHelpText(text: l10n.accountPhonePrivacyHelp),
                AccountSectionHeader(
                  label: l10n.accountPreferencesSectionTitle,
                ),
                AccountCard(
                  child: Column(
                    children: [
                      AccountPrefTile(
                        icon: Icons.restaurant_outlined,
                        tint: AccountIconTint.warning,
                        title: l10n.accountFoodAllergens,
                        subtitle: l10n.accountFoodAllergensSubtitle,
                        onTap: () => _openAllergensPage(data),
                      ),
                      const AccountCardDivider(),
                      AccountPrefTile(
                        icon: Icons.favorite,
                        tint: AccountIconTint.accent,
                        filled: true,
                        title: l10n.accountCupidonSpace,
                        subtitle: l10n.accountCupidonHistory,
                        onTap: () => context.push('/account/cupidon'),
                      ),
                      const AccountCardDivider(),
                      AccountPrefTile(
                        icon: Icons.language_outlined,
                        title: l10n.accountLanguageTitle,
                        subtitle: _languageSubtitle(currentLanguage, l10n),
                        trailing: AccountLanguageSelector(
                          currentLanguage: currentLanguage,
                          isUpdating: _isUpdatingLanguage,
                          frenchTooltip: l10n.languageFrench,
                          englishTooltip: l10n.languageEnglishUs,
                          onSelect: _updatePreferredLanguage,
                        ),
                      ),
                    ],
                  ),
                ),
                if (kIsWeb) ...[
                  AccountNotificationsButton(
                    label: _isEnablingPush
                        ? l10n.accountEnabling
                        : l10n.accountEnableNotifications,
                    isEnabling: _isEnablingPush,
                    onPressed:
                        _isEnablingPush ? null : _enablePushNotifications,
                  ),
                  AccountHelpText(text: l10n.accountWebPushHelp),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
