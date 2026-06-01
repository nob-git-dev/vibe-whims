"""``web_scraper`` Hermes plugin — entry point.

This module exposes a single function, ``register(ctx)``, which the
Hermes plugin manager calls once at startup. It adds the
``web_scraper_extract`` tool to the global tool registry.

Design references
-----------------
- ADR-INT-3: separation of concerns (entry / schemas / handler / check)
- ADR-INT-5: ``model`` is hidden from the agent
- ADR-INT-6: handler never raises; returns JSON strings only
- FU-INT-SEC-05: secret-redacting filter is attached as a side effect
  of importing ``_logging_setup`` (handler imports it; we also import
  it here so the filter is present even if ``register`` short-circuits
  before the handler module is touched).
- R-INT-SEC-06: this module must NOT call ``register_hook``.
- T-INT-SEC-08: ``register`` must not raise — internal failures are
  logged and swallowed so a buggy plugin cannot prevent Hermes from
  loading the rest of the plugin set.
"""

from __future__ import annotations

import logging

# Attaches the redaction filter at import time (FU-INT-SEC-05).
# Use relative import so the plugin loads both under the host pytest path
# (`plugins.web_scraper.*`) and under the Hermes plugin loader namespace
# (`hermes_plugins.web_scraper.*`); see hermes_cli/plugins.py:1474-1510.
from . import _logging_setup as _logging_setup  # noqa: F401

logger = logging.getLogger(__name__)


def register(ctx) -> None:
    """Register the ``web_scraper_extract`` tool with the Hermes context.

    Parameters
    ----------
    ctx:
        A ``PluginContext`` from ``hermes_cli.plugins`` (or a
        compatible test double). It must expose ``register_tool``.

    Notes
    -----
    Failures inside this function are logged at WARNING level and
    swallowed. They do NOT propagate to the plugin manager —
    ``hermes`` must remain bootable even when one plugin misbehaves.
    """
    try:
        from .schemas import WEB_SCRAPER_EXTRACT_SCHEMA
        from .handler import extract_web_data_handler
        from .check import check_web_scraper_available
    except Exception as exc:  # noqa: BLE001 — broad on purpose
        logger.warning(
            "web_scraper plugin: import failed (%s); tool will not be registered",
            type(exc).__name__,
        )
        return

    try:
        ctx.register_tool(
            name="web_scraper_extract",
            toolset="web_scraper",
            schema=WEB_SCRAPER_EXTRACT_SCHEMA,
            handler=extract_web_data_handler,
            check_fn=check_web_scraper_available,
            is_async=False,
            emoji="\U0001f578️",  # spider web
            override=False,
        )
    except Exception as exc:  # noqa: BLE001 — broad on purpose
        logger.warning(
            "web_scraper plugin: register_tool failed (%s)",
            type(exc).__name__,
        )
        return

    logger.info("web_scraper plugin: registered web_scraper_extract tool")
