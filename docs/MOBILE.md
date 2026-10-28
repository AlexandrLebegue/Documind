# DocuMind Mobile 0.1.0

## Installation Android

Télécharger un APK dans la [release v0.1.0-mobile](https://github.com/AlexandrLebegue/Documind/releases/tag/v0.1.0-mobile).
Choisir `documind-mobile-0.1.0-release.apk` (universel) en cas de doute, ou
`arm64-v8a` pour un téléphone Android ARM 64 bits. Les variantes `armeabi-v7a`
et `x86_64` sont également fournies. Autoriser l'installation depuis la source
utilisée pour télécharger le fichier, puis ouvrir l'APK.

Les quatre APK utilisent la même clé release. Le fichier `SHA256SUMS` permet de
vérifier leur intégrité, par exemple avec `sha256sum -c SHA256SUMS` après avoir
téléchargé tous les APK dans le même dossier.

Au premier lancement, saisir l'adresse du serveur DocuMind, par exemple
`192.168.1.50:8000`. Le téléphone doit pouvoir joindre ce serveur. L'adresse
est mémorisée et modifiable dans Réglages → Changer de serveur.

## Utilisation

- Documents : rechercher, filtrer, consulter les métadonnées et le texte OCR,
  télécharger, ouvrir ou partager l'original. Les PDF s'ouvrent dans une
  application externe ; les images disposent d'un aperçu intégré.
- Ajouter : choisir un fichier, une image de la galerie ou scanner un document.
  Le scanner permet plusieurs pages, comprimées et assemblées en un PDF avant
  l'envoi. L'écran d'analyse suit le traitement serveur.
- Chat : agent en streaming ou recherche dans les documents, avec sources.
- Alertes et Plus : échéances, démarches, journaux, réglages et validation des
  verdicts de synchronisation. Aucun agent de synchronisation ne tourne sur le
  téléphone.

## Validation et développement

Depuis `phone/`, exécuter `flutter pub get`, `flutter analyze` puis
`flutter test`. Les builds Android sont exécutés exclusivement par le workflow
Mobile. Les tags `v*-mobile` publient les APK universel et par architecture.
Les quatre secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` activent la signature release.
Sans secrets, un build de validation utilise une clé debug ; la publication
sur tag exige la clé release.

Les tests couvrent modèles/API, PDF, écrans à 360 dp et animations réduites.
Des captures synthétiques à 390×844 sont exportables avec le test optionnel
`test/captures_test.dart` ; voir [STATUS.md](STATUS.md) pour la commande.

La CI valide la compilation et les signatures. L'installation, la caméra,
le recadrage et le partage restent à vérifier sur un téléphone réel. Le projet
iOS et ses permissions sont conservés ; cette version n'a pas été compilée ni
validée sur iPhone.
