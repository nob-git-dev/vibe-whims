"""LLM-facing JSON Schema for the ``web_scraper_extract`` tool.

This module is intentionally tiny and side-effect-free so the schema can be
imported (and statically checked) without pulling in the adapter or any
runtime dependencies.

References:
- SPEC §F3.1 — exact parameter set and descriptions
- ADR-INT-5 — ``model`` is *hidden* from the agent; resolved via env / default
- FU-INT-SEC-10 — URL field guidance to avoid userinfo
"""

from __future__ import annotations

from typing import Any, Dict

#: Maximum allowed length of the extraction_schema string (FU-INT-SEC-11).
#: Mirrors plugins.web_scraper.handler.MAX_EXTRACTION_SCHEMA_LEN.
EXTRACTION_SCHEMA_MAX_LEN: int = 64 * 1024  # 64 KiB


WEB_SCRAPER_EXTRACT_SCHEMA: Dict[str, Any] = {
    "name": "web_scraper_extract",
    "description": (
        "Extract structured JSON from a single web page given a URL and an "
        "extraction schema (JSON Schema string or natural-language "
        "description). Built-in SSRF defense, robots.txt respect, and "
        "static + dynamic (Playwright) fallback. Always returns a JSON "
        "string with success/data/error/metadata keys. Prefer this over "
        "web_extract when you need structured output rather than raw "
        "markdown. Check the result.metadata.warnings field for fidelity "
        "hints."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "url": {
                "type": "string",
                "description": (
                    "Target URL (http:// or https:// only). Do NOT include "
                    "userinfo (``http://user:pass@host/``) — credentials in "
                    "the URL are recorded in the session log."
                ),
            },
            "extraction_schema": {
                "type": "string",
                "maxLength": EXTRACTION_SCHEMA_MAX_LEN,
                "description": (
                    "JSON Schema string (parseable via ``json.loads``) OR a "
                    "natural-language description of what to extract. Max "
                    f"{EXTRACTION_SCHEMA_MAX_LEN} characters."
                ),
            },
            "prefer_dynamic": {
                "type": "boolean",
                "description": (
                    "Skip the static fetch and go straight to Playwright. "
                    "Use this for SPA pages where the content is rendered "
                    "client-side. Default false."
                ),
            },
            "respect_robots": {
                "type": "boolean",
                "description": "Honor robots.txt. Default true.",
            },
            "timeout_s": {
                "type": "integer",
                "minimum": 1,
                "maximum": 300,
                "description": ("Per-request timeout in seconds (1-300). Default 30."),
            },
            "max_chars": {
                "type": "integer",
                "minimum": 1000,
                "maximum": 200000,
                "description": (
                    "Maximum characters fed to the LLM after content "
                    "extraction. Default 60000."
                ),
            },
            "user_agent": {
                "type": "string",
                "maxLength": 200,
                "description": (
                    "Override the default User-Agent string. Default "
                    "``WebScraperTool/1.0 (+https://...)``."
                ),
            },
        },
        "required": ["url", "extraction_schema"],
    },
}
