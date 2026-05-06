import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('en', 'US'),
    Locale('fr'),
    Locale('fr', 'FR')
  ];

  /// No description provided for @languageFrench.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @languageEnglishUs.
  ///
  /// In fr, this message translates to:
  /// **'Anglais (États-Unis)'**
  String get languageEnglishUs;

  /// No description provided for @commonCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get commonDelete;

  /// No description provided for @aboutTitle.
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get aboutTitle;

  /// No description provided for @aboutLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger la page À propos.'**
  String get aboutLoadError;

  /// No description provided for @aboutCarouselTitle.
  ///
  /// In fr, this message translates to:
  /// **'Quelques souvenirs'**
  String get aboutCarouselTitle;

  /// No description provided for @aboutCarouselCaption1.
  ///
  /// In fr, this message translates to:
  /// **'Saint-Gervais-les-Bains (Haute-Savoie), mai 2025'**
  String get aboutCarouselCaption1;

  /// No description provided for @aboutCarouselCaption2.
  ///
  /// In fr, this message translates to:
  /// **'Surf à Peniche (Portugal), septembre 2023'**
  String get aboutCarouselCaption2;

  /// No description provided for @aboutCarouselCaption3.
  ///
  /// In fr, this message translates to:
  /// **'Lac de Tavaneuse, Abondance (Haute-Savoie), juillet 2025'**
  String get aboutCarouselCaption3;

  /// No description provided for @aboutCarouselCaption4.
  ///
  /// In fr, this message translates to:
  /// **'Capo Rosso, Corse-du-Sud, avril 2026'**
  String get aboutCarouselCaption4;

  /// No description provided for @aboutCarouselCaption5.
  ///
  /// In fr, this message translates to:
  /// **'Week-end via ferrata en solo, Bourg-d\'Oisans (Isère), juin 2025'**
  String get aboutCarouselCaption5;

  /// No description provided for @aboutCarouselCaption6.
  ///
  /// In fr, this message translates to:
  /// **'Via ferrata du fort l\'Écluse (Ain), septembre 2024'**
  String get aboutCarouselCaption6;

  /// No description provided for @aboutCarouselCaption7.
  ///
  /// In fr, this message translates to:
  /// **'Vélo remis à neuf dans un atelier d\'auto-réparation à Lyon, juillet 2024'**
  String get aboutCarouselCaption7;

  /// No description provided for @aboutCarouselCaption7LinkLabel.
  ///
  /// In fr, this message translates to:
  /// **'Voir l\'atelier Etablicyclette'**
  String get aboutCarouselCaption7LinkLabel;

  /// No description provided for @aboutCarouselCaption8.
  ///
  /// In fr, this message translates to:
  /// **'Stage de golf UCPA, Saint-Cyprien (Pyrénées-Orientales), mai 2024'**
  String get aboutCarouselCaption8;

  /// No description provided for @aboutFullNameAndAge.
  ///
  /// In fr, this message translates to:
  /// **'Bruno Chappe, 48 ans'**
  String get aboutFullNameAndAge;

  /// No description provided for @aboutIntroText.
  ///
  /// In fr, this message translates to:
  /// **'Développeur, passionné de rando et montagne, j\'ai créé Planerz parce qu\'à chaque organisation de week-end ou voyage entre amis, on jongle entre plusieurs outils (messagerie, suivi des dépenses, tableurs pour chambres, voitures, repas et activités). Mon objectif : centraliser toute l\'organisation dans un seul endroit.'**
  String get aboutIntroText;

  /// No description provided for @aboutPassionsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Passions et occupations'**
  String get aboutPassionsTitle;

  /// No description provided for @aboutPassionHiking.
  ///
  /// In fr, this message translates to:
  /// **'Rando'**
  String get aboutPassionHiking;

  /// No description provided for @aboutPassionBachata.
  ///
  /// In fr, this message translates to:
  /// **'Bachata'**
  String get aboutPassionBachata;

  /// No description provided for @aboutPassionClimbing.
  ///
  /// In fr, this message translates to:
  /// **'Escalade'**
  String get aboutPassionClimbing;

  /// No description provided for @aboutPassionRunning.
  ///
  /// In fr, this message translates to:
  /// **'Running'**
  String get aboutPassionRunning;

  /// No description provided for @aboutPassionCinema.
  ///
  /// In fr, this message translates to:
  /// **'Ciné'**
  String get aboutPassionCinema;

  /// No description provided for @aboutPassionSeries.
  ///
  /// In fr, this message translates to:
  /// **'Séries'**
  String get aboutPassionSeries;

  /// No description provided for @aboutPassionGolf.
  ///
  /// In fr, this message translates to:
  /// **'Golf'**
  String get aboutPassionGolf;

  /// No description provided for @aboutPassionCooking.
  ///
  /// In fr, this message translates to:
  /// **'Cuisine'**
  String get aboutPassionCooking;

  /// No description provided for @aboutPassionBikeRepair.
  ///
  /// In fr, this message translates to:
  /// **'Réparation vélo'**
  String get aboutPassionBikeRepair;

  /// No description provided for @aboutPassionImprov.
  ///
  /// In fr, this message translates to:
  /// **'Théâtre d\'impro'**
  String get aboutPassionImprov;

  /// No description provided for @aboutPassionBoardGames.
  ///
  /// In fr, this message translates to:
  /// **'Jeux de société'**
  String get aboutPassionBoardGames;

  /// No description provided for @aboutNetworksTitle.
  ///
  /// In fr, this message translates to:
  /// **'Réseaux'**
  String get aboutNetworksTitle;

  /// No description provided for @aboutContactTitle.
  ///
  /// In fr, this message translates to:
  /// **'Contact'**
  String get aboutContactTitle;

  /// No description provided for @aboutQuotesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Citations'**
  String get aboutQuotesTitle;

  /// No description provided for @legalInfoTitle.
  ///
  /// In fr, this message translates to:
  /// **'Informations légales'**
  String get legalInfoTitle;

  /// No description provided for @legalInfoLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger les informations légales.'**
  String get legalInfoLoadError;

  /// No description provided for @legalMentionsTab.
  ///
  /// In fr, this message translates to:
  /// **'Mentions légales'**
  String get legalMentionsTab;

  /// No description provided for @legalPrivacyTab.
  ///
  /// In fr, this message translates to:
  /// **'Vie privée / RGPD'**
  String get legalPrivacyTab;

  /// No description provided for @signInAnimatedLabelOutings.
  ///
  /// In fr, this message translates to:
  /// **'SORTIES'**
  String get signInAnimatedLabelOutings;

  /// No description provided for @signInAnimatedLabelWeekends.
  ///
  /// In fr, this message translates to:
  /// **'WEEK-ENDS'**
  String get signInAnimatedLabelWeekends;

  /// No description provided for @signInAnimatedLabelTrips.
  ///
  /// In fr, this message translates to:
  /// **'VOYAGES'**
  String get signInAnimatedLabelTrips;

  /// No description provided for @signInSubtitleStatic.
  ///
  /// In fr, this message translates to:
  /// **'ENTRE AMIS'**
  String get signInSubtitleStatic;

  /// No description provided for @signInLoading.
  ///
  /// In fr, this message translates to:
  /// **'Connexion...'**
  String get signInLoading;

  /// No description provided for @signInContinueWithGoogle.
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec Google'**
  String get signInContinueWithGoogle;

  /// No description provided for @signInContinueWithEmailLink.
  ///
  /// In fr, this message translates to:
  /// **'Recevoir lien de connexion'**
  String get signInContinueWithEmailLink;

  /// No description provided for @signInEmailFieldLabel.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get signInEmailFieldLabel;

  /// No description provided for @signInSendEmailLinkCta.
  ///
  /// In fr, this message translates to:
  /// **'Recevoir un lien de connexion'**
  String get signInSendEmailLinkCta;

  /// No description provided for @signInEmailLinkSent.
  ///
  /// In fr, this message translates to:
  /// **'Lien de connexion envoyé par e-mail.'**
  String get signInEmailLinkSent;

  /// No description provided for @signInEmailLinkSendFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d envoyer le lien de connexion.'**
  String get signInEmailLinkSendFailed;

  /// No description provided for @signInEmailLinkConfirmFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de confirmer la connexion avec le lien.'**
  String get signInEmailLinkConfirmFailed;

  /// No description provided for @signInEmailLinkInvalidEmail.
  ///
  /// In fr, this message translates to:
  /// **'Adresse e-mail invalide.'**
  String get signInEmailLinkInvalidEmail;

  /// No description provided for @signInEmailLinkMissingEmail.
  ///
  /// In fr, this message translates to:
  /// **'Renseigne ton e-mail ici puis redemande un nouveau lien.'**
  String get signInEmailLinkMissingEmail;

  /// No description provided for @signInContinueWithPhone.
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec mon numéro'**
  String get signInContinueWithPhone;

  /// No description provided for @signInPhoneTitle.
  ///
  /// In fr, this message translates to:
  /// **'Connexion par SMS'**
  String get signInPhoneTitle;

  /// No description provided for @signInPhoneFieldLabel.
  ///
  /// In fr, this message translates to:
  /// **'Numéro de téléphone'**
  String get signInPhoneFieldLabel;

  /// No description provided for @signInPhoneSendCodeCta.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer le code SMS'**
  String get signInPhoneSendCodeCta;

  /// No description provided for @signInPhoneCodeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Vérification'**
  String get signInPhoneCodeTitle;

  /// No description provided for @signInPhoneCodeFieldLabel.
  ///
  /// In fr, this message translates to:
  /// **'Code à 6 chiffres'**
  String get signInPhoneCodeFieldLabel;

  /// No description provided for @signInPhoneConfirmCta.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier'**
  String get signInPhoneConfirmCta;

  /// No description provided for @signInPhoneCodeSent.
  ///
  /// In fr, this message translates to:
  /// **'Code SMS envoyé.'**
  String get signInPhoneCodeSent;

  /// No description provided for @signInPhoneSendFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'envoyer le code SMS.'**
  String get signInPhoneSendFailed;

  /// No description provided for @signInPhoneTooManyRequests.
  ///
  /// In fr, this message translates to:
  /// **'Trop de tentatives depuis cet appareil. Patiente quelques minutes puis réessaie.'**
  String get signInPhoneTooManyRequests;

  /// No description provided for @signInPhoneInvalidNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numéro invalide. Commence par + suivi de l\'indicatif pays.'**
  String get signInPhoneInvalidNumber;

  /// No description provided for @signInPhoneInvalidCode.
  ///
  /// In fr, this message translates to:
  /// **'Code invalide.'**
  String get signInPhoneInvalidCode;

  /// No description provided for @signInPhoneConfirmFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de vérifier le code.'**
  String get signInPhoneConfirmFailed;

  /// No description provided for @signInPhoneChangeNumber.
  ///
  /// In fr, this message translates to:
  /// **'Changer de numéro'**
  String get signInPhoneChangeNumber;

  /// No description provided for @signInPhoneResendCode.
  ///
  /// In fr, this message translates to:
  /// **'Renvoyer le code'**
  String get signInPhoneResendCode;

  /// No description provided for @signInAuthBetaPill.
  ///
  /// In fr, this message translates to:
  /// **'BETA'**
  String get signInAuthBetaPill;

  /// No description provided for @signInAndroidPwaInstallOverlayMessage.
  ///
  /// In fr, this message translates to:
  /// **'Pour une meilleure expérience sur Android, installe l\'application depuis GitHub.'**
  String get signInAndroidPwaInstallOverlayMessage;

  /// No description provided for @accountTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mon compte'**
  String get accountTitle;

  /// No description provided for @accountCropProfilePhotoTitle.
  ///
  /// In fr, this message translates to:
  /// **'Recadrer la photo de profil'**
  String get accountCropProfilePhotoTitle;

  /// No description provided for @accountPhotoUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Photo de profil mise à jour'**
  String get accountPhotoUpdated;

  /// No description provided for @accountPhotoDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Photo de profil supprimée'**
  String get accountPhotoDeleted;

  /// No description provided for @accountRemovePhotoDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la photo ?'**
  String get accountRemovePhotoDialogTitle;

  /// No description provided for @accountRemovePhotoDialogBody.
  ///
  /// In fr, this message translates to:
  /// **'La photo de profil sera retirée.'**
  String get accountRemovePhotoDialogBody;

  /// No description provided for @accountUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Compte mis à jour'**
  String get accountUpdated;

  /// No description provided for @accountNotificationsEnabled.
  ///
  /// In fr, this message translates to:
  /// **'Notifications activées.'**
  String get accountNotificationsEnabled;

  /// No description provided for @accountNotificationsEnableError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'activer les notifications.'**
  String get accountNotificationsEnableError;

  /// No description provided for @accountLanguageUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Langue mise à jour'**
  String get accountLanguageUpdated;

  /// No description provided for @accountPhotoActionsTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Actions photo de profil'**
  String get accountPhotoActionsTooltip;

  /// No description provided for @accountChooseFromGallery.
  ///
  /// In fr, this message translates to:
  /// **'Choisir dans la galerie'**
  String get accountChooseFromGallery;

  /// No description provided for @accountTakePhoto.
  ///
  /// In fr, this message translates to:
  /// **'Prendre une photo'**
  String get accountTakePhoto;

  /// No description provided for @accountEmailUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'E-mail indisponible'**
  String get accountEmailUnavailable;

  /// No description provided for @accountNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du compte'**
  String get accountNameLabel;

  /// No description provided for @accountNameHint.
  ///
  /// In fr, this message translates to:
  /// **'Ex : Alex'**
  String get accountNameHint;

  /// No description provided for @accountNameMaxLength.
  ///
  /// In fr, this message translates to:
  /// **'Maximum 60 caractères'**
  String get accountNameMaxLength;

  /// No description provided for @accountPhoneCountryCodeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Indicatif'**
  String get accountPhoneCountryCodeLabel;

  /// No description provided for @accountPhoneCountryCodeHint.
  ///
  /// In fr, this message translates to:
  /// **'+33'**
  String get accountPhoneCountryCodeHint;

  /// No description provided for @accountPhoneCountryCodeRequired.
  ///
  /// In fr, this message translates to:
  /// **'Indicatif requis'**
  String get accountPhoneCountryCodeRequired;

  /// No description provided for @accountPhoneCountryCodeInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Indicatif invalide (ex : +33)'**
  String get accountPhoneCountryCodeInvalid;

  /// No description provided for @accountPhoneNumberLabel.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get accountPhoneNumberLabel;

  /// No description provided for @accountPhoneNumberHint.
  ///
  /// In fr, this message translates to:
  /// **'6 12 34 56 78'**
  String get accountPhoneNumberHint;

  /// No description provided for @accountPhoneNumberRequired.
  ///
  /// In fr, this message translates to:
  /// **'Numéro requis'**
  String get accountPhoneNumberRequired;

  /// No description provided for @accountPhoneNumberInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Numéro invalide'**
  String get accountPhoneNumberInvalid;

  /// No description provided for @accountSavePhoneTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer le téléphone'**
  String get accountSavePhoneTooltip;

  /// No description provided for @accountPhonePrivacyHelp.
  ///
  /// In fr, this message translates to:
  /// **'Ce numéro ne sera jamais visible, sauf réglages particuliers pour les voyages.'**
  String get accountPhonePrivacyHelp;

  /// No description provided for @accountSaveNameTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer le nom'**
  String get accountSaveNameTooltip;

  /// No description provided for @accountNameFallbackHelp.
  ///
  /// In fr, this message translates to:
  /// **'Si vide, le nom affiché sera votre e-mail.'**
  String get accountNameFallbackHelp;

  /// No description provided for @accountFoodAllergens.
  ///
  /// In fr, this message translates to:
  /// **'Allergènes alimentaires'**
  String get accountFoodAllergens;

  /// No description provided for @accountCupidonSpace.
  ///
  /// In fr, this message translates to:
  /// **'Espace Cupidon'**
  String get accountCupidonSpace;

  /// No description provided for @accountCupidonHistory.
  ///
  /// In fr, this message translates to:
  /// **'Historique des matchs'**
  String get accountCupidonHistory;

  /// No description provided for @accountPreferencesSectionTitle.
  ///
  /// In fr, this message translates to:
  /// **'Préférences'**
  String get accountPreferencesSectionTitle;

  /// No description provided for @accountColorPalette.
  ///
  /// In fr, this message translates to:
  /// **'Palette de couleurs'**
  String get accountColorPalette;

  /// No description provided for @accountLanguageTitle.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get accountLanguageTitle;

  /// No description provided for @accountLanguageSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Langue de l\'application'**
  String get accountLanguageSubtitle;

  /// No description provided for @accountEnabling.
  ///
  /// In fr, this message translates to:
  /// **'Activation en cours...'**
  String get accountEnabling;

  /// No description provided for @accountEnableNotifications.
  ///
  /// In fr, this message translates to:
  /// **'Activer les notifications'**
  String get accountEnableNotifications;

  /// No description provided for @accountWebPushHelp.
  ///
  /// In fr, this message translates to:
  /// **'Sur iPhone : installe l\'app sur l\'écran d\'accueil, puis active ici.'**
  String get accountWebPushHelp;

  /// No description provided for @accountPhotoError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur photo : {error}'**
  String accountPhotoError(Object error);

  /// No description provided for @accountPhotoDeleteError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur suppression photo : {error}'**
  String accountPhotoDeleteError(Object error);

  /// No description provided for @accountUpdateError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur mise à jour compte : {error}'**
  String accountUpdateError(Object error);

  /// No description provided for @accountLanguageUpdateError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur mise à jour langue : {error}'**
  String accountLanguageUpdateError(Object error);

  /// No description provided for @accountPreferenceUpdateError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur mise à jour préférence : {error}'**
  String accountPreferenceUpdateError(Object error);

  /// No description provided for @tripsJoinWithInviteTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre avec un code d\'invitation'**
  String get tripsJoinWithInviteTooltip;

  /// No description provided for @tripsNewTripTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau voyage'**
  String get tripsNewTripTooltip;

  /// No description provided for @tripsMyTrips.
  ///
  /// In fr, this message translates to:
  /// **'Mes voyages'**
  String get tripsMyTrips;

  /// No description provided for @tripsEmptyState.
  ///
  /// In fr, this message translates to:
  /// **'Aucun voyage pour le moment.\nCrée ton premier voyage.'**
  String get tripsEmptyState;

  /// No description provided for @tripsTimelinePast.
  ///
  /// In fr, this message translates to:
  /// **'Passés'**
  String get tripsTimelinePast;

  /// No description provided for @tripsTimelineOngoing.
  ///
  /// In fr, this message translates to:
  /// **'En cours'**
  String get tripsTimelineOngoing;

  /// No description provided for @tripsTimelineUpcoming.
  ///
  /// In fr, this message translates to:
  /// **'À venir'**
  String get tripsTimelineUpcoming;

  /// No description provided for @tripsEmptyPast.
  ///
  /// In fr, this message translates to:
  /// **'Aucun voyage passé.'**
  String get tripsEmptyPast;

  /// No description provided for @tripsEmptyOngoing.
  ///
  /// In fr, this message translates to:
  /// **'Aucun voyage en cours.'**
  String get tripsEmptyOngoing;

  /// No description provided for @tripsEmptyUpcoming.
  ///
  /// In fr, this message translates to:
  /// **'Aucun voyage à venir.'**
  String get tripsEmptyUpcoming;

  /// No description provided for @tripsCreateDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer un voyage'**
  String get tripsCreateDialogTitle;

  /// No description provided for @tripsTitleLabel.
  ///
  /// In fr, this message translates to:
  /// **'Titre'**
  String get tripsTitleLabel;

  /// No description provided for @tripsDestinationLabel.
  ///
  /// In fr, this message translates to:
  /// **'Destination'**
  String get tripsDestinationLabel;

  /// No description provided for @tripsStartDateLabel.
  ///
  /// In fr, this message translates to:
  /// **'Date de début'**
  String get tripsStartDateLabel;

  /// No description provided for @tripsEndDateLabel.
  ///
  /// In fr, this message translates to:
  /// **'Date de fin'**
  String get tripsEndDateLabel;

  /// No description provided for @tripsCreateValidationRequired.
  ///
  /// In fr, this message translates to:
  /// **'Titre et destination obligatoires'**
  String get tripsCreateValidationRequired;

  /// No description provided for @tripsCreateValidationDateOrder.
  ///
  /// In fr, this message translates to:
  /// **'La date de fin doit être le même jour ou après la date de début'**
  String get tripsCreateValidationDateOrder;

  /// No description provided for @tripsCreateAction.
  ///
  /// In fr, this message translates to:
  /// **'Créer'**
  String get tripsCreateAction;

  /// No description provided for @tripsDeleteDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce voyage ?'**
  String get tripsDeleteDialogTitle;

  /// No description provided for @tripsDeleteDialogBody.
  ///
  /// In fr, this message translates to:
  /// **'Cette action est définitive.\n\nVoyage : {tripTitle}'**
  String tripsDeleteDialogBody(Object tripTitle);

  /// No description provided for @tripsDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Voyage supprimé'**
  String get tripsDeleted;

  /// No description provided for @tripsDeleteError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur suppression : {error}'**
  String tripsDeleteError(Object error);

  /// No description provided for @tripsFirestoreError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur Firestore : {error}'**
  String tripsFirestoreError(Object error);

  /// No description provided for @tripsJoinCodeNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Ce code d\'invitation est introuvable.'**
  String get tripsJoinCodeNotFound;

  /// No description provided for @tripsJoinCodeNotValid.
  ///
  /// In fr, this message translates to:
  /// **'Ce code d\'invitation n\'est plus valide.'**
  String get tripsJoinCodeNotValid;

  /// No description provided for @tripsJoinCodeInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Code d\'invitation invalide.'**
  String get tripsJoinCodeInvalid;

  /// No description provided for @tripsJoinCodeUnauthenticated.
  ///
  /// In fr, this message translates to:
  /// **'Connecte-toi pour rejoindre un voyage.'**
  String get tripsJoinCodeUnauthenticated;

  /// No description provided for @tripsJoinCodeRequired.
  ///
  /// In fr, this message translates to:
  /// **'Saisis le code d\'invitation.'**
  String get tripsJoinCodeRequired;

  /// No description provided for @tripsJoinCodeDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Code d\'invitation'**
  String get tripsJoinCodeDialogTitle;

  /// No description provided for @tripsJoinCodeDialogHelp.
  ///
  /// In fr, this message translates to:
  /// **'Colle le code envoyé par l\'organisateur du voyage (pas le lien, uniquement le code).'**
  String get tripsJoinCodeDialogHelp;

  /// No description provided for @tripsJoinCodeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Code'**
  String get tripsJoinCodeLabel;

  /// No description provided for @tripsJoinCodeAction.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre'**
  String get tripsJoinCodeAction;

  /// No description provided for @commonSave.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get commonClose;

  /// No description provided for @commonErrorWithDetails.
  ///
  /// In fr, this message translates to:
  /// **'Erreur : {error}'**
  String commonErrorWithDetails(Object error);

  /// No description provided for @linkInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Lien invalide'**
  String get linkInvalid;

  /// No description provided for @linkOpenImpossible.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'ouvrir le lien'**
  String get linkOpenImpossible;

  /// No description provided for @linkLabel.
  ///
  /// In fr, this message translates to:
  /// **'Lien'**
  String get linkLabel;

  /// No description provided for @linkPreviewUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Aperçu indisponible pour ce lien.'**
  String get linkPreviewUnavailable;

  /// No description provided for @nameSearchEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucun nom ne correspond.'**
  String get nameSearchEmpty;

  /// No description provided for @nameSearchLabel.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get nameSearchLabel;

  /// No description provided for @nameSearchHint.
  ///
  /// In fr, this message translates to:
  /// **'Filtrer par nom'**
  String get nameSearchHint;

  /// No description provided for @nameSearchClear.
  ///
  /// In fr, this message translates to:
  /// **'Effacer'**
  String get nameSearchClear;

  /// No description provided for @locationOpenImpossible.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'ouvrir la localisation'**
  String get locationOpenImpossible;

  /// No description provided for @accountAllergensSaved.
  ///
  /// In fr, this message translates to:
  /// **'Allergènes enregistrés'**
  String get accountAllergensSaved;

  /// No description provided for @accountAllergensSaveError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur enregistrement allergènes : {error}'**
  String accountAllergensSaveError(Object error);

  /// No description provided for @accountDownloadApk.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger l\'APK'**
  String get accountDownloadApk;

  /// No description provided for @accountAdministration.
  ///
  /// In fr, this message translates to:
  /// **'Administration'**
  String get accountAdministration;

  /// No description provided for @accountSignOut.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get accountSignOut;

  /// No description provided for @paletteSaved.
  ///
  /// In fr, this message translates to:
  /// **'Palette {label} enregistrée'**
  String paletteSaved(Object label);

  /// No description provided for @tripLabelGeneric.
  ///
  /// In fr, this message translates to:
  /// **'Voyage'**
  String get tripLabelGeneric;

  /// No description provided for @tripNotFoundOrNoAccess.
  ///
  /// In fr, this message translates to:
  /// **'Voyage introuvable ou accès refusé.'**
  String get tripNotFoundOrNoAccess;

  /// No description provided for @tripBackToTrip.
  ///
  /// In fr, this message translates to:
  /// **'Retour au voyage'**
  String get tripBackToTrip;

  /// No description provided for @tripSettingsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres du voyage'**
  String get tripSettingsTitle;

  /// No description provided for @tripUserPreferencesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mes préférences du voyage'**
  String get tripUserPreferencesTitle;

  /// No description provided for @tripUserPreferencesMenuAction.
  ///
  /// In fr, this message translates to:
  /// **'Mes préférences'**
  String get tripUserPreferencesMenuAction;

  /// No description provided for @tripPhoneVisibilityTitle.
  ///
  /// In fr, this message translates to:
  /// **'Rôle minimum pour voir mon numéro de téléphone'**
  String get tripPhoneVisibilityTitle;

  /// No description provided for @tripPhoneVisibilitySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Définis qui peut voir ton numéro dans ce voyage.'**
  String get tripPhoneVisibilitySubtitle;

  /// No description provided for @tripPhoneVisibilityRequiresProfileNumber.
  ///
  /// In fr, this message translates to:
  /// **'Tu n’as pas encore renseigné de numéro de téléphone dans ton profil.'**
  String get tripPhoneVisibilityRequiresProfileNumber;

  /// No description provided for @tripPhoneVisibilityPersonne.
  ///
  /// In fr, this message translates to:
  /// **'Personne'**
  String get tripPhoneVisibilityPersonne;

  /// No description provided for @tripPhoneVisibilityCreateur.
  ///
  /// In fr, this message translates to:
  /// **'Créateur'**
  String get tripPhoneVisibilityCreateur;

  /// No description provided for @tripPhoneVisibilityAdmin.
  ///
  /// In fr, this message translates to:
  /// **'Admin'**
  String get tripPhoneVisibilityAdmin;

  /// No description provided for @tripPhoneVisibilityParticipant.
  ///
  /// In fr, this message translates to:
  /// **'Participant'**
  String get tripPhoneVisibilityParticipant;

  /// No description provided for @tripPhoneVisibilityUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Visibilité du numéro mise à jour'**
  String get tripPhoneVisibilityUpdated;

  /// No description provided for @tripPhoneVisibilityUpdateError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur lors de la mise à jour de la visibilité du numéro : {error}'**
  String tripPhoneVisibilityUpdateError(Object error);

  /// No description provided for @tripMyRole.
  ///
  /// In fr, this message translates to:
  /// **'Mon rôle : {role}'**
  String tripMyRole(Object role);

  /// No description provided for @tripRoleHierarchyHint.
  ///
  /// In fr, this message translates to:
  /// **'Hiérarchie des privilèges : créateur > admin > chef > participant'**
  String get tripRoleHierarchyHint;

  /// No description provided for @tripSettingsPermissionsSectionTitle.
  ///
  /// In fr, this message translates to:
  /// **'Permissions'**
  String get tripSettingsPermissionsSectionTitle;

  /// No description provided for @tripSettingsPermissionsSectionDescription.
  ///
  /// In fr, this message translates to:
  /// **'Définis les rôles minimaux pour chaque domaine du voyage.'**
  String get tripSettingsPermissionsSectionDescription;

  /// No description provided for @tripSettingsGeneralSectionTitle.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres généraux'**
  String get tripSettingsGeneralSectionTitle;

  /// No description provided for @tripSettingsGeneralSectionDescription.
  ///
  /// In fr, this message translates to:
  /// **'Réglages transverses du voyage (hors permissions).'**
  String get tripSettingsGeneralSectionDescription;

  /// No description provided for @tripSettingsGeneralPhotosStorageTitle.
  ///
  /// In fr, this message translates to:
  /// **'Stockage des photos'**
  String get tripSettingsGeneralPhotosStorageTitle;

  /// No description provided for @tripSettingsGeneralPhotosStorageDescription.
  ///
  /// In fr, this message translates to:
  /// **'Lien du dossier ou service de stockage partagé pour les photos du voyage.'**
  String get tripSettingsGeneralPhotosStorageDescription;

  /// No description provided for @tripSettingsGeneralPhotosStorageFieldLabel.
  ///
  /// In fr, this message translates to:
  /// **'Lien de stockage photos'**
  String get tripSettingsGeneralPhotosStorageFieldLabel;

  /// No description provided for @tripSettingsGeneralPhotosStorageFieldHint.
  ///
  /// In fr, this message translates to:
  /// **'https://drive.google.com/... ou https://photos.app.goo.gl/...'**
  String get tripSettingsGeneralPhotosStorageFieldHint;

  /// No description provided for @tripSettingsGeneralCupidonModeDescription.
  ///
  /// In fr, this message translates to:
  /// **'Active ou désactive le mode Cupidon pour tous les participants de ce voyage.'**
  String get tripSettingsGeneralCupidonModeDescription;

  /// No description provided for @tripSettingsGeneralComingSoonTitle.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres généraux du voyage'**
  String get tripSettingsGeneralComingSoonTitle;

  /// No description provided for @tripSettingsGeneralComingSoonDescription.
  ///
  /// In fr, this message translates to:
  /// **'Cette section arrive bientôt.'**
  String get tripSettingsGeneralComingSoonDescription;

  /// No description provided for @roleOwner.
  ///
  /// In fr, this message translates to:
  /// **'Créateur'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In fr, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleChef.
  ///
  /// In fr, this message translates to:
  /// **'Chef'**
  String get roleChef;

  /// No description provided for @roleParticipant.
  ///
  /// In fr, this message translates to:
  /// **'Participant'**
  String get roleParticipant;

  /// No description provided for @tripGeneralPermissionsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Caractéristiques générales du voyage'**
  String get tripGeneralPermissionsTitle;

  /// No description provided for @tripGeneralPermissionsDescription.
  ///
  /// In fr, this message translates to:
  /// **'Permissions minimales par défaut pour les actions globales du voyage.'**
  String get tripGeneralPermissionsDescription;

  /// No description provided for @tripPermissionEditGeneralInfo.
  ///
  /// In fr, this message translates to:
  /// **'Modifier les infos générales'**
  String get tripPermissionEditGeneralInfo;

  /// No description provided for @tripPermissionManageBanner.
  ///
  /// In fr, this message translates to:
  /// **'Gérer la photo de bannière'**
  String get tripPermissionManageBanner;

  /// No description provided for @tripPermissionPublishAnnouncements.
  ///
  /// In fr, this message translates to:
  /// **'Publier des annonces'**
  String get tripPermissionPublishAnnouncements;

  /// No description provided for @tripPermissionShareAccess.
  ///
  /// In fr, this message translates to:
  /// **'Partager l\'accès du voyage'**
  String get tripPermissionShareAccess;

  /// No description provided for @tripPermissionManageTripSettings.
  ///
  /// In fr, this message translates to:
  /// **'Modifier les paramètres du voyage'**
  String get tripPermissionManageTripSettings;

  /// No description provided for @tripPermissionDeleteTrip.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le voyage'**
  String get tripPermissionDeleteTrip;

  /// No description provided for @tripPermissionsResetDefaultsAction.
  ///
  /// In fr, this message translates to:
  /// **'Réinitialiser (valeurs par défaut)'**
  String get tripPermissionsResetDefaultsAction;

  /// No description provided for @tripPermissionsResetDone.
  ///
  /// In fr, this message translates to:
  /// **'Valeurs par défaut réappliquées'**
  String get tripPermissionsResetDone;

  /// No description provided for @tripPermissionsParticipantsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Permissions liées aux participants'**
  String get tripPermissionsParticipantsTitle;

  /// No description provided for @tripPermissionsParticipantsDescription.
  ///
  /// In fr, this message translates to:
  /// **'Prépare la gestion des permissions liées aux participants du voyage.'**
  String get tripPermissionsParticipantsDescription;

  /// No description provided for @tripPermissionsParticipantsResetPending.
  ///
  /// In fr, this message translates to:
  /// **'Réinitialisation prête (liste des permissions à venir)'**
  String get tripPermissionsParticipantsResetPending;

  /// No description provided for @tripPermissionParticipantsCreate.
  ///
  /// In fr, this message translates to:
  /// **'Créer un participant temporaire'**
  String get tripPermissionParticipantsCreate;

  /// No description provided for @tripPermissionParticipantsEditPlaceholder.
  ///
  /// In fr, this message translates to:
  /// **'Modifier un participant temporaire'**
  String get tripPermissionParticipantsEditPlaceholder;

  /// No description provided for @tripPermissionParticipantsDeletePlaceholder.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer un participant temporaire'**
  String get tripPermissionParticipantsDeletePlaceholder;

  /// No description provided for @tripPermissionParticipantsDeleteRegistered.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer un participant inscrit'**
  String get tripPermissionParticipantsDeleteRegistered;

  /// No description provided for @tripPermissionParticipantsToggleAdmin.
  ///
  /// In fr, this message translates to:
  /// **'Passer un utilisateur en admin / participant'**
  String get tripPermissionParticipantsToggleAdmin;

  /// No description provided for @tripPermissionsColumnAction.
  ///
  /// In fr, this message translates to:
  /// **'Action'**
  String get tripPermissionsColumnAction;

  /// No description provided for @tripPermissionsColumnMinRole.
  ///
  /// In fr, this message translates to:
  /// **'Rôle minimal'**
  String get tripPermissionsColumnMinRole;

  /// No description provided for @tripPermissionsExpensesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Permissions liées aux dépenses'**
  String get tripPermissionsExpensesTitle;

  /// No description provided for @tripPermissionsExpensesDescription.
  ///
  /// In fr, this message translates to:
  /// **'Rôles minimaux pour les postes de dépense. Un poste non visible pour un membre reste inaccessible pour lui, même avec un rôle suffisant.'**
  String get tripPermissionsExpensesDescription;

  /// No description provided for @tripPermissionExpensesCreatePost.
  ///
  /// In fr, this message translates to:
  /// **'Créer un poste de dépense'**
  String get tripPermissionExpensesCreatePost;

  /// No description provided for @tripPermissionExpensesEditPost.
  ///
  /// In fr, this message translates to:
  /// **'Modifier un poste de dépense'**
  String get tripPermissionExpensesEditPost;

  /// No description provided for @tripPermissionExpensesDeletePost.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer un poste de dépense'**
  String get tripPermissionExpensesDeletePost;

  /// No description provided for @tripPermissionExpensesCreateExpense.
  ///
  /// In fr, this message translates to:
  /// **'Créer une dépense'**
  String get tripPermissionExpensesCreateExpense;

  /// No description provided for @tripPermissionExpensesEditExpense.
  ///
  /// In fr, this message translates to:
  /// **'Modifier une dépense'**
  String get tripPermissionExpensesEditExpense;

  /// No description provided for @tripPermissionExpensesDeleteExpense.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer une dépense'**
  String get tripPermissionExpensesDeleteExpense;

  /// No description provided for @tripPermissionsActivitiesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Permissions liées aux activités'**
  String get tripPermissionsActivitiesTitle;

  /// No description provided for @tripPermissionsActivitiesDescription.
  ///
  /// In fr, this message translates to:
  /// **'Rôles minimaux pour suggérer, planifier, modifier et supprimer une activité.'**
  String get tripPermissionsActivitiesDescription;

  /// No description provided for @tripPermissionActivitiesSuggest.
  ///
  /// In fr, this message translates to:
  /// **'Suggérer une activité'**
  String get tripPermissionActivitiesSuggest;

  /// No description provided for @tripPermissionActivitiesPlan.
  ///
  /// In fr, this message translates to:
  /// **'Planifier une activité'**
  String get tripPermissionActivitiesPlan;

  /// No description provided for @tripPermissionActivitiesEdit.
  ///
  /// In fr, this message translates to:
  /// **'Modifier une activité'**
  String get tripPermissionActivitiesEdit;

  /// No description provided for @tripPermissionActivitiesDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer une activité'**
  String get tripPermissionActivitiesDelete;

  /// No description provided for @tripPermissionsMealsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Permissions liées aux repas'**
  String get tripPermissionsMealsTitle;

  /// No description provided for @tripPermissionsMealsDescription.
  ///
  /// In fr, this message translates to:
  /// **'Rôles minimaux pour créer, supprimer, modifier les repas, ajouter un apport et gérer une recette.'**
  String get tripPermissionsMealsDescription;

  /// No description provided for @tripPermissionMealsCreate.
  ///
  /// In fr, this message translates to:
  /// **'Créer un repas'**
  String get tripPermissionMealsCreate;

  /// No description provided for @tripPermissionMealsDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer un repas'**
  String get tripPermissionMealsDelete;

  /// No description provided for @tripPermissionMealsEdit.
  ///
  /// In fr, this message translates to:
  /// **'Éditer un repas (date, type, participants, chef, catégorie)'**
  String get tripPermissionMealsEdit;

  /// No description provided for @tripPermissionMealsAddContribution.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un apport (mode auberge)'**
  String get tripPermissionMealsAddContribution;

  /// No description provided for @tripPermissionMealsManageRecipe.
  ///
  /// In fr, this message translates to:
  /// **'Créer / supprimer / éditer une recette (mode cuisine)'**
  String get tripPermissionMealsManageRecipe;

  /// No description provided for @tripSectionTrip.
  ///
  /// In fr, this message translates to:
  /// **'Voyage'**
  String get tripSectionTrip;

  /// No description provided for @tripSectionTripDescription.
  ///
  /// In fr, this message translates to:
  /// **'Règles liées aux informations générales du voyage.'**
  String get tripSectionTripDescription;

  /// No description provided for @tripSectionExpenses.
  ///
  /// In fr, this message translates to:
  /// **'Dépenses'**
  String get tripSectionExpenses;

  /// No description provided for @tripSectionExpensesDescription.
  ///
  /// In fr, this message translates to:
  /// **'Gestion des droits sur les dépenses du voyage.'**
  String get tripSectionExpensesDescription;

  /// No description provided for @tripSectionActivities.
  ///
  /// In fr, this message translates to:
  /// **'Planning'**
  String get tripSectionActivities;

  /// No description provided for @tripSectionActivitiesDescription.
  ///
  /// In fr, this message translates to:
  /// **'Gestion des droits sur les activités proposées.'**
  String get tripSectionActivitiesDescription;

  /// No description provided for @tripSectionMeals.
  ///
  /// In fr, this message translates to:
  /// **'Repas'**
  String get tripSectionMeals;

  /// No description provided for @tripSectionMealsDescription.
  ///
  /// In fr, this message translates to:
  /// **'Gestion des droits sur les repas et menus.'**
  String get tripSectionMealsDescription;

  /// No description provided for @tripSectionShopping.
  ///
  /// In fr, this message translates to:
  /// **'Courses'**
  String get tripSectionShopping;

  /// No description provided for @tripSectionShoppingDescription.
  ///
  /// In fr, this message translates to:
  /// **'Gestion des droits sur les listes de courses.'**
  String get tripSectionShoppingDescription;

  /// No description provided for @tripSectionParticipants.
  ///
  /// In fr, this message translates to:
  /// **'Participants'**
  String get tripSectionParticipants;

  /// No description provided for @tripSectionParticipantsDescription.
  ///
  /// In fr, this message translates to:
  /// **'Gestion des droits liés aux membres du voyage.'**
  String get tripSectionParticipantsDescription;

  /// No description provided for @tripTabOverview.
  ///
  /// In fr, this message translates to:
  /// **'Aperçu'**
  String get tripTabOverview;

  /// No description provided for @tripTabMessages.
  ///
  /// In fr, this message translates to:
  /// **'Messagerie'**
  String get tripTabMessages;

  /// No description provided for @tripTabActivities.
  ///
  /// In fr, this message translates to:
  /// **'Planning'**
  String get tripTabActivities;

  /// No description provided for @tripTabExpenses.
  ///
  /// In fr, this message translates to:
  /// **'Dépenses'**
  String get tripTabExpenses;

  /// No description provided for @tripTabMeals.
  ///
  /// In fr, this message translates to:
  /// **'Repas'**
  String get tripTabMeals;

  /// No description provided for @tripTabShopping.
  ///
  /// In fr, this message translates to:
  /// **'Courses'**
  String get tripTabShopping;

  /// No description provided for @tripCarsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Covoiturage'**
  String get tripCarsTitle;

  /// No description provided for @tripCarsComingSoon.
  ///
  /// In fr, this message translates to:
  /// **'Gestion du covoiturage. Contenu à venir.'**
  String get tripCarsComingSoon;

  /// No description provided for @tripMealsComingSoon.
  ///
  /// In fr, this message translates to:
  /// **'Planning des repas. Contenu à venir.'**
  String get tripMealsComingSoon;

  /// No description provided for @tripThisTrip.
  ///
  /// In fr, this message translates to:
  /// **'Ce voyage'**
  String get tripThisTrip;

  /// No description provided for @tripStayDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mes dates sur le voyage'**
  String get tripStayDialogTitle;

  /// No description provided for @tripStayInvalidRange.
  ///
  /// In fr, this message translates to:
  /// **'La plage de dates est invalide.'**
  String get tripStayInvalidRange;

  /// No description provided for @tripStayOutOfTripBounds.
  ///
  /// In fr, this message translates to:
  /// **'Les dates doivent rester dans les dates du voyage.'**
  String get tripStayOutOfTripBounds;

  /// No description provided for @tripStayUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Dates mises à jour'**
  String get tripStayUpdated;

  /// No description provided for @authErrorWithDetails.
  ///
  /// In fr, this message translates to:
  /// **'Erreur auth : {error}'**
  String authErrorWithDetails(Object error);

  /// No description provided for @foodAllergensAndIntolerances.
  ///
  /// In fr, this message translates to:
  /// **'Allergènes et intolérances'**
  String get foodAllergensAndIntolerances;

  /// No description provided for @commonAddEllipsis.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter...'**
  String get commonAddEllipsis;

  /// No description provided for @commonMoreActions.
  ///
  /// In fr, this message translates to:
  /// **'Plus d\'actions'**
  String get commonMoreActions;

  /// No description provided for @commonDone.
  ///
  /// In fr, this message translates to:
  /// **'Terminer'**
  String get commonDone;

  /// No description provided for @mealComponentTypeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Type de composant'**
  String get mealComponentTypeLabel;

  /// No description provided for @mealComponentNameOptionalLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du composant (optionnel)'**
  String get mealComponentNameOptionalLabel;

  /// No description provided for @mealContainsAllergen.
  ///
  /// In fr, this message translates to:
  /// **'Contient {allergen}'**
  String mealContainsAllergen(Object allergen);

  /// No description provided for @mealMayContainAllergen.
  ///
  /// In fr, this message translates to:
  /// **'Peut contenir {allergen}'**
  String mealMayContainAllergen(Object allergen);

  /// No description provided for @mealIngredientsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ingrédients'**
  String get mealIngredientsTitle;

  /// No description provided for @mealIngredientHint.
  ///
  /// In fr, this message translates to:
  /// **'Ingrédient...'**
  String get mealIngredientHint;

  /// No description provided for @mealAddIngredient.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un ingrédient'**
  String get mealAddIngredient;

  /// No description provided for @tripParticipantsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Participants'**
  String get tripParticipantsTitle;

  /// No description provided for @tripParticipantsEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucun participant.'**
  String get tripParticipantsEmpty;

  /// No description provided for @tripParticipantsTraveler.
  ///
  /// In fr, this message translates to:
  /// **'Voyageur'**
  String get tripParticipantsTraveler;

  /// No description provided for @tripParticipantsUser.
  ///
  /// In fr, this message translates to:
  /// **'Utilisateur'**
  String get tripParticipantsUser;

  /// No description provided for @tripParticipantsThisParticipant.
  ///
  /// In fr, this message translates to:
  /// **'Ce participant'**
  String get tripParticipantsThisParticipant;

  /// No description provided for @tripParticipantsAdminRemoved.
  ///
  /// In fr, this message translates to:
  /// **'Rôle administrateur retiré ({label}).'**
  String tripParticipantsAdminRemoved(Object label);

  /// No description provided for @tripParticipantsAdminGranted.
  ///
  /// In fr, this message translates to:
  /// **'{label} est administrateur.'**
  String tripParticipantsAdminGranted(Object label);

  /// No description provided for @tripParticipantsLikeSaveError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'enregistrer ce like pour le moment.'**
  String get tripParticipantsLikeSaveError;

  /// No description provided for @tripParticipantsAddPlannedTravelerTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un voyageur prévu'**
  String get tripParticipantsAddPlannedTravelerTitle;

  /// No description provided for @tripParticipantsPlannedTravelerAdded.
  ///
  /// In fr, this message translates to:
  /// **'Voyageur prévu ajouté'**
  String get tripParticipantsPlannedTravelerAdded;

  /// No description provided for @tripParticipantsEditNameTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le nom'**
  String get tripParticipantsEditNameTitle;

  /// No description provided for @tripParticipantsNameUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Nom mis à jour'**
  String get tripParticipantsNameUpdated;

  /// No description provided for @tripParticipantsRemovePlannedTravelerTitle.
  ///
  /// In fr, this message translates to:
  /// **'Retirer ce voyageur prévu ?'**
  String get tripParticipantsRemovePlannedTravelerTitle;

  /// No description provided for @tripParticipantsRemovePlannedTravelerBody.
  ///
  /// In fr, this message translates to:
  /// **'« {label} » sera retiré des participants.'**
  String tripParticipantsRemovePlannedTravelerBody(Object label);

  /// No description provided for @tripParticipantsRemoveAction.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get tripParticipantsRemoveAction;

  /// No description provided for @tripParticipantsPlannedTravelerRemoved.
  ///
  /// In fr, this message translates to:
  /// **'Voyageur prévu retiré'**
  String get tripParticipantsPlannedTravelerRemoved;

  /// No description provided for @tripParticipantsRemoveParticipantTitle.
  ///
  /// In fr, this message translates to:
  /// **'Retirer ce participant ?'**
  String get tripParticipantsRemoveParticipantTitle;

  /// No description provided for @tripParticipantsRemoveParticipantBody.
  ///
  /// In fr, this message translates to:
  /// **'Retirer « {label} » du voyage ?'**
  String tripParticipantsRemoveParticipantBody(Object label);

  /// No description provided for @tripParticipantsRemovedFromTrip.
  ///
  /// In fr, this message translates to:
  /// **'Participant retiré du voyage'**
  String get tripParticipantsRemovedFromTrip;

  /// No description provided for @tripParticipantsAdminHint.
  ///
  /// In fr, this message translates to:
  /// **'Clique sur l’icône à gauche d’un voyageur (prévu ou inscrit) pour lui donner ou retirer le rôle administrateur (sauf le créateur).'**
  String get tripParticipantsAdminHint;

  /// No description provided for @tripParticipantsUnlike.
  ///
  /// In fr, this message translates to:
  /// **'Retirer le like'**
  String get tripParticipantsUnlike;

  /// No description provided for @tripParticipantsLike.
  ///
  /// In fr, this message translates to:
  /// **'Liker'**
  String get tripParticipantsLike;

  /// No description provided for @tripParticipantsChangeRole.
  ///
  /// In fr, this message translates to:
  /// **'Changer le rôle'**
  String get tripParticipantsChangeRole;

  /// No description provided for @tripParticipantsOpenDialer.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le composeur'**
  String get tripParticipantsOpenDialer;

  /// No description provided for @tripNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Voyage introuvable'**
  String get tripNotFound;

  /// No description provided for @commonName.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get commonName;

  /// No description provided for @commonAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get commonAdd;

  /// No description provided for @commonEdit.
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get commonEdit;

  /// No description provided for @cupidonDefaultEnabled.
  ///
  /// In fr, this message translates to:
  /// **'Mode Cupidon activé par défaut'**
  String get cupidonDefaultEnabled;

  /// No description provided for @cupidonDefaultDisabled.
  ///
  /// In fr, this message translates to:
  /// **'Mode Cupidon désactivé par défaut'**
  String get cupidonDefaultDisabled;

  /// No description provided for @cupidonDeleteMatchTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce match ?'**
  String get cupidonDeleteMatchTitle;

  /// No description provided for @cupidonDeleteMatchBody.
  ///
  /// In fr, this message translates to:
  /// **'Ce match avec {memberLabel} (voyage \"{tripTitle}\") sera retiré de ton historique.'**
  String cupidonDeleteMatchBody(Object memberLabel, Object tripTitle);

  /// No description provided for @cupidonEnableByDefaultTitle.
  ///
  /// In fr, this message translates to:
  /// **'Activer Cupidon par défaut'**
  String get cupidonEnableByDefaultTitle;

  /// No description provided for @cupidonEnableByDefaultSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Quand tu rejoins un nouveau voyage, cette valeur est préremplie.'**
  String get cupidonEnableByDefaultSubtitle;

  /// No description provided for @cupidonPreferenceLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur chargement préférence : {error}'**
  String cupidonPreferenceLoadError(Object error);

  /// No description provided for @cupidonMyMatches.
  ///
  /// In fr, this message translates to:
  /// **'Mes matchs'**
  String get cupidonMyMatches;

  /// No description provided for @cupidonNoMatches.
  ///
  /// In fr, this message translates to:
  /// **'Aucun match enregistré pour le moment.'**
  String get cupidonNoMatches;

  /// No description provided for @cupidonDeleteMatchTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce match'**
  String get cupidonDeleteMatchTooltip;

  /// No description provided for @cupidonMatchesLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur chargement matchs : {error}'**
  String cupidonMatchesLoadError(Object error);

  /// No description provided for @roomsCreate.
  ///
  /// In fr, this message translates to:
  /// **'Créer'**
  String get roomsCreate;

  /// No description provided for @roomsCreateTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer une chambre'**
  String get roomsCreateTitle;

  /// No description provided for @roomsCreated.
  ///
  /// In fr, this message translates to:
  /// **'Chambre créée'**
  String get roomsCreated;

  /// No description provided for @roomsUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Chambre mise à jour'**
  String get roomsUpdated;

  /// No description provided for @roomsDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Chambre supprimée'**
  String get roomsDeleted;

  /// No description provided for @roomsUnnamedRoom.
  ///
  /// In fr, this message translates to:
  /// **'Chambre sans nom'**
  String get roomsUnnamedRoom;

  /// No description provided for @roomsRoomLabel.
  ///
  /// In fr, this message translates to:
  /// **'Chambre'**
  String get roomsRoomLabel;

  /// No description provided for @roomsDeleteTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la chambre ?'**
  String get roomsDeleteTitle;

  /// No description provided for @roomsDeleteBody.
  ///
  /// In fr, this message translates to:
  /// **'« {roomName} » sera supprimée.'**
  String roomsDeleteBody(Object roomName);

  /// No description provided for @roomsNameRequired.
  ///
  /// In fr, this message translates to:
  /// **'Nom obligatoire'**
  String get roomsNameRequired;

  /// No description provided for @roomsAddBed.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un lit'**
  String get roomsAddBed;

  /// No description provided for @roomsAddAtLeastOneBed.
  ///
  /// In fr, this message translates to:
  /// **'Ajoute au moins un lit'**
  String get roomsAddAtLeastOneBed;

  /// No description provided for @roomsBedCapacityExceeded.
  ///
  /// In fr, this message translates to:
  /// **'Capacité d\'un lit dépassée'**
  String get roomsBedCapacityExceeded;

  /// No description provided for @roomsThisBedCapacityReached.
  ///
  /// In fr, this message translates to:
  /// **'Capacité de ce lit atteinte'**
  String get roomsThisBedCapacityReached;

  /// No description provided for @roomsBedTypeSingle.
  ///
  /// In fr, this message translates to:
  /// **'Simple'**
  String get roomsBedTypeSingle;

  /// No description provided for @roomsBedTypeDouble.
  ///
  /// In fr, this message translates to:
  /// **'Double'**
  String get roomsBedTypeDouble;

  /// No description provided for @roomsBedKindRegular.
  ///
  /// In fr, this message translates to:
  /// **'Normal'**
  String get roomsBedKindRegular;

  /// No description provided for @roomsBedKindExtra.
  ///
  /// In fr, this message translates to:
  /// **'Appoint'**
  String get roomsBedKindExtra;

  /// No description provided for @roomsAlreadyAssigned.
  ///
  /// In fr, this message translates to:
  /// **'Déjà affecté chambre {roomName}'**
  String roomsAlreadyAssigned(Object roomName);

  /// No description provided for @roomsBedLabel.
  ///
  /// In fr, this message translates to:
  /// **'Lit {index}'**
  String roomsBedLabel(Object index);

  /// No description provided for @roomsBedTypeAndKind.
  ///
  /// In fr, this message translates to:
  /// **'{typeLabel} · {kindLabel}'**
  String roomsBedTypeAndKind(Object typeLabel, Object kindLabel);

  /// No description provided for @roomsBedSummary.
  ///
  /// In fr, this message translates to:
  /// **'Lit {index} · {typeLabel} · {kindLabel}'**
  String roomsBedSummary(Object index, Object typeLabel, Object kindLabel);

  /// No description provided for @roomsBedLine.
  ///
  /// In fr, this message translates to:
  /// **'Lit {index} · {typeLabel} · {kindLabel} · {assignedLabel}'**
  String roomsBedLine(
      Object index, Object typeLabel, Object kindLabel, Object assignedLabel);

  /// No description provided for @tripOverviewUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Voyage mis à jour'**
  String get tripOverviewUpdated;

  /// No description provided for @tripOverviewUpdateError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur modification : {error}'**
  String tripOverviewUpdateError(Object error);

  /// No description provided for @tripOverviewInviteCodeCopied.
  ///
  /// In fr, this message translates to:
  /// **'Code d\'invitation copié dans le presse-papiers'**
  String get tripOverviewInviteCodeCopied;

  /// No description provided for @tripOverviewInviteCodeCopyError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur copie du code : {error}'**
  String tripOverviewInviteCodeCopyError(Object error);

  /// No description provided for @cupidonEnabled.
  ///
  /// In fr, this message translates to:
  /// **'Mode Cupidon activé'**
  String get cupidonEnabled;

  /// No description provided for @cupidonDisabled.
  ///
  /// In fr, this message translates to:
  /// **'Mode Cupidon désactivé'**
  String get cupidonDisabled;

  /// No description provided for @cupidonModeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mode cupidon'**
  String get cupidonModeTitle;

  /// No description provided for @cupidonModeExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Si toi et un autre participant vous likez mutuellement, vous obtenez un match et recevez une notification.'**
  String get cupidonModeExplanation;

  /// No description provided for @cupidonModeDisabledByAdmin.
  ///
  /// In fr, this message translates to:
  /// **'Les admins ont désactivé cette option pour ce voyage.'**
  String get cupidonModeDisabledByAdmin;

  /// No description provided for @cupidonEnableAction.
  ///
  /// In fr, this message translates to:
  /// **'Activer Cupidon'**
  String get cupidonEnableAction;

  /// No description provided for @cupidonDisableAction.
  ///
  /// In fr, this message translates to:
  /// **'Désactiver Cupidon'**
  String get cupidonDisableAction;

  /// No description provided for @tripOverviewCupidonToggleError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur mode Cupidon : {error}'**
  String tripOverviewCupidonToggleError(Object error);

  /// No description provided for @tripOverviewCropBanner.
  ///
  /// In fr, this message translates to:
  /// **'Recadrer la bannière'**
  String get tripOverviewCropBanner;

  /// No description provided for @tripOverviewBannerUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Photo de bannière mise à jour'**
  String get tripOverviewBannerUpdated;

  /// No description provided for @tripOverviewBannerRemoveBody.
  ///
  /// In fr, this message translates to:
  /// **'La bannière sera retirée du voyage.'**
  String get tripOverviewBannerRemoveBody;

  /// No description provided for @tripOverviewActions.
  ///
  /// In fr, this message translates to:
  /// **'Actions voyage'**
  String get tripOverviewActions;

  /// No description provided for @tripOverviewPhotoActions.
  ///
  /// In fr, this message translates to:
  /// **'Actions photo'**
  String get tripOverviewPhotoActions;

  /// No description provided for @tripOverviewChangePhoto.
  ///
  /// In fr, this message translates to:
  /// **'Changer de photo'**
  String get tripOverviewChangePhoto;

  /// No description provided for @tripOverviewCopyCode.
  ///
  /// In fr, this message translates to:
  /// **'Copier le code'**
  String get tripOverviewCopyCode;

  /// No description provided for @tripOverviewEditTrip.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le voyage'**
  String get tripOverviewEditTrip;

  /// No description provided for @tripOverviewEditAddTripDates.
  ///
  /// In fr, this message translates to:
  /// **'Définir les dates du voyage'**
  String get tripOverviewEditAddTripDates;

  /// No description provided for @tripOverviewEditRemoveTripDates.
  ///
  /// In fr, this message translates to:
  /// **'Retirer les dates du voyage'**
  String get tripOverviewEditRemoveTripDates;

  /// No description provided for @tripOverviewTitleRequired.
  ///
  /// In fr, this message translates to:
  /// **'Titre obligatoire'**
  String get tripOverviewTitleRequired;

  /// No description provided for @tripOverviewDestinationRequired.
  ///
  /// In fr, this message translates to:
  /// **'Destination obligatoire'**
  String get tripOverviewDestinationRequired;

  /// No description provided for @tripOverviewAddressLabel.
  ///
  /// In fr, this message translates to:
  /// **'Adresse'**
  String get tripOverviewAddressLabel;

  /// No description provided for @tripOverviewAddressHint.
  ///
  /// In fr, this message translates to:
  /// **'10 Rue de Rivoli, 75001 Paris'**
  String get tripOverviewAddressHint;

  /// No description provided for @tripOverviewLinkLabel.
  ///
  /// In fr, this message translates to:
  /// **'Lien (Airbnb, Booking, site, ...)'**
  String get tripOverviewLinkLabel;

  /// No description provided for @tripOverviewLinkHint.
  ///
  /// In fr, this message translates to:
  /// **'https://...'**
  String get tripOverviewLinkHint;

  /// No description provided for @tripOverviewLinkInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Lien invalide (ex: https://...)'**
  String get tripOverviewLinkInvalid;

  /// No description provided for @tripOverviewLinkMustStartWithHttp.
  ///
  /// In fr, this message translates to:
  /// **'Le lien doit commencer par http(s)://'**
  String get tripOverviewLinkMustStartWithHttp;

  /// No description provided for @tripOverviewOpenLocation.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir la localisation'**
  String get tripOverviewOpenLocation;

  /// No description provided for @tripOverviewUntitled.
  ///
  /// In fr, this message translates to:
  /// **'Sans titre'**
  String get tripOverviewUntitled;

  /// No description provided for @tripOverviewUnknownDestination.
  ///
  /// In fr, this message translates to:
  /// **'Destination inconnue'**
  String get tripOverviewUnknownDestination;

  /// No description provided for @tripOverviewLeaveTripTitle.
  ///
  /// In fr, this message translates to:
  /// **'Quitter ce voyage ?'**
  String get tripOverviewLeaveTripTitle;

  /// No description provided for @tripOverviewLeaveAction.
  ///
  /// In fr, this message translates to:
  /// **'Quitter'**
  String get tripOverviewLeaveAction;

  /// No description provided for @tripOverviewLeaveTripCardTitle.
  ///
  /// In fr, this message translates to:
  /// **'Quitter le voyage'**
  String get tripOverviewLeaveTripCardTitle;

  /// No description provided for @tripOverviewLeaveTripDialogBody.
  ///
  /// In fr, this message translates to:
  /// **'Tu seras retiré de la liste des voyageurs. Sur chaque dépense partagée où tu participes, tu seras enlevé des participants : le partage sera recalculé pour les autres. Si tu étais seul sur une dépense, celle-ci sera supprimée.'**
  String get tripOverviewLeaveTripDialogBody;

  /// No description provided for @tripOverviewLeaveTripCardBody.
  ///
  /// In fr, this message translates to:
  /// **'Tu pourras quitter même si les comptes ne sont pas à zéro. Tu seras alors retiré automatiquement de toutes les dépenses où tu es inclus (les autres voyageurs verront les parts mises à jour).'**
  String get tripOverviewLeaveTripCardBody;

  /// No description provided for @inviteTitle.
  ///
  /// In fr, this message translates to:
  /// **'Invitation'**
  String get inviteTitle;

  /// No description provided for @inviteJoinedTrip.
  ///
  /// In fr, this message translates to:
  /// **'Vous avez rejoint le voyage'**
  String get inviteJoinedTrip;

  /// No description provided for @inviteChooseTravelerError.
  ///
  /// In fr, this message translates to:
  /// **'Choisis un voyageur sur la liste.'**
  String get inviteChooseTravelerError;

  /// No description provided for @inviteJoinTripStepOne.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre le voyage 1/2'**
  String get inviteJoinTripStepOne;

  /// No description provided for @inviteJoinTripStepTwo.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre le voyage 2/2'**
  String get inviteJoinTripStepTwo;

  /// No description provided for @inviteChooseTravelerWarning.
  ///
  /// In fr, this message translates to:
  /// **'Tu ne pourras faire ce choix qu’une seule fois pour ce voyage.'**
  String get inviteChooseTravelerWarning;

  /// No description provided for @inviteWhoAreYouInTrip.
  ///
  /// In fr, this message translates to:
  /// **'Qui es-tu dans ce voyage ?'**
  String get inviteWhoAreYouInTrip;

  /// No description provided for @inviteCupidonSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Tu pourras liker des participants du voyage.'**
  String get inviteCupidonSubtitle;

  /// No description provided for @inviteBack.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get inviteBack;

  /// No description provided for @inviteJoinWithCurrentProfileHint.
  ///
  /// In fr, this message translates to:
  /// **'Tu ne te trouves pas ou tu n’es pas sûr ? Rejoins avec ton profil actuel. Les admins pourront réattribuer ta place plus tard si besoin.'**
  String get inviteJoinWithCurrentProfileHint;

  /// No description provided for @inviteJoinWithCurrentProfileAction.
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec mon profil actuel'**
  String get inviteJoinWithCurrentProfileAction;

  /// No description provided for @inviteOptionsEditableAfterJoinInfo.
  ///
  /// In fr, this message translates to:
  /// **'Tu pourras modifier toutes ces options à tout moment après avoir rejoint le voyage.'**
  String get inviteOptionsEditableAfterJoinInfo;

  /// No description provided for @commonContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get commonContinue;

  /// No description provided for @commonConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get commonConfirm;

  /// No description provided for @inviteInvalidLink.
  ///
  /// In fr, this message translates to:
  /// **'Lien d’invitation invalide.'**
  String get inviteInvalidLink;

  /// No description provided for @inviteBackToTrips.
  ///
  /// In fr, this message translates to:
  /// **'Retour aux voyages'**
  String get inviteBackToTrips;

  /// No description provided for @inviteJoinThisTrip.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre ce voyage'**
  String get inviteJoinThisTrip;

  /// No description provided for @inviteJoinTripWithTitle.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre le voyage « {title} »'**
  String inviteJoinTripWithTitle(Object title);

  /// No description provided for @inviteChecking.
  ///
  /// In fr, this message translates to:
  /// **'Vérification de l’invitation…'**
  String get inviteChecking;

  /// No description provided for @inviteJoiningInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Ajout au voyage en cours…'**
  String get inviteJoiningInProgress;

  /// No description provided for @inviteJoiningTripWithTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajout au voyage « {title} » en cours…'**
  String inviteJoiningTripWithTitle(Object title);

  /// No description provided for @inviteAccepted.
  ///
  /// In fr, this message translates to:
  /// **'Invitation acceptée'**
  String get inviteAccepted;

  /// No description provided for @inviteAcceptedSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Tu fais partie du voyage. Les autres participants te verront avec ton compte.'**
  String get inviteAcceptedSubtitle;

  /// No description provided for @inviteOpenTrip.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le voyage'**
  String get inviteOpenTrip;

  /// No description provided for @inviteSeeMyTrips.
  ///
  /// In fr, this message translates to:
  /// **'Voir mes voyages'**
  String get inviteSeeMyTrips;

  /// No description provided for @inviteCouldNotFinalizeJoin.
  ///
  /// In fr, this message translates to:
  /// **'Nous n’avons pas pu finaliser ton entrée dans le voyage. Vérifie ta connexion et réessaie, ou demande un nouveau lien à l’organisateur.'**
  String get inviteCouldNotFinalizeJoin;

  /// No description provided for @commonRetry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get commonRetry;

  /// No description provided for @inviteJoinATrip.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre un voyage'**
  String get inviteJoinATrip;

  /// No description provided for @inviteOpenFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d’ouvrir l’invitation pour le moment. Vérifie ta connexion ou demande un nouveau lien à l’organisateur.'**
  String get inviteOpenFailed;

  /// No description provided for @commonToday.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd’hui'**
  String get commonToday;

  /// No description provided for @commonYesterday.
  ///
  /// In fr, this message translates to:
  /// **'Hier'**
  String get commonYesterday;

  /// No description provided for @activitiesTabSuggestions.
  ///
  /// In fr, this message translates to:
  /// **'Suggestions'**
  String get activitiesTabSuggestions;

  /// No description provided for @activitiesTabPlanned.
  ///
  /// In fr, this message translates to:
  /// **'Planifiées'**
  String get activitiesTabPlanned;

  /// No description provided for @activitiesTabAgenda.
  ///
  /// In fr, this message translates to:
  /// **'Agenda'**
  String get activitiesTabAgenda;

  /// No description provided for @activitiesVote.
  ///
  /// In fr, this message translates to:
  /// **'Voter'**
  String get activitiesVote;

  /// No description provided for @activitiesUnvote.
  ///
  /// In fr, this message translates to:
  /// **'Retirer mon vote'**
  String get activitiesUnvote;

  /// No description provided for @activitiesNoSuggestion.
  ///
  /// In fr, this message translates to:
  /// **'Aucune suggestion.'**
  String get activitiesNoSuggestion;

  /// No description provided for @activitiesNoPlanned.
  ///
  /// In fr, this message translates to:
  /// **'Aucune activité planifiée.'**
  String get activitiesNoPlanned;

  /// No description provided for @activitiesSuggestAction.
  ///
  /// In fr, this message translates to:
  /// **'Proposer'**
  String get activitiesSuggestAction;

  /// No description provided for @activitiesPreviousWeek.
  ///
  /// In fr, this message translates to:
  /// **'Semaine précédente'**
  String get activitiesPreviousWeek;

  /// No description provided for @activitiesNextWeek.
  ///
  /// In fr, this message translates to:
  /// **'Semaine suivante'**
  String get activitiesNextWeek;

  /// No description provided for @activitiesNoPlannedThisDay.
  ///
  /// In fr, this message translates to:
  /// **'Aucune activité planifiée ce jour.'**
  String get activitiesNoPlannedThisDay;

  /// No description provided for @activitiesUntitled.
  ///
  /// In fr, this message translates to:
  /// **'Sans titre'**
  String get activitiesUntitled;

  /// No description provided for @activitiesProposedBy.
  ///
  /// In fr, this message translates to:
  /// **'Proposé par {name}'**
  String activitiesProposedBy(Object name);

  /// No description provided for @activitiesAdded.
  ///
  /// In fr, this message translates to:
  /// **'Activité ajoutée'**
  String get activitiesAdded;

  /// No description provided for @activitiesLinkMustStartHttp.
  ///
  /// In fr, this message translates to:
  /// **'Le lien doit commencer par http(s)://'**
  String get activitiesLinkMustStartHttp;

  /// No description provided for @activitiesNewActivity.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle activité'**
  String get activitiesNewActivity;

  /// No description provided for @activitiesCategory.
  ///
  /// In fr, this message translates to:
  /// **'Catégorie'**
  String get activitiesCategory;

  /// No description provided for @activitiesLabel.
  ///
  /// In fr, this message translates to:
  /// **'Libellé'**
  String get activitiesLabel;

  /// No description provided for @activitiesLabelRequired.
  ///
  /// In fr, this message translates to:
  /// **'Libellé obligatoire'**
  String get activitiesLabelRequired;

  /// No description provided for @activitiesLink.
  ///
  /// In fr, this message translates to:
  /// **'Lien (site, billetterie, ...)'**
  String get activitiesLink;

  /// No description provided for @activitiesAddress.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du lieu (trajet depuis le voyage)'**
  String get activitiesAddress;

  /// No description provided for @activitiesAddressHint.
  ///
  /// In fr, this message translates to:
  /// **'Pour calculer distance et durée en voiture'**
  String get activitiesAddressHint;

  /// No description provided for @activitiesComments.
  ///
  /// In fr, this message translates to:
  /// **'Commentaires'**
  String get activitiesComments;

  /// No description provided for @linkInvalidExample.
  ///
  /// In fr, this message translates to:
  /// **'Lien invalide (ex: https://...)'**
  String get linkInvalidExample;

  /// No description provided for @shoppingDeleteCheckedTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer les éléments cochés ?'**
  String get shoppingDeleteCheckedTitle;

  /// No description provided for @shoppingDeleteCheckedContent.
  ///
  /// In fr, this message translates to:
  /// **'{count} élément(s) sera(ont) supprimé(s) définitivement. Cette opération est irréversible.'**
  String shoppingDeleteCheckedContent(Object count);

  /// No description provided for @shoppingDeletedCount.
  ///
  /// In fr, this message translates to:
  /// **'{count} élément(s) supprimé(s).'**
  String shoppingDeletedCount(Object count);

  /// No description provided for @shoppingFilterHelpTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Aide des filtres'**
  String get shoppingFilterHelpTooltip;

  /// No description provided for @shoppingEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Liste de courses vide'**
  String get shoppingEmptyTitle;

  /// No description provided for @shoppingEmptySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Appuyez sur + pour ajouter un article.'**
  String get shoppingEmptySubtitle;

  /// No description provided for @shoppingFiltersTitle.
  ///
  /// In fr, this message translates to:
  /// **'Filtres de la liste'**
  String get shoppingFiltersTitle;

  /// No description provided for @shoppingFiltersHelpBody.
  ///
  /// In fr, this message translates to:
  /// **'Le filtre affiche uniquement les éléments correspondant à l’état sélectionné.'**
  String get shoppingFiltersHelpBody;

  /// No description provided for @shoppingFilterAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous les éléments'**
  String get shoppingFilterAll;

  /// No description provided for @shoppingFilterTodo.
  ///
  /// In fr, this message translates to:
  /// **'À acheter'**
  String get shoppingFilterTodo;

  /// No description provided for @shoppingFilterDone.
  ///
  /// In fr, this message translates to:
  /// **'Déjà achetés'**
  String get shoppingFilterDone;

  /// No description provided for @shoppingFilterClaimedByMe.
  ///
  /// In fr, this message translates to:
  /// **'Claimés par moi'**
  String get shoppingFilterClaimedByMe;

  /// No description provided for @shoppingTravelerFallback.
  ///
  /// In fr, this message translates to:
  /// **'Voyageur'**
  String get shoppingTravelerFallback;

  /// No description provided for @shoppingClaimRemoveMine.
  ///
  /// In fr, this message translates to:
  /// **'Retirer mon claim'**
  String get shoppingClaimRemoveMine;

  /// No description provided for @shoppingClaimAlreadyBy.
  ///
  /// In fr, this message translates to:
  /// **'Déjà claimé par {name}'**
  String shoppingClaimAlreadyBy(Object name);

  /// No description provided for @shoppingClaimTake.
  ///
  /// In fr, this message translates to:
  /// **'Je m\'en occupe'**
  String get shoppingClaimTake;

  /// No description provided for @activityCategorySport.
  ///
  /// In fr, this message translates to:
  /// **'Sport'**
  String get activityCategorySport;

  /// No description provided for @activityCategoryHiking.
  ///
  /// In fr, this message translates to:
  /// **'Randonnée'**
  String get activityCategoryHiking;

  /// No description provided for @activityCategoryShopping.
  ///
  /// In fr, this message translates to:
  /// **'Shopping'**
  String get activityCategoryShopping;

  /// No description provided for @activityCategoryVisit.
  ///
  /// In fr, this message translates to:
  /// **'Visite'**
  String get activityCategoryVisit;

  /// No description provided for @activityCategoryRestaurant.
  ///
  /// In fr, this message translates to:
  /// **'Restaurant'**
  String get activityCategoryRestaurant;

  /// No description provided for @activityCategoryCafe.
  ///
  /// In fr, this message translates to:
  /// **'Café'**
  String get activityCategoryCafe;

  /// No description provided for @activityCategoryMuseum.
  ///
  /// In fr, this message translates to:
  /// **'Musée'**
  String get activityCategoryMuseum;

  /// No description provided for @activityCategoryShow.
  ///
  /// In fr, this message translates to:
  /// **'Spectacle'**
  String get activityCategoryShow;

  /// No description provided for @activityCategoryNightlife.
  ///
  /// In fr, this message translates to:
  /// **'Soirée'**
  String get activityCategoryNightlife;

  /// No description provided for @activityCategoryKaraoke.
  ///
  /// In fr, this message translates to:
  /// **'Karaoké'**
  String get activityCategoryKaraoke;

  /// No description provided for @activityCategoryGames.
  ///
  /// In fr, this message translates to:
  /// **'Jeux'**
  String get activityCategoryGames;

  /// No description provided for @activityCategoryBeach.
  ///
  /// In fr, this message translates to:
  /// **'Plage'**
  String get activityCategoryBeach;

  /// No description provided for @activityCategoryPark.
  ///
  /// In fr, this message translates to:
  /// **'Parc'**
  String get activityCategoryPark;

  /// No description provided for @activityCategoryTransport.
  ///
  /// In fr, this message translates to:
  /// **'Transport'**
  String get activityCategoryTransport;

  /// No description provided for @activityCategoryAccommodation.
  ///
  /// In fr, this message translates to:
  /// **'Hébergement'**
  String get activityCategoryAccommodation;

  /// No description provided for @activityCategoryWellness.
  ///
  /// In fr, this message translates to:
  /// **'Bien-être'**
  String get activityCategoryWellness;

  /// No description provided for @activityCategoryCooking.
  ///
  /// In fr, this message translates to:
  /// **'Cuisine'**
  String get activityCategoryCooking;

  /// No description provided for @activityCategoryWorkshop.
  ///
  /// In fr, this message translates to:
  /// **'Atelier'**
  String get activityCategoryWorkshop;

  /// No description provided for @activityCategoryMarket.
  ///
  /// In fr, this message translates to:
  /// **'Marché'**
  String get activityCategoryMarket;

  /// No description provided for @activityCategoryMeeting.
  ///
  /// In fr, this message translates to:
  /// **'Réunion'**
  String get activityCategoryMeeting;

  /// No description provided for @activitiesUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Activité mise à jour'**
  String get activitiesUpdated;

  /// No description provided for @activitiesDeleteTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer cette activité ?'**
  String get activitiesDeleteTitle;

  /// No description provided for @activitiesDeleteBody.
  ///
  /// In fr, this message translates to:
  /// **'« {label} » sera supprimée.'**
  String activitiesDeleteBody(Object label);

  /// No description provided for @activitiesDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Activité supprimée'**
  String get activitiesDeleted;

  /// No description provided for @activitiesNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Activité introuvable.'**
  String get activitiesNotFound;

  /// No description provided for @activitiesPlannedDateHelp.
  ///
  /// In fr, this message translates to:
  /// **'Date prévue'**
  String get activitiesPlannedDateHelp;

  /// No description provided for @activitiesAddressCardTitle.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du lieu'**
  String get activitiesAddressCardTitle;

  /// No description provided for @activitiesFromLodgingByCar.
  ///
  /// In fr, this message translates to:
  /// **'Depuis le logement (voiture)'**
  String get activitiesFromLodgingByCar;

  /// No description provided for @commonDash.
  ///
  /// In fr, this message translates to:
  /// **'—'**
  String get commonDash;

  /// No description provided for @activitiesDone.
  ///
  /// In fr, this message translates to:
  /// **'Activité faite'**
  String get activitiesDone;

  /// No description provided for @activitiesPlannedUnset.
  ///
  /// In fr, this message translates to:
  /// **'Prévue le : non renseignée'**
  String get activitiesPlannedUnset;

  /// No description provided for @activitiesPlannedOn.
  ///
  /// In fr, this message translates to:
  /// **'Prévue le {date}'**
  String activitiesPlannedOn(Object date);

  /// No description provided for @activitiesRemovePlannedDate.
  ///
  /// In fr, this message translates to:
  /// **'Retirer la date prévue'**
  String get activitiesRemovePlannedDate;

  /// No description provided for @activitiesLinkPreviewAfterSave.
  ///
  /// In fr, this message translates to:
  /// **'L\'aperçu du lien sera mis à jour après enregistrement.'**
  String get activitiesLinkPreviewAfterSave;

  /// No description provided for @activitiesRouteCalculating.
  ///
  /// In fr, this message translates to:
  /// **'Calcul en cours depuis l\'adresse du voyage.'**
  String get activitiesRouteCalculating;

  /// No description provided for @activitiesRouteDistance.
  ///
  /// In fr, this message translates to:
  /// **'Distance : {distance}'**
  String activitiesRouteDistance(Object distance);

  /// No description provided for @activitiesRouteDuration.
  ///
  /// In fr, this message translates to:
  /// **'Durée : {duration}'**
  String activitiesRouteDuration(Object duration);

  /// No description provided for @activitiesRouteCalculated.
  ///
  /// In fr, this message translates to:
  /// **'Trajet calculé.'**
  String get activitiesRouteCalculated;

  /// No description provided for @activitiesRouteMissingTripAddress.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du voyage manquante : renseignez-la dans l\'aperçu du voyage.'**
  String get activitiesRouteMissingTripAddress;

  /// No description provided for @activitiesRouteNoResult.
  ///
  /// In fr, this message translates to:
  /// **'Aucun trajet trouvé.'**
  String get activitiesRouteNoResult;

  /// No description provided for @activitiesRouteNoResultWithDetail.
  ///
  /// In fr, this message translates to:
  /// **'Aucun trajet trouvé ({detail}).'**
  String activitiesRouteNoResultWithDetail(Object detail);

  /// No description provided for @activitiesRouteError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de calculer le trajet.'**
  String get activitiesRouteError;

  /// No description provided for @activitiesRouteErrorWithMessage.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de calculer le trajet : {message}.'**
  String activitiesRouteErrorWithMessage(Object message);

  /// No description provided for @activitiesRouteStatus.
  ///
  /// In fr, this message translates to:
  /// **'Statut : {status}'**
  String activitiesRouteStatus(Object status);

  /// No description provided for @mealsNoMeal.
  ///
  /// In fr, this message translates to:
  /// **'Aucun repas'**
  String get mealsNoMeal;

  /// No description provided for @mealsPressPlusToPlan.
  ///
  /// In fr, this message translates to:
  /// **'Appuyez sur + pour planifier un repas.'**
  String get mealsPressPlusToPlan;

  /// No description provided for @dayPartMorning.
  ///
  /// In fr, this message translates to:
  /// **'Petit-déjeuner'**
  String get dayPartMorning;

  /// No description provided for @dayPartMidday.
  ///
  /// In fr, this message translates to:
  /// **'Déjeuner'**
  String get dayPartMidday;

  /// No description provided for @dayPartEvening.
  ///
  /// In fr, this message translates to:
  /// **'Dîner'**
  String get dayPartEvening;

  /// No description provided for @mealMomentBreakfast.
  ///
  /// In fr, this message translates to:
  /// **'Petit-déjeuner'**
  String get mealMomentBreakfast;

  /// No description provided for @mealMomentLunch.
  ///
  /// In fr, this message translates to:
  /// **'Déjeuner'**
  String get mealMomentLunch;

  /// No description provided for @mealMomentDinner.
  ///
  /// In fr, this message translates to:
  /// **'Dîner'**
  String get mealMomentDinner;

  /// No description provided for @commonUnsavedChangesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifications non enregistrées'**
  String get commonUnsavedChangesTitle;

  /// No description provided for @mealUnsavedChangesBody.
  ///
  /// In fr, this message translates to:
  /// **'Tu as des changements non enregistrés. Quitter sans enregistrer ?'**
  String get mealUnsavedChangesBody;

  /// No description provided for @commonStay.
  ///
  /// In fr, this message translates to:
  /// **'Rester'**
  String get commonStay;

  /// No description provided for @mealDateHelp.
  ///
  /// In fr, this message translates to:
  /// **'Date du repas'**
  String get mealDateHelp;

  /// No description provided for @mealCreated.
  ///
  /// In fr, this message translates to:
  /// **'Repas créé'**
  String get mealCreated;

  /// No description provided for @mealUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Repas mis à jour'**
  String get mealUpdated;

  /// No description provided for @mealDeleteTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce repas ?'**
  String get mealDeleteTitle;

  /// No description provided for @mealDeleteBody.
  ///
  /// In fr, this message translates to:
  /// **'Ce repas sera supprimé définitivement.'**
  String get mealDeleteBody;

  /// No description provided for @mealDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Repas supprimé'**
  String get mealDeleted;

  /// No description provided for @mealNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Repas introuvable'**
  String get mealNotFound;

  /// No description provided for @mealNew.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau repas'**
  String get mealNew;

  /// No description provided for @mealEdit.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le repas'**
  String get mealEdit;

  /// No description provided for @commonUnsaved.
  ///
  /// In fr, this message translates to:
  /// **'non enregistré'**
  String get commonUnsaved;

  /// No description provided for @commonDate.
  ///
  /// In fr, this message translates to:
  /// **'Date'**
  String get commonDate;

  /// No description provided for @commonChoose.
  ///
  /// In fr, this message translates to:
  /// **'Choisir'**
  String get commonChoose;

  /// No description provided for @mealMomentLabel.
  ///
  /// In fr, this message translates to:
  /// **'Moment'**
  String get mealMomentLabel;

  /// No description provided for @mealParticipantsCount.
  ///
  /// In fr, this message translates to:
  /// **'Participants ({count})'**
  String mealParticipantsCount(Object count);

  /// No description provided for @commonAuto.
  ///
  /// In fr, this message translates to:
  /// **'Auto'**
  String get commonAuto;

  /// No description provided for @commonAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get commonAll;

  /// No description provided for @commonNone.
  ///
  /// In fr, this message translates to:
  /// **'Aucun'**
  String get commonNone;

  /// No description provided for @commonSelectAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout sélectionner'**
  String get commonSelectAll;

  /// No description provided for @mealChefLongPressHint.
  ///
  /// In fr, this message translates to:
  /// **'Appui long sur un participant sélectionné pour définir ou retirer le chef.'**
  String get mealChefLongPressHint;

  /// No description provided for @mealComponentsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Composants du repas'**
  String get mealComponentsTitle;

  /// No description provided for @mealAddComponent.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un composant'**
  String get mealAddComponent;

  /// No description provided for @mealAddComponentWithKind.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter {kind}'**
  String mealAddComponentWithKind(Object kind);

  /// No description provided for @mealAddComponentHint.
  ///
  /// In fr, this message translates to:
  /// **'Ajoute un composant (entrée, plat, dessert, autre).'**
  String get mealAddComponentHint;

  /// No description provided for @mealIngredientsCount.
  ///
  /// In fr, this message translates to:
  /// **'{count} ingrédient(s)'**
  String mealIngredientsCount(Object count);

  /// No description provided for @mealComponentLockedByMe.
  ///
  /// In fr, this message translates to:
  /// **'Vous avez verrouillé ce composant.'**
  String get mealComponentLockedByMe;

  /// No description provided for @mealComponentLockedByUser.
  ///
  /// In fr, this message translates to:
  /// **'{user} est en train de modifier la recette.'**
  String mealComponentLockedByUser(Object user);

  /// No description provided for @mealComponentChangedUnsaved.
  ///
  /// In fr, this message translates to:
  /// **'Composant modifié non enregistré'**
  String get mealComponentChangedUnsaved;

  /// No description provided for @mealDeleteComponent.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce composant'**
  String get mealDeleteComponent;

  /// No description provided for @mealModeCooked.
  ///
  /// In fr, this message translates to:
  /// **'Repas cuisiné'**
  String get mealModeCooked;

  /// No description provided for @mealModeRestaurant.
  ///
  /// In fr, this message translates to:
  /// **'Restaurant'**
  String get mealModeRestaurant;

  /// No description provided for @mealModePotluck.
  ///
  /// In fr, this message translates to:
  /// **'Auberge espagnole'**
  String get mealModePotluck;

  /// No description provided for @mealModeCookedLabel.
  ///
  /// In fr, this message translates to:
  /// **'On cuisine !'**
  String get mealModeCookedLabel;

  /// No description provided for @mealModeRestaurantLabel.
  ///
  /// In fr, this message translates to:
  /// **'On va au restaurant !'**
  String get mealModeRestaurantLabel;

  /// No description provided for @mealModePotluckLabel.
  ///
  /// In fr, this message translates to:
  /// **'Chacun ramène un truc !'**
  String get mealModePotluckLabel;

  /// No description provided for @mealRestaurantLinkLabel.
  ///
  /// In fr, this message translates to:
  /// **'Lien du restaurant'**
  String get mealRestaurantLinkLabel;

  /// No description provided for @mealRestaurantLinkHint.
  ///
  /// In fr, this message translates to:
  /// **'Ajoute un lien pour afficher l\'aperçu du restaurant.'**
  String get mealRestaurantLinkHint;

  /// No description provided for @mealPotluckTitle.
  ///
  /// In fr, this message translates to:
  /// **'Liste des apports'**
  String get mealPotluckTitle;

  /// No description provided for @mealPotluckEmptyHint.
  ///
  /// In fr, this message translates to:
  /// **'Ajoute des éléments (boisson, entrée, plat, dessert, etc.).'**
  String get mealPotluckEmptyHint;

  /// No description provided for @mealPotluckAddItemTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un élément'**
  String get mealPotluckAddItemTitle;

  /// No description provided for @mealPotluckItemLabel.
  ///
  /// In fr, this message translates to:
  /// **'Élément'**
  String get mealPotluckItemLabel;

  /// No description provided for @mealPotluckQuantityLabel.
  ///
  /// In fr, this message translates to:
  /// **'Quantité (unités)'**
  String get mealPotluckQuantityLabel;

  /// No description provided for @mealPotluckCategorySalty.
  ///
  /// In fr, this message translates to:
  /// **'Salé'**
  String get mealPotluckCategorySalty;

  /// No description provided for @mealPotluckCategorySweet.
  ///
  /// In fr, this message translates to:
  /// **'Sucré'**
  String get mealPotluckCategorySweet;

  /// No description provided for @mealPotluckCategorySoft.
  ///
  /// In fr, this message translates to:
  /// **'Soft'**
  String get mealPotluckCategorySoft;

  /// No description provided for @mealPotluckCategoryAlcohol.
  ///
  /// In fr, this message translates to:
  /// **'Alcool'**
  String get mealPotluckCategoryAlcohol;

  /// No description provided for @mealPotluckMaxItemsReached.
  ///
  /// In fr, this message translates to:
  /// **'Maximum 5 éléments.'**
  String get mealPotluckMaxItemsReached;

  /// No description provided for @mealPotluckCreateRowsHint.
  ///
  /// In fr, this message translates to:
  /// **'{currentCount}/{maxCount} éléments ajoutés'**
  String mealPotluckCreateRowsHint(int currentCount, int maxCount);

  /// No description provided for @commonSaving.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrement...'**
  String get commonSaving;

  /// No description provided for @mealComponentKindEntree.
  ///
  /// In fr, this message translates to:
  /// **'Entrée'**
  String get mealComponentKindEntree;

  /// No description provided for @mealComponentKindMain.
  ///
  /// In fr, this message translates to:
  /// **'Plat'**
  String get mealComponentKindMain;

  /// No description provided for @mealComponentKindDessert.
  ///
  /// In fr, this message translates to:
  /// **'Dessert'**
  String get mealComponentKindDessert;

  /// No description provided for @commonMe.
  ///
  /// In fr, this message translates to:
  /// **'Moi'**
  String get commonMe;

  /// No description provided for @commonUnknown.
  ///
  /// In fr, this message translates to:
  /// **'Inconnu'**
  String get commonUnknown;

  /// No description provided for @commonRequired.
  ///
  /// In fr, this message translates to:
  /// **'Obligatoire'**
  String get commonRequired;

  /// No description provided for @expenseGroupSelectAtLeastOne.
  ///
  /// In fr, this message translates to:
  /// **'Coche au moins une personne qui voit ce poste'**
  String get expenseGroupSelectAtLeastOne;

  /// No description provided for @expenseGroupUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Poste mis à jour'**
  String get expenseGroupUpdated;

  /// No description provided for @expenseGroupCreated.
  ///
  /// In fr, this message translates to:
  /// **'Poste créé'**
  String get expenseGroupCreated;

  /// No description provided for @expenseGroupEditTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le poste'**
  String get expenseGroupEditTitle;

  /// No description provided for @expenseGroupNewTitle.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau poste de dépenses'**
  String get expenseGroupNewTitle;

  /// No description provided for @expenseGroupNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom du poste'**
  String get expenseGroupNameLabel;

  /// No description provided for @expenseGroupNameHint.
  ///
  /// In fr, this message translates to:
  /// **'Ex. Commun, Cadeau, Week-end…'**
  String get expenseGroupNameHint;

  /// No description provided for @expenseGroupWhoSees.
  ///
  /// In fr, this message translates to:
  /// **'Qui voit ce poste'**
  String get expenseGroupWhoSees;

  /// No description provided for @expenseGroupCanSee.
  ///
  /// In fr, this message translates to:
  /// **'Voit le poste'**
  String get expenseGroupCanSee;

  /// No description provided for @expenseGroupCreateAction.
  ///
  /// In fr, this message translates to:
  /// **'Créer le poste'**
  String get expenseGroupCreateAction;

  /// No description provided for @expensesAddExpenseTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une dépense'**
  String get expensesAddExpenseTooltip;

  /// No description provided for @expensesCreatePostFirst.
  ///
  /// In fr, this message translates to:
  /// **'Crée d\'abord un poste de dépenses (icône dossier dans l\'en-tête).'**
  String get expensesCreatePostFirst;

  /// No description provided for @expensesPostsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Postes de dépenses'**
  String get expensesPostsTitle;

  /// No description provided for @expensesNoPostYet.
  ///
  /// In fr, this message translates to:
  /// **'Aucun poste de dépenses pour l\'instant. Utilise l\'icône dossier en haut pour en créer un.'**
  String get expensesNoPostYet;

  /// No description provided for @expensesBalancesTab.
  ///
  /// In fr, this message translates to:
  /// **'Équilibres'**
  String get expensesBalancesTab;

  /// No description provided for @expensesDeletePostTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce poste ?'**
  String get expensesDeletePostTitle;

  /// No description provided for @expensesDeletePostBody.
  ///
  /// In fr, this message translates to:
  /// **'Le poste « {title} » et toutes ses opérations seront supprimés.'**
  String expensesDeletePostBody(Object title);

  /// No description provided for @expensesPostDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Poste supprimé'**
  String get expensesPostDeleted;

  /// No description provided for @expensesNoOperationInPost.
  ///
  /// In fr, this message translates to:
  /// **'Aucune opération dans ce poste.'**
  String get expensesNoOperationInPost;

  /// No description provided for @expensesYouOwe.
  ///
  /// In fr, this message translates to:
  /// **'Tu dois {amount} à {label}'**
  String expensesYouOwe(Object amount, Object label);

  /// No description provided for @expensesOwesYou.
  ///
  /// In fr, this message translates to:
  /// **'{label} te doit {amount}'**
  String expensesOwesYou(Object label, Object amount);

  /// No description provided for @expensesGivesTo.
  ///
  /// In fr, this message translates to:
  /// **'{from} donne {amount} à {to}'**
  String expensesGivesTo(Object from, Object amount, Object to);

  /// No description provided for @expensesMyTotalSpend.
  ///
  /// In fr, this message translates to:
  /// **'Mes dépenses totales'**
  String get expensesMyTotalSpend;

  /// No description provided for @expensesTripTotalCost.
  ///
  /// In fr, this message translates to:
  /// **'Coût total du séjour'**
  String get expensesTripTotalCost;

  /// No description provided for @expensesBalancesByCurrency.
  ///
  /// In fr, this message translates to:
  /// **'Soldes (par devise)'**
  String get expensesBalancesByCurrency;

  /// No description provided for @expensesAddToSeeBreakdown.
  ///
  /// In fr, this message translates to:
  /// **'Ajoute des dépenses pour voir la répartition.'**
  String get expensesAddToSeeBreakdown;

  /// No description provided for @expensesToReceive.
  ///
  /// In fr, this message translates to:
  /// **'À recevoir'**
  String get expensesToReceive;

  /// No description provided for @expensesToPay.
  ///
  /// In fr, this message translates to:
  /// **'À payer'**
  String get expensesToPay;

  /// No description provided for @expensesBalanced.
  ///
  /// In fr, this message translates to:
  /// **'Équilibré'**
  String get expensesBalanced;

  /// No description provided for @expensesSuggestedReimbursements.
  ///
  /// In fr, this message translates to:
  /// **'Remboursements suggérés'**
  String get expensesSuggestedReimbursements;

  /// No description provided for @expensesSuggestedReimbursementsHint.
  ///
  /// In fr, this message translates to:
  /// **'Nombre minimal de virements pour équilibrer les comptes (par devise).'**
  String get expensesSuggestedReimbursementsHint;

  /// No description provided for @expensesNoCalculationYet.
  ///
  /// In fr, this message translates to:
  /// **'Pas encore de calcul.'**
  String get expensesNoCalculationYet;

  /// No description provided for @expensesYouOweNothing.
  ///
  /// In fr, this message translates to:
  /// **'Tu ne dois rien à personne 😎'**
  String get expensesYouOweNothing;

  /// No description provided for @expensesMarkReimbursementDoneSemantics.
  ///
  /// In fr, this message translates to:
  /// **'Marquer ce remboursement comme effectué'**
  String get expensesMarkReimbursementDoneSemantics;

  /// No description provided for @expensesUnmarkReimbursementSemantics.
  ///
  /// In fr, this message translates to:
  /// **'Annuler le marquage de ce remboursement'**
  String get expensesUnmarkReimbursementSemantics;

  /// No description provided for @expensesDeleteExpenseTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer cette dépense ?'**
  String get expensesDeleteExpenseTitle;

  /// No description provided for @expensesDeleteExpenseBody.
  ///
  /// In fr, this message translates to:
  /// **'« {title} » sera supprimée.'**
  String expensesDeleteExpenseBody(Object title);

  /// No description provided for @expensesExpenseDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Dépense supprimée'**
  String get expensesExpenseDeleted;

  /// No description provided for @expensesChoosePayer.
  ///
  /// In fr, this message translates to:
  /// **'Choisis qui a payé'**
  String get expensesChoosePayer;

  /// No description provided for @expensesNoAllowedTraveler.
  ///
  /// In fr, this message translates to:
  /// **'Aucun voyageur autorisé dans ce poste.'**
  String get expensesNoAllowedTraveler;

  /// No description provided for @expensesInvalidPayerForPost.
  ///
  /// In fr, this message translates to:
  /// **'Payeur invalide pour ce poste'**
  String get expensesInvalidPayerForPost;

  /// No description provided for @expensesSelectAtLeastOneParticipant.
  ///
  /// In fr, this message translates to:
  /// **'Coche au moins un participant'**
  String get expensesSelectAtLeastOneParticipant;

  /// No description provided for @expensesParticipantOutOfScope.
  ///
  /// In fr, this message translates to:
  /// **'Participant hors périmètre du poste'**
  String get expensesParticipantOutOfScope;

  /// No description provided for @expensesInvalidAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant invalide'**
  String get expensesInvalidAmount;

  /// No description provided for @expensesCustomAmountValidation.
  ///
  /// In fr, this message translates to:
  /// **'Pour « Montants », chaque part doit être valide et la somme doit égaler le total.'**
  String get expensesCustomAmountValidation;

  /// No description provided for @expensesExpenseUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Dépense mise à jour'**
  String get expensesExpenseUpdated;

  /// No description provided for @expensesExpenseDetailTitle.
  ///
  /// In fr, this message translates to:
  /// **'Détail de la dépense'**
  String get expensesExpenseDetailTitle;

  /// No description provided for @expensesNoAllowedTravelerInPostHint.
  ///
  /// In fr, this message translates to:
  /// **'Aucun voyageur n\'est autorisé dans ce poste : modifie le poste ou le voyage pour pouvoir ajuster le partage.'**
  String get expensesNoAllowedTravelerInPostHint;

  /// No description provided for @expensesAmountLabel.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get expensesAmountLabel;

  /// No description provided for @expensesCurrencyLabel.
  ///
  /// In fr, this message translates to:
  /// **'Devise'**
  String get expensesCurrencyLabel;

  /// No description provided for @expensesCurrencyEuro.
  ///
  /// In fr, this message translates to:
  /// **'Euro (EUR)'**
  String get expensesCurrencyEuro;

  /// No description provided for @expensesCurrencyDollar.
  ///
  /// In fr, this message translates to:
  /// **'Dollar (USD)'**
  String get expensesCurrencyDollar;

  /// No description provided for @expensesPaidByLabel.
  ///
  /// In fr, this message translates to:
  /// **'Payé par'**
  String get expensesPaidByLabel;

  /// No description provided for @expensesPaidByWithLabel.
  ///
  /// In fr, this message translates to:
  /// **'Payé par {label}'**
  String expensesPaidByWithLabel(Object label);

  /// No description provided for @expensesDateLabel.
  ///
  /// In fr, this message translates to:
  /// **'Date de la dépense'**
  String get expensesDateLabel;

  /// No description provided for @expensesAmountSplit.
  ///
  /// In fr, this message translates to:
  /// **'Partage du montant'**
  String get expensesAmountSplit;

  /// No description provided for @expensesSplitEqual.
  ///
  /// In fr, this message translates to:
  /// **'Équitablement'**
  String get expensesSplitEqual;

  /// No description provided for @expensesSplitCustomAmounts.
  ///
  /// In fr, this message translates to:
  /// **'Montants'**
  String get expensesSplitCustomAmounts;

  /// No description provided for @expensesSaveChanges.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer les modifications'**
  String get expensesSaveChanges;

  /// No description provided for @expensesExpenseSaved.
  ///
  /// In fr, this message translates to:
  /// **'Dépense enregistrée'**
  String get expensesExpenseSaved;

  /// No description provided for @expensesNewExpenseTitle.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle dépense'**
  String get expensesNewExpenseTitle;

  /// No description provided for @expensesNoAllowedTravelerInPostForShare.
  ///
  /// In fr, this message translates to:
  /// **'Aucun voyageur autorisé dans ce poste pour partager une dépense.'**
  String get expensesNoAllowedTravelerInPostForShare;

  /// No description provided for @chatSendImpossible.
  ///
  /// In fr, this message translates to:
  /// **'Envoi impossible : {error}'**
  String chatSendImpossible(Object error);

  /// No description provided for @chatNoRecentEmoji.
  ///
  /// In fr, this message translates to:
  /// **'Aucun emoji récent'**
  String get chatNoRecentEmoji;

  /// No description provided for @chatUserNotConnected.
  ///
  /// In fr, this message translates to:
  /// **'Utilisateur non connecté'**
  String get chatUserNotConnected;

  /// No description provided for @chatReactionImpossible.
  ///
  /// In fr, this message translates to:
  /// **'Réaction impossible : {error}'**
  String chatReactionImpossible(Object error);

  /// No description provided for @chatEditImpossible.
  ///
  /// In fr, this message translates to:
  /// **'Modification impossible : {error}'**
  String chatEditImpossible(Object error);

  /// No description provided for @chatDeleteMessageConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce message ?'**
  String get chatDeleteMessageConfirm;

  /// No description provided for @chatDeleteImpossible.
  ///
  /// In fr, this message translates to:
  /// **'Suppression impossible : {error}'**
  String chatDeleteImpossible(Object error);

  /// No description provided for @chatCopied.
  ///
  /// In fr, this message translates to:
  /// **'Copié'**
  String get chatCopied;

  /// No description provided for @chatEmptyState.
  ///
  /// In fr, this message translates to:
  /// **'Aucun message pour l\'instant. Écris le premier pour lancer la discussion.'**
  String get chatEmptyState;

  /// No description provided for @chatMessageHint.
  ///
  /// In fr, this message translates to:
  /// **'Message…'**
  String get chatMessageHint;

  /// No description provided for @chatSend.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get chatSend;

  /// No description provided for @chatCopy.
  ///
  /// In fr, this message translates to:
  /// **'Copier'**
  String get chatCopy;

  /// No description provided for @chatReactWithEmoji.
  ///
  /// In fr, this message translates to:
  /// **'Réagir avec {emoji}'**
  String chatReactWithEmoji(Object emoji);

  /// No description provided for @chatMoreEmojis.
  ///
  /// In fr, this message translates to:
  /// **'Plus d\'émojis'**
  String get chatMoreEmojis;

  /// No description provided for @chatGoBottom.
  ///
  /// In fr, this message translates to:
  /// **'Aller en bas'**
  String get chatGoBottom;

  /// No description provided for @chatEditMessageTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le message'**
  String get chatEditMessageTitle;

  /// No description provided for @appCopyright.
  ///
  /// In fr, this message translates to:
  /// **'© 2026 Bruno Chappe'**
  String get appCopyright;

  /// No description provided for @tripsMemberCount.
  ///
  /// In fr, this message translates to:
  /// **'{count} membre(s)'**
  String tripsMemberCount(Object count);

  /// No description provided for @commonNotProvided.
  ///
  /// In fr, this message translates to:
  /// **'Non renseignée'**
  String get commonNotProvided;

  /// No description provided for @tripDateRangeBetween.
  ///
  /// In fr, this message translates to:
  /// **'Du {start} au {end}'**
  String tripDateRangeBetween(Object start, Object end);

  /// No description provided for @tripDateRangeFrom.
  ///
  /// In fr, this message translates to:
  /// **'À partir du {start}'**
  String tripDateRangeFrom(Object start);

  /// No description provided for @tripDateRangeUntil.
  ///
  /// In fr, this message translates to:
  /// **'Jusqu\'au {end}'**
  String tripDateRangeUntil(Object end);

  /// No description provided for @tripStayPresenceDatesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Dates de présence'**
  String get tripStayPresenceDatesTitle;

  /// No description provided for @tripMemberStayOptionsTab.
  ///
  /// In fr, this message translates to:
  /// **'Options'**
  String get tripMemberStayOptionsTab;

  /// No description provided for @tripStayMealsIncludedHint.
  ///
  /// In fr, this message translates to:
  /// **'Ces repas sont inclus dans tes dates de voyage.'**
  String get tripStayMealsIncludedHint;

  /// No description provided for @tripStayFromLabel.
  ///
  /// In fr, this message translates to:
  /// **'Du'**
  String get tripStayFromLabel;

  /// No description provided for @tripStayToLabel.
  ///
  /// In fr, this message translates to:
  /// **'au'**
  String get tripStayToLabel;

  /// No description provided for @tripOverviewTileParticipants.
  ///
  /// In fr, this message translates to:
  /// **'Participants'**
  String get tripOverviewTileParticipants;

  /// No description provided for @tripOverviewTileActivities.
  ///
  /// In fr, this message translates to:
  /// **'Planning'**
  String get tripOverviewTileActivities;

  /// No description provided for @tripOverviewTileRooms.
  ///
  /// In fr, this message translates to:
  /// **'Chambres'**
  String get tripOverviewTileRooms;

  /// No description provided for @tripOverviewTileCars.
  ///
  /// In fr, this message translates to:
  /// **'Voitures'**
  String get tripOverviewTileCars;

  /// No description provided for @tripOverviewTileCarpool.
  ///
  /// In fr, this message translates to:
  /// **'Covoiturage'**
  String get tripOverviewTileCarpool;

  /// No description provided for @tripOverviewTileGames.
  ///
  /// In fr, this message translates to:
  /// **'Jeux'**
  String get tripOverviewTileGames;

  /// No description provided for @tripGamesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Jeux'**
  String get tripGamesTitle;

  /// No description provided for @tripBoardGamesTab.
  ///
  /// In fr, this message translates to:
  /// **'Jeux de société'**
  String get tripBoardGamesTab;

  /// No description provided for @tripGamesEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucun jeu pour le moment.'**
  String get tripGamesEmpty;

  /// No description provided for @tripGamesAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un jeu'**
  String get tripGamesAdd;

  /// No description provided for @tripGamesAddTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un jeu'**
  String get tripGamesAddTitle;

  /// No description provided for @tripGamesEditTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le jeu'**
  String get tripGamesEditTitle;

  /// No description provided for @tripGamesUrlLabel.
  ///
  /// In fr, this message translates to:
  /// **'URL'**
  String get tripGamesUrlLabel;

  /// No description provided for @tripGamesDeleteTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le jeu'**
  String get tripGamesDeleteTitle;

  /// No description provided for @tripGamesDeleteBody.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce jeu de société ?'**
  String get tripGamesDeleteBody;

  /// No description provided for @tripGamesAdded.
  ///
  /// In fr, this message translates to:
  /// **'Jeu ajouté'**
  String get tripGamesAdded;

  /// No description provided for @tripGamesUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Jeu mis à jour'**
  String get tripGamesUpdated;

  /// No description provided for @tripGamesDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Jeu supprimé'**
  String get tripGamesDeleted;

  /// No description provided for @tripOverviewTopTabAnnouncements.
  ///
  /// In fr, this message translates to:
  /// **'Annonces'**
  String get tripOverviewTopTabAnnouncements;

  /// No description provided for @tripAnnouncementsPageTitle.
  ///
  /// In fr, this message translates to:
  /// **'Annonces des organisateurs'**
  String get tripAnnouncementsPageTitle;

  /// No description provided for @tripAnnouncementsEmptyState.
  ///
  /// In fr, this message translates to:
  /// **'Aucune annonce pour le moment.'**
  String get tripAnnouncementsEmptyState;

  /// No description provided for @tripAnnouncementsInputHint.
  ///
  /// In fr, this message translates to:
  /// **'Écrire une annonce...'**
  String get tripAnnouncementsInputHint;

  /// No description provided for @tripAnnouncementsDeleteConfirmBody.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer cette annonce ?'**
  String get tripAnnouncementsDeleteConfirmBody;

  /// No description provided for @tripAnnouncementsEditTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier l\'annonce'**
  String get tripAnnouncementsEditTitle;

  /// No description provided for @tripOverviewTopTabExpenses.
  ///
  /// In fr, this message translates to:
  /// **'Dépenses'**
  String get tripOverviewTopTabExpenses;

  /// No description provided for @tripOverviewTileNoActivitiesToday.
  ///
  /// In fr, this message translates to:
  /// **'Pas d\'activités prévues aujourd\'hui'**
  String get tripOverviewTileNoActivitiesToday;

  /// No description provided for @tripOverviewTileNoAssignedRoom.
  ///
  /// In fr, this message translates to:
  /// **'Aucune chambre attribuée'**
  String get tripOverviewTileNoAssignedRoom;

  /// No description provided for @tripOverviewTileComingSoon.
  ///
  /// In fr, this message translates to:
  /// **'[À venir]'**
  String get tripOverviewTileComingSoon;

  /// No description provided for @tripCarpoolDriverLabel.
  ///
  /// In fr, this message translates to:
  /// **'Conducteur'**
  String get tripCarpoolDriverLabel;

  /// No description provided for @tripCarpoolShoppingFlag.
  ///
  /// In fr, this message translates to:
  /// **'Courses'**
  String get tripCarpoolShoppingFlag;

  /// No description provided for @tripOverviewCarpoolPassengerSummary.
  ///
  /// In fr, this message translates to:
  /// **'Tu pars avec {driverName} à {departureTime} de {meetingPointAddress}'**
  String tripOverviewCarpoolPassengerSummary(
      Object driverName, Object departureTime, Object meetingPointAddress);

  /// No description provided for @tripOverviewCarpoolPassengerSummaryNoMeetingPoint.
  ///
  /// In fr, this message translates to:
  /// **'Tu pars avec {driverName} à {departureTime}'**
  String tripOverviewCarpoolPassengerSummaryNoMeetingPoint(
      Object driverName, Object departureTime);

  /// No description provided for @tripOverviewCarpoolDriverSummary.
  ///
  /// In fr, this message translates to:
  /// **'Tu enmènes {passengerNames}, départ à {departureTime}'**
  String tripOverviewCarpoolDriverSummary(
      Object passengerNames, Object departureTime);

  /// No description provided for @tripOverviewCarpoolShoppingTeamLine.
  ///
  /// In fr, this message translates to:
  /// **'Vous faites partie de l\'équipe qui fait les courses !'**
  String get tripOverviewCarpoolShoppingTeamLine;

  /// No description provided for @tripCarpoolTileNoAssignment.
  ///
  /// In fr, this message translates to:
  /// **'Aucune affectation'**
  String get tripCarpoolTileNoAssignment;

  /// No description provided for @tripCarpoolUnassignedWarningTitle.
  ///
  /// In fr, this message translates to:
  /// **'Affectation incomplète'**
  String get tripCarpoolUnassignedWarningTitle;

  /// No description provided for @tripCarpoolSelfUnassignedTitle.
  ///
  /// In fr, this message translates to:
  /// **'Pas de covoiturage'**
  String get tripCarpoolSelfUnassignedTitle;

  /// No description provided for @tripCarpoolSelfUnassignedBody.
  ///
  /// In fr, this message translates to:
  /// **'Rejoignez une voiture en tant que passager ou proposez-vous comme conducteur.'**
  String get tripCarpoolSelfUnassignedBody;

  /// No description provided for @tripCarpoolJoinTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre ce covoiturage'**
  String get tripCarpoolJoinTooltip;

  /// No description provided for @tripCarpoolLeaveTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Quitter ce covoiturage'**
  String get tripCarpoolLeaveTooltip;

  /// No description provided for @tripCarpoolJoinedSelfSnack.
  ///
  /// In fr, this message translates to:
  /// **'Vous êtes affecté à ce covoiturage.'**
  String get tripCarpoolJoinedSelfSnack;

  /// No description provided for @tripCarpoolLeftSelfSnack.
  ///
  /// In fr, this message translates to:
  /// **'Vous n\'êtes plus dans ce covoiturage.'**
  String get tripCarpoolLeftSelfSnack;

  /// No description provided for @tripCarpoolSelfAssignmentDriverBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Les conducteurs ne peuvent pas rejoindre ou quitter un covoiturage depuis cette liste.'**
  String get tripCarpoolSelfAssignmentDriverBlocked;

  /// No description provided for @tripCarpoolSelfAssignmentNotMember.
  ///
  /// In fr, this message translates to:
  /// **'Seuls les participants au voyage peuvent modifier leur affectation.'**
  String get tripCarpoolSelfAssignmentNotMember;

  /// No description provided for @tripCarpoolUnassignedWarningBody.
  ///
  /// In fr, this message translates to:
  /// **'{count} participant(s) n\'est/ne sont assigné(s) à aucune voiture.'**
  String tripCarpoolUnassignedWarningBody(int count);

  /// No description provided for @tripCarpoolGlobalMeetupTitle.
  ///
  /// In fr, this message translates to:
  /// **'Rendez-vous courses'**
  String get tripCarpoolGlobalMeetupTitle;

  /// No description provided for @tripCarpoolGlobalMeetupLabel.
  ///
  /// In fr, this message translates to:
  /// **'Lien Google Maps'**
  String get tripCarpoolGlobalMeetupLabel;

  /// No description provided for @tripCarpoolOpenMapsLink.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le lien Google Maps'**
  String get tripCarpoolOpenMapsLink;

  /// No description provided for @tripCarpoolEmptyState.
  ///
  /// In fr, this message translates to:
  /// **'Aucun covoiturage pour le moment.'**
  String get tripCarpoolEmptyState;

  /// No description provided for @tripCarpoolListTitle.
  ///
  /// In fr, this message translates to:
  /// **'Covoiturages'**
  String get tripCarpoolListTitle;

  /// No description provided for @tripCarpoolNavigateToMeetingPoint.
  ///
  /// In fr, this message translates to:
  /// **'Naviguer vers le point de rendez-vous'**
  String get tripCarpoolNavigateToMeetingPoint;

  /// No description provided for @tripCarpoolCreateAction.
  ///
  /// In fr, this message translates to:
  /// **'Proposer un covoiturage'**
  String get tripCarpoolCreateAction;

  /// No description provided for @tripCarpoolCreateTitle.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau covoiturage'**
  String get tripCarpoolCreateTitle;

  /// No description provided for @tripCarpoolEditTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le covoiturage'**
  String get tripCarpoolEditTitle;

  /// No description provided for @tripCarpoolMeetingPointLabel.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du point de rendez-vous'**
  String get tripCarpoolMeetingPointLabel;

  /// No description provided for @tripCarpoolNearestTransitStopLabel.
  ///
  /// In fr, this message translates to:
  /// **'Point transport en commun le plus proche'**
  String get tripCarpoolNearestTransitStopLabel;

  /// No description provided for @tripCarpoolDepartureAtLabel.
  ///
  /// In fr, this message translates to:
  /// **'Date et heure de départ'**
  String get tripCarpoolDepartureAtLabel;

  /// No description provided for @tripCarpoolMeetingHour.
  ///
  /// In fr, this message translates to:
  /// **'Heure de RDV : {hour}'**
  String tripCarpoolMeetingHour(Object hour);

  /// No description provided for @tripCarpoolAvailableSeatsLabel.
  ///
  /// In fr, this message translates to:
  /// **'Places disponibles'**
  String get tripCarpoolAvailableSeatsLabel;

  /// No description provided for @tripCarpoolRemainingSeats.
  ///
  /// In fr, this message translates to:
  /// **'{count} place(s) restante(s)'**
  String tripCarpoolRemainingSeats(int count);

  /// No description provided for @tripCarpoolFull.
  ///
  /// In fr, this message translates to:
  /// **'Complet'**
  String get tripCarpoolFull;

  /// No description provided for @tripCarpoolGoesShoppingLabel.
  ///
  /// In fr, this message translates to:
  /// **'Voiture désignée pour faire les courses'**
  String get tripCarpoolGoesShoppingLabel;

  /// No description provided for @tripCarpoolPassengersTitle.
  ///
  /// In fr, this message translates to:
  /// **'Participants transportés'**
  String get tripCarpoolPassengersTitle;

  /// No description provided for @tripCarpoolTemporaryParticipantLabel.
  ///
  /// In fr, this message translates to:
  /// **'Voyageur prévu'**
  String get tripCarpoolTemporaryParticipantLabel;

  /// No description provided for @tripCarpoolAlreadyAssignedTo.
  ///
  /// In fr, this message translates to:
  /// **'Déjà affecté à {carpoolLabel}'**
  String tripCarpoolAlreadyAssignedTo(Object carpoolLabel);

  /// No description provided for @tripCarpoolSeatsInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Le nombre de places doit être au moins 1.'**
  String get tripCarpoolSeatsInvalid;

  /// No description provided for @tripCarpoolSeatsExceeded.
  ///
  /// In fr, this message translates to:
  /// **'Le nombre de participants dépasse les places disponibles.'**
  String get tripCarpoolSeatsExceeded;

  /// No description provided for @tripCarpoolCreated.
  ///
  /// In fr, this message translates to:
  /// **'Covoiturage créé'**
  String get tripCarpoolCreated;

  /// No description provided for @tripCarpoolUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Covoiturage mis à jour'**
  String get tripCarpoolUpdated;

  /// No description provided for @tripCarpoolDeleteTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce covoiturage ?'**
  String get tripCarpoolDeleteTitle;

  /// No description provided for @tripCarpoolDeleteBody.
  ///
  /// In fr, this message translates to:
  /// **'Ce covoiturage sera supprimé définitivement.'**
  String get tripCarpoolDeleteBody;

  /// No description provided for @tripCarpoolDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Covoiturage supprimé'**
  String get tripCarpoolDeleted;

  /// No description provided for @tripCarpoolCreateComingSoon.
  ///
  /// In fr, this message translates to:
  /// **'Création de covoiturage disponible dans le prochain lot.'**
  String get tripCarpoolCreateComingSoon;

  /// No description provided for @tripCarpoolEditComingSoon.
  ///
  /// In fr, this message translates to:
  /// **'Édition de covoiturage disponible dans le prochain lot.'**
  String get tripCarpoolEditComingSoon;

  /// No description provided for @tripOverviewMyRoom.
  ///
  /// In fr, this message translates to:
  /// **'Ma chambre'**
  String get tripOverviewMyRoom;

  /// No description provided for @tripOverviewMyRooms.
  ///
  /// In fr, this message translates to:
  /// **'Mes chambres'**
  String get tripOverviewMyRooms;

  /// No description provided for @tripOverviewTabSummary.
  ///
  /// In fr, this message translates to:
  /// **'Aperçu'**
  String get tripOverviewTabSummary;

  /// No description provided for @tripOverviewTabAccommodationSuggestions.
  ///
  /// In fr, this message translates to:
  /// **'Hébergements'**
  String get tripOverviewTabAccommodationSuggestions;

  /// No description provided for @tripOverviewNoAccommodationSuggestions.
  ///
  /// In fr, this message translates to:
  /// **'Aucune suggestion d\'hébergement. Ajoute une activité \"Hébergement\" ici ou depuis le planning pour la voir apparaître.'**
  String get tripOverviewNoAccommodationSuggestions;

  /// No description provided for @tripOverviewNoRestaurantSuggestions.
  ///
  /// In fr, this message translates to:
  /// **'Aucune suggestion de restaurant. Ajoute une activité \"Restaurant\" ici ou depuis le planning pour la voir apparaître.'**
  String get tripOverviewNoRestaurantSuggestions;

  /// No description provided for @cupidonPopupTitle.
  ///
  /// In fr, this message translates to:
  /// **'Tu as un match'**
  String get cupidonPopupTitle;

  /// No description provided for @cupidonPopupViewMatchesAction.
  ///
  /// In fr, this message translates to:
  /// **'Voir mes matchs'**
  String get cupidonPopupViewMatchesAction;

  /// No description provided for @cupidonPopupUnknownMember.
  ///
  /// In fr, this message translates to:
  /// **'Quelqu\'un'**
  String get cupidonPopupUnknownMember;

  /// No description provided for @accountHelpSupport.
  ///
  /// In fr, this message translates to:
  /// **'Aide et support'**
  String get accountHelpSupport;

  /// No description provided for @helpSupportTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aide et support'**
  String get helpSupportTitle;

  /// No description provided for @helpSupportIntro.
  ///
  /// In fr, this message translates to:
  /// **'Merci d\'utiliser Planerz ! Cette application est développée et maintenue par une seule personne, avec passion. N\'hésite pas à partager tes retours, signaler un bug ou proposer une idée.'**
  String get helpSupportIntro;

  /// No description provided for @helpSupportContactIntro.
  ///
  /// In fr, this message translates to:
  /// **'Pour toute question, suggestion ou bug, plusieurs solutions :'**
  String get helpSupportContactIntro;

  /// No description provided for @helpSupportVersionLabel.
  ///
  /// In fr, this message translates to:
  /// **'Version'**
  String get helpSupportVersionLabel;

  /// No description provided for @helpSupportReleaseNotesLabel.
  ///
  /// In fr, this message translates to:
  /// **'Notes de version'**
  String get helpSupportReleaseNotesLabel;

  /// No description provided for @helpSupportGithubLabel.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir un ticket sur GitHub'**
  String get helpSupportGithubLabel;

  /// No description provided for @helpSupportEmailLabel.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer un mail'**
  String get helpSupportEmailLabel;

  /// No description provided for @helpSupportAboutLinkLabel.
  ///
  /// In fr, this message translates to:
  /// **'Contacter le développeur'**
  String get helpSupportAboutLinkLabel;

  /// No description provided for @updateRequiredTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mise à jour disponible'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredBody.
  ///
  /// In fr, this message translates to:
  /// **'Une nouvelle version de Planerz est disponible. Vous devez mettre à jour l\'application pour continuer à l\'utiliser.'**
  String get updateRequiredBody;

  /// No description provided for @updateRequiredCurrentVersion.
  ///
  /// In fr, this message translates to:
  /// **'Version actuelle'**
  String get updateRequiredCurrentVersion;

  /// No description provided for @updateRequiredNewVersion.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle version'**
  String get updateRequiredNewVersion;

  /// No description provided for @updateRequiredDownloading.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement en cours…'**
  String get updateRequiredDownloading;

  /// No description provided for @updateRequiredOpeningInstaller.
  ///
  /// In fr, this message translates to:
  /// **'Ouverture de l’installation…'**
  String get updateRequiredOpeningInstaller;

  /// No description provided for @updateRequiredRetryButton.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get updateRequiredRetryButton;

  /// No description provided for @updateRequiredOpenLinkButton.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le lien'**
  String get updateRequiredOpenLinkButton;

  /// No description provided for @updateRequiredDownloadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Échec du téléchargement.'**
  String get updateRequiredDownloadFailed;

  /// No description provided for @updateRequiredInstallerFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d’ouvrir l’installateur.'**
  String get updateRequiredInstallerFailed;

  /// No description provided for @updateRequiredAutomaticUpdateWarningIntro.
  ///
  /// In fr, this message translates to:
  /// **'En cas de problème avec la mise à jour automatique, désinstallez l’application et repassez par la version web à l’adresse suivante :'**
  String get updateRequiredAutomaticUpdateWarningIntro;

  /// No description provided for @globalAnnouncementsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Annonces générales'**
  String get globalAnnouncementsTitle;

  /// No description provided for @globalAnnouncementsEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucune annonce pour le moment.'**
  String get globalAnnouncementsEmpty;

  /// No description provided for @globalAnnouncementsBellTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Voir les annonces'**
  String get globalAnnouncementsBellTooltip;

  /// No description provided for @globalAnnouncementsDismissTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Masquer cette annonce'**
  String get globalAnnouncementsDismissTooltip;

  /// No description provided for @globalAnnouncementsRestoreHiddenTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Réafficher les annonces masquées'**
  String get globalAnnouncementsRestoreHiddenTooltip;

  /// No description provided for @globalAnnouncementsRestoreHiddenSnackBar.
  ///
  /// In fr, this message translates to:
  /// **'Les annonces masquées sont à nouveau visibles.'**
  String get globalAnnouncementsRestoreHiddenSnackBar;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'US':
            return AppLocalizationsEnUs();
        }
        break;
      }
    case 'fr':
      {
        switch (locale.countryCode) {
          case 'FR':
            return AppLocalizationsFrFr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
