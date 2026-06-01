# web_scraper_tool

> このページは日本語のみです。英語の概要は repository root の
> [README.md](../README.md) を参照してください。

> エージェント登録可能な汎用 Web データ抽出ツール

URL と「欲しいデータの形」（JSON Schema または自然言語）を渡すと、3 層
パイプライン（静的取得 → 動的取得 → LLM による構造化抽出）を経由して、
**常に JSON 文字列**を返す Python 関数 `extract_web_data` を提供します。

## 目次

- [何ができるか](#何ができるか)
- [インストール](#インストール)
- [基本的な使い方](#基本的な使い方)
- [出力スキーマ](#出力スキーマ)
- [サンプル出力](#サンプル出力)
- [エージェントフレームワークへの登録](#エージェントフレームワークへの登録)
- [テストの実行](#テストの実行)
- [既知の制約・制限事項](#既知の制約制限事項)
- [Security warnings](#security-warnings)
- [CI / Pre-commit 推奨](#ci--pre-commit-推奨)
- [一次情報の参照先](#一次情報の参照先)

## 何ができるか

| ユースケース | 入力 | 出力 |
|---|---|---|
| ブログ記事のタイトル・著者を取り出す | URL + JSON Schema | JSON Schema に沿った dict |
| SPA ページから本文を取り出す (`prefer_dynamic=True`) | URL + JSON Schema | Playwright で描画後の dict |
| 自然言語で「あれを抽出して」 | URL + "..." | LLM ベストエフォートの dict |
| 失敗を構造化エラーで受け取る | 任意 | `error.stage` 7 値で分類 |

- **常に JSON 文字列**で返り、例外を呼び出し側に投げません（F2/F3）。
- 内部はビルトインの SSRF 検証 / robots.txt 尊重 / リダイレクト追跡時の
  再検証 / プロンプトインジェクション耐性 / シークレットマスキングを実装。

## インストール

```bash
cd web_scraper_tool/

# 仮想環境（uv 推奨）
uv venv
uv pip install -r requirements.txt

# 動的取得（Playwright）を使う場合のみ Chromium をインストール
uv run playwright install chromium
```

### 環境変数

このパッケージは下記 3 つの環境変数のみで LLM バックエンドを切り替えられます
（SPEC F7）。

| 変数 | 既定値 | 説明 |
|---|---|---|
| `WEB_SCRAPER_LLM_MODEL` | `qwen3.5-122b` | モデル ID |
| `WEB_SCRAPER_LLM_BASE_URL` | `http://localhost:8000/v1` | OpenAI 互換ベース URL |
| `WEB_SCRAPER_LLM_API_KEY` | `EMPTY` | 認証クレデンシャル（vLLM は無認証） |
| `WEB_SCRAPER_LLM_ENABLE_THINKING` | `false` | thinking-mode 系モデル（qwen3.5 等）の reasoning を抑止 |

雛形は `dotenv-example.txt` という名前で同梱しています（生成時の都合で
`.env.example` 名にせず、利用者にリネームしてもらう運用です）。
利用時は

```bash
cp dotenv-example.txt .env.example   # コミット用（値は書かない）
cp dotenv-example.txt .env           # ローカル用（値を書く・要 .gitignore）
```

のいずれかで配置してください。

## 基本的な使い方

```python
from web_scraper_tool import extract_web_data
import json

raw = extract_web_data(
    url="https://example.com/article",
    extraction_schema=json.dumps({
        "type": "object",
        "required": ["title"],
        "properties": {
            "title": {"type": "string"},
            "author": {"type": "string"},
            "published_at": {"type": "string"}
        }
    }),
)
result = json.loads(raw)
if result["success"]:
    print(result["data"])
else:
    print(result["error"]["stage"], result["error"]["message"])
```

### 引数（一次情報: `web_scraper_tool.py` の `extract_web_data` Docstring）

| 引数 | 型 | 既定 | 説明 |
|---|---|---|---|
| `url` | `str` | — | `http` / `https` のみ。SSRF 検証 + IDN 正規化済み。 |
| `extraction_schema` | `str` | — | JSON Schema 文字列または自然言語。空文字列は不可。 |
| `model` | `str \| None` | `None` | 引数 > env > `qwen3.5-122b` の順で解決。 |
| `timeout_s` | `int` | `30` | 1 リクエストあたり。 |
| `max_chars` | `int` | `60000` | LLM 投入前の本文上限。 |
| `prefer_dynamic` | `bool` | `False` | `True` で静的をスキップし Playwright のみ。 |
| `respect_robots` | `bool` | `True` | `False` で robots.txt 無視。 |
| `user_agent` | `str \| None` | `None` | 既定は `WebScraperTool/1.0 (+...)`。 |

## 出力スキーマ

```jsonc
// 成功時
{
  "success": true,
  "data": { /* 抽出結果 (スキーマに準拠) */ },
  "error": null,
  "metadata": {
    "url": "https://example.com/article",
    "final_url": "https://example.com/article",
    "fetch_strategy": "static",  // "static" | "dynamic" | "none"
    "status_code": 200,
    "content_length": 12345,
    "elapsed_ms": 842,
    "model": "qwen3.5-122b",
    "schema_validated": true,
    "warnings": [],
    "redirect_chain": []
  }
}

// 失敗時
{
  "success": false,
  "data": null,
  "error": {
    "stage": "input_validation | robots | static_fetch | dynamic_fetch | extraction | validation | unknown",
    "message": "human-readable summary",
    "details": { /* stage 固有 */ },
    "retryable": false,
    "recommended_next_action": "what the caller agent should try next"
  },
  "metadata": { /* same shape as above */ }
}
```

## サンプル出力

> NOTE: 下記はテストスイートのモック（実装の実行結果）を貼っています。
> 実 LLM バックエンドに依存しないため、CI で再現可能です。

### 成功時（モック出力）

```json
{
  "success": true,
  "data": {"title": "記事", "body": "本文 本文"},
  "error": null,
  "metadata": {
    "url": "http://example.test/p",
    "final_url": "http://example.test/p",
    "fetch_strategy": "static",
    "status_code": 200,
    "content_length": 2348,
    "elapsed_ms": 12,
    "model": "qwen3.5-122b",
    "schema_validated": true,
    "warnings": [],
    "redirect_chain": []
  }
}
```

### 失敗時（モック出力・robots.txt Disallow）

```json
{
  "success": false,
  "data": null,
  "error": {
    "stage": "robots",
    "message": "robots.txt disallows this URL for the given User-Agent",
    "details": {
      "user_agent": "WebScraperTool/1.0 (+https://github.com/nob-git-dev/vibe-whims)",
      "url": "http://example.test/private"
    },
    "retryable": false,
    "recommended_next_action": "respect site policy or set respect_robots=False"
  },
  "metadata": {
    "url": "http://example.test/private",
    "final_url": null,
    "fetch_strategy": "none",
    "status_code": null,
    "content_length": 0,
    "elapsed_ms": 3,
    "model": "qwen3.5-122b",
    "schema_validated": false,
    "warnings": [],
    "redirect_chain": []
  }
}
```

### 失敗時（モック出力・SSRF 拒否）

```json
{
  "success": false,
  "data": null,
  "error": {
    "stage": "input_validation",
    "message": "resolved IP is private / reserved",
    "details": {"hostname": "internal.example.test", "resolved_ip": "10.0.0.5"},
    "retryable": false,
    "recommended_next_action": "do not target private network"
  },
  "metadata": {
    "url": "http://internal.example.test/x",
    "fetch_strategy": "none",
    "status_code": null,
    "content_length": 0,
    "elapsed_ms": 1,
    "model": "qwen3.5-122b",
    "schema_validated": false,
    "warnings": [],
    "redirect_chain": []
  }
}
```

## エージェントフレームワークへの登録

`agent_registration_examples.py` に 4 例を同梱しています。

### LangChain

```python
from agent_registration_examples import make_langchain_tool
tool = make_langchain_tool()
# tool を LangChain Agent の tools= に渡すだけ。
```

### LlamaIndex

```python
from agent_registration_examples import make_llamaindex_tool
tool = make_llamaindex_tool()
```

### 独自レジストリ (OpenAI / Anthropic 互換 Function Calling)

```python
from agent_registration_examples import WEB_SCRAPER_TOOL_SPEC, dispatch_tool_call

tools = [WEB_SCRAPER_TOOL_SPEC]
# LLM がツール呼び出しを返したら:
output = dispatch_tool_call("web_scraper_tool", {
    "url": "https://example.com/",
    "extraction_schema": '{"type":"object"}'
})
```

### Dify Custom Tool

```python
from agent_registration_examples import build_dify_flask_app
app = build_dify_flask_app()
app.run(host="0.0.0.0", port=8088)
# Dify 側で POST /extract を Custom Tool として登録する。
```

OpenAPI YAML サンプルは `agent_registration_examples.py` のコメント部に
記載しています。

## テストの実行

```bash
cd web_scraper_tool/
uv run pytest -v
```

テストは以下をカバーします（詳細はファイル先頭 Docstring を参照）:

- **F12**: 11 ケース（成功系・SSRF・404 / 403 / Timeout・robots・スキーマ違反・LLM 失敗等）
- **T-SEC-01..12**: IDN ホモグラフ / 数値 IP / IPv4-mapped IPv6 /
  クラウドメタデータ / リダイレクト先 SSRF / userinfo マスク /
  ログレダクション / プロンプト注入 / 巨大レスポンス / robots truncation /
  制御文字 / URL 長
- **INV-1..8**: 不変条件（AST 静的検査含む）

外部 NW 到達するテストは `@pytest.mark.integration` で分離されていますが、
本リリースでは integration マーカは未使用（すべてモックで完結）。

## 既知の制約・制限事項

- **`urllib.robotparser`** は `Crawl-delay` と `Sitemap:` を解釈しません
  （SPEC §S.3 / FU-SEC-06）。仕様準拠を上げるには `protego` への切替を
  推奨します。
- **DNS リバインディング**緩和は静的取得経路のみ。動的取得 (Playwright)
  経路では `--host-resolver-rules` 等の追加対策が必要（SPEC §S.2.3 /
  FU-SEC-02）。
- **`nest_asyncio`** は Python 3.13+ で挙動が変わる可能性があります。
  動作確認バージョン: **Python 3.11 / 3.12**。
- **CAPTCHA 回避・ログイン突破・プロキシローテーション・フィンガープリント
  偽装は実装しません**（F6 倫理上の固定方針）。
- 同梱 Chromium（Playwright）のゼロデイは playwright のメジャー更新で対応。

## Security warnings

```
WARNING: Web Page Content Is Untrusted
  The output JSON reflects whatever the LLM extracted from the page.
  If your agent uses the result as the next action's input (URL fetch, code run,
  filesystem write, message send), you MUST validate again at the agent layer.
  Consider:
    - schema_validated=false の場合は出力を信用しないか、人間レビューを介する
    - 出力 JSON の URL 値を許可ドメインリストで再検証する
    - free-form 文字列を直接 prompt に流し込まない（プロンプトインジェクションの再帰）
```

- 呼び出し側が `user_agent` を Googlebot 等に偽装して robots.txt を回避する
  ような使い方は **呼び出し側の責任**として扱います（SPEC §S.3.5 /
  FU-SEC-08）。本ツールはアクセス制御として UA 一致を強制しません。
- Playwright の `--no-sandbox` フラグは既定で付与しません。コンテナ環境で
  どうしても必要な場合のみ、運用者が `WEB_SCRAPER_PLAYWRIGHT_NO_SANDBOX=1`
  で明示的に有効化してください（SPEC §S.7.1 / FU-SEC-16）。
- **API キーやトークンを URL のクエリパラメータに含めないでください**
  （例: `?api_key=...` / `?token=...`）。本ツールの userinfo マスキングは
  ホスト前部の credentials (`http://user:pass@host/`) のみが対象で、
  querystring の値は `metadata.url` / `metadata.final_url` /
  `metadata.redirect_chain` にそのまま残ります。secret を URL ではなく
  HTTP ヘッダーで送る前提で利用してください（呼び出し側で URL を組み立てる
  時点で除去する責任があります）。

## CI / Pre-commit 推奨

依存脆弱性チェックと静的解析を CI に組み込むことを推奨します（FU-SEC-19）。

```yaml
# .pre-commit-config.yaml (サンプル・本リポジトリでは未配置)
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.0
    hooks:
      - id: ruff
        args: [--select=E,F,S,B,UP]
      - id: ruff-format
  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.10
    hooks:
      - id: bandit
        args: ["-c", "pyproject.toml"]
        additional_dependencies: ["bandit[toml]"]
  - repo: https://github.com/pypa/pip-audit
    rev: v2.7.3
    hooks:
      - id: pip-audit
        args: ["-r", "web_scraper_tool/requirements.txt"]
```

## 一次情報の参照先

- 公開関数 API: `web_scraper_tool.py` の `extract_web_data` Docstring
- 完全仕様: SPEC-web-scraper-tool.md（SPEC は private）
- LLM バックエンド既定値: `curl http://localhost:8000/v1/models`
  （`qwen3.5-122b` / OpenAI 互換 endpoint）
