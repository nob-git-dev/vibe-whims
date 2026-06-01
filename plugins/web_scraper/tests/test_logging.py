"""Secret-redacting logger filter tests (FU-INT-SEC-05 / T-INT-SEC-06).

The adapter logger must scrub:
- URL userinfo (``http://user:pass@host/``)
- ``Authorization: ...`` headers
- ``api_key=...`` style query/body fragments
"""

from __future__ import annotations

import logging


def _make_record(msg: str, args: tuple = ()) -> logging.LogRecord:
    return logging.LogRecord(
        name="plugins.web_scraper.handler",
        level=logging.WARNING,
        pathname=__file__,
        lineno=1,
        msg=msg,
        args=args,
        exc_info=None,
    )


def test_filter_redacts_url_userinfo() -> None:
    from plugins.web_scraper._logging_setup import SecretsRedactingFilter

    rec = _make_record("fetch %s", ("http://alice:secret@example.com/path",))
    f = SecretsRedactingFilter()
    assert f.filter(rec) is True
    msg = rec.getMessage()
    assert "alice" not in msg
    assert "secret" not in msg
    assert "example.com/path" in msg


def test_filter_redacts_https_userinfo() -> None:
    from plugins.web_scraper._logging_setup import SecretsRedactingFilter

    rec = _make_record("https://u:p@example.com/api?x=1")
    f = SecretsRedactingFilter()
    f.filter(rec)
    msg = rec.getMessage()
    assert "u:p@" not in msg


def test_filter_redacts_authorization_header() -> None:
    from plugins.web_scraper._logging_setup import SecretsRedactingFilter

    rec = _make_record('headers={"Authorization": "Bearer abc123token"}')
    f = SecretsRedactingFilter()
    f.filter(rec)
    msg = rec.getMessage()
    assert "abc123token" not in msg


def test_filter_redacts_api_key_query_param() -> None:
    from plugins.web_scraper._logging_setup import SecretsRedactingFilter

    rec = _make_record("calling https://x.example/?api_key=SUPERSECRET&q=1")
    f = SecretsRedactingFilter()
    f.filter(rec)
    msg = rec.getMessage()
    assert "SUPERSECRET" not in msg


def test_filter_redacts_api_key_in_body() -> None:
    from plugins.web_scraper._logging_setup import SecretsRedactingFilter

    rec = _make_record('payload={"api_key": "TOPSECRET", "x": 1}')
    f = SecretsRedactingFilter()
    f.filter(rec)
    msg = rec.getMessage()
    assert "TOPSECRET" not in msg


def test_filter_passes_innocuous_message_unchanged() -> None:
    from plugins.web_scraper._logging_setup import SecretsRedactingFilter

    rec = _make_record("plain message, no secrets")
    original = rec.getMessage()
    f = SecretsRedactingFilter()
    assert f.filter(rec) is True
    assert rec.getMessage() == original


def test_attach_redaction_filter_is_idempotent() -> None:
    """Calling attach twice does not stack filters."""
    from plugins.web_scraper._logging_setup import (
        SecretsRedactingFilter,
        attach_redaction_filter,
    )

    logger = logging.getLogger("plugins.web_scraper.tests.idempotent")
    # Clear any pre-existing filters from prior test runs
    logger.filters = []

    attach_redaction_filter(logger)
    attach_redaction_filter(logger)

    redaction_filters = [
        f for f in logger.filters if isinstance(f, SecretsRedactingFilter)
    ]
    assert len(redaction_filters) == 1


def test_attach_redaction_filter_actually_filters() -> None:
    """End-to-end: a logger with the filter installed scrubs secrets in caplog."""
    import io

    logger = logging.getLogger("plugins.web_scraper.tests.endtoend")
    logger.filters = []
    logger.handlers = []
    logger.setLevel(logging.DEBUG)

    buf = io.StringIO()
    h = logging.StreamHandler(buf)
    h.setLevel(logging.DEBUG)
    logger.addHandler(h)

    from plugins.web_scraper._logging_setup import attach_redaction_filter

    attach_redaction_filter(logger)

    logger.warning("fetched %s", "https://alice:secret@example.com/")

    out = buf.getvalue()
    assert "alice:secret" not in out
    assert "example.com" in out
