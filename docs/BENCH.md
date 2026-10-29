# Benchmark — pipeline local OvisOCR3 + MiniCPM5-2B (historique)

Mesures agrégées, sans contenu ni nom de document. Les CSV détaillés restent
sur le LXC 105 dans `/opt/documind-data/bench/`.

## Méthode

- LXC 105 : 4 vCPU, 4 Go RAM, Debian/Python 3.13, service `documind`.
- OCR : OvisOCR3 `http://192.168.1.59:8081/v1`, CPU, 1 slot, pages strictement
  séquentielles, DPI 130, prompt `plain`.
- LLM : MiniCPM5-2B `http://192.168.1.59:8080/v1`, thinking désactivé, texte seul.
- **Ce document est historique** : MiniCPM a été remplacé par Qwen3.8-27B
  (`http://192.168.1.59:18020/v1`). Les temps ci-dessous ne s'appliquent pas au
  nouveau modèle ; les prochains benchs seront publiés séparément.
- Embeddings : `all-MiniLM-L6-v2`, CPU, chargement paresseux.
- Temps OCR = rendu + OCR serveur par page, mesuré dans le pipeline ; temps LLM =
  extraction des métadonnées (hors embedding) ; `wall` = attente complète côté CLI,
  file incluse. Les PDF avec texte natif ne passent pas par l'OCR (0 s).
- Cache OCR vidé avant le sous-ensemble pour mesurer l'OCR réel.
- Les pages scannées et les pages natives sont séparées : la moyenne globale
  « s/page » n'a de sens que par catégorie.

## Sous-ensemble varié — 10 fichiers

10 fichiers, 22 pages, 12 documents produits (un scan multi-documents a donné
3 fiches). Aucune erreur.

| Catégorie | Fichiers | Pages | OCR total | OCR s/page | Documents |
|---|---:|---:|---:|---:|---:|
| Pages scannées (Ovis) | 5 | 13 | 416,61 s | **32,05** | 7 |
| Pages natives (pas d'OCR) | 5 | 9 | 0,10 s | 0,01 | 5 |
| **Total** | **10** | **22** | **416,71 s** | — | **12** |

- MiniCPM : **59,71 s** au total pour 12 documents produits (médiane à compléter
  avec le corpus complet), soit ~5 s par fiche.
- Durée murale cumulée : **506,89 s** (dont ~190 s pour le contrat scanné de
  5 pages et ~208 s pour le scan multi-documents de 5 pages).
- RAM crête du processus : **698,4 Mo** (embeddings chargés).
- OCR page scannée : médiane par fichier **26,86 s/page**, moyenne **32,05 s/page**.
  La dispersion vient de la densité de page et du nombre de tokens générés.

### Long document

Un PDF natif de 21 pages a demandé 0,19 s d'OCR (texte natif) mais ~70,6 s de
MiniCPM : le texte dépassait le seuil de map-reduce, qui a découpé puis fusionné
les métadonnées. C'est le comportement attendu pour les gros documents.

## Contrôle qualité OCR vs Tesseract (3 scans)

Comparaison sur la première page, Tesseract 300 DPI avec `fra` contre Ovis 130 DPI.
La similarité caractère est peu informative quand l'ordre des lignes diffère ;
le rappel de mots et la lecture manuelle le sont davantage.

| Type de page | Ovis (car.) | Tesseract (car.) | Rappel mots vs Tesseract | Constat |
|---|---:|---:|---:|---|
| Carte d'identité, recto | 515 | 533 | 0,745 | Ovis lit correctement nom, prénom, date et lieu ; Tesseract dégrade le nom et la date. |
| Carte d'identité, verso | 245 | 26 | 0,500 | Ovis extrait l'adresse, les dates et l'autorité ; Tesseract ne rend qu'une ligne. |
| Contrat, page 1 | 2 338 | 2 348 | 0,990 | Textes quasi identiques (similarité 0,992). |

Conclusion : Ovis est nettement meilleur sur les cartes et les scans difficiles,
équivalent à Tesseract sur un contrat propre. Le repli Tesseract reste utile en
cas d'indisponibilité d'Ovis, pas comme backend principal.

## Segmentation multi-documents

Sur les 10 fichiers du sous-ensemble, un scan de 5 pages a été détecté comme
3 documents contigus :

| Segments | Pages | Types |
|---|---|---|
| 3 | 1–2, 3–4, 5–5 | autre, autre, identité |

Couverture complète, sans chevauchement. Les 9 autres fichiers sont restés
mono-document.

## Corpus complet — 88 fichiers

Exécution terminée avec `--resume`, sans erreur.

| Indicateur | Valeur |
|---|---:|
| Fichiers traités | 88 |
| Pages | 158 (49 scannées, 109 natives) |
| Contenus uniques (SHA-256) | 60 |
| Doublons de contenu | 28 fichiers |
| Documents produits | 90 |
| Échecs | **0** |
| Durée murale cumulée | 2 101,8 s (~35 min) |
| Durée murale médiane / p90 | 6,0 s / 50,1 s |
| Fichier le plus long | 450,8 s (scan de 7 pages, 22 Mo) |
| MiniCPM total | 477,8 s |
| MiniCPM médian / p90 par fichier | 3,66 s / 8,44 s |
| MiniCPM moyen par fiche | 5,31 s |
| RAM crête du processus | **925,2 Mo** |

### OCR à froid (contenus uniques)

Le corpus contient 28 doublons exacts (mêmes SHA-256). Le cache page évite de
ré-OCRiser ces doublons : 6 doublons scannés (14 pages) ont été servis par le
cache, économisant ~508 s. Pour ne pas sous-estimer l'OCR, les statistiques
ci-dessous ne gardent que la première mesure à froid de chaque contenu.

| Indicateur | Valeur |
|---|---:|
| Fichiers scannés uniques | 20 |
| Pages scannées uniques | 35 |
| Temps OCR froid total | 1 451,8 s |
| Moyenne | **41,48 s/page** |
| Médiane | **36,30 s/page** |
| p90 | **61,23 s/page** |

Les 80 pages natives uniques ne passent pas par l'OCR (~0,01 s/page). La moyenne
globale de 9,21 s/page sur les 158 pages n'est donc pas représentative : il faut
raisonner par catégorie.

### Segmentation et formats

- 1 scan sur 88 a été segmenté : 5 pages → 3 documents contigus (1–2, 3–4, 5–5).
- 7 fichiers non supportés (2 `.docx`, 2 `.txt`, 2 `.rar`, 1 `.zip`) ont été
  listés et ignorés sans erreur.
- Aucun document n'est resté en `error` à la fin du run.

## Reproduire

```bash
# Sous-ensemble (liste de chemins, un par ligne)
documind bench --files-from /opt/documind-data/bench/subset-files.txt \
  --out /opt/documind-data/bench/subset.csv

# Corpus complet, reprise après interruption
documind bench /srv/docs-test --out /opt/documind-data/bench/all.csv --resume
```

Le CSV contient une ligne par fichier : pages, secondes OCR et s/page, secondes
MiniCPM, nombre de documents produits, types/titres, temps mural, RSS/crête,
backend OCR et erreurs.
