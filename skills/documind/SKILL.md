---
name: documind
description: Piloter l'archive documentaire locale Documind (OCR OvisOCR3, métadonnées Qwen, recherche hybride, questions RAG). À utiliser dès qu'il faut téléverser, lister, consulter, rechercher, interroger, retraiter, supprimer ou mesurer des documents sur le LXC 105, sans passer par l'interface web.
---

# Documind

Documind est une archive documentaire auto-hébergée. Chaque fichier est OCRisé
(OvisOCR3 en local, CPU, page par page), analysé par Qwen3.8-27B via HyperQwen/vLLM (texte seul),
puis indexé pour la recherche plein texte + sémantique. Les scans contenant
plusieurs documents sont découpés en fiches distinctes.

- API : `http://192.168.1.67:8000` (surchargeable par `DOCUMIND_URL` ou `--url`).
- CLI sur le LXC 105 : `/opt/documind/bin/documind`.
- Depuis le dépôt : `./bin/documind`.
- Sortie **JSON par défaut** ; ajouter `--human` pour un rendu lisible.
- Les options globales (`--url`, `--human`, `--timeout`) se placent **avant**
  la sous-commande : `documind --human list`, pas `documind list --human`.

## Quand l'utiliser

- Téléverser un PDF ou une image, ou tout un dossier, et attendre le traitement.
- Retrouver un document par type, date, mots-clés ou similarité.
- Poser une question en langage naturel sur la collection (RAG).
- Vérifier l'état du service, de la file ou d'un document.
- Relancer le pipeline après un changement de modèle ou une erreur.
- Mesurer les performances sur un corpus sans exposer le contenu des documents.

## Commandes

```bash
documind status                     # santé, RAM, file, statuts
documind status <id>                # un document + ses segments
documind queue                      # file de traitement
documind upload fichier.pdf --wait  # traiter et attendre la fin
documind upload dossier/            # ingestion séquentielle (sans attendre)
documind list --type facture --since 2024-01-01 --q EDF
documind show <id> --meta           # métadonnées seules (défaut)
documind show <id> --text           # texte OCR complet
documind show <id> --pages          # texte page par page
documind search "facture électricité 2024"
documind ask "Combien ai-je payé d'impôts en 2023 ?"
documind reprocess <id> --wait
documind delete <id> --yes
documind stats
documind bench /srv/docs-test --out /opt/documind-data/bench/run.csv
```

### Exemples

```bash
# Ingérer un scan et récupérer son identifiant
documind upload ~/scan.pdf --wait | jq -r '.files[0].id'

# Vérifier qu'un scan multi-documents a bien été découpé
documind --human status <id>

# Recherche JSON pour un agent
documind search "attestation employeur" | jq '.results[0].document | {id,title,doc_type}'

# Question avec sources
documind --human ask "Quelle est la date d'expiration de ma carte d'identité ?"
```

## Comportement important

- **File unique** : les traitements sont séquentiels (OvisOCR3 n'a qu'un slot).
  `upload dossier/` renvoie vite ; utiliser `queue` ou `status` pour suivre.
  Ne pas lancer plusieurs `bench` ou gros `upload --wait` en parallèle.
- **`--wait`** attend le document et, si c'est un scan multi-documents, ses
  enfants (`status: segmented`, champs `parent_id`, `page_start`, `page_end`).
- **Temps** : compter ~20–60 s par page selon DPI et densité ; un document de
  5 pages peut prendre plusieurs minutes. Le timeout CLI par défaut est 600 s.
- **Segmentation** : le parent `segmented` n'a plus de texte ni d'embedding ;
  ce sont les enfants qui sont cherchables. `list` et `stats` excluent le parent.
- **Suppression** : `delete` supprime aussi les enfants d'un parent segmenté ;
  le fichier original n'est retiré que si plus aucune fiche ne le référence.
- **Données personnelles** : ne jamais copier de texte OCR, de nom ou de contenu
  de document dans un commit, un ticket, un log externe ou une réponse publique.
  Le CSV de `bench` contient des noms de fichiers : le garder sur le LXC 105.

## API (si le CLI ne suffit pas)

- `GET /api/health`, `GET /api/system`, `GET /api/queue`
- `POST /api/documents/upload` (multipart champ `file`)
- `GET /api/documents` (`doc_type`, `date_from`, `q`, `limit`, `offset`)
- `GET /api/documents/{id}`, `GET /api/documents/{id}/segments`
- `GET /api/documents/{id}/file`
- `POST /api/documents/{id}/reprocess`, `DELETE /api/documents/{id}`
- `POST /api/search` `{"query": "..."}`
- `POST /api/chat` `{"message": "...", "session_id": "..."}`
- `GET /api/stats`

## Erreurs fréquentes

- **`Cannot reach http://…`** : service arrêté ou mauvaise URL. Vérifier
  `systemctl status documind` sur le LXC 105, puis `curl /api/health`.
- **HTTP 503 « LLM or embedding model not loaded »** : le service démarre encore
  ou Qwen/Ovis est injoignable. Vérifier `/api/health`, puis les backends
  (`http://192.168.1.59:18020/v1/models`, `http://192.168.1.59:8081/v1/models`).
- **Qwen ou Ovis ne répond pas** : vérifier `LLM_API_KEY` et `LLM_BASE_URL`
  dans l'environnement du service, puis réveiller la machine GPU avec
  `~/.local/bin/proxboss-wake "..."` puis relancer `documind status`.
- **Document en `error`** : lire `error_message` via `documind status <id>`,
  corriger la cause, puis `documind reprocess <id> --wait`.
- **`total_seconds` null sur un ancien document** : fiche traitée avant l'ajout
  des mesures ; `reprocess` pour la compléter.
- **Argument `--wait` non reconnu après `upload`** : le placer après le chemin
  (`documind upload fichier --wait`) ; `--human` se place avant `upload`.

## Bonnes pratiques

1. Vérifier `documind status` avant un lot ; s'assurer que `file.en attente = 0`.
2. Pour un lot, préférer `documind bench dossier` ou `upload dossier/` puis
   surveiller `queue`, plutôt que des dizaines de `upload --wait`.
3. Utiliser `--human` pour un humain, JSON + `jq` pour un agent.
4. Ne pas paralléliser : le pipeline est volontairement séquentiel (RAM et slot
   OCR uniques).
5. Après un changement de modèle/prompt, `reprocess` un échantillon avant de
   relancer tout le corpus.
6. Garder les résultats de bench et les documents dans
   `/opt/documind-data/` (jamais dans git).
