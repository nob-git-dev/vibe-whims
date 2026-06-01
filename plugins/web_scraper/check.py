"""Availability gate for the ``web_scraper_extract`` tool.

Hermes uses this function to decide whether the tool is shown to the
agent (``hermes tools list``). The function returns ``True`` only when
every required runtime dependency imports successfully.

Behaviour
---------
- Fail-closed: any ``ImportError`` (or arbitrary exception during
  import) results in ``False``.
- Side-effect on success: logs the resolved ``web_scraper_tool.__file__``
  at INFO level so operators can spot a PYTHONPATH-hijack
  (FU-INT-SEC-03). The path is logged as-is — it never contains
  agent input.
- Playwright is *not* required by ``check`` — the static-fetch path
  works without it, and ``extract_web_data`` itself surfaces a
  structured ``dynamic_fetch`` error if Playwright is missing
  (ADR-INT-3 / S.INT.10.1 fail-soft).
"""

from __future__ import annotations

import importlib
import logging
from typing import Final

logger = logging.getLogger(__name__)


#: Modules that MUST import for the tool to be considered available.
_REQUIRED_MODULES: Final[tuple[str, ...]] = (
    "web_scraper_tool",  # the in-repo library (via PYTHONPATH)
    "litellm",  # LLM extraction phase
    "trafilatura",  # static content extraction
    "bs4",  # HTML parsing
    "lxml",  # bs4's high-speed parser
    "nest_asyncio",  # sync ↔ async bridge inside extract_web_data
    "jsonschema",  # output schema validation
    "httpx",  # static fetch
)


def check_web_scraper_available() -> bool:
    """Return True iff every required module imports successfully.

    This is invoked by the Hermes tool registry as the ``check_fn``
    for ``web_scraper_extract``. It must be cheap, idempotent, and
    never raise.
    """
    for name in _REQUIRED_MODULES:
        try:
            module = importlib.import_module(name)
        except Exception as exc:  # noqa: BLE001 — fail-closed for any failure
            # NOTE: ``exc`` here is internal — not derived from agent input,
            # so logging its message is safe.
            logger.info(
                "web_scraper unavailable: import %s failed (%s)",
                name,
                type(exc).__name__,
            )
            return False
        # FU-INT-SEC-03: log the resolved path for the upstream library so
        # PYTHONPATH-hijack attempts (shadow ``litellm.py`` etc.) become
        # visible in container logs.
        if name == "web_scraper_tool":
            module_file = getattr(module, "__file__", "<unknown>")
            logger.info(
                "web_scraper loaded from %s",
                module_file,
            )
    return True
