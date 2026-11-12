# Validation effectuée

Date : 12 novembre 2026. Environnement Linux, sans Xcode ni SDK iOS.

## Exécuté avec succès

- Analyse syntaxique des **17 fichiers Swift** (sources et XCTest) avec le parseur Tree-sitter Swift : aucune erreur de parsing.
- Lecture du `project.pbxproj` avec OpenStep : **67 objets, 91 références** ; aucune référence manquante, tous les chemins de ressources/sources existent.
- Lecture des plist, du manifeste de confidentialité, des JSON et du schéma Xcode : formats valides.
- `node --check Backend/functions/index.js` : syntaxe Node valide.
- **5 tests de logique Node** : limites des semaines dans le fuseau du groupe, changements d’heure/année, plafond du casting, hash des invitations, limites MIME/taille.
- **6 tests de règles contre les vrais émulateurs Firebase Firestore et Storage** : refus des outsiders et clients non connectés ; requêtes des groupes autorisées par appartenance ; interdiction de changer membres/fuseau ; refus des publications clientes et de l’usurpation d’auteur ; identité/type/parent des réactions ; accès aux objets privés et écriture réservée à l’auteur avec MIME autorisé.

Résultat : **11 tests Node/émulateurs passés, 0 échec.** Les messages PERMISSION_DENIED présents dans les logs correspondent aux refus attendus par `assertFails`.

## Fournis, mais pas exécutés ici

Les XCTest de `PlotTwistTests/` couvrent : calendrier Swift, changement d’heure, passage d’année, brouillons périmés, identifiants journaliers, sélection équitable/chronologique de 24 scènes, clips courts, remplacement journalier et suppression réservée à l’auteur. `RendererTests` encode un vrai MP4 court et vérifie sa piste 1080×1920/durée, l’échec sans sources et le token d’annulation.

**Aucune compilation, aucun lancement iOS et aucun rendu MP4 n’a été exécuté dans cet environnement.** Le parsing Swift n’effectue ni résolution des API Apple, ni vérification des types ou de l’isolation des acteurs. Les performances physiques et le stress test à plusieurs dizaines de médias restent à mesurer.

Le fichier de projet local n’utilise pas les packages Firebase. Le gateway conditionnel et la génération optionnelle avec Firebase doivent aussi être compilés et testés séparément sur Mac. Les callables serveur ont été vérifiés syntaxiquement ; leurs transactions, App Check et scénarios de panne n’ont pas été testés avec l’émulateur Functions.

## Reproduire les tests Node

```sh
cd Backend/functions
node --test domain.test.js
node --check index.js
cd ..
npm install
npm test
```

Java 21 et Node 22 sont nécessaires aux émulateurs. Le projet de test est `demo-plottwist`, sans accès aux services de production. Voir `TESTING.md` pour les vérifications physiques et `FIREBASE.md` pour les limites du backend.
