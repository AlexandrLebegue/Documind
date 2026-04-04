"""Web tools for the Documind agent: search, scraping, and link checking."""

import asyncio
import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Tool 1: Web search via DuckDuckGo (no API key required)
# ---------------------------------------------------------------------------

async def recherche_web(query: str, max_results: int = 5) -> list[dict]:
    """Search the web via DuckDuckGo and return titles, URLs, and excerpts."""
    try:
        from duckduckgo_search import DDGS
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))
        return [
            {"titre": r["title"], "url": r["href"], "extrait": r["body"]}
            for r in results
        ]
    except ImportError:
        logger.error("duckduckgo-search is not installed. Run: pip install duckduckgo-search")
        return [{"erreur": "Module duckduckgo-search non installé."}]
    except Exception as exc:
        logger.error("recherche_web failed: %s", exc)
        return [{"erreur": str(exc)}]


# ---------------------------------------------------------------------------
# Tool 2: Page scraping via crawl4ai (converts HTML to clean Markdown)
# ---------------------------------------------------------------------------

async def scraper_page(url: str) -> dict:
    """Fetch a web page and convert it to clean LLM-ready Markdown."""
    try:
        from crawl4ai import AsyncWebCrawler
        async with AsyncWebCrawler() as crawler:
            result = await crawler.arun(url)
            markdown = result.markdown or ""
            internal_links = [
                lnk["href"]
                for lnk in result.links.get("internal", [])
                if lnk.get("href")
            ][:10]
            return {
                "url": url,
                "markdown": markdown[:8000],
                "liens": internal_links,
            }
    except ImportError:
        logger.error("crawl4ai is not installed. Run: pip install crawl4ai && crawl4ai-setup")
        return {"url": url, "erreur": "Module crawl4ai non installé."}
    except Exception as exc:
        logger.error("scraper_page failed for %s: %s", url, exc)
        return {"url": url, "erreur": str(exc)}


# ---------------------------------------------------------------------------
# Tool 3: Adaptive crawler for extracting procedures from a site
# ---------------------------------------------------------------------------

async def crawler_procedures(url_base: str, requete: str) -> dict:
    """Intelligently crawl a site until enough relevant content is found."""
    try:
        from crawl4ai import AsyncWebCrawler, AdaptiveCrawler
        async with AsyncWebCrawler() as crawler:
            adaptive = AdaptiveCrawler(crawler)
            result = await adaptive.digest(start_url=url_base, query=requete)
            return {
                "pages_crawlees": len(result.crawled_urls),
                "confiance": f"{adaptive.confidence:.0%}",
                "contenu": result.markdown[:8000],
            }
    except ImportError:
        logger.error("crawl4ai is not installed. Run: pip install crawl4ai && crawl4ai-setup")
        return {"erreur": "Module crawl4ai non installé."}
    except Exception as exc:
        logger.error("crawler_procedures failed for %s: %s", url_base, exc)
        return {"erreur": str(exc)}


# ---------------------------------------------------------------------------
# Tool 4: Bulk link checker (parallel HEAD requests)
# ---------------------------------------------------------------------------

async def verifier_liens(urls: list[str]) -> list[dict]:
    """Check in parallel whether a list of URLs are still reachable."""

    async def _check(client: httpx.AsyncClient, url: str) -> dict:
        try:
            r = await client.head(url, follow_redirects=True, timeout=8)
            return {"url": url, "statut": r.status_code, "valide": r.status_code < 400}
        except Exception as exc:
            return {"url": url, "statut": None, "valide": False, "erreur": str(exc)}

    async with httpx.AsyncClient() as client:
        results = await asyncio.gather(*[_check(client, u) for u in urls])
    return list(results)
