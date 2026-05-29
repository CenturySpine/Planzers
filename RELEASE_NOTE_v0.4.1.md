# Notes de version — v0.4.1

> Période couverte : v0.4.0 → v0.4.1

## Pour les utilisateurs

### Messagerie

- **Répondre à un message :** depuis le menu d’un message (appui long), l’action « Répondre » cite le message d’origine dans votre bulle ; la citation reste visible pour tout le fil.
- **Photos dans le chat :** envoi d’images depuis la galerie ou l’appareil photo, avec recadrage avant envoi ; la photo s’affiche tout de suite pendant l’envoi, puis s’ouvre en plein écran au toucher. Les images dépassant 10 Mo sont refusées avec un message explicite.
- **Réactions enrichies :** sélecteur d’émojis façon messagerie instantanée pour réagir ou choisir un emoji personnalisé ; réactions possibles sur les messages texte et photo ; affichage immédiat après votre réaction ; pastilles de réaction recentrées pour ne pas masquer le contenu.
- **Appui long :** la barre d’actions en haut (fermer, modifier, supprimer, copier) et la rangée de réactions rapides au-dessus du message sont de nouveau disponibles comme avant la refonte.
- **Lecture plus fluide :** bulles aux coins adaptés lorsque plusieurs messages consécutifs viennent du même auteur ; largeur des bulles plafonnée pour un fil plus lisible ; couleurs des bulles alignées sur l’identité visuelle du produit ; liens internet de nouveau cliquables dans le texte.

---

## Détails complémentaires (technique et exploitation)

### Messagerie

- **SDK flyer.chat :** le fil de discussion voyage repose sur `flutter_chat_ui` / `flutter_chat_core` avec un `FirestoreChatController` dédié, mappers de messages texte et image, composer (texte, emoji, image) et builders UI (citations, images, réactions).
- **Modèle Firestore :** messages texte ou `type: image` (`imageUrl`, `imageStoragePath`, dimensions optionnelles) ; champ `replyToMessageId` ; mises à jour de réactions isolées via `reactionsByUser` (règles `tripMessageReactionUpdateOnly`).
- **Stockage :** chemins `trips/{tripId}/messages/*` — lecture réservée aux membres, écriture image < 10 Mo (`storage.rules`).
- **Notifications push :** la fonction `notifyTripMessageRecipients` notifie aussi les envois photo (corps « a envoyé une photo » si pas de légende).

### Exploitation

- **Script `scripts/trip_export_import.js` :** export JSON complet d’un voyage (document + sous-collections + profils utilisateurs liés) et import avec dry-run par défaut (`--apply` pour écrire).
- **Script `scripts/ensure_default_expense_group.js` :** détecte et peut corriger les postes « Commun » dont `visibleToMemberIds` n’inclut pas tous les participants, en plus de la création du poste manquant.
- **Déploiement requis après mise à jour :** `firebase deploy --only firestore:rules,storage,functions --project <id>` (voir [`RELEASE.md`](RELEASE.md)), puis vérification IAM `roles/run.invoker` sur les fonctions concernées si besoin.
