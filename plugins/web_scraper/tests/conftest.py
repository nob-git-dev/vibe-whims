"""pytest fixtures for the web_scraper plugin tests.

These tests run without any network access. The existing
``extract_web_data`` library is replaced with a controllable mock so we
can exercise the adapter behaviour deterministically.

Two import paths are supported for ``extract_web_data``:

1. ``web_scraper_tool`` — module-level import as the production code
   uses (resolved via PYTHONPATH in the container, see ADR-INT-2).
2. ``tools.web_scraper_tool.web_scraper_tool`` — used only when the
   real library happens to be importable; the adapter never imports
   it that way.

The fixture installs a stub ``web_scraper_tool`` module in
``sys.modules`` so ``from web_scraper_tool import extract_web_data``
works in the test environment without touching real network code.
"""

from __future__ import annotations

import importlib
import json
import logging
import sys
import types
from typing import Any, Callable

import pytest


@pytest.fixture(autouse=True)
def _reset_handler_module_cache() -> None:
    """Drop cached plugin modules between tests so each test can re-import
    against a freshly built stub. We avoid touching the real package."""
    # Modules under test that close over `web_scraper_tool`.
    for mod in (
        "plugins.web_scraper.handler",
        "plugins.web_scraper.check",
        "plugins.web_scraper.schemas",
        "plugins.web_scraper.__init__",
        "plugins.web_scraper",
        "plugins.web_scraper._logging_setup",
    ):
        sys.modules.pop(mod, None)
    yield
    # Best-effort cleanup of the stub; the next test will re-install.
    sys.modules.pop("web_scraper_tool", None)


@pytest.fixture
def extract_web_data_mock(monkeypatch: pytest.MonkeyPatch) -> dict:
    """Install a stub ``web_scraper_tool`` module with a controllable
    ``extract_web_data`` function.

    Returns a dict with two entries:

    - ``calls``: list[tuple[args, kwargs]] captured per call.
    - ``set_return(value)``: helper to set the value the stub returns.
    - ``set_raises(exc)``: helper to make the stub raise ``exc``.
    """

    calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    state: dict[str, Any] = {
        "return_value": json.dumps(
            {
                "success": True,
                "data": {"title": "ok"},
                "error": None,
                "metadata": {"url": "https://example.com"},
            },
            ensure_ascii=False,
        ),
        "raises": None,
    }

    def _extract_web_data(*args: Any, **kwargs: Any) -> str:
        calls.append((args, kwargs))
        if state["raises"] is not None:
            raise state["raises"]
        return state["return_value"]

    stub = types.ModuleType("web_scraper_tool")
    stub.extract_web_data = _extract_web_data  # type: ignore[attr-defined]
    # The real module exposes __all__ = ["extract_web_data"]; mirror it.
    stub.__all__ = ["extract_web_data"]  # type: ignore[attr-defined]
    # Mark a stable __file__ so FU-INT-SEC-03 (path-check) can be exercised.
    stub.__file__ = "/path/to/web_scraper_tool/web_scraper_tool.py"
    monkeypatch.setitem(sys.modules, "web_scraper_tool", stub)

    def _set_return(value: Any) -> None:
        state["return_value"] = value
        state["raises"] = None

    def _set_raises(exc: BaseException) -> None:
        state["raises"] = exc

    return {
        "calls": calls,
        "set_return": _set_return,
        "set_raises": _set_raises,
    }


@pytest.fixture
def plugin_ctx() -> "FakePluginCtx":
    """A minimal stand-in for ``hermes_cli.plugins.PluginContext``.

    Captures all ``register_tool`` / ``register_hook`` / ``register_cli_command``
    calls so tests can assert on what was registered.
    """
    return FakePluginCtx()


class FakePluginCtx:
    """Test double for ``PluginContext``."""

    def __init__(self) -> None:
        self.registered_tools: list[dict[str, Any]] = []
        self.registered_hooks: list[tuple[str, Callable[..., Any]]] = []
        self.registered_cli_commands: list[dict[str, Any]] = []

    def register_tool(
        self,
        *,
        name: str,
        toolset: str,
        schema: dict,
        handler: Callable[..., Any],
        check_fn: Callable[[], bool] | None = None,
        requires_env: list | None = None,
        is_async: bool = False,
        description: str = "",
        emoji: str = "",
        override: bool = False,
    ) -> None:
        self.registered_tools.append(
            {
                "name": name,
                "toolset": toolset,
                "schema": schema,
                "handler": handler,
                "check_fn": check_fn,
                "requires_env": requires_env,
                "is_async": is_async,
                "description": description,
                "emoji": emoji,
                "override": override,
            }
        )

    def register_hook(self, hook_name: str, callback: Callable[..., Any]) -> None:
        self.registered_hooks.append((hook_name, callback))

    def register_cli_command(self, **kwargs: Any) -> None:
        self.registered_cli_commands.append(kwargs)


@pytest.fixture
def caplog_plugin(caplog: pytest.LogCaptureFixture) -> pytest.LogCaptureFixture:
    """``caplog`` scoped to all plugin loggers at INFO level."""
    caplog.set_level(logging.DEBUG, logger="plugins.web_scraper")
    caplog.set_level(logging.DEBUG, logger="plugins.web_scraper.handler")
    caplog.set_level(logging.DEBUG, logger="plugins.web_scraper.check")
    caplog.set_level(logging.DEBUG, logger="plugins.web_scraper._logging_setup")
    return caplog


def _maybe_reload(name: str) -> Any:
    """Import-or-reload helper used in tests."""
    if name in sys.modules:
        return importlib.reload(sys.modules[name])
    return importlib.import_module(name)
