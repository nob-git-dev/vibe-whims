"""Plugin-side secret-redacting log filter (FU-INT-SEC-05).

Why this exists
---------------
The upstream ``web_scraper_tool/web_scraper_tool.py`` installs a
``_SecretsRedactingFilter`` on its own logger (``web_scraper_tool``) at
import time. That filter only protects records emitted by *that* logger.

The plugin adapter (``plugins.web_scraper.handler``) uses its own logger
namespace (``plugins.web_scraper.*``) so the upstream filter does NOT
cover it. Without an equivalent filter, any adapter ``logger.warning``
call that ends up echoing URL userinfo, ``Authorization:`` headers, or
``api_key=...`` fragments will leak secrets through Hermes' log surface
(stderr, session DB indirectly via formatted records).

This module re-defines the same redaction *pattern* (we do NOT import the
private upstream class — its ``_`` prefix marks it as private and the
upstream public API is only ``extract_web_data``). The regex set is
intentionally narrow: URL userinfo, Authorization headers, and api_key
keyword-value pairs.

Side effect on import
---------------------
Importing this module attaches the filter to the
``plugins.web_scraper.handler`` and ``plugins.web_scraper`` loggers.
Repeated imports / attaches are idempotent (the attach helper checks for
an existing instance before adding).
"""

from __future__ import annotations

import logging
import re
from typing import Final, Iterable, Pattern

logger = logging.getLogger(__name__)


# URL userinfo: scheme://user:pass@host/...
_RE_URL_USERINFO: Final[Pattern[str]] = re.compile(
    r"(?P<scheme>https?://)[^/\s@]+@(?P<host>[^/\s]+)",
    flags=re.IGNORECASE,
)

# Authorization: <anything> (header value)
# Matches header_name + separator + (optional) quote + entire value
# (including ``Bearer xxx`` so the token after the scheme is also scrubbed).
_RE_AUTHORIZATION: Final[Pattern[str]] = re.compile(
    r'(?P<prefix>["\']?Authorization["\']?\s*[:=]\s*["\']?)'
    r"(?P<value>[^\"'\n}]+)",
    flags=re.IGNORECASE,
)

# api_key / apikey: in a JSON-ish or query-string fragment
_RE_API_KEY: Final[Pattern[str]] = re.compile(
    r'(?P<prefix>["\']?api[_-]?key["\']?\s*[:=]\s*["\']?)'
    r"(?P<value>[^\"'\s,}\]&]+)",
    flags=re.IGNORECASE,
)

# Generic Bearer token (in case Authorization key isn't named explicitly)
_RE_BEARER: Final[Pattern[str]] = re.compile(
    r"(?P<prefix>Bearer\s+)(?P<value>[A-Za-z0-9._\-+/=]{8,})",
    flags=re.IGNORECASE,
)


_REPLACEMENTS: Final[tuple[tuple[Pattern[str], str], ...]] = (
    (_RE_URL_USERINFO, r"\g<scheme><REDACTED>@\g<host>"),
    (_RE_AUTHORIZATION, r"\g<prefix><REDACTED>"),
    (_RE_API_KEY, r"\g<prefix><REDACTED>"),
    (_RE_BEARER, r"\g<prefix><REDACTED>"),
)


def _redact(text: str) -> str:
    """Apply every redaction pattern in turn."""
    for pattern, replacement in _REPLACEMENTS:
        text = pattern.sub(replacement, text)
    return text


class SecretsRedactingFilter(logging.Filter):
    """Mutates each LogRecord's formatted message to scrub known secrets.

    We rewrite ``record.msg`` (and clear ``record.args``) so subsequent
    formatters cannot recombine the original ``%s`` template with raw
    args. This is the same approach used by upstream's
    ``_SecretsRedactingFilter``.
    """

    name = "plugins.web_scraper.redact"

    def filter(self, record: logging.LogRecord) -> bool:  # noqa: D401
        try:
            formatted = record.getMessage()
        except Exception:
            # Best-effort: never break logging because of formatting issues.
            return True

        redacted = _redact(formatted)
        if redacted != formatted:
            record.msg = redacted
            record.args = None
        return True


def attach_redaction_filter(logger_obj: logging.Logger) -> None:
    """Install ``SecretsRedactingFilter`` on ``logger_obj`` if not already there."""
    for existing in logger_obj.filters:
        if isinstance(existing, SecretsRedactingFilter):
            return
    logger_obj.addFilter(SecretsRedactingFilter())


def install_redaction_filters(
    logger_names: Iterable[str] = (
        "plugins.web_scraper",
        "plugins.web_scraper.handler",
    ),
) -> None:
    """Attach the redaction filter to every named logger.

    This is the entry point called from ``__init__.py`` (via
    ``from . import _logging_setup``).
    """
    for name in logger_names:
        attach_redaction_filter(logging.getLogger(name))


# Side-effect on import: attach to the plugin's two main loggers.
install_redaction_filters()
