# DocuMind mobile

Client Flutter de DocuMind (Android d'abord, compatible iOS). L'application se
connecte à un serveur DocuMind accessible sur le réseau local et reprend les
écrans du client web, à l'exception de l'agent et du service de synchronisation.

## Développement

```bash
flutter pub get
flutter analyze
flutter test
```

Le SDK Flutter local (`~/flutter`, stable) suffit pour l'analyse et les tests.
La construction de l'APK se fait en CI, pas sur le LXC 103.

## Configuration

Au premier lancement, saisir l'adresse du serveur (par exemple
`192.168.1.50:8000`). Elle est mémorisée localement et peut être modifiée dans
Réglages. Le trafic LAN en HTTP clair est autorisé côté Android
(`network_security_config.xml`) et iOS (exception ATS).

## Structure

- `lib/api/` : client HTTP et SSE
- `lib/models/` : modèles API
- `lib/screens/` : écrans et navigation
- `lib/widgets/` : composants réutilisables
- `lib/theme/` : jetons de la direction artistique web
