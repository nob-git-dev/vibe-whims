"""Adapter / handler unit tests.

Reference SPEC sections:
- F8.1 (≥ 8 cases)
- ADR-INT-5 (``model`` hidden from schema, never forwarded)
- ADR-INT-6 (handler never raises, JSON string guarantee)
- FU-INT-SEC-05 (secret-redacting logger applied to plugin logger)
- FU-INT-SEC-06 (final except logs only ``type(e).__name__``)
- FU-INT-SEC-11 (extraction_schema length limit)
- T-INT-SEC-06 / T-INT-SEC-10 / T-INT-SEC-11 / T-INT-SEC-12 / T-INT-SEC-16
"""

from __future__ import annotations

import json

import pytest


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


def test_handler_calls_extract_web_data_on_valid_input(extract_web_data_mock) -> None:
    """Case #1: url + schema valid → extract_web_data is called once."""
    from plugins.web_scraper.handler import extract_web_data_handler

    result = extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": '{"type":"object"}'}
    )

    assert len(extract_web_data_mock["calls"]) == 1
    args, kwargs = extract_web_data_mock["calls"][0]
    assert args == ("https://example.com/", '{"type":"object"}')
    # Optional kwargs should default to empty when not provided
    assert kwargs == {}
    # Should return what the mock returned (passthrough)
    assert json.loads(result)["success"] is True


def test_handler_returns_parseable_json_on_success(extract_web_data_mock) -> None:
    """Case #6 / #8: passes through the JSON string verbatim & always parseable."""
    from plugins.web_scraper.handler import extract_web_data_handler

    sentinel = json.dumps(
        {"success": True, "data": {"x": 1}, "error": None, "metadata": {}},
        ensure_ascii=False,
    )
    extract_web_data_mock["set_return"](sentinel)

    out = extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": "any"}
    )
    assert out == sentinel
    parsed = json.loads(out)
    assert parsed["success"] is True


# ---------------------------------------------------------------------------
# Validation failures (no mock call)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("url_value", [None, "", "   "])
def test_handler_rejects_missing_url(extract_web_data_mock, url_value) -> None:
    """Case #2: missing/blank url → input_validation, mock not called."""
    from plugins.web_scraper.handler import extract_web_data_handler

    args = {"extraction_schema": "any"}
    if url_value is not None:
        args["url"] = url_value
    out = extract_web_data_handler(args)

    parsed = json.loads(out)
    assert parsed["success"] is False
    assert parsed["error"]["stage"] == "input_validation"
    assert "url" in parsed["error"]["message"]
    assert parsed["error"]["retryable"] is False
    assert len(extract_web_data_mock["calls"]) == 0


@pytest.mark.parametrize("schema_value", [None, ""])
def test_handler_rejects_missing_schema(extract_web_data_mock, schema_value) -> None:
    """Case #3: missing extraction_schema → input_validation."""
    from plugins.web_scraper.handler import extract_web_data_handler

    args = {"url": "https://example.com/"}
    if schema_value is not None:
        args["extraction_schema"] = schema_value
    out = extract_web_data_handler(args)

    parsed = json.loads(out)
    assert parsed["success"] is False
    assert parsed["error"]["stage"] == "input_validation"
    assert "extraction_schema" in parsed["error"]["message"]
    assert len(extract_web_data_mock["calls"]) == 0


# ---------------------------------------------------------------------------
# kwargs forwarding (whitelist)
# ---------------------------------------------------------------------------


def test_handler_forwards_optional_kwargs(extract_web_data_mock) -> None:
    """Case #4: optional kwargs are forwarded to extract_web_data."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_handler(
        {
            "url": "https://example.com/",
            "extraction_schema": "x",
            "prefer_dynamic": True,
            "respect_robots": False,
            "timeout_s": 60,
            "max_chars": 90000,
            "user_agent": "MyAgent/1.0",
        }
    )

    _, kwargs = extract_web_data_mock["calls"][0]
    assert kwargs == {
        "prefer_dynamic": True,
        "respect_robots": False,
        "timeout_s": 60,
        "max_chars": 90000,
        "user_agent": "MyAgent/1.0",
    }


def test_handler_drops_none_kwargs(extract_web_data_mock) -> None:
    """Case #5: optional kwargs whose value is None must NOT be forwarded."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_handler(
        {
            "url": "https://example.com/",
            "extraction_schema": "x",
            "prefer_dynamic": None,
            "respect_robots": None,
            "timeout_s": None,
            "max_chars": None,
            "user_agent": None,
        }
    )

    _, kwargs = extract_web_data_mock["calls"][0]
    assert kwargs == {}


def test_handler_drops_unknown_kwargs(extract_web_data_mock) -> None:
    """Unknown keys (e.g. ``model``, garbage) are silently dropped (T-INT-SEC-16)."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_handler(
        {
            "url": "https://example.com/",
            "extraction_schema": "x",
            "model": "gpt-4o",  # ADR-INT-5 hidden — must never flow through
            "evil": "drop me",
            "__proto__": "drop me too",
        }
    )

    _, kwargs = extract_web_data_mock["calls"][0]
    assert "model" not in kwargs
    assert "evil" not in kwargs
    assert "__proto__" not in kwargs


def test_handler_strips_url_whitespace(extract_web_data_mock) -> None:
    """Case (+9): leading/trailing whitespace is stripped before dispatching."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_handler(
        {"url": "  https://example.com/  ", "extraction_schema": "x"}
    )

    args, _ = extract_web_data_mock["calls"][0]
    assert args[0] == "https://example.com/"


# ---------------------------------------------------------------------------
# extraction_schema length limit (FU-INT-SEC-11 / T-INT-SEC-12)
# ---------------------------------------------------------------------------


def test_handler_rejects_oversized_extraction_schema(extract_web_data_mock) -> None:
    """T-INT-SEC-12 / FU-INT-SEC-11: schema longer than 64 KiB is rejected."""
    from plugins.web_scraper.handler import (
        MAX_EXTRACTION_SCHEMA_LEN,
        extract_web_data_handler,
    )

    oversized = "a" * (MAX_EXTRACTION_SCHEMA_LEN + 1)
    out = extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": oversized}
    )
    parsed = json.loads(out)
    assert parsed["success"] is False
    assert parsed["error"]["stage"] == "input_validation"
    assert "extraction_schema" in parsed["error"]["message"]
    # No call to underlying tool when input is rejected
    assert len(extract_web_data_mock["calls"]) == 0


def test_handler_accepts_max_length_extraction_schema(extract_web_data_mock) -> None:
    """Boundary: exactly MAX bytes is allowed."""
    from plugins.web_scraper.handler import (
        MAX_EXTRACTION_SCHEMA_LEN,
        extract_web_data_handler,
    )

    at_limit = "a" * MAX_EXTRACTION_SCHEMA_LEN
    extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": at_limit}
    )
    assert len(extract_web_data_mock["calls"]) == 1


# ---------------------------------------------------------------------------
# Exception handling (ADR-INT-6 / Case #7)
# ---------------------------------------------------------------------------


def test_handler_catches_unexpected_exception(extract_web_data_mock) -> None:
    """Case #7: extract_web_data raises → JSON unknown stage, never re-raises."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_mock["set_raises"](RuntimeError("boom"))

    out = extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": "x"}
    )

    parsed = json.loads(out)
    assert parsed["success"] is False
    assert parsed["error"]["stage"] == "unknown"
    assert "RuntimeError" in parsed["error"]["message"]
    assert parsed["error"]["retryable"] is False
    assert parsed["data"] is None


def test_handler_catches_base_exception(extract_web_data_mock) -> None:
    """Even BaseException (e.g. SystemExit) is caught — final defence."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_mock["set_raises"](SystemExit("nope"))

    out = extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": "x"}
    )
    parsed = json.loads(out)
    assert parsed["success"] is False
    assert parsed["error"]["stage"] == "unknown"


def test_handler_catches_import_error(monkeypatch, extract_web_data_mock) -> None:
    """If web_scraper_tool somehow disappears at call time, return JSON."""
    import sys
    from plugins.web_scraper.handler import extract_web_data_handler

    # Remove the stub mid-flight so the in-function import fails.
    monkeypatch.setitem(sys.modules, "web_scraper_tool", None)

    out = extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": "x"}
    )
    parsed = json.loads(out)
    assert parsed["success"] is False
    assert parsed["error"]["stage"] == "unknown"


# ---------------------------------------------------------------------------
# Logging: no agent input leakage (R-INT-SEC-01, R-INT-SEC-02, FU-INT-SEC-06)
# ---------------------------------------------------------------------------


def test_handler_does_not_log_args_on_exception(
    extract_web_data_mock, caplog_plugin
) -> None:
    """T-INT-SEC-11 / R-INT-SEC-02: on exception only ``type(e).__name__`` is logged."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_mock["set_raises"](RuntimeError("very secret detail"))

    url = "https://user:pass@example.com/"
    extract_web_data_handler({"url": url, "extraction_schema": "secret-schema"})

    # The exception message and args should NOT appear in any log record.
    combined = "\n".join(rec.getMessage() for rec in caplog_plugin.records)
    assert "user:pass" not in combined
    assert "very secret detail" not in combined
    assert "secret-schema" not in combined
    # The exception type name is allowed (it carries no secret data).
    assert "RuntimeError" in combined


def test_handler_does_not_log_args_on_validation_failure(
    extract_web_data_mock, caplog_plugin
) -> None:
    """R-INT-SEC-01: validation errors must not leak agent input."""
    from plugins.web_scraper.handler import extract_web_data_handler

    extract_web_data_handler({"url": "https://user:pass@example.com/"})

    combined = "\n".join(rec.getMessage() for rec in caplog_plugin.records)
    assert "user:pass" not in combined


# ---------------------------------------------------------------------------
# 4-key contract guarantee (Case #8)
# ---------------------------------------------------------------------------


def test_error_responses_have_all_four_keys(extract_web_data_mock) -> None:
    """Every adapter-generated error JSON has success/data/error/metadata keys."""
    from plugins.web_scraper.handler import extract_web_data_handler

    # url missing
    out_1 = extract_web_data_handler({"extraction_schema": "x"})
    # schema missing
    out_2 = extract_web_data_handler({"url": "https://example.com/"})
    # exception
    extract_web_data_mock["set_raises"](RuntimeError())
    out_3 = extract_web_data_handler(
        {"url": "https://example.com/", "extraction_schema": "x"}
    )
    # oversized schema
    from plugins.web_scraper.handler import MAX_EXTRACTION_SCHEMA_LEN

    out_4 = extract_web_data_handler(
        {
            "url": "https://example.com/",
            "extraction_schema": "x" * (MAX_EXTRACTION_SCHEMA_LEN + 1),
        }
    )

    for raw in (out_1, out_2, out_3, out_4):
        parsed = json.loads(raw)
        assert set(parsed.keys()) == {"success", "data", "error", "metadata"}
        assert parsed["success"] is False
        assert parsed["data"] is None
        assert isinstance(parsed["error"], dict)
        assert "stage" in parsed["error"]
        assert "message" in parsed["error"]
        assert "retryable" in parsed["error"]
        assert "recommended_next_action" in parsed["error"]


# ---------------------------------------------------------------------------
# `model` hiding (T-INT-SEC-16 / R-INT-SEC-03)
# ---------------------------------------------------------------------------


def test_model_arg_is_not_forwarded(extract_web_data_mock) -> None:
    """T-INT-SEC-16: ``model`` is dropped silently — ADR-INT-5."""
    from plugins.web_scraper.handler import (
        FORWARDABLE_KEYS,
        extract_web_data_handler,
    )

    assert "model" not in FORWARDABLE_KEYS

    extract_web_data_handler(
        {
            "url": "https://example.com/",
            "extraction_schema": "x",
            "model": "gpt-4o",
        }
    )

    _, kwargs = extract_web_data_mock["calls"][0]
    assert "model" not in kwargs
