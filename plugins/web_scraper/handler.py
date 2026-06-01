"""Adapter from Hermes tool-call args → ``extract_web_data`` (existing library).

Invariants (enforced by tests; see ``tests/test_handler.py``)
-------------------------------------------------------------
- Returns a JSON string parseable by ``json.loads`` *for every input*.
- Never raises (final ``except BaseException`` net).
- Never mutates the input ``args`` dict (we always go through ``.get``).
- Forwards only whitelisted kwargs; the ``model`` parameter is hidden
  from the agent and silently dropped if it slips in (ADR-INT-5,
  R-INT-SEC-03, T-INT-SEC-16).
- Never logs the raw ``args`` dict or URL on either the success or
  failure path (R-INT-SEC-01). On exception, only ``type(e).__name__``
  is logged (R-INT-SEC-02, FU-INT-SEC-06).
- Rejects ``extraction_schema`` strings larger than 64 KiB
  (FU-INT-SEC-11 / T-INT-SEC-12).
"""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, Final

# Importing this module attaches the secret-redacting filter to the
# adapter's logger before any record is emitted.
# Use relative import so the plugin loads both under host pytest
# (`plugins.web_scraper.*`) and under the Hermes plugin loader namespace
# (`hermes_plugins.web_scraper.*`); see hermes_cli/plugins.py:1474-1510.
from . import _logging_setup as _logging_setup  # noqa: F401

logger = logging.getLogger(__name__)


#: Optional keys we are allowed to forward to ``extract_web_data``.
#: ``model`` is intentionally absent — ADR-INT-5.
FORWARDABLE_KEYS: Final[tuple[str, ...]] = (
    "prefer_dynamic",
    "respect_robots",
    "timeout_s",
    "max_chars",
    "user_agent",
)

#: Upper bound on the extraction_schema string length (FU-INT-SEC-11).
MAX_EXTRACTION_SCHEMA_LEN: Final[int] = 64 * 1024  # 64 KiB


def extract_web_data_handler(args: Dict[str, Any], **_kwargs: Any) -> str:
    """Hermes tool entrypoint for ``web_scraper_extract``.

    Parameters
    ----------
    args:
        Mapping supplied by the agent. Must include ``url`` and
        ``extraction_schema``. Any of ``prefer_dynamic``,
        ``respect_robots``, ``timeout_s``, ``max_chars``,
        ``user_agent`` may be present.

    Returns
    -------
    str
        A JSON string with the keys ``success``, ``data``, ``error``,
        ``metadata`` — matching the upstream tool's contract.
    """
    if not isinstance(args, dict):
        return _error_json(
            "input_validation",
            "args must be an object",
            "pass a JSON object with at least url and extraction_schema",
        )

    url = args.get("url")
    url = url.strip() if isinstance(url, str) else ""
    if not url:
        return _error_json(
            "input_validation",
            "url is required",
            "pass a valid http(s) URL",
        )

    schema = args.get("extraction_schema")
    schema = schema if isinstance(schema, str) else ""
    if not schema:
        return _error_json(
            "input_validation",
            "extraction_schema is required",
            "pass a JSON Schema string or natural-language description",
        )

    if len(schema) > MAX_EXTRACTION_SCHEMA_LEN:
        return _error_json(
            "input_validation",
            (
                f"extraction_schema too long "
                f"({len(schema)} > {MAX_EXTRACTION_SCHEMA_LEN})"
            ),
            f"trim the schema to under {MAX_EXTRACTION_SCHEMA_LEN} characters",
        )

    optional_kwargs: Dict[str, Any] = {
        k: args[k] for k in FORWARDABLE_KEYS if k in args and args[k] is not None
    }

    try:
        # Late-bound import: keeps the adapter testable without the heavy
        # web_scraper_tool stack loaded (and matches the SPEC's lazy
        # design — the registry calls us long after import time).
        from web_scraper_tool import extract_web_data  # type: ignore[import-not-found]

        return extract_web_data(url, schema, **optional_kwargs)
    except BaseException as exc:  # noqa: BLE001 — last line of defence
        # Intentionally minimal logging: only the exception type name.
        # Per FU-INT-SEC-06, we do not call logger.exception (which would
        # capture a traceback with local variables, including args).
        logger.warning("adapter error: %s", type(exc).__name__)
        return _error_json(
            "unknown",
            f"adapter unexpected error: {type(exc).__name__}",
            "report a bug to the plugin author",
        )


def _error_json(stage: str, message: str, recommended_next_action: str) -> str:
    """Build a 4-key error JSON string matching ``extract_web_data``'s shape."""
    return json.dumps(
        {
            "success": False,
            "data": None,
            "error": {
                "stage": stage,
                "message": message,
                "details": {},
                "retryable": False,
                "recommended_next_action": recommended_next_action,
            },
            "metadata": {},
        },
        ensure_ascii=False,
    )
