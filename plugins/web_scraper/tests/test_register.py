"""Tests for the plugin entrypoint (`register(ctx)`).

Reference:
- R-INT-SEC-06: ``__init__.py`` must NOT call ``register_hook``
- R-INT-SEC-07: ``_logging_setup`` is loaded so the filter is attached
- T-INT-SEC-08: register() never raises — even when imports fail
"""

from __future__ import annotations

import importlib
import sys


def test_register_attaches_one_tool(extract_web_data_mock, plugin_ctx) -> None:
    """The plugin registers exactly one tool: ``web_scraper_extract``."""
    import types

    for name in ("litellm", "trafilatura", "bs4", "lxml", "nest_asyncio"):
        sys.modules.setdefault(name, types.ModuleType(name))

    pkg = importlib.import_module("plugins.web_scraper")
    pkg.register(plugin_ctx)

    assert len(plugin_ctx.registered_tools) == 1
    spec = plugin_ctx.registered_tools[0]
    assert spec["name"] == "web_scraper_extract"
    assert spec["toolset"] == "web_scraper"
    assert spec["override"] is False
    assert spec["is_async"] is False
    assert callable(spec["handler"])
    assert callable(spec["check_fn"])
    assert spec["schema"]["name"] == "web_scraper_extract"


def test_register_does_not_register_hooks(extract_web_data_mock, plugin_ctx) -> None:
    """R-INT-SEC-06: hooks are forbidden for this plugin."""
    import types

    for name in ("litellm", "trafilatura", "bs4", "lxml", "nest_asyncio"):
        sys.modules.setdefault(name, types.ModuleType(name))

    pkg = importlib.import_module("plugins.web_scraper")
    pkg.register(plugin_ctx)

    assert plugin_ctx.registered_hooks == []
    assert plugin_ctx.registered_cli_commands == []


def test_register_swallows_internal_import_failures(plugin_ctx, monkeypatch) -> None:
    """T-INT-SEC-08 / fail-soft: even if a sub-module raises during import,
    ``register()`` must not propagate the exception so other plugins
    continue to load.
    """
    # First make sure the plugin module itself is loaded fresh.
    pkg = importlib.import_module("plugins.web_scraper")
    pkg = importlib.reload(pkg)

    # Install a sentinel that explodes on *attribute access* — this is how
    # ``from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA``
    # will fail inside ``register()``.
    class _Exploding:
        def __getattr__(self, name: str) -> object:
            raise RuntimeError(f"deliberate boom on {name}")

    monkeypatch.setitem(sys.modules, "plugins.web_scraper.schemas", _Exploding())

    # Should not raise even with a borked submodule.
    pkg.register(plugin_ctx)
    assert plugin_ctx.registered_tools == []
    assert plugin_ctx.registered_hooks == []


def test_register_is_idempotent_per_ctx(extract_web_data_mock) -> None:
    """Calling register on two separate ctx objects yields one tool each."""
    import types
    from plugins.web_scraper.tests.conftest import FakePluginCtx

    for name in ("litellm", "trafilatura", "bs4", "lxml", "nest_asyncio"):
        sys.modules.setdefault(name, types.ModuleType(name))

    pkg = importlib.import_module("plugins.web_scraper")
    ctx_a = FakePluginCtx()
    ctx_b = FakePluginCtx()
    pkg.register(ctx_a)
    pkg.register(ctx_b)
    assert len(ctx_a.registered_tools) == 1
    assert len(ctx_b.registered_tools) == 1
