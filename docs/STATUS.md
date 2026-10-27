# DocuMind — État d'avancement

> Mémoire entre sessions. Mis à jour à chaque jalon.

## Environnement
- Dépôt de travail : `/home/dev/projects/Documind` (LXC 103), branche `main`.
- Cible : LXC 105 `documind`, `ssh root@192.168.1.67`, app `/opt/documind`, données `/opt/documind-data`, port 8000.
- OvisOCR3 : `http://192.168.1.59:8081/v1`, modèle `ovisocr3` — **OK**.
- MiniCPM5-2B : `http://192.168.1.59:8080/v1`, alias `minicpm5-2b` — **injoignable (connection refused) au démarrage**, ProxBoss réveillé.

## Décisions
- Pipeline cible : OvisOCR3 page par page (CPU, séquentiel) → MiniCPM **texte seul** (mise en forme + métadonnées + segmentation).
- OCR natif conservé pour les PDF numériques (texte natif par page ≥ `MIN_TEXT_LENGTH_PER_PAGE`).
- Cache OCR par page : `sha256(fichier) + n° page` sous `DATA_DIR/ocr_cache/`.
- Embeddings chargés paresseusement (gain RAM/démarrage), connexions SQLite réutilisées par thread.
- Aucun document personnel dans git / docs / logs poussés ; bench stocké sur LXC 105.

## Mesures
(vierge — voir `docs/PERF.md` et `docs/BENCH.md`)

## TODO
- [ ] A. Profiling + optimisations mesurées
- [ ] Déploiement LXC 105
- [ ] B. Backend OCR `ovis`
- [ ] C. MiniCPM texte seul
- [ ] D. Segmentation multi-documents
- [ ] E. CLI + skill
- [ ] F. Bench
- [ ] G. README / .env.example
