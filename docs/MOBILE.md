# DocuMind Mobile 0.1.1

## Installation Android

Télécharger un APK dans la [release v0.1.1-mobile](https://github.com/AlexandrLebegue/Documind/releases/tag/v0.1.1-mobile).
Choisir `documind-mobile-0.1.1-release.apk` (universel) en cas de doute, ou
`arm64-v8a` pour un téléphone Android ARM 64 bits. Les variantes `armeabi-v7a`
et `x86_64` sont également fournies. Autoriser l'installation depuis la source
utilisée pour télécharger le fichier, puis ouvrir l'APK.

Les quatre APK utilisent la même clé release. Le fichier `SHA256SUMS` permet de
vérifier leur intégrité, par exemple avec `sha256sum -c SHA256SUMS` après avoir
téléchargé les quatre APK et l’IPA dans le même dossier (ou vérifier la ligne du fichier choisi).

Au premier lancement, saisir l'adresse du serveur DocuMind, par exemple
`192.168.1.50:8000`. Le téléphone doit pouvoir joindre ce serveur. L'adresse
est mémorisée et modifiable dans Réglages → Changer de serveur.

## Installation iPhone

Voir le guide pas à pas [IPHONE.md](IPHONE.md) (Sideloadly + Apple ID gratuit,
réinstallation tous les 7 jours, même Wi-Fi que le serveur).

## Utilisation

- Documents : rechercher, filtrer, consulter les métadonnées et le texte OCR,
  télécharger, ouvrir ou partager l'original. Les PDF s'ouvrent dans une
  application externe ; les images disposent d'un aperçu intégré.
- Ajouter : choisir un fichier, une image de la galerie ou scanner un document.
  Le scanner permet plusieurs pages, comprimées et assemblées en un PDF avant
  l'envoi. La pop-up affiche immédiatement « Envoi… », les octets transférés,
  puis la position dans la file serveur, l’OCR page par page et l’analyse LLM.
  « Voir la fiche » ouvre le résultat ; toute erreur offre « Réessayer ».
  Fermer le suivi laisse les envois continuer tant que l’application reste ouverte.
  Le badge global en haut permet de retrouver les envois et toute la file du serveur.
- Chat : agent en streaming ou recherche dans les documents, avec sources.
  Le bouton retour en haut revient à l’onglet précédent, même clavier ouvert.
  Toucher hors de la saisie ou faire défiler les messages ferme le clavier.
- Alertes et Plus : échéances, démarches, journaux, réglages et validation des
  verdicts de synchronisation. Aucun agent de synchronisation ne tourne sur le
  téléphone.

## Validation et développement

Depuis `phone/`, exécuter `flutter pub get`, `flutter analyze` puis
`flutter test`. Les builds Android sont exécutés exclusivement par le workflow
Mobile. Les tags `v*-mobile` publient les APK universel et par architecture, l’IPA non
signée et un `SHA256SUMS` commun, après réussite des deux jobs Android et iOS.
Les quatre secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` activent la signature release.
Sans secrets, un build de validation utilise une clé debug ; la publication
sur tag exige la clé release.

Les tests couvrent modèles/API, PDF, écrans à 360 dp et animations réduites,
les retours différés des trois sélecteurs natifs avec vérification du POST multipart,
les erreurs et annulations, le suivi des octets/file/OCR/LLM, les réessais,
la réouverture par le badge et le retour du chat à 360 dp avec clavier ouvert.
Des captures synthétiques à 390×844 sont exportables avec le test optionnel
`test/captures_test.dart` ; voir [STATUS.md](STATUS.md) pour la commande.

La CI valide la compilation et les signatures. L'installation, la caméra,
le recadrage et le partage restent à vérifier sur un téléphone réel. La CI compile
aussi l'application iOS sans signature (IPA jointe à la release) ; elle reste à
valider sur un iPhone réel.
