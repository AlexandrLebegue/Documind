# DocuMind — État d'avancement

> Mémoire entre sessions. Mis à jour à chaque jalon.

## Environnement
- Dépôt de travail : `/home/dev/projects/Documind` (LXC 103), branche `main`.
- Cible : LXC 105 `documind`, `ssh root@192.168.1.67`, app `/opt/documind`, données `/opt/documind-data`, port 8000.
- OvisOCR3 : `http://192.168.1.59:8081/v1`, modèle `ovisocr3` — **OK**.
- MiniCPM5-2B : `http://192.168.1.59:8080/v1`, alias `minicpm5-2b` — **OK**, thinking désactivé.
- Hôte GPU `.59` : relancé par ProxBoss après saturation du cache RAM de `llama-server` (plafonné à 256 Mo).

## Décisions
- Pipeline cible : OvisOCR3 page par page (CPU, séquentiel) → MiniCPM **texte seul** (mise en forme + métadonnées + segmentation).
- OCR natif conservé pour les PDF numériques (texte natif par page ≥ `MIN_TEXT_LENGTH_PER_PAGE`).
- Cache OCR par page : `sha256(fichier) + n° page` sous `DATA_DIR/ocr_cache/`.
- Embeddings chargés paresseusement (gain RAM/démarrage), connexions SQLite réutilisées par thread.
- Aucun document personnel dans git / docs / logs poussés ; bench stocké sur LXC 105.
- Types canoniques : scolarité, santé, logement, banque (`releve_bancaire`), emploi, administratif ; `identite` réservé CNI/passeport/titre de séjour/permis.
- Classification : alias + mots-clés + titre + indice de nom de fichier ; titre `type — émetteur — date`, sans tags LLM ni libellés génériques.
- Dédoublonnage SHA-256 à l'upload et via `documind dedupe` ; les fichiers physiques ne sont pas supprimés.
- Reprocessus inclut désormais les documents enfants et exclut les racines déjà segmentées.
- Ingestion synchronisée : registre `file_marks` clé SHA-256, verdicts `pending|accepted|rejected|error`, seuil `INGEST_JUDGE_CONFIDENCE=0.7`.
- Candidat accepté : OCR réutilisé (`process_extracted_pages`), fichier déplacé dans `originals/` ; refusé : fichier supprimé, seules empreinte + raison conservées ; doute : fichier + texte gardés pour validation manuelle.
- CORS : `CORS_ORIGINS` configurable, défaut `*` + origines Tauri (`tauri://localhost`, `http://tauri.localhost`, `https://tauri.localhost`).
- Client desktop : Tauri 2, même export statique Next.js, écran de connexion animé (950 ms, réduit si `prefers-reduced-motion`), adresse mémorisée côté Tauri et localStorage.
- Agent : filtres locaux (extensions, magic bytes, cachés/temporaires, taille 1 Ko–50 Mo, stabilité 2 passages), cache SHA-256 chemin+taille+mtime, check serveur puis upload des seules empreintes inconnues.
- Service agent : Windows `sc` + runtime `windows-service` (ProgramData), Linux unité `systemd --user` avec copie stable dans `~/.local/bin`.

## Mesures
- Démarrage (LXC 105) : RSS 473 Mo → 32 Mo, embeddings différés (`docs/PERF.md`).
- SQLite 1 000 docs : `init_db` 17,6 → 1,1 ms, `list` 6,8 → 0,5 ms, `stats` 9,1 → 0,6 ms.
- OvisOCR3 8081 OK ; MiniCPM 8080 relancé par ProxBoss, health OK.
- OCR DPI retenu : **130**. CI.pdf : 100 DPI 23,9 s / 495 car. (champs prénom/lieu manquants), 130 DPI 34,8 s / 515 car., 150 DPI 45,1 s / 551 car. (+4 lignes, dont MRZ/taille). 130 = meilleur compromis.
- Pipeline complet mesuré : CI.pdf 1 page = ~21 s (OCR + MiniCPM + embedding) ; scan 2 documents = segmentation OK (2 enfants, textes/métadonnées/embeddings séparés).
- Service LXC 105 : RSS ~114 Mo au repos (embeddings non chargés) ; CLI `/usr/local/bin/documind` (symlink posé par l'installeur).
- Sous-ensemble 10 fichiers : 22 pages, 12 documents, 0 erreur ; 13 pages scannées à 32,05 s/page (médiane 26,86), 9 pages natives ~0,01 s/page, MiniCPM 59,71 s, crête 698 Mo.
- Corpus complet 88 fichiers / 158 pages : 90 documents, 0 erreur, ~35 min, crête 925 Mo. OCR à froid sur contenus uniques : 35 pages scannées, moyenne 41,48 s/page, médiane 36,30, p90 61,23. 28 doublons exacts, 6 doublons scannés servis par le cache (~508 s économisées).
- Segmentation réelle : 1 scan de 5 pages → 3 documents (1–2, 3–4, 5–5). 7 fichiers non supportés ignorés sans erreur.
- Comparaison Tesseract sur 3 scans : Ovis lit correctement les cartes (Tesseract dégrade nom/date ou ne rend presque rien) ; quasi-identique sur un contrat propre (similarité 0,992).
- Dédoublonnage SHA-256 : 90 → 62 documents (28 doublons supprimés), second passage : 0 doublon.
- Retraitement complet (racines + enfants) : 62 documents, 0 erreur ; `autre` = 0, expirés = 0, échéances < 30 j = 0, 63 documents au total.
- UI mobile vérifiée en 360 et 390 px : aucun débordement horizontal, titre du document avant l'aperçu, boutons principaux ≥ 44 px.
- Chat : ordre chronologique rétabli (question puis réponse), vérifié sur 3 échanges ; sources toujours affichées par titre, jamais par identifiant brut.
- Classification DGFiP : questionnaires d'activité professionnelle classés `administratif` (2 documents retraités).
- Doublons questionnaires : vérifiés comme pages différentes (1 page vs 2 pages, contenus OCR distincts, ratio 0,65), aucun dédoublonnage.
- Documents mobile : filtres type/tri + bascule grille/liste sur une seule ligne à 390 px.
- Ingestion : 16 tests `pytest` verts sur LXC 105 (validation magic bytes, seuil, registre, endpoints check/candidate, isolation de la queue).
- Agent testé de bout en bout (LXC 103 → serveur de test LXC 105:8001) : 6 candidats, filtres OK (ZIP, caché, temporaire, trop petit, fausse extension, fichier instable), 3 documents acceptés, 3 mises en attente, refus manuel et acceptation manuelle vérifiés.
- Juge (éval finale, 97 items = 90 positifs + 7 négatifs, 0 erreur) : tp=89, fn=1, fp=1, tn=6, précision 0,989, rappel 0,989, 7 `pending` (1 positif + 6 négatifs) en validation manuelle, 248,6 s. Seul faux positif : capture d'écran de paramètres acceptée à 0,85 ; le seul faux négatif (`pole emploi.txt`, conf. 0,3) part en revue manuelle.
- Desktop : `npx tauri build --no-bundle` OK (binaire `desktop/target/release/documind-desktop`) ; lancement sous Xvfb 20 s sans crash ; `cargo check`, `cargo clippy -D warnings` et `cargo fmt` verts sur l'agent.
- Frontend : `npm run lint`, `npx tsc --noEmit`, `npm run build` verts (16 routes, dont `/sync`).

## TODO
- [x] A. Profiling + optimisations mesurées
- [x] Déploiement LXC 105 (service `documind` actif, port 8000, UI servie)
- [x] B. Backend OCR `ovis` (cache page, progression, repli Tesseract)
- [x] C. MiniCPM texte seul (thinking off, JSON robuste, map-reduce)
- [x] D. Segmentation multi-documents (champs parent_id/page_start/page_end)
- [x] E. CLI + skill (`cli.py`, `bin/documind`, `skills/documind/SKILL.md`, endpoints system/segments)
- [x] F. Bench (`documind bench`, reprise, `docs/BENCH.md` : 10 fichiers puis 88)
- [x] G. README / `.env.example` / installeurs Proxmox locaux (sans clé API)
- [x] H. Classification canonique + dédoublonnage + alertes + titres utiles (commit `9f9c26d`)
- [x] I. UI mobile : navigation, chat, procédures, logs, aperçu document, cibles tactiles 44 px (commit `7493a68`)
- [x] J. Contrôle visuel desktop final et clôture du brief UI
- [x] K. Ingestion synchronisée : `file_marks`, check/candidate, juge MiniCPM, validation manuelle, CLI `documind marks`
- [x] L. Client PC Tauri 2 : écran de connexion, /sync, réglages agent, build Linux
- [x] M. Agent de synchronisation : filtres, cache SHA-256, service Windows/systemd, test bout en bout
- [x] N. CI GitHub Actions (frontend, backend, agent) + workflow desktop Windows/Linux et release sur tag
- [ ] O. Validation visuelle réelle du client Windows (poste utilisateur) et clôture du brief desktop

## Reprise desktop — 2026-10-27
- État GitHub vérifié : CI `40477005354` et Desktop `40477005378` réussis sur `18f153b`, deux plateformes et artefacts présents. Aucune release desktop à la reprise.
- Serveur LXC 105 : service actif, `/api/system` répond.
- Correction avant release : lecture du champ `status` imbriqué dans `state.json` pour afficher les vrais compteurs de l'agent ; test de régression ajouté.
- Tests Rust agent ajoutés : chemins cachés/temporaires, signatures PDF/PNG/JPEG/BMP, texte latin-1, rejet des fausses signatures et octets nuls (2 tests locaux verts).
- CI : suppression locale héritée de `DOCUMIND_DATA_DIR` conservée (isolation déjà assurée dans `tests/conftest.py`). Permission `contents: write` explicite pour la release : permission par défaut du dépôt vérifiée en lecture seule.
- **Jalon 4 terminé** : tag `v0.1.0-desktop` sur `72033d3`, client 0.1.0 (distinct du serveur 1.0.0).
- [CI main](https://github.com/AlexandrLebegue/Documind/actions/runs/40478874136) verte (frontend, backend, agent) ; [Desktop main](https://github.com/AlexandrLebegue/Documind/actions/runs/40478874044) vert sur Windows/Linux, tests desktop inclus.
- [Workflow du tag](https://github.com/AlexandrLebegue/Documind/actions/runs/40479731250) entièrement vert sur les deux plateformes.
- [Release publiée](https://github.com/AlexandrLebegue/Documind/releases/tag/v0.1.0-desktop), non brouillon : `DocuMind_0.1.0_x64-setup.exe` (3 157 423 octets), `DocuMind_0.1.0_amd64.AppImage` (82 983 416 octets), `DocuMind_0.1.0_amd64.deb` (4 574 458 octets). Trois fichiers confirmés `uploaded` par l'API GitHub avec empreintes SHA-256.
- Paquet Debian publié téléchargé et inspecté : `usr/bin/documind-desktop` et `usr/bin/documind-agent` présents. Test local de lecture des compteurs desktop vert ; les deux tests agent sont verts.
- Reste hors jalon 4 : validation visuelle et UAC/service sur un vrai poste Windows utilisateur (TODO O). Les builds Windows réussis ne remplacent pas cette validation interactive.

## Correctif archives déjà présentes — 2026-10-27
- `/api/ingest/check` consulte aussi les empreintes des documents originaux archivés (y compris ajoutés via le web après le démarrage) et crée les marques manquantes `accepted`. `/candidate` utilise la même protection, même avec `force=true`.
- Migration SQL idempotente au démarrage : rétro-remplissage depuis les originaux avec `file_hash`, sans modifier les marques/verdicts explicites existants ni créer de marques pour les segments enfants.
- LXC 105 : sauvegarde SQLite locale avant migration ; 1 → 61 marques, second passage toujours 61, 0 original avec empreinte sans marque. Service redémarré, cas signalé vérifié via l'API réelle : 1 connu `accepted`, 0 inconnu, document lié.
- 20 tests Python verts sur LXC 105, dont migration répétée, préservation des quatre verdicts, exclusion des segments/sans empreinte, archive ajoutée après démarrage, candidat déjà archivé non remis en file.
- Aucun changement client/agent : release desktop `v0.1.0-desktop` conservée ; correctif uniquement serveur. Correctif serveur `70e3edf` poussé et déployé ; [suivi CI du correctif](https://github.com/AlexandrLebegue/Documind/actions/runs/40480878218).

## Correctif Windows v0.1.1-desktop — 2026-10-27
- Causes établies dans le code v0.1.0 : commandes Tauri synchrones (`agent_status`, lecture/écriture config, installation) exécutant des accès disque et `sc`/PowerShell sans timeout ni `CREATE_NO_WINDOW`. L'ouverture de Réglages déclenchait ces commandes, puis un polling toutes les 10 s. Pas de trace du poste Windows permettant d'attribuer précisément la popup observée ; l'UAC était aussi possible via le fallback d'écriture élevé.
- Disparition des dossiers : le polling appelait `agent_get_config` puis `setConfig(cfg)` sans tenir compte des modifications locales ; l'ajout n'était pas sauvegardé avant le bouton Enregistrer. Une sélection restait donc visible au maximum jusqu'au prochain polling. Ce défaut est reproduit/couvert par le test front. Aucune preuve d'une corruption des antislashs/UNC ; tests de roundtrip ajoutés.
- Autre défaut certain : écriture dans ProgramData puis fallback PowerShell élevé, qui ne propageait pas le code de sortie du processus agent. Une erreur pouvait donc être rapportée comme un succès. Configuration principale désormais dans `app_config_dir` utilisateur, migration depuis l'ancienne config, écriture atomique par fichier temporaire unique, erreurs de lecture/JSON/écriture propagées.
- Modifications front sauvegardées automatiquement en série ; le polling ne lit que le statut et ne se chevauche pas. Une erreur de sauvegarde conserve le dossier visible et affiche un toast. Le sélecteur utilise la configuration courante au retour, sans capturer une ancienne liste.
- Installation / application au service explicite : copie de la configuration utilisateur via `install --from`, élévation Windows uniquement sur cette action. Le service continue de lire sa copie ProgramData ; après modification, utiliser « Appliquer au service ». Le code de sortie élevé est contrôlé. `sc` utilise ses codes numériques plutôt que des messages localisés.
- Commandes Tauri système/disque asynchrones via `tokio::task::spawn_blocking`, délai global 125 s ; sous-processus bornés (statut 3 s, agent 120 s, commandes internes service 10 s), processus direct tué/récolté au timeout, fenêtres console masquées sous Windows. Le sélecteur natif reste asynchrone et attend le choix utilisateur.
- Vérifications locales : 4 tests Rust desktop + 2 agent verts ; 2 régressions React vertes (UNC, polling, remontage, toast et conservation après refus d'écriture), lint et TypeScript verts. Workflow Desktop : tests workspace et front avant toute publication, matrice incluant windows-latest.
- Validation interactive sur le poste Windows réel à refaire après installation ; elle ne peut pas être remplacée par la CI. CI et publication : résultats à renseigner après exécution.
- [CI générale du correctif](https://github.com/AlexandrLebegue/Documind/actions/runs/40489411605) entièrement verte. [Desktop de validation](https://github.com/AlexandrLebegue/Documind/actions/runs/40489411785) : tests Rust/front, builds et packaging Windows/Linux réussis, deux artefacts présents (Windows 3 177 367 octets ; Linux 86 987 643 octets). Clippy local workspace avec `-D warnings` vert.
- Ajustement final : `$ErrorActionPreference = 'Stop'` pour propager aussi les erreurs de lancement/refus UAC ; tous les tests Rust locaux relancés et verts. Contrôles workspace/front conservés avant publication ; suppression du second passage Rust redondant après packaging.
- **Release v0.1.1-desktop publiée**, tag sur `b522076` : [workflow du tag entièrement vert](https://github.com/AlexandrLebegue/Documind/actions/runs/40490722761), tests avant publication sur windows-latest et Linux ; [CI finale](https://github.com/AlexandrLebegue/Documind/actions/runs/40490720196) verte.
- [Fichiers publiés](https://github.com/AlexandrLebegue/Documind/releases/tag/v0.1.1-desktop), release non brouillon, tous `uploaded` : `DocuMind_0.1.1_x64-setup.exe` (3 192 243 octets), `DocuMind_0.1.1_amd64.AppImage` (83 036 664 octets), `DocuMind_0.1.1_amd64.deb` (4 635 990 octets).
- Installateur Windows téléchargé et identifié PE/NSIS GUI ; SHA-256 `aada17851a137b9d7c5f8270739182efdff600e21c78cdc2d5c77e3acbeeb5c4`. Paquet Debian téléchargé et inspecté : client et agent présents dans `usr/bin`. Notes de release mises à jour avec les corrections, l'application explicite au service et les limites de validation interactive.

## Synchronisation Windows v0.1.2-desktop — 2026-10-27
- Signalement Chef : aucune requête agent `/api/ingest/check` ou `/candidate` depuis `192.168.1.24`, alors que les API de l’interface répondent. Cela confirme l’absence de trafic ingestion, sans établir à lui seul l’état du SCM ni le contenu de ProgramData sur ce poste.
- **Crash Windows reproduit en CI** : [run 40497121388](https://github.com/AlexandrLebegue/Documind/actions/runs/40497121388), test CLI avec un fichier valide : `thread 'main' has overflowed its stack`, après entrée dans le passage. `hash_file` allouait `[0u8; 1024 * 1024]` sur la pile (déjà présent en v0.1.1), au-delà de la marge disponible sur les threads Windows/SCM. Correction : tampon alloué sur le tas (`Vec`). En v0.1.1 le hachage précédait le premier check HTTP : ce crash est donc une cause probable forte de l’absence totale de `/check` après le premier passage de stabilité. Reproduction CI avérée ; crash du poste de Chef lui-même non observé.
- **Autres causes réelles établies dans v0.1.1** : aucun bouton ni commande Tauri n’exécutait l’agent localement ; le bouton « Synchroniser maintenant » existant appelait la synchronisation NAS du serveur. La configuration des dossiers était enregistrée dans le profil utilisateur, mais le service lisait exclusivement sa copie ProgramData (application explicite indispensable). `once` ignorait tout si `enabled=false` et rapportait pourtant un succès. Au premier passage, tous les nouveaux fichiers étaient différés jusqu’au passage suivant (60 min par défaut), sans check HTTP. Un fichier de configuration absent/invalide devenait silencieusement une configuration vide/désactivée avec URL loopback. Enfin le statut affichait un booléen persistant, pas l’état réel du service Windows.
- L’installation v0.1.1 appelait déjà `sc start` et copiait bien l’URL via `install --from` : absence de démarrage systématique et perte systématique d’URL ne sont pas démontrées. En revanche une réapplication sur service déjà démarré acceptait 1056, sans interrompre son sommeil ni mettre à jour son chemin binaire. Correction : `sc config`, arrêt attendu via SCM numérique (indépendant de la langue Windows), démarrage ; redémarrage également sous Linux.
- **Attribution au poste de Chef** : l’absence de commande locale et la confusion NAS sont certaines. Pour l’automatique, service absent/arrêté, configuration ProgramData ancienne/désactivée et accès LocalSystem restent des hypothèses tant qu’aucun état/journal du poste n’est disponible ; ne pas les présenter comme observés.
- Nouveau lancement manuel direct avec `once --from <configuration utilisateur> --data-dir <profil>/manual-sync`, sous le compte de l’utilisateur, même sans service ou automatique désactivé. État/cache/journal séparés du service pour éviter les écritures concurrentes. Stabilité vérifiée pendant le passage (deux observations espacées de 250 ms), plutôt qu’une attente de l’intervalle complet. Une seule exécution manuelle simultanée par processus app, délai de commande distinct permettant les lots longs, stderr récupéré pour les erreurs/toasts.
- Réglages : état SCM réel installé/démarré/arrêté/erreur ; dernier passage (y compris échec), prochain passage automatique, compteurs du dernier passage vus/ignorés/envoyés/acceptés/refusés/erreurs ; phase et compteurs pendant le lancement, résultat détaillé en toast, 50 dernières lignes du journal du passage le plus récent. Avertissement explicite lorsque la configuration locale diffère de celle appliquée au service ; rappel du compte LocalSystem et de l’indisponibilité possible des lecteurs réseau utilisateur. Bouton NAS renommé pour préciser son périmètre.
- Agent : journal de service `%ProgramData%\DocuMind\logs\agent.log` (rotation 2 Mo) conservé ; erreurs de configuration, de parcours et de réseau explicites ; heartbeat par POST `/api/ingest/check` avec liste vide à chaque passage et en-tête `x-documind-machine` sur toutes les requêtes. Le serveur voit désormais le passage même sans candidat stable. Aucune modification serveur nécessaire.
- Vérifications locales : 8 tests Rust (dont 2 intégrations CLI/HTTP), 4 tests React ; lint, types, clippy workspace `-D warnings`. Workflow Desktop enrichi d’un vrai test Windows installation/réapplication/redémarrage, état SCM, copie des dossiers/URL et présence du journal ; exécuté avant publication.
- La validation interactive sur le poste de Chef reste nécessaire pour confirmer l’accès à ses dossiers et attribuer définitivement son incident au crash reproduit ou à sa configuration de service.
- **Validation Windows après correction du crash** : [Desktop 40497657718](https://github.com/AlexandrLebegue/Documind/actions/runs/40497657718), job Windows terminé avec succès : tests Rust/CLI HTTP, React, véritable installation et réapplication du service sous SCM, packaging NSIS et artefact. [CI générale 40497657529](https://github.com/AlexandrLebegue/Documind/actions/runs/40497657529) entièrement verte. Le job Linux de ce run attend encore ses dépendances système ; le packaging Linux du run précédent (même interface/commandes desktop, avant le déplacement du tampon sur le tas) est vert. Publication du tag en cours après validation Windows.

- **Release v0.1.2-desktop publiée**, tag sur `2ff21f1` : [release](https://github.com/AlexandrLebegue/Documind/releases/tag/v0.1.2-desktop), non brouillon. [CI du commit du tag](https://github.com/AlexandrLebegue/Documind/actions/runs/40498368858) entièrement verte. [Workflow du tag](https://github.com/AlexandrLebegue/Documind/actions/runs/40498372003) : job `windows-latest` entièrement vert, tests d’intégration CLI, service réel et packaging inclus. Linux encore en cours à l’installation des dépendances système au moment du contrôle ; les paquets Linux seront publiés automatiquement à sa réussite.
- Installateur publié et téléchargé : `DocuMind_0.1.2_x64-setup.exe`, 3 215 770 octets, état API `uploaded`, reconnu PE/NSIS GUI. SHA-256 local : `6576794810c88bac0a50fc5d61a2b4fc376487873ba45792e9859adeb0e5b795`. Notes de release détaillées et instructions manuel/automatique mises à jour. Aucun changement serveur requis.

## Mobile v0.1 — 2026-10-28
- Application Flutter dans `phone/` (Android d'abord, `ios/` conservé), thème extrait du web : beige `#FAF8F5`/`#F5F0EB`/`#E8DDD3`, accent `#2E75B6`, mode clair uniquement, rayons/ombres identiques.
- Premier lancement : adresse du serveur validée via `/api/system` (HTTP accepté, erreurs réseau en français), mémorisée avec `shared_preferences`, modifiable depuis Réglages. Transition géométrique reprise du client PC (`GeometricTransition`) et animations respectant « réduire les animations ».
- Écrans complets : accueil, documents (recherche, filtres, tri, grille/liste, pagination), fiche document (aperçu, métadonnées éditables, OCR, échéances, segments, téléchargement/ouverture, partage, re-analyse, suppression), chat agent en streaming + mode Documents RAG, alertes/renouvellements/manquants, démarches (liste, création/édition avec documents requis, détail, exécution), synchronisation (verdicts, accept/refus/réévaluation), journaux SSE, réglages (serveur, IA, NAS, mises à jour).
- Upload validé de bout en bout sur le vrai serveur (`/api/documents/upload`, `source=phone`) : PNG de test généré (aucun document du Chef), OCR relu, suppression puis 404, compteur revenu à 91. Aucun fichier de test dans le dépôt.
- Appels API validés contre le vrai serveur avec `phone/tool/api_smoke.dart` : probe/health/stats/documents/alertes/démarches/ingest/settings, flux SSE des logs, chat streaming avec suppression de session, upload/poll/delete d'une image de test.
- Vérifications : `flutter analyze` sans erreur ; `flutter test` vert (15 tests : modèles/API avec mocks, formatters, génération PDF, widget des écrans principaux et layout à 360 dp).
- Corrections issues des tests : tags `Hero` uniques entre onglets (accueil/documents), titres de cartes Réglages flexibles, skeleton d'accueil scrollable, grille de statistiques ajustée à 360 dp.
- Compression des scans : `flutter_image_compress` sur Android/iOS avec repli portable `image` (JPEG 85 %, côté long ≤ 2000 px) ; assemblage PDF via `pdf`. `image` épinglé à 4.8.0 (`4.11.0` casse avec `archive 4.0.9`).
- Cleartext Android : `network_security_config.xml` + `usesCleartextTraffic` ; iOS : exception ATS `NSAllowsArbitraryLoads` (serveur LAN HTTP), permissions caméra/photos déclarées dans les deux plateformes.
- Workflow CI `mobile.yml` : analyze, test, APK universel + arm64-v8a/armeabi-v7a/x86_64, contrôle des signatures avec apksigner et SHA256SUMS ; publication sur tag `v*-mobile`. Caches Flutter/pub et Gradle. Aucun build Android local.
- [Run initial 40677708668](https://github.com/AlexandrLebegue/Documind/actions/runs/40677708668) sur `9a7c922` entièrement vert (APK debug de validation). [CI signée 40678396230](https://github.com/AlexandrLebegue/Documind/actions/runs/40678396230) entièrement verte sur `098f78e` : quatre APK, signatures v2 RSA 3072 vérifiées, artefacts téléchargés et SHA256SUMS validés.
- Signature release RSA 3072 : keystore et mots de passe sauvegardés hors git dans `~/documind-brief/android-keystore/` (fichiers chmod 600), quatre secrets GitHub configurés. Repli debug sans secrets pour les builds de validation ; publication tag refusée sans clé release.
- Animations corrigées : cascade atteignant réellement opacité 1 et translation 0, shimmer sans ticker avec réduction des animations, transition géométrique immédiatement terminée en mode réduit, bottom sheet 240/150 ms ou sans animation.
- 18 tests verts (dont 3 régressions animations), analyze sans erreur ; un test optionnel de captures (exécuté et vert, ignoré en CI sans variable d’export). Neuf captures golden 390×844 sur fixtures synthétiques, contrôlées visuellement : serveur, accueil, documents, chat, alertes, plus, réglages, ajout, fiche. Stockées dans `/opt/documind-data/screens/mobile/` sur LXC 105, hors git. Polices Roboto/MaterialIcons chargées explicitement dans le banc de capture.
- Export reproductible : depuis `phone/`, définir `MOBILE_CAPTURES_DIR` (répertoire absolu), `MOBILE_CAPTURES_FONT` (Roboto-Regular.ttf du cache Flutter) et `MOBILE_CAPTURES_ICONS` (MaterialIcons-Regular.otf du même cache), puis `flutter test test/captures_test.dart --update-goldens`.
- Test réel relancé après reprise : probe, API principales, SSE journaux et chat (session supprimée), upload PNG synthétique → statut ready → suppression, succès complet. Aucun document réel exporté. Release publiée et vérifiée.

### Parité écran web -> mobile
| Écran web | Écran mobile | État |
|---|---|---|
| `/` tableau de bord | Accueil (`dashboard_screen.dart`) | Fait |
| `/documents` liste + recherche/filtres/tri | Documents (`documents_screen.dart`) | Fait |
| `/documents/view` fiche | Fiche document (`document_detail_screen.dart`) | Fait |
| Upload / ajout document | Bottom sheet + fichier/galerie/scanner | Fait, validé E2E |
| `/chat` chat agent | Chat (`chat_screen.dart`) | Fait (agent SSE + RAG) |
| `/alerts` alertes | Alertes (`alerts_screen.dart`) | Fait |
| `/procedures` liste | Démarches (`procedures_screen.dart`) | Fait |
| `/procedures/view` détail | Démarche détail (`procedure_detail_screen.dart`) | Fait |
| `/procedures/new` création | Démarche création (`procedure_editor_screen.dart`) | Fait |
| `/procedures/edit` édition | Démarche édition (`procedure_editor_screen.dart`) | Fait |
| `/sync` verdicts | Synchronisation (`sync_screen.dart`) | Fait |
| `/logs` journaux | Journaux (`logs_screen.dart`) | Fait (SSE) |
| `/settings` réglages | Réglages (`settings_screen.dart`) | Fait |

### Livraison mobile — validation CI
- [CI générale finale](https://github.com/AlexandrLebegue/Documind/actions/runs/40678907410) verte sur `0150e2b` ; [Mobile final](https://github.com/AlexandrLebegue/Documind/actions/runs/40678907417) entièrement vert : analyze, tests, quatre builds et vérification des signatures réussis.
- Certificat release SHA-256 : `3bfa467e4b7bf11efd6f5ea8286f85602e4fbe643e9081c4e427b17033724174`, identique au certificat du keystore privé. Aucune compilation Android locale.
- Limites : scanner/caméra, partage natif et installation à valider sur téléphone Android réel ; iOS conservé mais non compilé dans ce jalon. Le PDF original s’ouvre dans une application externe ; aperçu intégré réservé aux images.

### Release v0.1.0-mobile publiée
- **Jalon 4 terminé** : tag `v0.1.0-mobile` sur `d79f322`, [workflow du tag 40679954980 entièrement vert](https://github.com/AlexandrLebegue/Documind/actions/runs/40679954980), [release publique non brouillon](https://github.com/AlexandrLebegue/Documind/releases/tag/v0.1.0-mobile).
- Quatre APK release et `SHA256SUMS` confirmés `uploaded` via l’API GitHub, téléchargés puis vérifiés (`sha256sum -c SHA256SUMS` : 4 OK). Les quatre certificats vus par apksigner sont identiques à la clé sauvegardée. Notice : [MOBILE.md](MOBILE.md).
- Correction du filtre Desktop : l’ancien `v*` avait aussi déclenché un packaging PC sur le tag mobile ; trois installateurs PC retirés de cette release, exclusion `!v*-mobile` ajoutée au workflow Desktop. Aucun APK modifié, releases desktop conservées.

| APK publié | Octets | SHA-256 |
|---|---:|---|
| `documind-mobile-0.1.0-arm64-v8a-release.apk` | 22109760 | `e87df9c14f70f506b0790e53e87a18cfad97ddc33bb37b49eeef320e05f27b87` |
| `documind-mobile-0.1.0-armeabi-v7a-release.apk` | 20228566 | `aa16a4a59a5e0c2163d17d63eebbe439d3d1f0a0ab5a2af67e80e0b13933ea68` |
| `documind-mobile-0.1.0-release.apk` | 60850829 | `9e57c21dd9a00bfe8d0db6af6c66d86a31f45ff10a607b0a6173157373e9d45a` |
| `documind-mobile-0.1.0-x86_64-release.apk` | 23281855 | `58818276d80630ffc5b23a43d07d237ea2af6ba3b0ffe9463ac9973808b8d4cc` |

### Correctifs mobile v0.1.1 — 2026-10-28
- **Cause du blocage établie par reproduction widget** : les trois actions de `AddDocumentSheet` faisaient `Navigator.pop` puis attendaient le sélecteur/scanner avec le contexte de cette même bottom sheet. Après l’animation inverse, le contexte était démonté ; le contrôle `context.mounted` abandonnait silencieusement le résultat avant `uploadDocument`. Le test initial du retour différé de galerie attendait un POST et en observait **0**. Les validations API de v0.1.0 contournaient ce parcours et ne pouvaient pas détecter ce bug.
- La sheet retourne désormais uniquement le choix de source ; son appelant utilise le contexte durable du shell pour le sélecteur, la revue du scan, le PDF et le suivi. Tests des trois canaux natifs avec réponse différée après destruction effective de la sheet : POST `/api/documents/upload`, corps multipart sérialisé par Dio, octets PNG/PDF et source contrôlés. Erreurs natives visibles en français, annulations sans effet de bord.
- `TransferState`, détenu par `AppState`, conserve les envois et leurs fichiers pour réessai indépendamment de la modale. Suivi immédiat « Envoi… » et octets envoyés/total, puis `/api/documents/{id}` et `/api/queue` toutes les 2 s : position, OCR page x/y, analyse LLM lorsque toutes les pages OCR sont traitées, fiche finale, erreur et réessai (nouvel upload ou `/reprocess` selon la phase). Le badge global rouvre les transferts et la file complète (travail actif, tous les travaux en attente et historique). Fermer la modale ne coupe pas les envois ; polling suspendu lorsque l’app passe en arrière-plan. Les envois ne sont pas un service de transfert après fermeture de l’app.
- Entrées fichiers : lecture en flux demandée au picker, chemins natifs mis en cache, URI `file://` normalisées, repli bytes/flux vers un fichier temporaire réutilisable. Une entrée inaccessible, vide ou supérieure à 50 Mo affiche une erreur plutôt que disparaître. Une page de scan illisible interrompt la création du PDF avec son numéro, sans omission silencieuse.
- Plateformes inspectées : `Info.plist` déclare caméra et photothèque, ATS pour le serveur HTTP ; manifeste Android : Internet, caméra, images et cleartext. Le picker iOS 11.0.3 convertit le filtre `pdf/jpg/jpeg/png/txt` en UTI système avant `UIDocumentPickerViewController` ; aucun type personnalisé à déclarer. Les fournisseurs Android sont copiés par le plugin dans son cache local avant retour ; une URI brute non exploitable produit une erreur visible. Ces permissions ne sont pas la cause commune observée.
- Chat : vraie AppBar avec retour vers l’onglet précédent, fermeture du clavier au retour, au tap extérieur et `keyboardDismissBehavior.onDrag` sur les deux listes (suggestions et messages). Régression à 360 dp avec `viewInsets.bottom=300` : bouton en haut accessible, retour Documents et focus fermé, aucun débordement.
- Livraison préparée : version Flutter `0.1.1+2`, CI Android/iOS puis job de publication commun dépendant des deux succès ; quatre APK signés, IPA non signée et `SHA256SUMS` commun. Notices MOBILE/IPHONE actualisées. Aucune compilation Android locale, aucun changement serveur.
- Vérification locale finale : `flutter analyze --no-pub` sans aucun diagnostic ; `flutter test --no-pub` : **37 tests réussis**, 1 test de captures optionnel ignoré. Les 19 nouveaux tests couvrent les trois sources (POST différé, erreur, annulation), le suivi/badge/réessai, clavier/retour, URI/bytes/flux, limites de taille et page de scan illisible.
