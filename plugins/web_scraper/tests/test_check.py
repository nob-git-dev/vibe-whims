"""Availability gate tests (T-INT-SEC-05 / T-INT-SEC-09 / FU-INT-SEC-03)."""

from __future__ import annotations

import logging
import sys

import pytest


def test_check_returns_true_when_all_modules_importable(extract_web_data_mock) -> None:
    """Happy path: every required module is importable → ``True``.

    The conftest ``extract_web_data_mock`` fixture installs a stub for
    ``web_scraper_tool``. The remaining required modules
    (litellm/trafilatura/etc.) are stubbed in this test as well.
    """
    import types

    real_modules = {
        "litellm": types.ModuleType("litellm"),
        "trafilatura": types.ModuleType("trafilatura"),
        "bs4": types.ModuleType("bs4"),
        "lxml": types.ModuleType("lxml"),
        "nest_asyncio": types.ModuleType("nest_asyncio"),
        "jsonschema": types.ModuleType("jsonschema"),
        "httpx": types.ModuleType("httpx"),
    }
    for name, module in real_modules.items():
        sys.modules[name] = module

    from plugins.web_scraper.check import check_web_scraper_available

    assert check_web_scraper_available() is True


@pytest.mark.parametrize(
    "missing",
    ["web_scraper_tool", "litellm", "trafilatura", "bs4", "lxml", "nest_asyncio"],
)
def test_check_returns_false_when_module_missing(
    monkeypatch, extract_web_data_mock, caplog, missing
) -> None:
    """T-INT-SEC-05 / T-INT-SEC-09: any required missing dep → False (fail-closed)."""
    import types

    # Install stubs for every required module *except* the one we are testing.
    deps = [
        "litellm",
        "trafilatura",
        "bs4",
        "lxml",
        "nest_asyncio",
        "jsonschema",
        "httpx",
    ]
    for name in deps:
        if name != missing:
            sys.modules.setdefault(name, types.ModuleType(name))

    # Force the missing module's lookup to fail.
    monkeypatch.setitem(sys.modules, missing, None)

    caplog.set_level(logging.INFO, logger="plugins.web_scraper.check")

    from plugins.web_scraper.check import check_web_scraper_available

    assert check_web_scraper_available() is False


def test_check_logs_loaded_path_for_web_scraper_tool(
    extract_web_data_mock, caplog
) -> None:
    """FU-INT-SEC-03: ``web_scraper_tool.__file__`` is logged on success so
    operators can spot PYTHONPATH-hijack attempts."""
    import types

    for name in ("litellm", "trafilatura", "bs4", "lxml", "nest_asyncio"):
        sys.modules.setdefault(name, types.ModuleType(name))

    caplog.set_level(logging.INFO, logger="plugins.web_scraper.check")

    from plugins.web_scraper.check import check_web_scraper_available

    assert check_web_scraper_available() is True

    msgs = " ".join(rec.getMessage() for rec in caplog.records)
    # Path from the conftest stub
    assert "/path/to/web_scraper_tool/web_scraper_tool.py" in msgs


def test_check_does_not_raise_on_missing_module(
    monkeypatch, extract_web_data_mock
) -> None:
    """Even if a dependency raises an unusual error, ``check`` returns False
    rather than propagating the exception."""
    import types

    for name in ("litellm", "trafilatura", "bs4", "lxml", "nest_asyncio"):
        sys.modules.setdefault(name, types.ModuleType(name))

    monkeypatch.setitem(sys.modules, "litellm", None)

    from plugins.web_scraper.check import check_web_scraper_available

    # Even with a None entry forcing ImportError, must not raise.
    result = check_web_scraper_available()
    assert result is False
