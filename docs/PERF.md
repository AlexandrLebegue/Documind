# DocuMind — Profiling et gains (étape A)

Mesures réalisées sur le LXC 105 (`documind`, Debian 13, 4 vCPU, 4 Go RAM,
Python 3.13, venv `/opt/documind/venv`) avec les dépendances de production.
La base de test est synthétique : 1 000 documents, ~2,3 ko de texte chacun,
un embedding de 384 dims stocké par document. Aucun document personnel n'est
utilisé dans ce fichier.

Reproductibilité :

```bash
# Depuis la racine du dépôt, dans le venv de production
python scripts/perf_profile.py imports
python scripts/perf_profile.py startup
python scripts/perf_profile.py db --docs 1000 --iterations 100
```

Comparaison « avant » = commit `617bf7a`, « après » = ce commit. Les deux
checkouts utilisent le même venv et le même cache de modèle.

## 1. Démarrage (chemin historique = init DB + chargement embeddings)

| Mesure | Avant | Après | Gain |
|---|---:|---:|---:|
| `init_db()` (base vide) | 19,8 ms | 7,4 ms | **-63 %** |
| Chargement du modèle d'embedding au démarrage | 1 354,8 ms | 0,02 ms | **différé** |
| RSS après démarrage | 473,1 Mo | 31,6 Mo | **-93 %** |
| Premier usage réel (recherche / 1er document) | 0 ms (déjà chargé) | 4 355 ms | payé une seule fois |
| RSS après premier usage | 473,1 Mo | 473,0 Mo | identique |

Le modèle `all-MiniLM-L6-v2` n'est plus chargé au boot : une instance au
repos (ou qui ne fait que servir l'API / l'UI) reste à ~32 Mo au lieu de
~470 Mo. Le coût torch + modèle est payé à la première recherche ou au
premier document traité, puis reste en mémoire.

## 2. Base SQLite / FTS5 (1 000 documents)

| Opération | Avant (médiane) | Après (médiane) | Gain |
|---|---:|---:|---:|
| `init_db()` sur base peuplée | 17,58 ms | 1,07 ms | **-94 %** |
| `list_documents(limit=50)` | 6,76 ms | 0,54 ms | **-92 %** |
| `list_documents(doc_type=…)` | 3,80 ms | 1,62 ms | -57 % |
| `count_documents()` | 0,21 ms | 0,01 ms | **-95 %** |
| `get_document()` | 0,23 ms | 0,02 ms | **-91 %** |
| `get_stats()` | 9,10 ms | 0,64 ms | **-93 %** |
| `get_all_embeddings()` | 2,42 ms | 1,47 ms | -39 % |
| `search_fts()` | 2,02 ms | 2,10 ms | inchangé (coût du MATCH) |
| RSS du process de bench | 293,7 Mo | 29,2 Mo | **-90 %** |

### Ce qui a changé
1. **Connexion SQLite réutilisée par thread** (`threading.local`) au lieu
   d'ouvrir/fermer une connexion et de rejouer les PRAGMAs à chaque requête.
2. **PRAGMAs de production** : `synchronous=NORMAL`, `busy_timeout=30 s`,
   `temp_store=MEMORY`, `cache_size` 20 Mo, `mmap_size` 128 Mo.
3. **Index** sur `doc_type`, `doc_date`, `status`, `created_at`,
   `date_expiration`, `date_echeance`, `parent_id`.
4. **Plus de `DROP`/`REBUILD` FTS5 à chaque démarrage** : la table et les
   triggers sont créés une seule fois (`IF NOT EXISTS`) ; le rebuild n'a lieu
   qu'à la création initiale. C'était le poste dominant du boot sur une base
   déjà peuplée.
5. `PRAGMA optimize` au démarrage pour rafraîchir les statistiques.

## 3. Imports et empreinte mémoire

| Import | Avant | Après |
|---|---:|---:|
| `main` (temps) | 0,456 s | 0,425 s |
| `main` (RSS) | 99,8 Mo | 100,0 Mo |

Les imports étaient déjà raisonnablement légers ; le gain principal vient
du chargement paresseux de `torch`/`sentence-transformers` et de `cv2`
(désormais importés au premier usage Tesseract, pas au démarrage).

## 4. Frontend / polling

- L'indicateur de file (`QueueIndicator`) interrogeait `/api/queue` toutes
  les **2,5 s** en permanence. Il passe à **4 s** et **saute le poll quand
  l'onglet est masqué** (`document.visibilityState`), ce qui supprime les
  requêtes inutiles en arrière-plan.
- Les autres pages chargent leurs données à la navigation ; pas de polling
  permanent identifié ailleurs.

## 5. Pistes non retenues (volontairement)

- **Remplacer sentence-transformers par un modèle plus petit** : le modèle
  actuel (384 dims, ~90 Mo) est déjà léger ; le coût est surtout l'import
  torch. Le lazy-load supprime le problème pour les instances au repos.
- **Réécrire la file ou l'API** : la file FIFO mono-worker est correcte pour
  OvisOCR3 (1 slot) ; aucune réécriture nécessaire.
- **Cache HTTP / pagination côté UI** : gains marginaux à cette échelle.
