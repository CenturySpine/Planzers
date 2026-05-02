# Notes de version — v0.2.0-beta2

> Période couverte : v0.2.0-beta1 → v0.2.0-beta2

---

## 1) L'essentiel pour les utilisateurs

### Voyages

- **Annonces globales** : sur la liste des voyages, une **cloche** avec une pastille discrète (sans compteur) indique qu’au moins une annonce globale **n’a pas encore été consultée**. L’ouverture de la page dédiée présente les messages dans la langue de l’application ; les **URL sont des liens cliquables**. Les **annonces de voyage** affichent aussi leurs **liens sous forme cliquable**.
- **Démarrage** : l’application affiche systématiquement la **liste des voyages** au lancement, sans rouvrir automatiquement le dernier voyage consulté.
- **Navigation dans le voyage** : le volet et les libellés associés aux activités utilisent le nom **Planning** (harmonisation de l’interface).

### Activités

- Lors du choix d’une **date prévue**, la proposition par défaut **correspond à la date de début du voyage**.

### Profil utilisateur et application

- **Mise à jour obligatoire (Android)** : lorsque la politique de version impose une mise à jour sur cette plate-forme, l’application peut **télécharger l’APK**, **lancer l’installateur**, puis **poursuivre le parcours** (installation ou réouverture) sans perdre le fil.

### Administration (super-administrateurs)

- **Annonces globales** : création, modification et suppression de messages pour tous les utilisateurs connectés, rédaction **multilingue** avec **assistance à la traduction**.
- **Masquage côté utilisateur** : par annonce, choix d’**autoriser ou non** le masquage individuel ; possibilité de **réafficher** depuis l’administration les annonces masquées par les utilisateurs.

---

## 2) Détails complémentaires (technique et exploitation)

- **Firebase et sécurité** :
  - **Règles Firestore** pour les annonces globales, l’état **lu/non lu**, les préférences de **masquage** utilisateur et une collection **`applicationLogs`** consultable uniquement par les **propriétaires d’application** (écriture réservée au backend).
  - **Builds preview** : la version distante attendue est lue depuis **Firebase Storage** (fichier de métadonnées et APK preview du projet preview), avec la **même logique semver et le même écran de contrôle** qu’en production ; le flux **production** continue d’utiliser **GitHub**.
- **Cloud Functions** :
  - Exécution **planifiée** pour purger les enregistrements de masquage **orphelins** après suppression d’une annonce côté admin.
  - **Journalisation applicative** côté serveur et fonction **traduction** à la demande pour l’édition des annonces globales.
- **Exploitation et dépôt** :
  - **Script de migration** pour une opération massive sur les annonces de voyage (maintenance).
  - **Documentation interne** (plans) sur le déploiement des annonces globales et sur la détection de version preview.
