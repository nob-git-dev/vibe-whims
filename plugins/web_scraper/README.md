# web_scraper — Hermes plugin

> This page is English only. For a Japanese summary, see the repository
> root [README.md](../../README.md).

Thin adapter that exposes the in-repo `web_scraper_tool/web_scraper_tool.py`
library to the Hermes agent runtime as a registered tool named
**`web_scraper_extract`** in the **`web_scraper`** toolset.

It does **not** re-implement scraping logic — the heavy lifting (SSRF
defence, robots.txt handling, static + dynamic fetch, LLM-driven JSON
extraction) lives in the upstream module. This plugin is a Hermes-shaped
wrapper around that single `extract_web_data(url, extraction_schema, ...)`
function.

## Purpose

Lets an agent say "extract `{title, author}` from `https://...`" and get
back a strict JSON envelope with the result, without writing scraping
code each turn.

## Layout

```
plugins/web_scraper/
├── plugin.yaml          # Hermes manifest (name / version / provides_tools)
├── __init__.py          # register(ctx) — Hermes entry point
├── schemas.py           # WEB_SCRAPER_EXTRACT_SCHEMA (OpenAI function-call shape)
├── handler.py           # adapter: args dict → extract_web_data() JSON string
├── check.py             # check_fn: gate on dependency availability
├── _logging_setup.py    # SecretsRedactingFilter for the plugin's loggers
├── README.md            # this file
└── tests/               # pytest unit tests (no network)
```

The upstream library is **not** vendored here. It is reached at runtime
by adding the parent directory of `web_scraper_tool/` to `PYTHONPATH`
(e.g. `PYTHONPATH=/path/to/repo/` if the directory layout matches this
repository, or whatever your container/host injects for the Hermes
plugin loader).

## Public surface

| Tool name              | Toolset       | Returns                              |
|------------------------|---------------|--------------------------------------|
| `web_scraper_extract`  | `web_scraper` | JSON string `{success, data, error, metadata}` |

### Parameters (LLM-facing)

| Name                | Required | Default | Notes |
|---------------------|----------|---------|-------|
| `url`               | yes      | —       | http/https only. **Do not include userinfo.** |
| `extraction_schema` | yes      | —       | JSON Schema string OR natural-language description. Max 64 KiB. |
| `prefer_dynamic`    | no       | false   | Skip static fetch, jump to Playwright. |
| `respect_robots`    | no       | true    | Honor robots.txt. |
| `timeout_s`         | no       | 30      | 1–300 seconds. |
| `max_chars`         | no       | 60000   | LLM input trim (1000–200000). |
| `user_agent`        | no       | default | Override the UA. |

> **`model` is intentionally hidden** from the agent (ADR-INT-5). The
> backing LLM is resolved from `WEB_SCRAPER_LLM_MODEL` / module defaults
> inside `extract_web_data`. Hiding it prevents prompt-injection-driven
> redirection to external LLMs (cost + key exfiltration risk).

### Return envelope

Always JSON-parseable, always four top-level keys:

```jsonc
{
  "success": true,
  "data":    { ... },     // extraction_schema-shaped object
  "error":   null,        // or { stage, message, details, retryable, recommended_next_action }
  "metadata": { ... }     // url, final_url, fetch_strategy, status_code, elapsed_ms, model, ...
}
```

Failure paths set `success=false`, `data=null`, populate `error.stage`
(one of `input_validation`, `robots`, `static_fetch`, `dynamic_fetch`,
`extraction`, `validation`, `unknown`), and still return JSON.

## Local development

```bash
cd plugins/web_scraper/
uv venv
uv pip install pytest pyyaml jsonschema ruff

# The handler imports ``web_scraper_tool`` lazily. Tests mock it, so the
# real library does NOT need to be installed to run the suite.
PYTHONPATH=../.. uv run pytest tests/ -v

# Lint
uv run ruff check
uv run ruff format --check
```

Inside the container the real library is on PYTHONPATH; the handler will
resolve `from web_scraper_tool import extract_web_data` at call time.

## Known limitations / operational guidance

- **Do not include userinfo in `url`.**
  Credentials embedded as `http://user:pass@host/` are recorded in the
  Hermes session log alongside other tool arguments. The plugin scrubs
  them from its own log output (`SecretsRedactingFilter`), but the
  session DB args are managed by Hermes core and are out of scope here.
  See SPEC §FU-INT-SEC-10.
- **Playwright is optional at availability-check time.** Static fetch
  works without it; if the page needs dynamic rendering and Playwright
  is missing, you'll get `error.stage="dynamic_fetch"` rather than the
  tool disappearing.
- **6 extra deps in the container.** `playwright`, `trafilatura`,
  `litellm`, `bs4`, `lxml`, `nest_asyncio`. Added once via the Dockerfile
  (see SPEC §2 and `## デプロイ計画` for the diff). The Playwright Python
  package is pinned to `>=1.49,<1.50` to match the chromium revision
  (`chromium_headless_shell-1223`) already installed in the image — do
  NOT bump it without also bumping the chromium revision (ADR-INT-7).
- **Host-side file permissions matter (FU-INT-SEC-01).**
  Anyone with write access to `plugins/web_scraper/` can run arbitrary
  code in the Hermes container by editing `__init__.py`. Keep the
  directory under `<your-user>:<your-group> 0755` (or whatever your
  project owner is), version-control it in git, and review diffs to
  `__init__.py` carefully in PRs.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `hermes tools list` doesn't show `web_scraper` | plugin disabled | Add `web_scraper` under `plugins.enabled` in `config.yaml` then `docker compose restart hermes`. |
| `web_scraper` shown but `web_scraper_extract` is `✗ disabled` | `check_fn` returned False | `docker exec hermes /opt/hermes/.venv/bin/python -c "from plugins.web_scraper.check import check_web_scraper_available as c; print(c())"` and check the container log for `import X failed`. |
| handler returns `error.stage="unknown"` | Bug in adapter or upstream | The log line `adapter error: <TypeName>` carries no agent-input details — grep for it, then inspect `docker logs hermes` around the same timestamp. |
| Playwright crashes with `browser binary not found` | Python `playwright` and the bundled chromium revision drifted | Re-pin in Dockerfile to match `chromium_headless_shell-1223` (Playwright 1.49.x); see ADR-INT-7. |

## References

- `SPEC-web-scraper-tool-integration.md` — this plugin's spec (private)
- `SPEC-web-scraper-tool.md` — upstream library spec (private)
- Hermes plugin protocol — see the upstream Hermes documentation
