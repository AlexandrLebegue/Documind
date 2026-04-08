"""Documind agentic chat loop using tool_use (OpenAI-compatible format)."""

import json
import logging
from typing import Optional, Callable, Awaitable

import httpx

import uuid

import config as _cfg
from llm import _active_model
from web_tools import recherche_web, scraper_page, crawler_procedures, verifier_liens


logger = logging.getLogger(__name__)

# Maximum agentic loop iterations (prevents infinite loops)
_MAX_ITERATIONS = 10

# Tool definitions in OpenAI function-calling format
AGENT_TOOLS: list[dict] = [
    {
        "type": "function",
        "function": {
            "name": "recherche_web",
            "description": (
                "Recherche des informations récentes sur le web via DuckDuckGo. "
                "Utilise cet outil pour trouver des informations manquantes, vérifier "
                "des faits actuels, ou enrichir une procédure avec des données récentes."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "La requête de recherche à effectuer",
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Nombre maximum de résultats (défaut: 5)",
                        "default": 5,
                    },
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "scraper_page",
            "description": (
                "Récupère et nettoie le contenu complet d'une page web en Markdown. "
                "Utilise cet outil après une recherche web pour lire le contenu détaillé "
                "d'une page pertinente."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "URL complète de la page à scraper",
                    },
                },
                "required": ["url"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "verifier_liens",
            "description": (
                "Vérifie en parallèle si une liste d'URLs sont encore accessibles. "
                "Utilise cet outil pour contrôler la validité des liens dans une procédure."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "urls": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Liste des URLs à vérifier",
                    },
                },
                "required": ["urls"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "creer_procedure",
            "description": (
                "Crée une nouvelle procédure administrative dans Documind à partir d'une description "
                "en langage naturel. L'IA analyse la description, identifie les documents requis, "
                "et enregistre la procédure. Utilise cet outil dès que l'utilisateur demande de "
                "créer, ajouter ou enregistrer une procédure."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "procedure_type": {
                        "type": "string",
                        "enum": ["administrative", "contrat", "bancaire", "sante", "emploi", "immobilier"],
                        "description": "Catégorie de la procédure",
                    },
                    "description": {
                        "type": "string",
                        "description": "Description libre de la procédure (ex: 'renouvellement de passeport en préfecture')",
                    },
                    "name": {
                        "type": "string",
                        "description": "Nom court de la procédure. Laisse vide pour que l'IA le génère automatiquement.",
                    },
                    "manual_documents": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Liste des documents requis connus (ex: ['CNI', 'justificatif de domicile'])",
                    },
                },
                "required": ["procedure_type", "description", "manual_documents"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "crawler_procedures",
            "description": (
                "Crawle intelligemment un site web pour extraire des procédures. "
                "S'arrête automatiquement quand assez d'informations sont collectées."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "url_base": {
                        "type": "string",
                        "description": "URL de départ du site à crawler",
                    },
                    "requete": {
                        "type": "string",
                        "description": "Ce qu'on cherche sur ce site (ex: 'formulaire CERFA demande passeport')",
                    },
                },
                "required": ["url_base", "requete"],
            },
        },
    },
]


async def _tool_creer_procedure(
    llm_client: httpx.Client,
    procedure_type: str,
    description: str,
    name: Optional[str] = None,
    manual_documents: Optional[list[str]] = None,
) -> dict:
    """Analyse une description et crée une procédure dans la base de données."""
    from llm import analyze_procedure
    from database import insert_procedure

    analysis = analyze_procedure(
        client=llm_client,
        procedure_type=procedure_type,
        manual_documents=manual_documents,
        remarks=description,
    )

    proc_id = str(uuid.uuid4())
    proc_name = name.strip() if name and name.strip() else analysis.get("name", "Nouvelle procédure")

    insert_procedure(
        proc_id=proc_id,
        name=proc_name,
        procedure_type=procedure_type,
        description=analysis.get("description"),
        required_documents=analysis.get("required_documents", []),
        remarks=description,
    )

    required_docs = analysis.get("required_documents", [])
    return {
        "succès": True,
        "id": proc_id,
        "nom": proc_name,
        "type": procedure_type,
        "description": analysis.get("description", ""),
        "documents_requis": [
            {"type": d.get("doc_type"), "libellé": d.get("label")}
            for d in required_docs
        ],
        "message": f"Procédure « {proc_name} » créée avec {len(required_docs)} document(s) requis.",
    }


async def _execute_tool(name: str, params: dict, llm_client: Optional[httpx.Client] = None) -> str:
    """Dispatch a tool call and return the JSON-serialised result."""
    try:
        if name == "recherche_web":
            result = await recherche_web(**params)
        elif name == "scraper_page":
            result = await scraper_page(**params)
        elif name == "verifier_liens":
            result = await verifier_liens(**params)
        elif name == "crawler_procedures":
            result = await crawler_procedures(**params)
        elif name == "creer_procedure":
            if llm_client is None:
                result = {"erreur": "Client LLM non disponible pour créer une procédure."}
            else:
                result = await _tool_creer_procedure(llm_client, **params)
        else:
            result = {"erreur": f"Outil inconnu: {name}"}
    except Exception as exc:
        logger.error("Tool %s failed: %s", name, exc)
        result = {"erreur": str(exc)}

    return json.dumps(result, ensure_ascii=False)


async def run_agent(
    llm_client: httpx.Client,
    user_message: str,
    context_procedure: str = "",
    conversation_history: Optional[list[dict]] = None,
    on_tool_start: Optional[Callable[[str, dict], Awaitable[None]]] = None,
    on_tool_done: Optional[Callable[[str, dict, str], Awaitable[None]]] = None,
) -> tuple[str, list[dict]]:
    """Run the agentic loop and return (final_reply, tool_calls_log).

    Args:
        llm_client: Pre-configured httpx.Client pointed at OpenRouter.
        user_message: The user's current message.
        context_procedure: Optional procedure text to include in the system prompt.
        conversation_history: Prior messages for multi-turn support (role/content dicts).

    Returns:
        A tuple of (assistant reply text, list of tool call log entries).
        Each log entry has: tool, args, result_preview.
    """
    system_parts = [
        "Tu es DocuMind, un assistant de gestion documentaire avec accès à Internet.",
        "Tu peux utiliser des outils web pour rechercher des informations récentes,",
        "vérifier des liens, scraper des pages, ou extraire des procédures depuis des sites.",
        "",
        "Règles :",
        "- Utilise les outils web quand la question nécessite des données récentes ou externes.",
        "- Chaîne plusieurs outils si nécessaire (ex: recherche puis scraping du résultat).",
        "- Réponds toujours en français, de façon précise et concise.",
        "- Si tu ne trouves pas d'information pertinente, dis-le clairement.",
    ]
    if context_procedure:
        system_parts += ["", "Procédure en cours :", context_procedure]

    system_prompt = "\n".join(system_parts)

    # Build the message list (history + current user message)
    messages: list[dict] = []
    if conversation_history:
        # Only include simple role/content messages from history
        for msg in conversation_history:
            if msg.get("role") in ("user", "assistant") and isinstance(msg.get("content"), str):
                messages.append({"role": msg["role"], "content": msg["content"]})
    messages.append({"role": "user", "content": user_message})

    tool_calls_log: list[dict] = []
    model_name = _active_model()

    for iteration in range(_MAX_ITERATIONS):
        payload: dict = {
            "model": model_name,
            "messages": [{"role": "system", "content": system_prompt}] + messages,
            "tools": AGENT_TOOLS,
            "tool_choice": "auto",
            "temperature": _cfg.LLM_TEMPERATURE,
            "max_tokens": 4096,
        }

        try:
            response = llm_client.post("/chat/completions", json=payload)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            logger.error("LLM API error (iteration %d): %s — body: %s",
                         iteration, exc, exc.response.text[:500])
            return f"Erreur API ({exc.response.status_code}). Veuillez réessayer.", tool_calls_log

        data = response.json()
        choice = data["choices"][0]
        msg = choice["message"]
        finish_reason = choice.get("finish_reason", "stop")

        # Add the assistant's turn to message history
        messages.append(msg)

        # Done — return the text reply
        if finish_reason in ("stop", "end_turn") or not msg.get("tool_calls"):
            reply = msg.get("content") or ""
            return reply, tool_calls_log

        # Process tool calls
        if finish_reason == "tool_calls" or msg.get("tool_calls"):
            tool_results: list[dict] = []

            for tool_call in msg.get("tool_calls", []):
                fn = tool_call.get("function", {})
                name = fn.get("name", "")
                try:
                    args = json.loads(fn.get("arguments", "{}"))
                except json.JSONDecodeError:
                    args = {}

                logger.info("Agent tool call: %s(%s)", name, args)
                if on_tool_start:
                    await on_tool_start(name, args)
                result_str = await _execute_tool(name, args, llm_client=llm_client)
                if on_tool_done:
                    await on_tool_done(name, args, result_str)

                tool_calls_log.append({
                    "tool": name,
                    "args": args,
                    "result_preview": result_str[:300],
                })

                tool_results.append({
                    "role": "tool",
                    "tool_call_id": tool_call.get("id", ""),
                    "content": result_str,
                })

            messages.extend(tool_results)

    logger.warning("Agent reached max iterations (%d)", _MAX_ITERATIONS)
    return "Limite du nombre d'itérations atteinte.", tool_calls_log
