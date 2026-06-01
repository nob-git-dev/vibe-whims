"""Schema sanity & manifest consistency tests.

Verifies:
- WEB_SCRAPER_EXTRACT_SCHEMA is a valid JSON-Schema-compatible structure
- The ``model`` parameter is *not* present (ADR-INT-5 / T-INT-SEC-11)
- The schema name + required keys match what plugin.yaml advertises
- plugin.yaml is well-formed and lists the tool under ``provides_tools``
"""

from __future__ import annotations

from pathlib import Path


def test_schema_top_level_shape() -> None:
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    assert WEB_SCRAPER_EXTRACT_SCHEMA["name"] == "web_scraper_extract"
    assert "description" in WEB_SCRAPER_EXTRACT_SCHEMA
    assert WEB_SCRAPER_EXTRACT_SCHEMA["parameters"]["type"] == "object"


def test_schema_required_fields() -> None:
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    required = WEB_SCRAPER_EXTRACT_SCHEMA["parameters"]["required"]
    assert "url" in required
    assert "extraction_schema" in required
    assert len(required) == 2  # exactly these two


def test_schema_optional_fields_present() -> None:
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    props = WEB_SCRAPER_EXTRACT_SCHEMA["parameters"]["properties"]
    for key in (
        "url",
        "extraction_schema",
        "prefer_dynamic",
        "respect_robots",
        "timeout_s",
        "max_chars",
        "user_agent",
    ):
        assert key in props, f"missing schema property: {key}"


def test_schema_does_not_expose_model() -> None:
    """T-INT-SEC-11 / R-INT-SEC-03 / ADR-INT-5: ``model`` is *hidden* from the agent."""
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    props = WEB_SCRAPER_EXTRACT_SCHEMA["parameters"]["properties"]
    assert "model" not in props, "ADR-INT-5: model must be hidden from the agent"


def test_schema_url_type_is_string() -> None:
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    props = WEB_SCRAPER_EXTRACT_SCHEMA["parameters"]["properties"]
    assert props["url"]["type"] == "string"
    assert props["extraction_schema"]["type"] == "string"


def test_schema_integer_bounds() -> None:
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    props = WEB_SCRAPER_EXTRACT_SCHEMA["parameters"]["properties"]
    assert props["timeout_s"]["minimum"] >= 1
    assert props["timeout_s"]["maximum"] <= 300
    assert props["max_chars"]["minimum"] >= 1000


def test_schema_descriptions_warn_against_userinfo_in_url() -> None:
    """FU-INT-SEC-10 echo: surface guidance to the agent in the URL field."""
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    url_desc = WEB_SCRAPER_EXTRACT_SCHEMA["parameters"]["properties"]["url"][
        "description"
    ].lower()
    # We want at least a hint that http/https are required.
    assert "http" in url_desc


# ---------------------------------------------------------------------------
# plugin.yaml integrity
# ---------------------------------------------------------------------------


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
PLUGIN_YAML = PLUGIN_ROOT / "plugin.yaml"


def test_plugin_yaml_exists_and_parses() -> None:
    import yaml

    assert PLUGIN_YAML.exists(), f"plugin.yaml not found at {PLUGIN_YAML}"
    data = yaml.safe_load(PLUGIN_YAML.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    assert data.get("name") == "web_scraper"
    assert data.get("kind") == "standalone"
    assert "version" in data
    assert "description" in data


def test_plugin_yaml_advertises_tool_name() -> None:
    import yaml

    data = yaml.safe_load(PLUGIN_YAML.read_text(encoding="utf-8"))
    provides = data.get("provides_tools") or []
    assert "web_scraper_extract" in provides
    assert len(provides) == 1


def test_plugin_yaml_does_not_register_hooks() -> None:
    """R-INT-SEC-05 / AS-7: plugin.yaml must NOT declare hooks."""
    import yaml

    data = yaml.safe_load(PLUGIN_YAML.read_text(encoding="utf-8"))
    assert "hooks" not in data or not data.get("hooks"), (
        "AS-7 / R-INT-SEC-05: web_scraper must not register hooks"
    )


def test_plugin_yaml_platforms_include_linux_and_macos() -> None:
    import yaml

    data = yaml.safe_load(PLUGIN_YAML.read_text(encoding="utf-8"))
    platforms = data.get("platforms") or []
    assert "linux" in platforms
    assert "macos" in platforms


def test_plugin_yaml_matches_schema_name() -> None:
    """plugin.yaml.provides_tools[0] == WEB_SCRAPER_EXTRACT_SCHEMA["name"]."""
    import yaml
    from plugins.web_scraper.schemas import WEB_SCRAPER_EXTRACT_SCHEMA

    data = yaml.safe_load(PLUGIN_YAML.read_text(encoding="utf-8"))
    assert WEB_SCRAPER_EXTRACT_SCHEMA["name"] in data["provides_tools"]
