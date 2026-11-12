# PlotTwist

Application iPhone native SwiftUI, iOS 17+, interface anglaise, identité nocturne/corail/violet.

## Ouvrir l’application

1. Sur un **Mac avec Xcode 16 ou supérieur**, ouvrir `PlotTwist.xcodeproj`.
2. Choisir le schéma **PlotTwist**, puis un simulateur iPhone iOS 17+.
3. Lancer avec **⌘R**. Le projet local ne dépend d’aucun package externe, compte Firebase ou clé.
4. Sur un vrai iPhone : sélectionner votre équipe dans **Signing & Capabilities**, remplacer `com.example.plottwist` par un identifiant unique, connecter l’iPhone, activer son mode développeur et lancer.
5. Pour tester immédiatement un épisode terminé : troisième page d’onboarding → **Explore demo**. Les personnages et affiches sont fictifs et explicitement marqués comme démonstration. Les mêmes vrais importeurs, stockage et moteur vidéo sont utilisés.

Le projet `.xcodeproj` est fourni directement : XcodeGen n’est pas nécessaire. Les fichiers `project.yml` et `project-firebase.yml` permettent de le régénérer si souhaité.

## Implémenté

- Trois pages d’onboarding, profil éditable et avatar.
- Groupes locaux, couverture, description et fuseau horaire immuable ; sélection du groupe et suppression locale.
- Accueil, timeline navigable par semaines, bibliothèque avec affichage progressif, casting et statistiques dérivées des données.
- PhotosPicker ; photos JPEG redimensionnées à 1920 px ; vidéos MP4 720p limitées aux dix premières secondes et 30 Mo.
- Prévisualisation, légende, brouillon persistant, remplacement du souvenir du jour et suppression de ses propres médias.
- Un identifiant déterministe par utilisateur/groupe/jour ; semaine lundi→lundi dans le fuseau du groupe, changements d’heure compris.
- Réactions locales Laugh, Fire, Plot twist : une par type/utilisateur/souvenir.
- Détection des semaines terminées à l’ouverture et au retour au premier plan ; aucun rendu serveur ou en arrière-plan promis.
- Éditeur persistant : titre, trois styles qui changent réellement le rendu, ordre, inclusion, couverture, légendes, audio original et volume.
- **Encodage MP4 réel** : 1080×1920, H.264, 30 FPS, images sans déformation, zoom léger, fades, textes, intro et conclusion. Lecture frame par frame des vidéos avec leur orientation ; audio original optionnel recomposé ensuite.
- Bande-annonce courte, lecteur plein écran, partage iOS et ajout à Photos.
- Progression fondée sur les frames écrites et l’export audio ; annulation et erreurs ; fichiers partiels supprimés.
- Rappels locaux à heure choisie et rappel du lundi, demandés uniquement après action. Le rappel hebdomadaire est conditionnel dans son texte : il ne prétend pas connaître un épisode déjà généré.
- Sauvegarde JSON atomique en Application Support, protection des fichiers et nettoyage après 24 h des fichiers qui ne sont plus référencés.
- Icône originale, configurations Debug/Release, manifeste de confidentialité et premières ressources en/fr.

## État réel et limites

**Ce dépôt est une première implémentation locale ; il ne constitue pas une version App Store validée.**

L’environnement de création est Linux : aucun SDK iOS, Xcode, simulateur ou iPhone n’y est disponible. Le projet n’a donc **pas été compilé avec Xcode**, et les rendus AVFoundation n’ont pas été exécutés ici. Une analyse syntaxique Swift ne remplace pas une compilation. Voir `VALIDATION.md` pour distinguer les tests exécutés des tests fournis.

**Collaboration Firebase non raccordée à l’interface.** L’application n’envoie rien automatiquement. L’adaptateur SDK optionnel, les règles et les fonctions serveur sont fournis dans `Backend/` pour préparer la phase 3 ; ajouter le plist seul n’active pas la synchronisation. Il reste à développer le repository distant, les listeners, les conflits/hors-ligne, les invitations dans l’interface et les tests multiappareils. Il n’y a donc pas encore de parcours complet « inviter mes vrais amis » dans cette version. Voir `FIREBASE.md`.

Autres limites assumées :

- Recadrage automatique centré dans la vidéo ; pas d’éditeur de crop manuel ni de sélection de la portion du clip (premières dix secondes).
- Les styles changent palette, typographie, cadre et overlays ; pas de filtre film avancé ni de musique intégrée.
- Les épisodes peu fournis sont plus courts. Maximum 24 scènes, budget jusqu’à environ 75 secondes ; bande-annonce : jusqu’à six scènes, environ 14 secondes au maximum.
- Équilibrage des membres lors de la sélection initiale ; l’utilisateur peut ensuite modifier l’ordre et la sélection.
- Rendu à garder au premier plan. Une courte tâche de fond protège les interruptions ; iOS peut l’expirer et annuler. Pas de reprise à mi-export.
- Décodage par AVAssetImageGenerator : mémoire bornée par scène, mais débit à mesurer sur iPhone. Pas encore de rendu matériel optimisé ni de cache d’images partagé.
- Aucun fichier vidéo cloud ; seules les sources/paramètres sont envisagés pour le backend. Les données locales ne survivent pas à la désinstallation sans sauvegarde de l’appareil.
- Pas de push, pas de paiement, pas de publication automatique sur les réseaux, pas d’analytics.
- Prise en charge VoiceOver de base et texte système ; grands titres personnalisés à auditer en très grande taille de texte. Localisation française partielle, pas complète.
- Le compte local est indépendant de l’identité Firebase. Le lien Apple est une méthode de l’adaptateur, pas encore une action du profil.
- Les données démo sont accessibles volontairement dans cette version de développement. Les exclure d’une édition App Store et utiliser une installation propre pour la validation Release.

## Structure

`PlotTwist/App` : lancement et navigation ; `Models` : état Codable ; `Core` : calendrier/planification ; `Services` : stockage, médias, notifications et adaptateur Firebase ; `Features` : écrans ; `Components` : design ; `VideoRendering` : moteur AVFoundation ; `Resources` : icône, permissions et localisation. `PlotTwistTests` contient les tests XCTest. `Backend` contient les fonctions Node, règles et tests Firebase.

## Vérifier sur Mac

```sh
xcodebuild -list -project PlotTwist.xcodeproj
# Remplacer par un simulateur disponible avec : xcrun simctl list devices available
xcodebuild -project PlotTwist.xcodeproj -scheme PlotTwist \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Les tests `RendererTests` encodent effectivement une courte vidéo : ils nécessitent un environnement iOS avec encodeur, pas seulement un interpréteur Swift. Le guide de test physique et les points de publication sont dans `TESTING.md`.
