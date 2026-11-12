# Firebase — backend préparé, synchronisation UI à terminer

Le projet principal fonctionne entièrement en local. **Ne pas présenter l’adaptateur comme une synchronisation fonctionnelle.** Ni un plist ni des règles déployées ne suffisent à raccorder l’interface au serveur.

## Configuration du projet

1. Créer un projet dans la console Firebase et une application iOS avec le bundle ID choisi dans Xcode.
2. Créer Firestore et Storage dans la région appropriée ; activer **Authentication → Anonymous**. Le déploiement de Cloud Functions et Storage peut nécessiter la facturation Blaze. Aucun rendu vidéo serveur n’est utilisé.
3. Télécharger `GoogleService-Info.plist`, l’ajouter au target iOS dans Xcode et vérifier sa présence dans Copy Bundle Resources. Ne pas committer les fichiers de configuration de votre compte. Aucun compte de service ou clé privée ne doit aller dans l’application.
4. Option de génération reproductible sur Mac : installer XcodeGen, puis `xcodegen generate --spec project-firebase.yml`. Cela ajoute FirebaseAuth, Firestore, Storage, Functions et AppCheck via Swift Package Manager. Le seul fournisseur externe est Firebase, conformément au cahier des charges ; le montage ne dépend que des frameworks Apple.
5. Activer Firebase **App Check / App Attest**. Installer un `AppCheckProviderFactory` avant `FirebaseGateway.configureIfPresent()`. Les fonctions exigent App Check. Pour les tests de développement, utiliser le fournisseur debug officiel et enregistrer son token dans Firebase ; ne pas désactiver App Check en production.
6. Appeler `configureIfPresent()` uniquement dans le futur flux de connexion explicite, puis `signIn()`. Ces fonctions ne sont volontairement pas appelées au lancement local actuel.
7. Apple ultérieurement : ajouter la capability **Sign in with Apple**, configurer le provider dans Firebase, générer un nonce cryptographique, fournir son SHA-256 à la requête Apple et son original à `linkApple`. Le contrôle Apple et la gestion des comptes existants restent à implémenter.

## Déployer

Node 22+, Java 21 pour les émulateurs, Firebase CLI et un compte autorisé :

```sh
cd Backend/functions
npm install
npm test
cd ..
firebase login
firebase use --add
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

Sélectionner votre propre projet avec `firebase use --add`. Aucun projet utilisateur n’est présélectionné dans le dépôt. Les callables sont dans **europe-west1** ; ajuster cette valeur dans le serveur et `FirebaseGateway` si une autre région est choisie. Autoriser l’accès interservices Firestore demandé lors du déploiement des règles Storage.

## Modèle distant

- `users/{uid}` : profil propre à l’utilisateur.
- `groups/{gid}` : nom, description, ownerID, timezoneID, createdAt et memberIDs (max. 8 via transactions serveur). Le tableau sert à autoriser et filtrer les requêtes, pas de groupes publics.
- `groups/{gid}/members/{uid}` : rôle et date d’entrée. Les noms/profils visibles au casting devront être matérialisés ici lors du raccordement, sans rendre les profils globaux publics.
- `invitations/{sha256(code)}` : groupID, expiresAt, createdBy. Jamais lisible directement par un client. Codes de 192 bits retournés uniquement à la création ; expiration de 72 h et révocation.
- `groups/{gid}/moments/{uid_yyyy-MM-dd}` : date déterminée par le serveur dans le fuseau du groupe, semaine yyyy-MM-dd du lundi ; seul le callable peut publier. Un document par jour/groupe/utilisateur.
- `.../moments/{mid}/reactions/{uid_type}` : identité et type stricts, parent existant, une réaction de chaque type.
- `groups/{gid}/episodes/{eid}` : réservé pour les métadonnées partagées ; **écriture cliente refusée** tant que la préparation des épisodes côté serveur n’est pas implémentée.
- `groups/{gid}/edits/{uid_episodeID}` : paramètres partagés en lecture dans le groupe, écriture propre à l’auteur.
- Storage : `groups/{gid}/uploads/{uid}/{UUID}.jpg|mp4`. Objets immuables, accès par membre, écritures propres à l’auteur, JPEG ≤8 Mo et MP4 ≤30 Mo.

Pas d’URL publique stockée dans Firestore. `FirebaseGateway.download` utilise le SDK authentifié. `publishMoment` retire les tokens de téléchargement Firebase avant de référencer la source publiée. La phase de staging et la révocation de liens précédemment copiés doivent être auditées : aucun système ne peut rappeler des copies déjà téléchargées par un membre autorisé.

La validation de 10 secondes est locale et la valeur de durée est contrôlée côté callable, mais **le serveur ne décode pas le fichier pour vérifier la durée réelle**. Un worker de validation des médias malveillants est requis avant une mise en production.

## Fonctions fournies

`createGroup`, `createInvitation`, `revokeInvitation`, `joinGroup`, `publishMoment`, `deleteMoment`, `leaveGroup`, `removeMember`, `transferOwnership`, `deleteAccount`.

Les transactions sérialisent les invitations et le plafond de huit membres. Les règles interdisent toute modification cliente de l’appartenance ou du fuseau horaire. Les propriétaires doivent transférer la propriété avant de quitter un groupe avec d’autres membres.

## Travail restant pour une vraie collaboration

- Raccorder un `CloudStoryRepository` à `StoryStore` via un protocole ; conserver une séparation explicite avec les groupes locaux.
- Convertir les documents et identifiants distants ; écouter les semaines récentes et paginer l’historique par semaine/curseur.
- Ajouter les écrans de connexion, invitation, saisie du code, révocation et gestion des membres ; n’afficher le succès qu’après réponse serveur.
- Queue persistante des uploads, reprise après interruption, annulation, progression/erreurs ; le brouillon local doit survivre à chaque erreur.
- Matérialisation serveur des épisodes et validation des IDs de scènes dans les edits ; conflits de versions et rendus invalidés sur changement de sources.
- Suppression complète et idempotente : le code retire les médias d’un membre, mais il reste à purger ses réactions sur les souvenirs des autres, références de couverture/edits, anciennes invitations et sous-collections de groupes supprimés. Ajouter une queue de nettoyage qui reprend après panne.
- Nettoyage planifié des uploads orphelins/remplacés, quotas, rate limiting et monitoring. Pas de compteurs facturables illimités en production.
- Tests des callables, concurrence des huit membres, App Check, reconnexion, rotation des codes et suppression avec panne partielle.
- Aucune fusion automatique entre compte local, compte anonyme Firebase et compte Apple n’est implémentée.

Les règles réduisent les accès côté client ; les fonctions Admin contournent ces règles et doivent donc être auditées indépendamment avant déploiement public.
