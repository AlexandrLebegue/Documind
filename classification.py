"""Deterministic document classification helpers.

The local LLM sometimes returns a type outside the supported list (for
example ``bulletin_de_paie`` or ``rib``) or falls back to ``autre`` even
when the document is obvious.  This module normalises those answers with
an alias table and a keyword fallback on the title / OCR text, and repairs
missing or generic titles.
"""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path

VALID_DOC_TYPES = [
    "facture",
    "fiche_de_paie",
    "avis_imposition",
    "contrat",
    "attestation",
    "courrier",
    "banque",
    "quittance",
    "identite",
    "scolarite",
    "sante",
    "logement",
    "emploi",
    "administratif",
    "autre",
]

TYPE_LABELS = {
    "facture": "Facture",
    "fiche_de_paie": "Bulletin de paie",
    "avis_imposition": "Avis d'imposition",
    "contrat": "Contrat",
    "attestation": "Attestation",
    "courrier": "Courrier",
    "banque": "Document bancaire",
    "quittance": "Quittance",
    "identite": "Pièce d'identité",
    "scolarite": "Scolarité",
    "sante": "Santé",
    "logement": "Logement",
    "emploi": "Emploi",
    "administratif": "Document administratif",
    "autre": "Document",
}

# Types for which an expiry date makes sense.  Other documents (old tax
# notices, invoices...) must never be shown as "Expiré".
EXPIRABLE_TYPES = {
    "identite",
    "sante",
    "logement",
    "emploi",
    "scolarite",
    "contrat",
    "attestation",
}

# Raw value -> canonical type.  Keys are compared after accent/case folding.
ALIASES = {
    # payroll
    "bulletin_de_paie": "fiche_de_paie",
    "bulletin_de_salaire": "fiche_de_paie",
    "bulletin_paie": "fiche_de_paie",
    "bulletin_salaire": "fiche_de_paie",
    "fiche_paie": "fiche_de_paie",
    "fiche_de_salaire": "fiche_de_paie",
    "paie": "fiche_de_paie",
    "salaire": "fiche_de_paie",
    "payslip": "fiche_de_paie",
    # bank
    "rib": "banque",
    "releve_identite_bancaire": "banque",
    "releve_d_identite_bancaire": "banque",
    "releve_bancaire": "banque",
    "releve_de_compte": "banque",
    "releve_de_banque": "banque",
    "releve": "banque",
    "banque": "banque",
    "compte_bancaire": "banque",
    # identity
    "cni": "identite",
    "carte_identite": "identite",
    "carte_nationale_identite": "identite",
    "carte_nationale_d_identite": "identite",
    "carte_d_identite": "identite",
    "passeport": "identite",
    "titre_de_sejour": "identite",
    "titre_sejour": "identite",
    "carte_de_sejour": "identite",
    "permis": "identite",
    "permis_de_conduire": "identite",
    "permis_conduire": "identite",
    # school
    "scolarite": "scolarite",
    "scolaire": "scolarite",
    "certificat_scolarite": "scolarite",
    "certificat_de_scolarite": "scolarite",
    "diplome": "scolarite",
    "bac": "scolarite",
    "baccalaureat": "scolarite",
    "releve_notes": "scolarite",
    "releve_de_notes": "scolarite",
    "certification": "scolarite",
    "certificat_voltaire": "scolarite",
    "voltaire": "scolarite",
    # health
    "sante": "sante",
    "medical": "sante",
    "carte_vitale": "sante",
    "vitale": "sante",
    "cpam": "sante",
    "mutuelle": "sante",
    "ordonnance": "sante",
    "prise_en_charge": "sante",
    "compte_rendu_medical": "sante",
    "assurance_maladie": "sante",
    # housing
    "logement": "logement",
    "bail": "logement",
    "contrat_de_bail": "logement",
    "contrat_de_location": "logement",
    "etat_des_lieux": "logement",
    "etat_des_lieux_entree": "logement",
    "etat_des_lieux_sortie": "logement",
    "caution": "logement",
    # employment
    "emploi": "emploi",
    "contrat_de_travail": "emploi",
    "contrat_travail": "emploi",
    "avenant": "emploi",
    "avenant_contrat": "emploi",
    "avenant_au_contrat": "emploi",
    # administration
    "administratif": "administratif",
    "recensement": "administratif",
    "jdc": "administratif",
    "journee_defense": "administratif",
    "acte_naissance": "administratif",
    "acte_de_naissance": "administratif",
    "acte_mariage": "administratif",
    "acte_de_mariage": "administratif",
    "livret_de_famille": "administratif",
    "formulaire": "administratif",
    "immigration": "administratif",
    # common plurals / synonyms
    "factures": "facture",
    "facture": "facture",
    "contrats": "contrat",
    "contrat": "contrat",
    "attestations": "attestation",
    "attestation": "attestation",
    "courriers": "courrier",
    "courrier": "courrier",
    "lettre": "courrier",
    "quittances": "quittance",
    "quittance": "quittance",
    "avis_impot": "avis_imposition",
    "impot": "avis_imposition",
    "avis_imposition": "avis_imposition",
    "identite": "identite",
    "autre": "autre",
    "inconnu": "autre",
    "unknown": "autre",
}

# Ordered from most specific to most generic.  Each tuple is
# (canonical type, list of accent-folded regexes).
_KEYWORD_RULES: list[tuple[str, list[str]]] = [
    ("identite", [
        r"\bcarte nationale d identite\b",
        r"\bcarte d identite\b",
        r"\bcni\b",
        r"\bpasseport\b",
        r"\btitre de sejour\b",
        r"\btitre de voyage\b",
        r"\bpermis de conduire\b",
    ]),
    ("scolarite", [
        r"\bcertificat de scolarite\b",
        r"\bscolarite\b",
        r"\bdiplome\b",
        r"\bbaccalaureat\b",
        r"\bbac\b",
        r"\breleve de notes\b",
        r"\breleve des notes\b",
        r"\bvoltaire\b",
        r"\bcertification\b",
        r"\battestation de reussite\b",
        r"\buniversite\b",
    ]),
    ("sante", [
        r"\bcarte vitale\b",
        r"\bcarte d assurance maladie\b",
        r"\bassurance maladie\b",
        r"\bcpam\b",
        r"\bmutuelle\b",
        r"\bcompte rendu medical\b",
        r"\bcompte rendu d hospitalisation\b",
        r"\bordonnance\b",
        r"\bprise en charge\b",
        r"\bcertificat medical\b",
        r"\bsecurite sociale\b",
        r"\bhopital\b",
        r"\bmedecin\b",
    ]),
    ("banque", [
        r"\breleve d identite bancaire\b",
        r"\breleve identite bancaire\b",
        r"\brib\b",
        r"\biban\b",
        r"\breleve de compte\b",
        r"\breleve bancaire\b",
        r"\bcompte bancaire\b",
        r"\bbanque\b",
        r"\bdomiciliation bancaire\b",
    ]),
    ("emploi", [
        r"\bcontrat de travail\b",
        r"\bcontrat de travail a duree\b",
        r"\bavenant au contrat\b",
        r"\bavenant\b",
        r"\bcdi\b",
        r"\bcdd\b",
        r"\bperiode d essai\b",
        r"\bfrance travail\b",
        r"\bpole emploi\b",
    ]),
    ("quittance", [
        r"\bquittance de loyer\b",
        r"\bquittance\b",
    ]),
    ("logement", [
        r"\bcontrat de bail\b",
        r"\bcontrat de location\b",
        r"\bbail d habitation\b",
        r"\bbail\b",
        r"\betat des lieux\b",
        r"\bquittance de loyer\b",  # caught by quittance first when title says so
        r"\bcaution\b",
        r"\bdepot de garantie\b",
        r"\bloyer\b",
    ]),
    ("fiche_de_paie", [
        r"\bbulletin de paie\b",
        r"\bbulletin de salaire\b",
        r"\bbulletin de paye\b",
        r"\bfiche de paie\b",
        r"\bfiche de paye\b",
        r"\bcumul imposable\b",
        r"\bnet a payer\b.*\bbrut\b",
    ]),
    ("avis_imposition", [
        r"\bavis d imposition\b",
        r"\bavis de non imposition\b",
        r"\bavis de situation\b",
        r"\bavis d impot\b",
        r"\bimpot sur le revenu\b",
        r"\bdeclaration de revenus\b",
        r"\bdeclaration d impots\b",
    ]),
    ("facture", [
        r"\bfacture\b",
        r"\bfacture d electricite\b",
        r"\bfacture d eau\b",
        r"\bmontant ttc\b",
        r"\btotal ttc\b",
        r"\bconsommation\b.*\beur\b",
    ]),
    ("administratif", [
        r"\brecensement\b",
        r"\bjournee defense\b",
        r"\bjournee citoyen\b",
        r"\bjdc\b",
        r"\bacte de naissance\b",
        r"\bacte de mariage\b",
        r"\bacte de deces\b",
        r"\blivret de famille\b",
        r"\bformulaire\b",
        r"\bimmigration\b",
        r"\bprefecture\b",
        r"\bmairie\b",
    ]),
    ("contrat", [
        r"\bcontrat\b",
        r"\bconditions generales\b",
        r"\bassurance\b",
    ]),
    ("attestation", [
        r"\battestation\b",
        r"\bjustificatif\b",
    ]),
    ("courrier", [
        r"\bcourrier\b",
        r"\blettre\b",
        r"\bnotification\b",
        r"\bmise en demeure\b",
        r"\bopposition\b",
    ]),
]

_GENERIC_TITLES = {
    "",
    "document",
    "document sans titre",
    "sans titre",
    "document non classe",
    "document non classifie",
    "document non identifie",
    "document administratif ocr",
    "document administratif",
    "document long",
    "document long fusionne",
    "nouveau document",
    "piece jointe",
    "pieces justificatives",
    "justificatif",
    "facture",
    "bulletin de paie",
    "avis d imposition",
    "contrat",
    "attestation",
    "courrier",
    "document bancaire",
    "quittance",
    "piece d identite",
    "scolarite",
    "sante",
    "logement",
    "emploi",
    "document administratif",
    "image",
    "scan",
    "unknown",
}

_ALIAS_KEYS = sorted(ALIASES, key=len, reverse=True)
_FAILED_TITLE_WORDS = (
    "document non identifie",
    "document administratif non identifie",
    "document non reconnu",
    "non identifie",
    "non identifiable",
    "facture ocr",
    "inconnu",
    "document administratif ocr",
)


def _norm(value: str | None) -> str:
    """Lowercase, strip accents and collapse punctuation to single spaces."""
    if not value:
        return ""
    folded = unicodedata.normalize("NFKD", str(value))
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    folded = folded.lower().replace("'", " ").replace("’", " ")
    return re.sub(r"[^a-z0-9]+", " ", folded).strip()


def _alias_lookup(raw: str) -> str | None:
    if not raw:
        return None
    compact = raw.replace(" ", "_")
    if compact in ALIASES:
        return ALIASES[compact]
    if raw in ALIASES:
        return ALIASES[raw]
    for key in _ALIAS_KEYS:
        key_folded = _norm(key).replace(" ", "_")
        if key_folded and (key_folded in compact or _norm(key) == raw):
            return ALIASES[key]
    return None


def _score_patterns(patterns: list[str], haystack: str) -> int:
    if not haystack:
        return 0
    score = 0
    for pattern in patterns:
        score += len(re.findall(pattern, haystack))
    return score


def _best_match(haystack: str, prefer_first: bool = False) -> tuple[str | None, int]:
    """Pick the best type in *haystack* and return ``(type, score)``.

    When *prefer_first* is true (titles), the earliest keyword position wins;
    this classifies "Attestation de paiement de facture" as an attestation
    rather than a facture.  Otherwise the highest score wins.
    """
    if not haystack:
        return None, 0
    best_candidate: tuple | None = None
    best_type: str | None = None
    best_score = 0
    for order, (doc_type, patterns) in enumerate(_KEYWORD_RULES):
        score = 0
        first_pos: int | None = None
        for pattern in patterns:
            for match in re.finditer(pattern, haystack):
                score += 1
                if first_pos is None or match.start() < first_pos:
                    first_pos = match.start()
        if score:
            if prefer_first:
                candidate = (-(first_pos if first_pos is not None else 10**6), score, -order, doc_type)
            else:
                candidate = (score, -order, doc_type)
            if best_candidate is None or candidate > best_candidate:
                best_candidate = candidate
                best_type = doc_type
                best_score = score
    return best_type, best_score


def _best_type(haystack: str, prefer_first: bool = False) -> str | None:
    return _best_match(haystack, prefer_first=prefer_first)[0]


def classify_short_match(
    *,
    title: str = "",
    emetteur: str = "",
    resume: str = "",
    tags: list[str] | None = None,
) -> tuple[str | None, int]:
    """Return ``(type, score)`` from title/issuer/tags, then summary."""
    title_hay = _norm(" ".join([title or "", emetteur or "", " ".join(tags or [])]))
    matched, score = _best_match(title_hay, prefer_first=True)
    if matched:
        return matched, score
    return _best_match(_norm(resume))


def classify_short(
    *,
    title: str = "",
    emetteur: str = "",
    resume: str = "",
    tags: list[str] | None = None,
) -> str | None:
    """Classify from the strongest signals: title/issuer/tags, then summary."""
    return classify_short_match(title=title, emetteur=emetteur, resume=resume, tags=tags)[0]


def classify_text(text: str) -> str | None:
    """Classify from the beginning of the OCR text (weakest signal)."""
    return _best_type(_norm((text or "")[:12000]))


def classify_by_keywords(
    *,
    title: str = "",
    emetteur: str = "",
    resume: str = "",
    tags: list[str] | None = None,
    text: str = "",
) -> str | None:
    """Return the best matching type from short fields, then full text."""
    return classify_short(title=title, emetteur=emetteur, resume=resume, tags=tags) or classify_text(text)


def normalize_doc_type(
    raw_type: str | None,
    *,
    title: str = "",
    emetteur: str = "",
    resume: str = "",
    tags: list[str] | None = None,
    text: str = "",
    filename: str = "",
) -> str:
    """Map an LLM type to a canonical type using title, aliases, then text.

    A clear title/issuer match always wins, which fixes the common case
    where the model answered ``autre`` or put everything in ``identite``.
    For broad LLM answers (autre, identite, contrat, attestation) the OCR
    text is also used before accepting the model's fallback.
    """
    raw = _norm(raw_type).replace(" ", "_")
    aliased = _alias_lookup(raw)

    title_hay = _norm(" ".join([title or "", emetteur or ""]))
    title_type, _ = _best_match(title_hay, prefer_first=True)
    resume_type, _ = _best_match(_norm(" ".join([resume or "", " ".join(tags or [])])))
    file_type, file_score = _best_match(_norm(filename), prefer_first=True)
    text_type, text_score = _best_match(_norm((text or "")[:12000]))

    # The filename can correct a wrong title when the OCR text agrees with it
    # (e.g. a RIB whose LLM title was "Fiche de paie").
    specific_file_types = {
        "identite", "scolarite", "sante", "banque", "emploi",
        "logement", "administratif", "fiche_de_paie", "avis_imposition",
        "quittance",
    }
    if title_type:
        if (
            file_type in specific_file_types
            and file_type != title_type
            and text_type == file_type
            and text_score >= 2
            and file_score >= 1
        ):
            return file_type
        return title_type
    if resume_type:
        return resume_type
    if file_type:
        return file_type

    broad = {"autre", "identite", "contrat", "attestation", "administratif"}
    if aliased in broad or (aliased is None and raw in broad):
        if text_type:
            return text_type
    if aliased and aliased != "autre":
        return aliased
    if raw in VALID_DOC_TYPES:
        return text_type or raw
    return text_type or "autre"


def is_generic_title(title: str | None) -> bool:
    """True for empty, placeholder or obviously broken titles."""
    if not title or not str(title).strip():
        return True
    folded = _norm(title)
    if folded in _GENERIC_TITLES:
        return True
    return any(word in folded for word in _FAILED_TITLE_WORDS)


def _clean_filename(filename: str | None) -> str:
    if not filename:
        return ""
    stem = Path(filename).stem
    stem = re.sub(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[_-]?", "", stem)
    stem = re.sub(r"[_\-]+", " ", stem)
    stem = re.sub(r"\s+", " ", stem).strip()
    if not stem:
        return ""
    return stem[0].upper() + stem[1:]


def _meaningful_filename(filename: str | None) -> str | None:
    cleaned = _clean_filename(filename)
    if not cleaned:
        return None
    folded = _norm(cleaned)
    if len(folded) < 3:
        return None
    if folded in _GENERIC_TITLES:
        return None
    if re.fullmatch(r"(scan|img|image|photo|document|doc|file|piece|pj)[a-z]? ?\d*", folded):
        return None
    if re.fullmatch(r"\d+", folded):
        return None
    return cleaned


def build_title(
    *,
    metadata: dict,
    filename: str | None = None,
    preferred_title: str | None = None,
) -> str:
    """Return a useful title: type + issuer + date, filename fallback."""
    current = str(metadata.get("titre") or "").strip()
    doc_type = metadata.get("type") or "autre"
    label_fold = _norm(TYPE_LABELS.get(doc_type, TYPE_LABELS["autre"]))
    useless = {"inconnu", "non identifie", "non identifiable", "sans emetteur", "banque"}
    current_fold = _norm(current)
    weak_current = current_fold == label_fold
    if current_fold.startswith(label_fold + " "):
        rest = current_fold[len(label_fold):].strip()
        if rest in _GENERIC_TITLES or rest in useless or rest.startswith(label_fold):
            weak_current = True
    if current and not is_generic_title(current) and not weak_current:
        current_type, _ = _best_match(_norm(current), prefer_first=True)
        if not current_type or current_type == doc_type:
            return current

    if preferred_title and not is_generic_title(preferred_title):
        preferred_type, _ = _best_match(_norm(preferred_title), prefer_first=True)
        if not preferred_type or preferred_type == doc_type:
            return str(preferred_title).strip()

    label = TYPE_LABELS.get(doc_type, TYPE_LABELS["autre"])
    emetteur = str(metadata.get("emetteur") or "").strip()
    useful_emetteur = (
        bool(emetteur)
        and _norm(emetteur) not in _GENERIC_TITLES
        and _norm(emetteur) not in {
            "inconnu", "non identifie", "non identifiable",
            "sans emetteur", "banque",
        }
    )
    date = str(metadata.get("date") or "").strip()
    date_part = date[:7] if re.match(r"^\d{4}-\d{2}", date) else date
    parts = [label]
    if useful_emetteur and _norm(emetteur) not in _norm(label):
        parts.append(emetteur)
    if date_part:
        parts.append(date_part)

    if len(parts) > 1:
        return " — ".join(parts)

    filename_title = _meaningful_filename(filename)
    if filename_title and doc_type == "autre":
        return filename_title
    if filename_title and len(parts) == 1:
        return f"{label} — {filename_title}"
    return label


def finalize_metadata(
    metadata: dict,
    *,
    text: str = "",
    filename: str | None = None,
    preferred_title: str | None = None,
) -> dict:
    """Repair type and title of a parsed metadata dict in place."""
    if not isinstance(metadata, dict):
        return metadata
    filename_hint = _clean_filename(filename)
    metadata["type"] = normalize_doc_type(
        metadata.get("type"),
        title=" ".join(
            part for part in (
                str(metadata.get("titre") or ""),
                str(preferred_title or ""),
            ) if part
        ),
        emetteur=str(metadata.get("emetteur") or ""),
        resume=str(metadata.get("resume") or ""),
        tags=metadata.get("tags") if isinstance(metadata.get("tags"), list) else None,
        text=text,
        filename=filename_hint,
    )
    metadata["titre"] = build_title(
        metadata=metadata,
        filename=filename,
        preferred_title=preferred_title,
    )
    return metadata
