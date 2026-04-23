// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get languageFrench => 'Français';

  @override
  String get languageEnglishUs => 'Anglais (États-Unis)';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get legalInfoTitle => 'Informations légales';

  @override
  String get legalInfoLoadError =>
      'Impossible de charger les informations légales.';

  @override
  String get legalMentionsTab => 'Mentions légales';

  @override
  String get legalPrivacyTab => 'Vie privée / RGPD';

  @override
  String get signInAnimatedLabelOutings => 'SORTIES';

  @override
  String get signInAnimatedLabelWeekends => 'WEEK-ENDS';

  @override
  String get signInAnimatedLabelTrips => 'VOYAGES';

  @override
  String get signInSubtitleStatic => 'ENTRE AMIS';

  @override
  String get signInLoading => 'Connexion...';

  @override
  String get signInContinueWithGoogle => 'Continuer avec Google';

  @override
  String get accountTitle => 'Mon compte';

  @override
  String get accountCropProfilePhotoTitle => 'Recadrer la photo de profil';

  @override
  String get accountPhotoUpdated => 'Photo de profil mise à jour';

  @override
  String get accountPhotoDeleted => 'Photo de profil supprimée';

  @override
  String get accountRemovePhotoDialogTitle => 'Supprimer la photo ?';

  @override
  String get accountRemovePhotoDialogBody => 'La photo de profil sera retirée.';

  @override
  String get accountUpdated => 'Compte mis à jour';

  @override
  String get accountNotificationsEnabled => 'Notifications activées.';

  @override
  String get accountNotificationsEnableError =>
      'Impossible d\'activer les notifications.';

  @override
  String get accountLanguageUpdated => 'Langue mise à jour';

  @override
  String get accountPhotoActionsTooltip => 'Actions photo de profil';

  @override
  String get accountChooseFromGallery => 'Choisir dans la galerie';

  @override
  String get accountTakePhoto => 'Prendre une photo';

  @override
  String get accountEmailUnavailable => 'E-mail indisponible';

  @override
  String get accountNameLabel => 'Nom du compte';

  @override
  String get accountNameHint => 'Ex : Alex';

  @override
  String get accountNameMaxLength => 'Maximum 60 caractères';

  @override
  String get accountSaveNameTooltip => 'Enregistrer le nom';

  @override
  String get accountNameFallbackHelp =>
      'Si vide, le nom affiché sera votre e-mail.';

  @override
  String get accountFoodAllergens => 'Allergènes alimentaires';

  @override
  String get accountCupidonSpace => 'Espace Cupidon';

  @override
  String get accountCupidonHistory => 'Historique des matchs';

  @override
  String get accountPreferencesSectionTitle => 'Préférences';

  @override
  String get accountColorPalette => 'Palette de couleurs';

  @override
  String get accountLanguageTitle => 'Langue';

  @override
  String get accountLanguageSubtitle => 'Langue de l\'application';

  @override
  String get accountAutoOpenCurrentTripTitle =>
      'Ouvrir automatiquement le voyage en cours';

  @override
  String get accountAutoOpenCurrentTripSubtitle =>
      'Si un seul voyage est en cours aujourd\'hui, il s\'ouvre au lancement.';

  @override
  String get accountAutoOpenCurrentTripEnabled =>
      'Ouverture auto du voyage activée';

  @override
  String get accountAutoOpenCurrentTripDisabled =>
      'Ouverture auto du voyage désactivée';

  @override
  String get accountEnabling => 'Activation en cours...';

  @override
  String get accountEnableNotifications => 'Activer les notifications';

  @override
  String get accountWebPushHelp =>
      'Sur iPhone : installe l\'app sur l\'écran d\'accueil, puis active ici.';

  @override
  String accountPhotoError(Object error) {
    return 'Erreur photo : $error';
  }

  @override
  String accountPhotoDeleteError(Object error) {
    return 'Erreur suppression photo : $error';
  }

  @override
  String accountUpdateError(Object error) {
    return 'Erreur mise à jour compte : $error';
  }

  @override
  String accountLanguageUpdateError(Object error) {
    return 'Erreur mise à jour langue : $error';
  }

  @override
  String accountPreferenceUpdateError(Object error) {
    return 'Erreur mise à jour préférence : $error';
  }

  @override
  String get tripsJoinWithInviteTooltip =>
      'Rejoindre avec un code d\'invitation';

  @override
  String get tripsNewTripTooltip => 'Nouveau voyage';

  @override
  String get tripsMyTrips => 'Mes voyages';

  @override
  String get tripsEmptyState =>
      'Aucun voyage pour le moment.\\nCrée ton premier voyage.';

  @override
  String get tripsTimelinePast => 'Passés';

  @override
  String get tripsTimelineOngoing => 'En cours';

  @override
  String get tripsTimelineUpcoming => 'À venir';

  @override
  String get tripsEmptyPast => 'Aucun voyage passé.';

  @override
  String get tripsEmptyOngoing => 'Aucun voyage en cours.';

  @override
  String get tripsEmptyUpcoming => 'Aucun voyage à venir.';

  @override
  String get tripsCreateDialogTitle => 'Créer un voyage';

  @override
  String get tripsTitleLabel => 'Titre';

  @override
  String get tripsDestinationLabel => 'Destination';

  @override
  String get tripsStartDateLabel => 'Date de début';

  @override
  String get tripsEndDateLabel => 'Date de fin';

  @override
  String get tripsCreateValidationRequired =>
      'Titre et destination obligatoires';

  @override
  String get tripsCreateValidationDateOrder =>
      'La date de fin doit être le même jour ou après la date de début';

  @override
  String get tripsCreateAction => 'Créer';

  @override
  String get tripsDeleteDialogTitle => 'Supprimer ce voyage ?';

  @override
  String tripsDeleteDialogBody(Object tripTitle) {
    return 'Cette action est définitive.\n\nVoyage : $tripTitle';
  }

  @override
  String get tripsDeleted => 'Voyage supprimé';

  @override
  String tripsDeleteError(Object error) {
    return 'Erreur suppression : $error';
  }

  @override
  String tripsFirestoreError(Object error) {
    return 'Erreur Firestore : $error';
  }

  @override
  String get tripsJoinCodeNotFound => 'Ce code d\'invitation est introuvable.';

  @override
  String get tripsJoinCodeNotValid =>
      'Ce code d\'invitation n\'est plus valide.';

  @override
  String get tripsJoinCodeInvalid => 'Code d\'invitation invalide.';

  @override
  String get tripsJoinCodeUnauthenticated =>
      'Connecte-toi pour rejoindre un voyage.';

  @override
  String get tripsJoinCodeRequired => 'Saisis le code d\'invitation.';

  @override
  String get tripsJoinCodeDialogTitle => 'Code d\'invitation';

  @override
  String get tripsJoinCodeDialogHelp =>
      'Colle le code envoyé par l\'organisateur du voyage (pas le lien, uniquement le code).';

  @override
  String get tripsJoinCodeLabel => 'Code';

  @override
  String get tripsJoinCodeAction => 'Rejoindre';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonClose => 'Fermer';

  @override
  String commonErrorWithDetails(Object error) {
    return 'Erreur : $error';
  }

  @override
  String get linkInvalid => 'Lien invalide';

  @override
  String get linkOpenImpossible => 'Impossible d\'ouvrir le lien';

  @override
  String get linkLabel => 'Lien';

  @override
  String get linkPreviewUnavailable => 'Aperçu indisponible pour ce lien.';

  @override
  String get nameSearchEmpty => 'Aucun nom ne correspond.';

  @override
  String get nameSearchLabel => 'Rechercher';

  @override
  String get nameSearchHint => 'Filtrer par nom';

  @override
  String get nameSearchClear => 'Effacer';

  @override
  String get locationOpenImpossible => 'Impossible d\'ouvrir la localisation';

  @override
  String get accountAllergensSaved => 'Allergènes enregistrés';

  @override
  String accountAllergensSaveError(Object error) {
    return 'Erreur enregistrement allergènes : $error';
  }

  @override
  String get accountDownloadApk => 'Télécharger l\'APK';

  @override
  String get accountSignOut => 'Se déconnecter';

  @override
  String paletteSaved(Object label) {
    return 'Palette $label enregistrée';
  }

  @override
  String get tripLabelGeneric => 'Voyage';

  @override
  String get tripNotFoundOrNoAccess => 'Voyage introuvable ou accès refusé.';

  @override
  String get tripBackToTrip => 'Retour au voyage';

  @override
  String get tripSettingsTitle => 'Paramètres du voyage';

  @override
  String tripMyRole(Object role) {
    return 'Mon rôle : $role';
  }

  @override
  String get tripRoleHierarchyHint =>
      'Hiérarchie des privilèges : créateur > admin > participant';

  @override
  String get roleOwner => 'Créateur';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleParticipant => 'Participant';

  @override
  String get tripSectionTrip => 'Voyage';

  @override
  String get tripSectionTripDescription =>
      'Règles liées aux informations générales du voyage.';

  @override
  String get tripSectionExpenses => 'Dépenses';

  @override
  String get tripSectionExpensesDescription =>
      'Gestion des droits sur les dépenses du voyage.';

  @override
  String get tripSectionActivities => 'Activités';

  @override
  String get tripSectionActivitiesDescription =>
      'Gestion des droits sur les activités proposées.';

  @override
  String get tripSectionMeals => 'Repas';

  @override
  String get tripSectionMealsDescription =>
      'Gestion des droits sur les repas et menus.';

  @override
  String get tripSectionShopping => 'Courses';

  @override
  String get tripSectionShoppingDescription =>
      'Gestion des droits sur les listes de courses.';

  @override
  String get tripSectionParticipants => 'Participants';

  @override
  String get tripSectionParticipantsDescription =>
      'Gestion des droits liés aux membres du voyage.';

  @override
  String get tripTabOverview => 'Aperçu';

  @override
  String get tripTabMessages => 'Messagerie';

  @override
  String get tripTabActivities => 'Activités';

  @override
  String get tripTabExpenses => 'Dépenses';

  @override
  String get tripTabMeals => 'Repas';

  @override
  String get tripTabShopping => 'Courses';

  @override
  String get tripCarsTitle => 'Voitures';

  @override
  String get tripCarsComingSoon => 'Covoiturage et véhicules. Contenu à venir.';

  @override
  String get tripMealsComingSoon => 'Planning des repas. Contenu à venir.';

  @override
  String get tripThisTrip => 'Ce voyage';

  @override
  String get tripStayDialogTitle => 'Mes dates sur le voyage';

  @override
  String get tripStayInvalidRange => 'La plage de dates est invalide.';

  @override
  String get tripStayOutOfTripBounds =>
      'Les dates doivent rester dans les dates du voyage.';

  @override
  String get tripStayUpdated => 'Dates mises à jour';

  @override
  String authErrorWithDetails(Object error) {
    return 'Erreur auth : $error';
  }

  @override
  String get foodAllergensAndIntolerances => 'Allergènes et intolérances';

  @override
  String get commonAddEllipsis => 'Ajouter...';

  @override
  String get commonMoreActions => 'Plus d\'actions';

  @override
  String get commonDone => 'Terminer';

  @override
  String get mealComponentTypeLabel => 'Type de composant';

  @override
  String get mealComponentNameOptionalLabel => 'Nom du composant (optionnel)';

  @override
  String mealContainsAllergen(Object allergen) {
    return 'Contient $allergen';
  }

  @override
  String mealMayContainAllergen(Object allergen) {
    return 'Peut contenir $allergen';
  }

  @override
  String get mealIngredientsTitle => 'Ingrédients';

  @override
  String get mealIngredientHint => 'Ingrédient...';

  @override
  String get mealAddIngredient => 'Ajouter un ingrédient';

  @override
  String get tripParticipantsTitle => 'Participants';

  @override
  String get tripParticipantsEmpty => 'Aucun participant.';

  @override
  String get tripParticipantsTraveler => 'Voyageur';

  @override
  String get tripParticipantsUser => 'Utilisateur';

  @override
  String get tripParticipantsThisParticipant => 'Ce participant';

  @override
  String tripParticipantsAdminRemoved(Object label) {
    return 'Rôle administrateur retiré ($label).';
  }

  @override
  String tripParticipantsAdminGranted(Object label) {
    return '$label est administrateur.';
  }

  @override
  String get tripParticipantsLikeSaveError =>
      'Impossible d\'enregistrer ce like pour le moment.';

  @override
  String get tripParticipantsAddPlannedTravelerTitle =>
      'Ajouter un voyageur prévu';

  @override
  String get tripParticipantsPlannedTravelerAdded => 'Voyageur prévu ajouté';

  @override
  String get tripParticipantsEditNameTitle => 'Modifier le nom';

  @override
  String get tripParticipantsNameUpdated => 'Nom mis à jour';

  @override
  String get tripParticipantsRemovePlannedTravelerTitle =>
      'Retirer ce voyageur prévu ?';

  @override
  String tripParticipantsRemovePlannedTravelerBody(Object label) {
    return '« $label » sera retiré des participants.';
  }

  @override
  String get tripParticipantsRemoveAction => 'Retirer';

  @override
  String get tripParticipantsPlannedTravelerRemoved => 'Voyageur prévu retiré';

  @override
  String get tripParticipantsRemoveParticipantTitle =>
      'Retirer ce participant ?';

  @override
  String tripParticipantsRemoveParticipantBody(Object label) {
    return 'Retirer « $label » du voyage ?';
  }

  @override
  String get tripParticipantsRemovedFromTrip => 'Participant retiré du voyage';

  @override
  String get tripParticipantsAdminHint =>
      'Clique sur l’icône à gauche d’un voyageur (prévu ou inscrit) pour lui donner ou retirer le rôle administrateur (sauf le créateur).';

  @override
  String get tripParticipantsUnlike => 'Retirer le like';

  @override
  String get tripParticipantsLike => 'Liker';

  @override
  String get tripParticipantsChangeRole => 'Changer le rôle';

  @override
  String get tripNotFound => 'Voyage introuvable';

  @override
  String get commonName => 'Nom';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get cupidonDefaultEnabled => 'Mode Cupidon activé par défaut';

  @override
  String get cupidonDefaultDisabled => 'Mode Cupidon désactivé par défaut';

  @override
  String get cupidonDeleteMatchTitle => 'Supprimer ce match ?';

  @override
  String cupidonDeleteMatchBody(Object memberLabel, Object tripTitle) {
    return 'Ce match avec $memberLabel (voyage \"$tripTitle\") sera retiré de ton historique.';
  }

  @override
  String get cupidonEnableByDefaultTitle => 'Activer Cupidon par défaut';

  @override
  String get cupidonEnableByDefaultSubtitle =>
      'Quand tu rejoins un nouveau voyage, cette valeur est préremplie.';

  @override
  String cupidonPreferenceLoadError(Object error) {
    return 'Erreur chargement préférence : $error';
  }

  @override
  String get cupidonMyMatches => 'Mes matchs';

  @override
  String get cupidonNoMatches => 'Aucun match enregistré pour le moment.';

  @override
  String get cupidonDeleteMatchTooltip => 'Supprimer ce match';

  @override
  String cupidonMatchesLoadError(Object error) {
    return 'Erreur chargement matchs : $error';
  }

  @override
  String get roomsCreate => 'Créer';

  @override
  String get roomsCreateTitle => 'Créer une chambre';

  @override
  String get roomsCreated => 'Chambre créée';

  @override
  String get roomsUpdated => 'Chambre mise à jour';

  @override
  String get roomsDeleted => 'Chambre supprimée';

  @override
  String get roomsUnnamedRoom => 'Chambre sans nom';

  @override
  String get roomsRoomLabel => 'Chambre';

  @override
  String get roomsDeleteTitle => 'Supprimer la chambre ?';

  @override
  String roomsDeleteBody(Object roomName) {
    return '« $roomName » sera supprimée.';
  }

  @override
  String get roomsNameRequired => 'Nom obligatoire';

  @override
  String get roomsAddBed => 'Ajouter un lit';

  @override
  String get roomsAddAtLeastOneBed => 'Ajoute au moins un lit';

  @override
  String get roomsBedCapacityExceeded => 'Capacité d\'un lit dépassée';

  @override
  String get roomsThisBedCapacityReached => 'Capacité de ce lit atteinte';

  @override
  String get roomsBedTypeSingle => 'Simple';

  @override
  String get roomsBedTypeDouble => 'Double';

  @override
  String get roomsBedKindRegular => 'Normal';

  @override
  String get roomsBedKindExtra => 'Appoint';

  @override
  String roomsAlreadyAssigned(Object roomName) {
    return 'Déjà affecté chambre $roomName';
  }

  @override
  String roomsBedLabel(Object index) {
    return 'Lit $index';
  }

  @override
  String roomsBedTypeAndKind(Object typeLabel, Object kindLabel) {
    return '$typeLabel · $kindLabel';
  }

  @override
  String roomsBedSummary(Object index, Object typeLabel, Object kindLabel) {
    return 'Lit $index · $typeLabel · $kindLabel';
  }

  @override
  String roomsBedLine(
      Object index, Object typeLabel, Object kindLabel, Object assignedLabel) {
    return 'Lit $index · $typeLabel · $kindLabel · $assignedLabel';
  }

  @override
  String get tripOverviewUpdated => 'Voyage mis à jour';

  @override
  String tripOverviewUpdateError(Object error) {
    return 'Erreur modification : $error';
  }

  @override
  String get tripOverviewInviteLinkCopied =>
      'Lien d\'invitation copié dans le presse-papiers';

  @override
  String tripOverviewInviteShareError(Object error) {
    return 'Erreur partage invitation : $error';
  }

  @override
  String get tripOverviewInviteCodeCopied =>
      'Code d\'invitation copié dans le presse-papiers';

  @override
  String tripOverviewInviteCodeCopyError(Object error) {
    return 'Erreur copie du code : $error';
  }

  @override
  String get cupidonEnabled => 'Mode Cupidon activé';

  @override
  String get cupidonDisabled => 'Mode Cupidon désactivé';

  @override
  String get cupidonEnableAction => 'Activer Cupidon';

  @override
  String get cupidonDisableAction => 'Désactiver Cupidon';

  @override
  String tripOverviewCupidonToggleError(Object error) {
    return 'Erreur mode Cupidon : $error';
  }

  @override
  String get tripOverviewCropBanner => 'Recadrer la bannière';

  @override
  String get tripOverviewBannerUpdated => 'Photo de bannière mise à jour';

  @override
  String get tripOverviewBannerRemoveBody =>
      'La bannière sera retirée du voyage.';

  @override
  String get tripOverviewActions => 'Actions voyage';

  @override
  String get tripOverviewPhotoActions => 'Actions photo';

  @override
  String get tripOverviewChangePhoto => 'Changer de photo';

  @override
  String get tripOverviewShareInvite => 'Partager invitation';

  @override
  String get tripOverviewCopyCode => 'Copier le code';

  @override
  String get tripOverviewEditTrip => 'Modifier le voyage';

  @override
  String get tripOverviewTitleRequired => 'Titre obligatoire';

  @override
  String get tripOverviewDestinationRequired => 'Destination obligatoire';

  @override
  String get tripOverviewAddressLabel => 'Adresse';

  @override
  String get tripOverviewAddressHint => '10 Rue de Rivoli, 75001 Paris';

  @override
  String get tripOverviewLinkLabel => 'Lien (Airbnb, Booking, site, ...)';

  @override
  String get tripOverviewLinkHint => 'https://...';

  @override
  String get tripOverviewLinkInvalid => 'Lien invalide (ex: https://...)';

  @override
  String get tripOverviewLinkMustStartWithHttp =>
      'Le lien doit commencer par http(s)://';

  @override
  String get tripOverviewOpenLocation => 'Ouvrir la localisation';

  @override
  String get tripOverviewUntitled => 'Sans titre';

  @override
  String get tripOverviewUnknownDestination => 'Destination inconnue';

  @override
  String get tripOverviewLeaveTripTitle => 'Quitter ce voyage ?';

  @override
  String get tripOverviewLeaveAction => 'Quitter';

  @override
  String get tripOverviewLeaveTripCardTitle => 'Quitter le voyage';

  @override
  String get tripOverviewLeaveTripDialogBody =>
      'Tu seras retiré de la liste des voyageurs. Sur chaque dépense partagée où tu participes, tu seras enlevé des participants : le partage sera recalculé pour les autres. Si tu étais seul sur une dépense, celle-ci sera supprimée.';

  @override
  String get tripOverviewLeaveTripCardBody =>
      'Tu pourras quitter même si les comptes ne sont pas à zéro. Tu seras alors retiré automatiquement de toutes les dépenses où tu es inclus (les autres voyageurs verront les parts mises à jour).';

  @override
  String get inviteTitle => 'Invitation';

  @override
  String get inviteJoinedTrip => 'Vous avez rejoint le voyage';

  @override
  String get inviteChooseTravelerError => 'Choisis un voyageur sur la liste.';

  @override
  String get inviteJoinTripStepOne => 'Rejoindre le voyage 1/2';

  @override
  String get inviteJoinTripStepTwo => 'Rejoindre le voyage 2/2';

  @override
  String get inviteChooseTravelerWarning =>
      'Tu ne pourras faire ce choix qu’une seule fois pour ce voyage.';

  @override
  String get inviteWhoAreYouInTrip => 'Qui es-tu dans ce voyage ?';

  @override
  String get inviteCupidonSubtitle =>
      'Tu pourras liker des participants du voyage.';

  @override
  String get inviteEditTravelerChoice => 'Modifier le choix du voyageur';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get commonConfirm => 'Valider';

  @override
  String get inviteInvalidLink => 'Lien d’invitation invalide.';

  @override
  String get inviteBackToTrips => 'Retour aux voyages';

  @override
  String get inviteJoinThisTrip => 'Rejoindre ce voyage';

  @override
  String inviteJoinTripWithTitle(Object title) {
    return 'Rejoindre le voyage « $title »';
  }

  @override
  String get inviteChecking => 'Vérification de l’invitation…';

  @override
  String get inviteJoiningInProgress => 'Ajout au voyage en cours…';

  @override
  String inviteJoiningTripWithTitle(Object title) {
    return 'Ajout au voyage « $title » en cours…';
  }

  @override
  String get inviteAccepted => 'Invitation acceptée';

  @override
  String get inviteAcceptedSubtitle =>
      'Tu fais partie du voyage. Les autres participants te verront avec ton compte.';

  @override
  String get inviteOpenTrip => 'Ouvrir le voyage';

  @override
  String get inviteSeeMyTrips => 'Voir mes voyages';

  @override
  String get inviteCouldNotFinalizeJoin =>
      'Nous n’avons pas pu finaliser ton entrée dans le voyage. Vérifie ta connexion et réessaie, ou demande un nouveau lien à l’organisateur.';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get inviteJoinATrip => 'Rejoindre un voyage';

  @override
  String get inviteOpenFailed =>
      'Impossible d’ouvrir l’invitation pour le moment. Vérifie ta connexion ou demande un nouveau lien à l’organisateur.';

  @override
  String get commonToday => 'Aujourd’hui';

  @override
  String get commonYesterday => 'Hier';

  @override
  String get activitiesTabSuggestions => 'Suggestions';

  @override
  String get activitiesTabPlanned => 'Planifiées';

  @override
  String get activitiesTabAgenda => 'Agenda';

  @override
  String get activitiesNoSuggestion => 'Aucune suggestion.';

  @override
  String get activitiesNoPlanned => 'Aucune activité planifiée.';

  @override
  String get activitiesSuggestAction => 'Proposer';

  @override
  String get activitiesPreviousWeek => 'Semaine précédente';

  @override
  String get activitiesNextWeek => 'Semaine suivante';

  @override
  String get activitiesNoPlannedThisDay => 'Aucune activité planifiée ce jour.';

  @override
  String get activitiesUntitled => 'Sans titre';

  @override
  String activitiesProposedBy(Object name) {
    return 'Proposé par $name';
  }

  @override
  String get activitiesAdded => 'Activité ajoutée';

  @override
  String get activitiesLinkMustStartHttp =>
      'Le lien doit commencer par http(s)://';

  @override
  String get activitiesNewActivity => 'Nouvelle activité';

  @override
  String get activitiesCategory => 'Catégorie';

  @override
  String get activitiesLabel => 'Libellé';

  @override
  String get activitiesLabelRequired => 'Libellé obligatoire';

  @override
  String get activitiesLink => 'Lien (site, billetterie, ...)';

  @override
  String get activitiesAddress => 'Adresse du lieu (trajet depuis le voyage)';

  @override
  String get activitiesAddressHint =>
      'Pour calculer distance et durée en voiture';

  @override
  String get activitiesLocked => 'Activité verrouillée';

  @override
  String get activitiesLockedHint =>
      'Si activée, seuls les admins peuvent modifier cette activité.';

  @override
  String get activitiesComments => 'Commentaires';

  @override
  String get linkInvalidExample => 'Lien invalide (ex: https://...)';

  @override
  String get shoppingDeleteCheckedTitle => 'Supprimer les éléments cochés ?';

  @override
  String shoppingDeleteCheckedContent(Object count) {
    return '$count élément(s) sera(ont) supprimé(s) définitivement. Cette opération est irréversible.';
  }

  @override
  String shoppingDeletedCount(Object count) {
    return '$count élément(s) supprimé(s).';
  }

  @override
  String get shoppingFilterHelpTooltip => 'Aide des filtres';

  @override
  String get shoppingEmptyTitle => 'Liste de courses vide';

  @override
  String get shoppingEmptySubtitle => 'Appuyez sur + pour ajouter un article.';

  @override
  String get shoppingFiltersTitle => 'Filtres de la liste';

  @override
  String get shoppingFiltersHelpBody =>
      'Le filtre affiche uniquement les éléments correspondant à l’état sélectionné.';

  @override
  String get shoppingFilterAll => 'Tous les éléments';

  @override
  String get shoppingFilterTodo => 'À acheter';

  @override
  String get shoppingFilterDone => 'Déjà achetés';

  @override
  String get shoppingFilterClaimedByMe => 'Claimés par moi';

  @override
  String get shoppingTravelerFallback => 'Voyageur';

  @override
  String get shoppingClaimRemoveMine => 'Retirer mon claim';

  @override
  String shoppingClaimAlreadyBy(Object name) {
    return 'Déjà claimé par $name';
  }

  @override
  String get shoppingClaimTake => 'Je m\'en occupe';

  @override
  String get activityCategorySport => 'Sport';

  @override
  String get activityCategoryHiking => 'Randonnée';

  @override
  String get activityCategoryShopping => 'Shopping';

  @override
  String get activityCategoryVisit => 'Visite';

  @override
  String get activityCategoryRestaurant => 'Restaurant';

  @override
  String get activitiesUpdated => 'Activité mise à jour';

  @override
  String get activitiesDeleteTitle => 'Supprimer cette activité ?';

  @override
  String activitiesDeleteBody(Object label) {
    return '« $label » sera supprimée.';
  }

  @override
  String get activitiesDeleted => 'Activité supprimée';

  @override
  String get activitiesNotFound => 'Activité introuvable.';

  @override
  String get activitiesPlannedDateHelp => 'Date prévue';

  @override
  String get activitiesAddressCardTitle => 'Adresse du lieu';

  @override
  String get activitiesFromLodgingByCar => 'Depuis le logement (voiture)';

  @override
  String get commonDash => '—';

  @override
  String get activitiesDone => 'Activité faite';

  @override
  String get activitiesPlannedUnset => 'Prévue le : non renseignée';

  @override
  String activitiesPlannedOn(Object date) {
    return 'Prévue le $date';
  }

  @override
  String get activitiesRemovePlannedDate => 'Retirer la date prévue';

  @override
  String get activitiesLinkPreviewAfterSave =>
      'L\'aperçu du lien sera mis à jour après enregistrement.';

  @override
  String get activitiesRouteCalculating =>
      'Calcul en cours depuis l\'adresse du voyage.';

  @override
  String activitiesRouteDistance(Object distance) {
    return 'Distance : $distance';
  }

  @override
  String activitiesRouteDuration(Object duration) {
    return 'Durée : $duration';
  }

  @override
  String get activitiesRouteCalculated => 'Trajet calculé.';

  @override
  String get activitiesRouteMissingTripAddress =>
      'Adresse du voyage manquante : renseignez-la dans l\'aperçu du voyage.';

  @override
  String get activitiesRouteNoResult => 'Aucun trajet trouvé.';

  @override
  String activitiesRouteNoResultWithDetail(Object detail) {
    return 'Aucun trajet trouvé ($detail).';
  }

  @override
  String get activitiesRouteError => 'Impossible de calculer le trajet.';

  @override
  String activitiesRouteErrorWithMessage(Object message) {
    return 'Impossible de calculer le trajet : $message.';
  }

  @override
  String activitiesRouteStatus(Object status) {
    return 'Statut : $status';
  }

  @override
  String get mealsNoMeal => 'Aucun repas';

  @override
  String get mealsPressPlusToPlan => 'Appuyez sur + pour planifier un repas.';

  @override
  String get dayPartMorning => 'Matin';

  @override
  String get dayPartMidday => 'Midi';

  @override
  String get dayPartEvening => 'Soir';

  @override
  String get mealMomentBreakfast => 'Petit-déjeuner';

  @override
  String get mealMomentLunch => 'Déjeuner';

  @override
  String get mealMomentDinner => 'Dîner';

  @override
  String get commonUnsavedChangesTitle => 'Modifications non enregistrées';

  @override
  String get mealUnsavedChangesBody =>
      'Tu as des changements non enregistrés. Quitter sans enregistrer ?';

  @override
  String get commonStay => 'Rester';

  @override
  String get mealDateHelp => 'Date du repas';

  @override
  String get mealCreated => 'Repas créé';

  @override
  String get mealUpdated => 'Repas mis à jour';

  @override
  String get mealDeleteTitle => 'Supprimer ce repas ?';

  @override
  String get mealDeleteBody => 'Ce repas sera supprimé définitivement.';

  @override
  String get mealDeleted => 'Repas supprimé';

  @override
  String get mealNotFound => 'Repas introuvable';

  @override
  String get mealNew => 'Nouveau repas';

  @override
  String get mealEdit => 'Modifier le repas';

  @override
  String get commonUnsaved => 'non enregistré';

  @override
  String get mealNameLabel => 'Nom du repas';

  @override
  String get mealNameRequired => 'Nom obligatoire';

  @override
  String get commonDate => 'Date';

  @override
  String get commonChoose => 'Choisir';

  @override
  String get mealMomentLabel => 'Moment';

  @override
  String mealParticipantsCount(Object count) {
    return 'Participants ($count)';
  }

  @override
  String get commonAuto => 'Auto';

  @override
  String get mealComponentsTitle => 'Composants du repas';

  @override
  String get mealAddComponent => 'Ajouter un composant';

  @override
  String mealAddComponentWithKind(Object kind) {
    return 'Ajouter $kind';
  }

  @override
  String get mealAddComponentHint =>
      'Ajoute un composant (entrée, plat, dessert, autre).';

  @override
  String mealIngredientsCount(Object count) {
    return '$count ingrédient(s)';
  }

  @override
  String get mealComponentChangedUnsaved => 'Composant modifié non enregistré';

  @override
  String get mealDeleteComponent => 'Supprimer ce composant';

  @override
  String get commonSaving => 'Enregistrement...';

  @override
  String get mealComponentKindEntree => 'Entrée';

  @override
  String get mealComponentKindMain => 'Plat';

  @override
  String get mealComponentKindDessert => 'Dessert';

  @override
  String get mealComponentKindOther => 'Autre';

  @override
  String get commonMe => 'Moi';

  @override
  String get commonRequired => 'Obligatoire';

  @override
  String get expenseGroupSelectAtLeastOne =>
      'Coche au moins une personne qui voit ce poste';

  @override
  String get expenseGroupUpdated => 'Poste mis à jour';

  @override
  String get expenseGroupCreated => 'Poste créé';

  @override
  String get expenseGroupEditTitle => 'Modifier le poste';

  @override
  String get expenseGroupNewTitle => 'Nouveau poste de dépenses';

  @override
  String get expenseGroupNameLabel => 'Nom du poste';

  @override
  String get expenseGroupNameHint => 'Ex. Commun, Cadeau, Week-end…';

  @override
  String get expenseGroupWhoSees => 'Qui voit ce poste';

  @override
  String get expenseGroupCanSee => 'Voit le poste';

  @override
  String get expenseGroupCreateAction => 'Créer le poste';

  @override
  String get expensesAddExpenseTooltip => 'Ajouter une dépense';

  @override
  String get expensesCreatePostFirst =>
      'Crée d\'abord un poste de dépenses (icône dossier dans l\'en-tête).';

  @override
  String get expensesPostsTitle => 'Postes de dépenses';

  @override
  String get expensesNoPostYet =>
      'Aucun poste de dépenses pour l\'instant. Utilise l\'icône dossier en haut pour en créer un.';

  @override
  String get expensesBalancesTab => 'Équilibres';

  @override
  String get expensesDeletePostTitle => 'Supprimer ce poste ?';

  @override
  String expensesDeletePostBody(Object title) {
    return 'Le poste « $title » et toutes ses opérations seront supprimés.';
  }

  @override
  String get expensesPostDeleted => 'Poste supprimé';

  @override
  String get expensesNoOperationInPost => 'Aucune opération dans ce poste.';

  @override
  String expensesYouOwe(Object amount, Object label) {
    return 'Tu dois $amount à $label';
  }

  @override
  String expensesOwesYou(Object label, Object amount) {
    return '$label te doit $amount';
  }

  @override
  String expensesGivesTo(Object from, Object amount, Object to) {
    return '$from donne $amount à $to';
  }

  @override
  String get expensesMyTotalSpend => 'Mes dépenses totales';

  @override
  String get expensesTripTotalCost => 'Coût total du séjour';

  @override
  String get expensesBalancesByCurrency => 'Soldes (par devise)';

  @override
  String get expensesAddToSeeBreakdown =>
      'Ajoute des dépenses pour voir la répartition.';

  @override
  String get expensesToReceive => 'À recevoir';

  @override
  String get expensesToPay => 'À payer';

  @override
  String get expensesBalanced => 'Équilibré';

  @override
  String get expensesSuggestedReimbursements => 'Remboursements suggérés';

  @override
  String get expensesSuggestedReimbursementsHint =>
      'Nombre minimal de virements pour équilibrer les comptes (par devise).';

  @override
  String get expensesNoCalculationYet => 'Pas encore de calcul.';

  @override
  String get expensesYouOweNothing => 'Tu ne dois rien à personne 😎';

  @override
  String get expensesMarkReimbursementDoneSemantics =>
      'Marquer ce remboursement comme effectué';

  @override
  String get expensesUnmarkReimbursementSemantics =>
      'Annuler le marquage de ce remboursement';

  @override
  String get expensesDeleteExpenseTitle => 'Supprimer cette dépense ?';

  @override
  String expensesDeleteExpenseBody(Object title) {
    return '« $title » sera supprimée.';
  }

  @override
  String get expensesExpenseDeleted => 'Dépense supprimée';

  @override
  String get expensesChoosePayer => 'Choisis qui a payé';

  @override
  String get expensesNoAllowedTraveler =>
      'Aucun voyageur autorisé dans ce poste.';

  @override
  String get expensesInvalidPayerForPost => 'Payeur invalide pour ce poste';

  @override
  String get expensesSelectAtLeastOneParticipant =>
      'Coche au moins un participant';

  @override
  String get expensesParticipantOutOfScope =>
      'Participant hors périmètre du poste';

  @override
  String get expensesInvalidAmount => 'Montant invalide';

  @override
  String get expensesCustomAmountValidation =>
      'Pour « Montants », chaque part doit être valide et la somme doit égaler le total.';

  @override
  String get expensesExpenseUpdated => 'Dépense mise à jour';

  @override
  String get expensesExpenseDetailTitle => 'Détail de la dépense';

  @override
  String get expensesNoAllowedTravelerInPostHint =>
      'Aucun voyageur n\'est autorisé dans ce poste : modifie le poste ou le voyage pour pouvoir ajuster le partage.';

  @override
  String get expensesAmountLabel => 'Montant';

  @override
  String get expensesCurrencyLabel => 'Devise';

  @override
  String get expensesCurrencyEuro => 'Euro (EUR)';

  @override
  String get expensesCurrencyDollar => 'Dollar (USD)';

  @override
  String get expensesPaidByLabel => 'Payé par';

  @override
  String expensesPaidByWithLabel(Object label) {
    return 'Payé par $label';
  }

  @override
  String get expensesDateLabel => 'Date de la dépense';

  @override
  String get expensesAmountSplit => 'Partage du montant';

  @override
  String get expensesSplitEqual => 'Équitablement';

  @override
  String get expensesSplitCustomAmounts => 'Montants';

  @override
  String get expensesSaveChanges => 'Enregistrer les modifications';

  @override
  String get expensesExpenseSaved => 'Dépense enregistrée';

  @override
  String get expensesNewExpenseTitle => 'Nouvelle dépense';

  @override
  String get expensesNoAllowedTravelerInPostForShare =>
      'Aucun voyageur autorisé dans ce poste pour partager une dépense.';

  @override
  String chatSendImpossible(Object error) {
    return 'Envoi impossible : $error';
  }

  @override
  String get chatNoRecentEmoji => 'Aucun emoji récent';

  @override
  String get chatUserNotConnected => 'Utilisateur non connecté';

  @override
  String chatReactionImpossible(Object error) {
    return 'Réaction impossible : $error';
  }

  @override
  String chatEditImpossible(Object error) {
    return 'Modification impossible : $error';
  }

  @override
  String get chatDeleteMessageConfirm => 'Supprimer ce message ?';

  @override
  String chatDeleteImpossible(Object error) {
    return 'Suppression impossible : $error';
  }

  @override
  String get chatCopied => 'Copié';

  @override
  String get chatEmptyState =>
      'Aucun message pour l\'instant. Écris le premier pour lancer la discussion.';

  @override
  String get chatMessageHint => 'Message…';

  @override
  String get chatSend => 'Envoyer';

  @override
  String get chatCopy => 'Copier';

  @override
  String chatReactWithEmoji(Object emoji) {
    return 'Réagir avec $emoji';
  }

  @override
  String get chatMoreEmojis => 'Plus d\'émojis';

  @override
  String get chatGoBottom => 'Aller en bas';

  @override
  String get chatEditMessageTitle => 'Modifier le message';

  @override
  String get appCopyright => '© 2026 Bruno Chappe';

  @override
  String tripsMemberCount(Object count) {
    return '$count membre(s)';
  }

  @override
  String get commonNotProvided => 'Non renseignée';

  @override
  String tripDateRangeBetween(Object start, Object end) {
    return 'Du $start au $end';
  }

  @override
  String tripDateRangeFrom(Object start) {
    return 'À partir du $start';
  }

  @override
  String tripDateRangeUntil(Object end) {
    return 'Jusqu\'au $end';
  }

  @override
  String get tripStayPresenceDatesTitle => 'Dates de présence';

  @override
  String get tripStayFromLabel => 'Du';

  @override
  String get tripStayToLabel => 'au';

  @override
  String get tripOverviewTileParticipants => 'Participants';

  @override
  String get tripOverviewTileActivities => 'Activités';

  @override
  String get tripOverviewTileRooms => 'Chambres';

  @override
  String get tripOverviewTileCars => 'Voitures';

  @override
  String get tripOverviewTileNoActivitiesToday =>
      'Pas d\'activités prévues aujourd\'hui';

  @override
  String get tripOverviewTileNoAssignedRoom => 'Aucune chambre attribuée';

  @override
  String get tripOverviewTileComingSoon => '[À venir]';

  @override
  String get tripOverviewMyRoom => 'Ma chambre';

  @override
  String get tripOverviewMyRooms => 'Mes chambres';

  @override
  String get cupidonPopupTitle => 'Tu as un match';

  @override
  String get cupidonPopupViewMatchesAction => 'Voir mes matchs';

  @override
  String get cupidonPopupUnknownMember => 'Quelqu\'un';
}

/// The translations for French, as used in France (`fr_FR`).
class AppLocalizationsFrFr extends AppLocalizationsFr {
  AppLocalizationsFrFr() : super('fr_FR');

  @override
  String get languageFrench => 'Français';

  @override
  String get languageEnglishUs => 'Anglais (États-Unis)';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get legalInfoTitle => 'Informations légales';

  @override
  String get legalInfoLoadError =>
      'Impossible de charger les informations légales.';

  @override
  String get legalMentionsTab => 'Mentions légales';

  @override
  String get legalPrivacyTab => 'Vie privée / RGPD';

  @override
  String get signInAnimatedLabelOutings => 'SORTIES';

  @override
  String get signInAnimatedLabelWeekends => 'WEEK-ENDS';

  @override
  String get signInAnimatedLabelTrips => 'VOYAGES';

  @override
  String get signInSubtitleStatic => 'ENTRE AMIS';

  @override
  String get signInLoading => 'Connexion...';

  @override
  String get signInContinueWithGoogle => 'Continuer avec Google';

  @override
  String get accountTitle => 'Mon compte';

  @override
  String get accountCropProfilePhotoTitle => 'Recadrer la photo de profil';

  @override
  String get accountPhotoUpdated => 'Photo de profil mise à jour';

  @override
  String get accountPhotoDeleted => 'Photo de profil supprimée';

  @override
  String get accountRemovePhotoDialogTitle => 'Supprimer la photo ?';

  @override
  String get accountRemovePhotoDialogBody => 'La photo de profil sera retirée.';

  @override
  String get accountUpdated => 'Compte mis à jour';

  @override
  String get accountNotificationsEnabled => 'Notifications activées.';

  @override
  String get accountNotificationsEnableError =>
      'Impossible d\'activer les notifications.';

  @override
  String get accountLanguageUpdated => 'Langue mise à jour';

  @override
  String get accountPhotoActionsTooltip => 'Actions photo de profil';

  @override
  String get accountChooseFromGallery => 'Choisir dans la galerie';

  @override
  String get accountTakePhoto => 'Prendre une photo';

  @override
  String get accountEmailUnavailable => 'E-mail indisponible';

  @override
  String get accountNameLabel => 'Nom du compte';

  @override
  String get accountNameHint => 'Ex : Alex';

  @override
  String get accountNameMaxLength => 'Maximum 60 caractères';

  @override
  String get accountSaveNameTooltip => 'Enregistrer le nom';

  @override
  String get accountNameFallbackHelp =>
      'Si vide, le nom affiché sera votre e-mail.';

  @override
  String get accountFoodAllergens => 'Allergènes alimentaires';

  @override
  String get accountCupidonSpace => 'Espace Cupidon';

  @override
  String get accountCupidonHistory => 'Historique des matchs';

  @override
  String get accountPreferencesSectionTitle => 'Préférences';

  @override
  String get accountColorPalette => 'Palette de couleurs';

  @override
  String get accountLanguageTitle => 'Langue';

  @override
  String get accountLanguageSubtitle => 'Langue de l\'application';

  @override
  String get accountAutoOpenCurrentTripTitle =>
      'Ouvrir automatiquement le voyage en cours';

  @override
  String get accountAutoOpenCurrentTripSubtitle =>
      'Si un seul voyage est en cours aujourd\'hui, il s\'ouvre au lancement.';

  @override
  String get accountAutoOpenCurrentTripEnabled =>
      'Ouverture auto du voyage activée';

  @override
  String get accountAutoOpenCurrentTripDisabled =>
      'Ouverture auto du voyage désactivée';

  @override
  String get accountEnabling => 'Activation en cours...';

  @override
  String get accountEnableNotifications => 'Activer les notifications';

  @override
  String get accountWebPushHelp =>
      'Sur iPhone : installe l\'app sur l\'écran d\'accueil, puis active ici.';

  @override
  String accountPhotoError(Object error) {
    return 'Erreur photo : $error';
  }

  @override
  String accountPhotoDeleteError(Object error) {
    return 'Erreur suppression photo : $error';
  }

  @override
  String accountUpdateError(Object error) {
    return 'Erreur mise à jour compte : $error';
  }

  @override
  String accountLanguageUpdateError(Object error) {
    return 'Erreur mise à jour langue : $error';
  }

  @override
  String accountPreferenceUpdateError(Object error) {
    return 'Erreur mise à jour préférence : $error';
  }

  @override
  String get tripsJoinWithInviteTooltip =>
      'Rejoindre avec un code d\'invitation';

  @override
  String get tripsNewTripTooltip => 'Nouveau voyage';

  @override
  String get tripsMyTrips => 'Mes voyages';

  @override
  String get tripsEmptyState =>
      'Aucun voyage pour le moment.\\nCrée ton premier voyage.';

  @override
  String get tripsTimelinePast => 'Passés';

  @override
  String get tripsTimelineOngoing => 'En cours';

  @override
  String get tripsTimelineUpcoming => 'À venir';

  @override
  String get tripsEmptyPast => 'Aucun voyage passé.';

  @override
  String get tripsEmptyOngoing => 'Aucun voyage en cours.';

  @override
  String get tripsEmptyUpcoming => 'Aucun voyage à venir.';

  @override
  String get tripsCreateDialogTitle => 'Créer un voyage';

  @override
  String get tripsTitleLabel => 'Titre';

  @override
  String get tripsDestinationLabel => 'Destination';

  @override
  String get tripsStartDateLabel => 'Date de début';

  @override
  String get tripsEndDateLabel => 'Date de fin';

  @override
  String get tripsCreateValidationRequired =>
      'Titre et destination obligatoires';

  @override
  String get tripsCreateValidationDateOrder =>
      'La date de fin doit être le même jour ou après la date de début';

  @override
  String get tripsCreateAction => 'Créer';

  @override
  String get tripsDeleteDialogTitle => 'Supprimer ce voyage ?';

  @override
  String tripsDeleteDialogBody(Object tripTitle) {
    return 'Cette action est définitive.\n\nVoyage : $tripTitle';
  }

  @override
  String get tripsDeleted => 'Voyage supprimé';

  @override
  String tripsDeleteError(Object error) {
    return 'Erreur suppression : $error';
  }

  @override
  String tripsFirestoreError(Object error) {
    return 'Erreur Firestore : $error';
  }

  @override
  String get tripsJoinCodeNotFound => 'Ce code d\'invitation est introuvable.';

  @override
  String get tripsJoinCodeNotValid =>
      'Ce code d\'invitation n\'est plus valide.';

  @override
  String get tripsJoinCodeInvalid => 'Code d\'invitation invalide.';

  @override
  String get tripsJoinCodeUnauthenticated =>
      'Connecte-toi pour rejoindre un voyage.';

  @override
  String get tripsJoinCodeRequired => 'Saisis le code d\'invitation.';

  @override
  String get tripsJoinCodeDialogTitle => 'Code d\'invitation';

  @override
  String get tripsJoinCodeDialogHelp =>
      'Colle le code envoyé par l\'organisateur du voyage (pas le lien, uniquement le code).';

  @override
  String get tripsJoinCodeLabel => 'Code';

  @override
  String get tripsJoinCodeAction => 'Rejoindre';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonClose => 'Fermer';

  @override
  String commonErrorWithDetails(Object error) {
    return 'Erreur : $error';
  }

  @override
  String get linkInvalid => 'Lien invalide';

  @override
  String get linkOpenImpossible => 'Impossible d\'ouvrir le lien';

  @override
  String get linkLabel => 'Lien';

  @override
  String get linkPreviewUnavailable => 'Aperçu indisponible pour ce lien.';

  @override
  String get nameSearchEmpty => 'Aucun nom ne correspond.';

  @override
  String get nameSearchLabel => 'Rechercher';

  @override
  String get nameSearchHint => 'Filtrer par nom';

  @override
  String get nameSearchClear => 'Effacer';

  @override
  String get locationOpenImpossible => 'Impossible d\'ouvrir la localisation';

  @override
  String get accountAllergensSaved => 'Allergènes enregistrés';

  @override
  String accountAllergensSaveError(Object error) {
    return 'Erreur enregistrement allergènes : $error';
  }

  @override
  String get accountDownloadApk => 'Télécharger l\'APK';

  @override
  String get accountSignOut => 'Se déconnecter';

  @override
  String paletteSaved(Object label) {
    return 'Palette $label enregistrée';
  }

  @override
  String get tripLabelGeneric => 'Voyage';

  @override
  String get tripNotFoundOrNoAccess => 'Voyage introuvable ou accès refusé.';

  @override
  String get tripBackToTrip => 'Retour au voyage';

  @override
  String get tripSettingsTitle => 'Paramètres du voyage';

  @override
  String tripMyRole(Object role) {
    return 'Mon rôle : $role';
  }

  @override
  String get tripRoleHierarchyHint =>
      'Hiérarchie des privilèges : créateur > admin > participant';

  @override
  String get roleOwner => 'Créateur';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleParticipant => 'Participant';

  @override
  String get tripSectionTrip => 'Voyage';

  @override
  String get tripSectionTripDescription =>
      'Règles liées aux informations générales du voyage.';

  @override
  String get tripSectionExpenses => 'Dépenses';

  @override
  String get tripSectionExpensesDescription =>
      'Gestion des droits sur les dépenses du voyage.';

  @override
  String get tripSectionActivities => 'Activités';

  @override
  String get tripSectionActivitiesDescription =>
      'Gestion des droits sur les activités proposées.';

  @override
  String get tripSectionMeals => 'Repas';

  @override
  String get tripSectionMealsDescription =>
      'Gestion des droits sur les repas et menus.';

  @override
  String get tripSectionShopping => 'Courses';

  @override
  String get tripSectionShoppingDescription =>
      'Gestion des droits sur les listes de courses.';

  @override
  String get tripSectionParticipants => 'Participants';

  @override
  String get tripSectionParticipantsDescription =>
      'Gestion des droits liés aux membres du voyage.';

  @override
  String get tripTabOverview => 'Aperçu';

  @override
  String get tripTabMessages => 'Messagerie';

  @override
  String get tripTabActivities => 'Activités';

  @override
  String get tripTabExpenses => 'Dépenses';

  @override
  String get tripTabMeals => 'Repas';

  @override
  String get tripTabShopping => 'Courses';

  @override
  String get tripCarsTitle => 'Voitures';

  @override
  String get tripCarsComingSoon => 'Covoiturage et véhicules. Contenu à venir.';

  @override
  String get tripMealsComingSoon => 'Planning des repas. Contenu à venir.';

  @override
  String get tripThisTrip => 'Ce voyage';

  @override
  String get tripStayDialogTitle => 'Mes dates sur le voyage';

  @override
  String get tripStayInvalidRange => 'La plage de dates est invalide.';

  @override
  String get tripStayOutOfTripBounds =>
      'Les dates doivent rester dans les dates du voyage.';

  @override
  String get tripStayUpdated => 'Dates mises à jour';

  @override
  String authErrorWithDetails(Object error) {
    return 'Erreur auth : $error';
  }

  @override
  String get foodAllergensAndIntolerances => 'Allergènes et intolérances';

  @override
  String get commonAddEllipsis => 'Ajouter...';

  @override
  String get commonMoreActions => 'Plus d\'actions';

  @override
  String get commonDone => 'Terminer';

  @override
  String get mealComponentTypeLabel => 'Type de composant';

  @override
  String get mealComponentNameOptionalLabel => 'Nom du composant (optionnel)';

  @override
  String mealContainsAllergen(Object allergen) {
    return 'Contient $allergen';
  }

  @override
  String mealMayContainAllergen(Object allergen) {
    return 'Peut contenir $allergen';
  }

  @override
  String get mealIngredientsTitle => 'Ingrédients';

  @override
  String get mealIngredientHint => 'Ingrédient...';

  @override
  String get mealAddIngredient => 'Ajouter un ingrédient';

  @override
  String get tripParticipantsTitle => 'Participants';

  @override
  String get tripParticipantsEmpty => 'Aucun participant.';

  @override
  String get tripParticipantsTraveler => 'Voyageur';

  @override
  String get tripParticipantsUser => 'Utilisateur';

  @override
  String get tripParticipantsThisParticipant => 'Ce participant';

  @override
  String tripParticipantsAdminRemoved(Object label) {
    return 'Rôle administrateur retiré ($label).';
  }

  @override
  String tripParticipantsAdminGranted(Object label) {
    return '$label est administrateur.';
  }

  @override
  String get tripParticipantsLikeSaveError =>
      'Impossible d\'enregistrer ce like pour le moment.';

  @override
  String get tripParticipantsAddPlannedTravelerTitle =>
      'Ajouter un voyageur prévu';

  @override
  String get tripParticipantsPlannedTravelerAdded => 'Voyageur prévu ajouté';

  @override
  String get tripParticipantsEditNameTitle => 'Modifier le nom';

  @override
  String get tripParticipantsNameUpdated => 'Nom mis à jour';

  @override
  String get tripParticipantsRemovePlannedTravelerTitle =>
      'Retirer ce voyageur prévu ?';

  @override
  String tripParticipantsRemovePlannedTravelerBody(Object label) {
    return '« $label » sera retiré des participants.';
  }

  @override
  String get tripParticipantsRemoveAction => 'Retirer';

  @override
  String get tripParticipantsPlannedTravelerRemoved => 'Voyageur prévu retiré';

  @override
  String get tripParticipantsRemoveParticipantTitle =>
      'Retirer ce participant ?';

  @override
  String tripParticipantsRemoveParticipantBody(Object label) {
    return 'Retirer « $label » du voyage ?';
  }

  @override
  String get tripParticipantsRemovedFromTrip => 'Participant retiré du voyage';

  @override
  String get tripParticipantsAdminHint =>
      'Clique sur l’icône à gauche d’un voyageur (prévu ou inscrit) pour lui donner ou retirer le rôle administrateur (sauf le créateur).';

  @override
  String get tripParticipantsUnlike => 'Retirer le like';

  @override
  String get tripParticipantsLike => 'Liker';

  @override
  String get tripParticipantsChangeRole => 'Changer le rôle';

  @override
  String get tripNotFound => 'Voyage introuvable';

  @override
  String get commonName => 'Nom';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get cupidonDefaultEnabled => 'Mode Cupidon activé par défaut';

  @override
  String get cupidonDefaultDisabled => 'Mode Cupidon désactivé par défaut';

  @override
  String get cupidonDeleteMatchTitle => 'Supprimer ce match ?';

  @override
  String cupidonDeleteMatchBody(Object memberLabel, Object tripTitle) {
    return 'Ce match avec $memberLabel (voyage \"$tripTitle\") sera retiré de ton historique.';
  }

  @override
  String get cupidonEnableByDefaultTitle => 'Activer Cupidon par défaut';

  @override
  String get cupidonEnableByDefaultSubtitle =>
      'Quand tu rejoins un nouveau voyage, cette valeur est préremplie.';

  @override
  String cupidonPreferenceLoadError(Object error) {
    return 'Erreur chargement préférence : $error';
  }

  @override
  String get cupidonMyMatches => 'Mes matchs';

  @override
  String get cupidonNoMatches => 'Aucun match enregistré pour le moment.';

  @override
  String get cupidonDeleteMatchTooltip => 'Supprimer ce match';

  @override
  String cupidonMatchesLoadError(Object error) {
    return 'Erreur chargement matchs : $error';
  }

  @override
  String get roomsCreate => 'Créer';

  @override
  String get roomsCreateTitle => 'Créer une chambre';

  @override
  String get roomsCreated => 'Chambre créée';

  @override
  String get roomsUpdated => 'Chambre mise à jour';

  @override
  String get roomsDeleted => 'Chambre supprimée';

  @override
  String get roomsUnnamedRoom => 'Chambre sans nom';

  @override
  String get roomsRoomLabel => 'Chambre';

  @override
  String get roomsDeleteTitle => 'Supprimer la chambre ?';

  @override
  String roomsDeleteBody(Object roomName) {
    return '« $roomName » sera supprimée.';
  }

  @override
  String get roomsNameRequired => 'Nom obligatoire';

  @override
  String get roomsAddBed => 'Ajouter un lit';

  @override
  String get roomsAddAtLeastOneBed => 'Ajoute au moins un lit';

  @override
  String get roomsBedCapacityExceeded => 'Capacité d\'un lit dépassée';

  @override
  String get roomsThisBedCapacityReached => 'Capacité de ce lit atteinte';

  @override
  String get roomsBedTypeSingle => 'Simple';

  @override
  String get roomsBedTypeDouble => 'Double';

  @override
  String get roomsBedKindRegular => 'Normal';

  @override
  String get roomsBedKindExtra => 'Appoint';

  @override
  String roomsAlreadyAssigned(Object roomName) {
    return 'Déjà affecté chambre $roomName';
  }

  @override
  String roomsBedLabel(Object index) {
    return 'Lit $index';
  }

  @override
  String roomsBedTypeAndKind(Object typeLabel, Object kindLabel) {
    return '$typeLabel · $kindLabel';
  }

  @override
  String roomsBedSummary(Object index, Object typeLabel, Object kindLabel) {
    return 'Lit $index · $typeLabel · $kindLabel';
  }

  @override
  String roomsBedLine(
      Object index, Object typeLabel, Object kindLabel, Object assignedLabel) {
    return 'Lit $index · $typeLabel · $kindLabel · $assignedLabel';
  }

  @override
  String get tripOverviewUpdated => 'Voyage mis à jour';

  @override
  String tripOverviewUpdateError(Object error) {
    return 'Erreur modification : $error';
  }

  @override
  String get tripOverviewInviteLinkCopied =>
      'Lien d\'invitation copié dans le presse-papiers';

  @override
  String tripOverviewInviteShareError(Object error) {
    return 'Erreur partage invitation : $error';
  }

  @override
  String get tripOverviewInviteCodeCopied =>
      'Code d\'invitation copié dans le presse-papiers';

  @override
  String tripOverviewInviteCodeCopyError(Object error) {
    return 'Erreur copie du code : $error';
  }

  @override
  String get cupidonEnabled => 'Mode Cupidon activé';

  @override
  String get cupidonDisabled => 'Mode Cupidon désactivé';

  @override
  String get cupidonEnableAction => 'Activer Cupidon';

  @override
  String get cupidonDisableAction => 'Désactiver Cupidon';

  @override
  String tripOverviewCupidonToggleError(Object error) {
    return 'Erreur mode Cupidon : $error';
  }

  @override
  String get tripOverviewCropBanner => 'Recadrer la bannière';

  @override
  String get tripOverviewBannerUpdated => 'Photo de bannière mise à jour';

  @override
  String get tripOverviewBannerRemoveBody =>
      'La bannière sera retirée du voyage.';

  @override
  String get tripOverviewActions => 'Actions voyage';

  @override
  String get tripOverviewPhotoActions => 'Actions photo';

  @override
  String get tripOverviewChangePhoto => 'Changer de photo';

  @override
  String get tripOverviewShareInvite => 'Partager invitation';

  @override
  String get tripOverviewCopyCode => 'Copier le code';

  @override
  String get tripOverviewEditTrip => 'Modifier le voyage';

  @override
  String get tripOverviewTitleRequired => 'Titre obligatoire';

  @override
  String get tripOverviewDestinationRequired => 'Destination obligatoire';

  @override
  String get tripOverviewAddressLabel => 'Adresse';

  @override
  String get tripOverviewAddressHint => '10 Rue de Rivoli, 75001 Paris';

  @override
  String get tripOverviewLinkLabel => 'Lien (Airbnb, Booking, site, ...)';

  @override
  String get tripOverviewLinkHint => 'https://...';

  @override
  String get tripOverviewLinkInvalid => 'Lien invalide (ex: https://...)';

  @override
  String get tripOverviewLinkMustStartWithHttp =>
      'Le lien doit commencer par http(s)://';

  @override
  String get tripOverviewOpenLocation => 'Ouvrir la localisation';

  @override
  String get tripOverviewUntitled => 'Sans titre';

  @override
  String get tripOverviewUnknownDestination => 'Destination inconnue';

  @override
  String get tripOverviewLeaveTripTitle => 'Quitter ce voyage ?';

  @override
  String get tripOverviewLeaveAction => 'Quitter';

  @override
  String get tripOverviewLeaveTripCardTitle => 'Quitter le voyage';

  @override
  String get tripOverviewLeaveTripDialogBody =>
      'Tu seras retiré de la liste des voyageurs. Sur chaque dépense partagée où tu participes, tu seras enlevé des participants : le partage sera recalculé pour les autres. Si tu étais seul sur une dépense, celle-ci sera supprimée.';

  @override
  String get tripOverviewLeaveTripCardBody =>
      'Tu pourras quitter même si les comptes ne sont pas à zéro. Tu seras alors retiré automatiquement de toutes les dépenses où tu es inclus (les autres voyageurs verront les parts mises à jour).';

  @override
  String get inviteTitle => 'Invitation';

  @override
  String get inviteJoinedTrip => 'Vous avez rejoint le voyage';

  @override
  String get inviteChooseTravelerError => 'Choisis un voyageur sur la liste.';

  @override
  String get inviteJoinTripStepOne => 'Rejoindre le voyage 1/2';

  @override
  String get inviteJoinTripStepTwo => 'Rejoindre le voyage 2/2';

  @override
  String get inviteChooseTravelerWarning =>
      'Tu ne pourras faire ce choix qu’une seule fois pour ce voyage.';

  @override
  String get inviteWhoAreYouInTrip => 'Qui es-tu dans ce voyage ?';

  @override
  String get inviteCupidonSubtitle =>
      'Tu pourras liker des participants du voyage.';

  @override
  String get inviteEditTravelerChoice => 'Modifier le choix du voyageur';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get commonConfirm => 'Valider';

  @override
  String get inviteInvalidLink => 'Lien d’invitation invalide.';

  @override
  String get inviteBackToTrips => 'Retour aux voyages';

  @override
  String get inviteJoinThisTrip => 'Rejoindre ce voyage';

  @override
  String inviteJoinTripWithTitle(Object title) {
    return 'Rejoindre le voyage « $title »';
  }

  @override
  String get inviteChecking => 'Vérification de l’invitation…';

  @override
  String get inviteJoiningInProgress => 'Ajout au voyage en cours…';

  @override
  String inviteJoiningTripWithTitle(Object title) {
    return 'Ajout au voyage « $title » en cours…';
  }

  @override
  String get inviteAccepted => 'Invitation acceptée';

  @override
  String get inviteAcceptedSubtitle =>
      'Tu fais partie du voyage. Les autres participants te verront avec ton compte.';

  @override
  String get inviteOpenTrip => 'Ouvrir le voyage';

  @override
  String get inviteSeeMyTrips => 'Voir mes voyages';

  @override
  String get inviteCouldNotFinalizeJoin =>
      'Nous n’avons pas pu finaliser ton entrée dans le voyage. Vérifie ta connexion et réessaie, ou demande un nouveau lien à l’organisateur.';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get inviteJoinATrip => 'Rejoindre un voyage';

  @override
  String get inviteOpenFailed =>
      'Impossible d’ouvrir l’invitation pour le moment. Vérifie ta connexion ou demande un nouveau lien à l’organisateur.';

  @override
  String get commonToday => 'Aujourd’hui';

  @override
  String get commonYesterday => 'Hier';

  @override
  String get activitiesTabSuggestions => 'Suggestions';

  @override
  String get activitiesTabPlanned => 'Planifiées';

  @override
  String get activitiesTabAgenda => 'Agenda';

  @override
  String get activitiesNoSuggestion => 'Aucune suggestion.';

  @override
  String get activitiesNoPlanned => 'Aucune activité planifiée.';

  @override
  String get activitiesSuggestAction => 'Proposer';

  @override
  String get activitiesPreviousWeek => 'Semaine précédente';

  @override
  String get activitiesNextWeek => 'Semaine suivante';

  @override
  String get activitiesNoPlannedThisDay => 'Aucune activité planifiée ce jour.';

  @override
  String get activitiesUntitled => 'Sans titre';

  @override
  String activitiesProposedBy(Object name) {
    return 'Proposé par $name';
  }

  @override
  String get activitiesAdded => 'Activité ajoutée';

  @override
  String get activitiesLinkMustStartHttp =>
      'Le lien doit commencer par http(s)://';

  @override
  String get activitiesNewActivity => 'Nouvelle activité';

  @override
  String get activitiesCategory => 'Catégorie';

  @override
  String get activitiesLabel => 'Libellé';

  @override
  String get activitiesLabelRequired => 'Libellé obligatoire';

  @override
  String get activitiesLink => 'Lien (site, billetterie, ...)';

  @override
  String get activitiesAddress => 'Adresse du lieu (trajet depuis le voyage)';

  @override
  String get activitiesAddressHint =>
      'Pour calculer distance et durée en voiture';

  @override
  String get activitiesLocked => 'Activité verrouillée';

  @override
  String get activitiesLockedHint =>
      'Si activée, seuls les admins peuvent modifier cette activité.';

  @override
  String get activitiesComments => 'Commentaires';

  @override
  String get linkInvalidExample => 'Lien invalide (ex: https://...)';

  @override
  String get shoppingDeleteCheckedTitle => 'Supprimer les éléments cochés ?';

  @override
  String shoppingDeleteCheckedContent(Object count) {
    return '$count élément(s) sera(ont) supprimé(s) définitivement. Cette opération est irréversible.';
  }

  @override
  String shoppingDeletedCount(Object count) {
    return '$count élément(s) supprimé(s).';
  }

  @override
  String get shoppingFilterHelpTooltip => 'Aide des filtres';

  @override
  String get shoppingEmptyTitle => 'Liste de courses vide';

  @override
  String get shoppingEmptySubtitle => 'Appuyez sur + pour ajouter un article.';

  @override
  String get shoppingFiltersTitle => 'Filtres de la liste';

  @override
  String get shoppingFiltersHelpBody =>
      'Le filtre affiche uniquement les éléments correspondant à l’état sélectionné.';

  @override
  String get shoppingFilterAll => 'Tous les éléments';

  @override
  String get shoppingFilterTodo => 'À acheter';

  @override
  String get shoppingFilterDone => 'Déjà achetés';

  @override
  String get shoppingFilterClaimedByMe => 'Claimés par moi';

  @override
  String get shoppingTravelerFallback => 'Voyageur';

  @override
  String get shoppingClaimRemoveMine => 'Retirer mon claim';

  @override
  String shoppingClaimAlreadyBy(Object name) {
    return 'Déjà claimé par $name';
  }

  @override
  String get shoppingClaimTake => 'Je m\'en occupe';

  @override
  String get activityCategorySport => 'Sport';

  @override
  String get activityCategoryHiking => 'Randonnée';

  @override
  String get activityCategoryShopping => 'Shopping';

  @override
  String get activityCategoryVisit => 'Visite';

  @override
  String get activityCategoryRestaurant => 'Restaurant';

  @override
  String get activitiesUpdated => 'Activité mise à jour';

  @override
  String get activitiesDeleteTitle => 'Supprimer cette activité ?';

  @override
  String activitiesDeleteBody(Object label) {
    return '« $label » sera supprimée.';
  }

  @override
  String get activitiesDeleted => 'Activité supprimée';

  @override
  String get activitiesNotFound => 'Activité introuvable.';

  @override
  String get activitiesPlannedDateHelp => 'Date prévue';

  @override
  String get activitiesAddressCardTitle => 'Adresse du lieu';

  @override
  String get activitiesFromLodgingByCar => 'Depuis le logement (voiture)';

  @override
  String get commonDash => '—';

  @override
  String get activitiesDone => 'Activité faite';

  @override
  String get activitiesPlannedUnset => 'Prévue le : non renseignée';

  @override
  String activitiesPlannedOn(Object date) {
    return 'Prévue le $date';
  }

  @override
  String get activitiesRemovePlannedDate => 'Retirer la date prévue';

  @override
  String get activitiesLinkPreviewAfterSave =>
      'L\'aperçu du lien sera mis à jour après enregistrement.';

  @override
  String get activitiesRouteCalculating =>
      'Calcul en cours depuis l\'adresse du voyage.';

  @override
  String activitiesRouteDistance(Object distance) {
    return 'Distance : $distance';
  }

  @override
  String activitiesRouteDuration(Object duration) {
    return 'Durée : $duration';
  }

  @override
  String get activitiesRouteCalculated => 'Trajet calculé.';

  @override
  String get activitiesRouteMissingTripAddress =>
      'Adresse du voyage manquante : renseignez-la dans l\'aperçu du voyage.';

  @override
  String get activitiesRouteNoResult => 'Aucun trajet trouvé.';

  @override
  String activitiesRouteNoResultWithDetail(Object detail) {
    return 'Aucun trajet trouvé ($detail).';
  }

  @override
  String get activitiesRouteError => 'Impossible de calculer le trajet.';

  @override
  String activitiesRouteErrorWithMessage(Object message) {
    return 'Impossible de calculer le trajet : $message.';
  }

  @override
  String activitiesRouteStatus(Object status) {
    return 'Statut : $status';
  }

  @override
  String get mealsNoMeal => 'Aucun repas';

  @override
  String get mealsPressPlusToPlan => 'Appuyez sur + pour planifier un repas.';

  @override
  String get dayPartMorning => 'Matin';

  @override
  String get dayPartMidday => 'Midi';

  @override
  String get dayPartEvening => 'Soir';

  @override
  String get mealMomentBreakfast => 'Petit-déjeuner';

  @override
  String get mealMomentLunch => 'Déjeuner';

  @override
  String get mealMomentDinner => 'Dîner';

  @override
  String get commonUnsavedChangesTitle => 'Modifications non enregistrées';

  @override
  String get mealUnsavedChangesBody =>
      'Tu as des changements non enregistrés. Quitter sans enregistrer ?';

  @override
  String get commonStay => 'Rester';

  @override
  String get mealDateHelp => 'Date du repas';

  @override
  String get mealCreated => 'Repas créé';

  @override
  String get mealUpdated => 'Repas mis à jour';

  @override
  String get mealDeleteTitle => 'Supprimer ce repas ?';

  @override
  String get mealDeleteBody => 'Ce repas sera supprimé définitivement.';

  @override
  String get mealDeleted => 'Repas supprimé';

  @override
  String get mealNotFound => 'Repas introuvable';

  @override
  String get mealNew => 'Nouveau repas';

  @override
  String get mealEdit => 'Modifier le repas';

  @override
  String get commonUnsaved => 'non enregistré';

  @override
  String get mealNameLabel => 'Nom du repas';

  @override
  String get mealNameRequired => 'Nom obligatoire';

  @override
  String get commonDate => 'Date';

  @override
  String get commonChoose => 'Choisir';

  @override
  String get mealMomentLabel => 'Moment';

  @override
  String mealParticipantsCount(Object count) {
    return 'Participants ($count)';
  }

  @override
  String get commonAuto => 'Auto';

  @override
  String get mealComponentsTitle => 'Composants du repas';

  @override
  String get mealAddComponent => 'Ajouter un composant';

  @override
  String mealAddComponentWithKind(Object kind) {
    return 'Ajouter $kind';
  }

  @override
  String get mealAddComponentHint =>
      'Ajoute un composant (entrée, plat, dessert, autre).';

  @override
  String mealIngredientsCount(Object count) {
    return '$count ingrédient(s)';
  }

  @override
  String get mealComponentChangedUnsaved => 'Composant modifié non enregistré';

  @override
  String get mealDeleteComponent => 'Supprimer ce composant';

  @override
  String get commonSaving => 'Enregistrement...';

  @override
  String get mealComponentKindEntree => 'Entrée';

  @override
  String get mealComponentKindMain => 'Plat';

  @override
  String get mealComponentKindDessert => 'Dessert';

  @override
  String get mealComponentKindOther => 'Autre';

  @override
  String get commonMe => 'Moi';

  @override
  String get commonRequired => 'Obligatoire';

  @override
  String get expenseGroupSelectAtLeastOne =>
      'Coche au moins une personne qui voit ce poste';

  @override
  String get expenseGroupUpdated => 'Poste mis à jour';

  @override
  String get expenseGroupCreated => 'Poste créé';

  @override
  String get expenseGroupEditTitle => 'Modifier le poste';

  @override
  String get expenseGroupNewTitle => 'Nouveau poste de dépenses';

  @override
  String get expenseGroupNameLabel => 'Nom du poste';

  @override
  String get expenseGroupNameHint => 'Ex. Commun, Cadeau, Week-end…';

  @override
  String get expenseGroupWhoSees => 'Qui voit ce poste';

  @override
  String get expenseGroupCanSee => 'Voit le poste';

  @override
  String get expenseGroupCreateAction => 'Créer le poste';

  @override
  String get expensesAddExpenseTooltip => 'Ajouter une dépense';

  @override
  String get expensesCreatePostFirst =>
      'Crée d\'abord un poste de dépenses (icône dossier dans l\'en-tête).';

  @override
  String get expensesPostsTitle => 'Postes de dépenses';

  @override
  String get expensesNoPostYet =>
      'Aucun poste de dépenses pour l\'instant. Utilise l\'icône dossier en haut pour en créer un.';

  @override
  String get expensesBalancesTab => 'Équilibres';

  @override
  String get expensesDeletePostTitle => 'Supprimer ce poste ?';

  @override
  String expensesDeletePostBody(Object title) {
    return 'Le poste « $title » et toutes ses opérations seront supprimés.';
  }

  @override
  String get expensesPostDeleted => 'Poste supprimé';

  @override
  String get expensesNoOperationInPost => 'Aucune opération dans ce poste.';

  @override
  String expensesYouOwe(Object amount, Object label) {
    return 'Tu dois $amount à $label';
  }

  @override
  String expensesOwesYou(Object label, Object amount) {
    return '$label te doit $amount';
  }

  @override
  String expensesGivesTo(Object from, Object amount, Object to) {
    return '$from donne $amount à $to';
  }

  @override
  String get expensesMyTotalSpend => 'Mes dépenses totales';

  @override
  String get expensesTripTotalCost => 'Coût total du séjour';

  @override
  String get expensesBalancesByCurrency => 'Soldes (par devise)';

  @override
  String get expensesAddToSeeBreakdown =>
      'Ajoute des dépenses pour voir la répartition.';

  @override
  String get expensesToReceive => 'À recevoir';

  @override
  String get expensesToPay => 'À payer';

  @override
  String get expensesBalanced => 'Équilibré';

  @override
  String get expensesSuggestedReimbursements => 'Remboursements suggérés';

  @override
  String get expensesSuggestedReimbursementsHint =>
      'Nombre minimal de virements pour équilibrer les comptes (par devise).';

  @override
  String get expensesNoCalculationYet => 'Pas encore de calcul.';

  @override
  String get expensesYouOweNothing => 'Tu ne dois rien à personne 😎';

  @override
  String get expensesMarkReimbursementDoneSemantics =>
      'Marquer ce remboursement comme effectué';

  @override
  String get expensesUnmarkReimbursementSemantics =>
      'Annuler le marquage de ce remboursement';

  @override
  String get expensesDeleteExpenseTitle => 'Supprimer cette dépense ?';

  @override
  String expensesDeleteExpenseBody(Object title) {
    return '« $title » sera supprimée.';
  }

  @override
  String get expensesExpenseDeleted => 'Dépense supprimée';

  @override
  String get expensesChoosePayer => 'Choisis qui a payé';

  @override
  String get expensesNoAllowedTraveler =>
      'Aucun voyageur autorisé dans ce poste.';

  @override
  String get expensesInvalidPayerForPost => 'Payeur invalide pour ce poste';

  @override
  String get expensesSelectAtLeastOneParticipant =>
      'Coche au moins un participant';

  @override
  String get expensesParticipantOutOfScope =>
      'Participant hors périmètre du poste';

  @override
  String get expensesInvalidAmount => 'Montant invalide';

  @override
  String get expensesCustomAmountValidation =>
      'Pour « Montants », chaque part doit être valide et la somme doit égaler le total.';

  @override
  String get expensesExpenseUpdated => 'Dépense mise à jour';

  @override
  String get expensesExpenseDetailTitle => 'Détail de la dépense';

  @override
  String get expensesNoAllowedTravelerInPostHint =>
      'Aucun voyageur n\'est autorisé dans ce poste : modifie le poste ou le voyage pour pouvoir ajuster le partage.';

  @override
  String get expensesAmountLabel => 'Montant';

  @override
  String get expensesCurrencyLabel => 'Devise';

  @override
  String get expensesCurrencyEuro => 'Euro (EUR)';

  @override
  String get expensesCurrencyDollar => 'Dollar (USD)';

  @override
  String get expensesPaidByLabel => 'Payé par';

  @override
  String expensesPaidByWithLabel(Object label) {
    return 'Payé par $label';
  }

  @override
  String get expensesDateLabel => 'Date de la dépense';

  @override
  String get expensesAmountSplit => 'Partage du montant';

  @override
  String get expensesSplitEqual => 'Équitablement';

  @override
  String get expensesSplitCustomAmounts => 'Montants';

  @override
  String get expensesSaveChanges => 'Enregistrer les modifications';

  @override
  String get expensesExpenseSaved => 'Dépense enregistrée';

  @override
  String get expensesNewExpenseTitle => 'Nouvelle dépense';

  @override
  String get expensesNoAllowedTravelerInPostForShare =>
      'Aucun voyageur autorisé dans ce poste pour partager une dépense.';

  @override
  String chatSendImpossible(Object error) {
    return 'Envoi impossible : $error';
  }

  @override
  String get chatNoRecentEmoji => 'Aucun emoji récent';

  @override
  String get chatUserNotConnected => 'Utilisateur non connecté';

  @override
  String chatReactionImpossible(Object error) {
    return 'Réaction impossible : $error';
  }

  @override
  String chatEditImpossible(Object error) {
    return 'Modification impossible : $error';
  }

  @override
  String get chatDeleteMessageConfirm => 'Supprimer ce message ?';

  @override
  String chatDeleteImpossible(Object error) {
    return 'Suppression impossible : $error';
  }

  @override
  String get chatCopied => 'Copié';

  @override
  String get chatEmptyState =>
      'Aucun message pour l\'instant. Écris le premier pour lancer la discussion.';

  @override
  String get chatMessageHint => 'Message…';

  @override
  String get chatSend => 'Envoyer';

  @override
  String get chatCopy => 'Copier';

  @override
  String chatReactWithEmoji(Object emoji) {
    return 'Réagir avec $emoji';
  }

  @override
  String get chatMoreEmojis => 'Plus d\'émojis';

  @override
  String get chatGoBottom => 'Aller en bas';

  @override
  String get chatEditMessageTitle => 'Modifier le message';

  @override
  String get appCopyright => '© 2026 Bruno Chappe';

  @override
  String tripsMemberCount(Object count) {
    return '$count membre(s)';
  }

  @override
  String get commonNotProvided => 'Non renseignée';

  @override
  String tripDateRangeBetween(Object start, Object end) {
    return 'Du $start au $end';
  }

  @override
  String tripDateRangeFrom(Object start) {
    return 'À partir du $start';
  }

  @override
  String tripDateRangeUntil(Object end) {
    return 'Jusqu\'au $end';
  }

  @override
  String get tripStayPresenceDatesTitle => 'Dates de présence';

  @override
  String get tripStayFromLabel => 'Du';

  @override
  String get tripStayToLabel => 'au';

  @override
  String get tripOverviewTileParticipants => 'Participants';

  @override
  String get tripOverviewTileActivities => 'Activités';

  @override
  String get tripOverviewTileRooms => 'Chambres';

  @override
  String get tripOverviewTileCars => 'Voitures';

  @override
  String get tripOverviewTileNoActivitiesToday =>
      'Pas d\'activités prévues aujourd\'hui';

  @override
  String get tripOverviewTileNoAssignedRoom => 'Aucune chambre attribuée';

  @override
  String get tripOverviewTileComingSoon => '[À venir]';

  @override
  String get tripOverviewMyRoom => 'Ma chambre';

  @override
  String get tripOverviewMyRooms => 'Mes chambres';

  @override
  String get cupidonPopupTitle => 'Tu as un match';

  @override
  String get cupidonPopupViewMatchesAction => 'Voir mes matchs';

  @override
  String get cupidonPopupUnknownMember => 'Quelqu\'un';
}
