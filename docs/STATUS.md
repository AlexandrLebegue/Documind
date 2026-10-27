# DocuMind — État d'avancement

> Mémoire entre sessions. Mis à jour à chaque jalon.

## Environnement
- Dépôt de travail : `/home/dev/projects/Documind` (LXC 103), branche `main`.
- Cible : LXC 105 `documind`, `ssh root@192.168.1.67`, app `/opt/documind`, données `/opt/documind-data`, port 8000.
- OvisOCR3 : `http://192.168.1.59:8081/v1`, modèle `ovisocr3` — **OK**.
- MiniCPM5-2B : `http://192.168.1.59:8080/v1`, alias `minicpm5-2b` — **OK** (relancé par ProxBoss), thinking désactivé.

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
- [ ] J. Contrôle visuel desktop final et clôture du brief UI
