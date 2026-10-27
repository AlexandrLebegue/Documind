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
