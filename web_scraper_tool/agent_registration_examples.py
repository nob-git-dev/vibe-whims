"""agent_registration_examples.py

web_scraper_tool を主要なエージェントフレームワーク・自前レジストリに
登録するためのサンプル集。すべてコピペで動かせる形を目標にしている。

NOTE: ここでは ``from web_scraper_tool import extract_web_data`` のみに依存し、
      内部関数を一切呼ばない。公開 API の安定性を実際にデモする。

カバー例:
- 1. LangChain ``Tool`` 形式
- 2. LlamaIndex ``FunctionTool`` 形式
- 3. 独自レジストリ (純粋な辞書ベース)
- 4. Dify カスタムツール用 HTTP ラッパ（Flask 1 ファイル）
"""

from __future__ import annotations

import json
from typing import Any

from web_scraper_tool import extract_web_data


# ----------------------------------------------------------------------
# 1. LangChain
# ----------------------------------------------------------------------


def make_langchain_tool() -> Any:
    """LangChain の :class:`langchain_core.tools.Tool` を返す。

    使い方::

        from agent_registration_examples import make_langchain_tool
        tool = make_langchain_tool()
        agent_executor = create_react_agent(model=..., tools=[tool], ...)

    依存: ``pip install langchain langchain-core``
    """
    from langchain_core.tools import Tool  # type: ignore

    def _run(input_str: str) -> str:
        """LangChain は単一文字列の入出力を好むので JSON を文字列でやり取り。

        入力フォーマット例 (JSON 文字列)::

            {
              "url": "https://example.com/article",
              "extraction_schema": "{\"type\":\"object\",...}",
              "prefer_dynamic": false
            }
        """
        try:
            payload = json.loads(input_str)
        except Exception:
            return json.dumps(
                {
                    "success": False,
                    "data": None,
                    "error": {
                        "stage": "input_validation",
                        "message": "tool input must be a JSON string",
                        "details": {},
                        "retryable": False,
                        "recommended_next_action": "pass a JSON object as the tool input",
                    },
                    "metadata": {},
                }
            )
        url = payload.pop("url", "")
        schema = payload.pop("extraction_schema", "")
        return extract_web_data(url, schema, **payload)

    return Tool(
        name="web_scraper_tool",
        description=(
            "Extract structured JSON from a web page. "
            "Input: JSON string with keys 'url' and 'extraction_schema' "
            "(plus optional 'model', 'timeout_s', 'max_chars', 'prefer_dynamic', "
            "'respect_robots', 'user_agent'). "
            "Output: JSON string with 'success', 'data', 'error', 'metadata'."
        ),
        func=_run,
    )


# ----------------------------------------------------------------------
# 2. LlamaIndex
# ----------------------------------------------------------------------


def make_llamaindex_tool() -> Any:
    """LlamaIndex の :class:`FunctionTool` を返す。

    使い方::

        from agent_registration_examples import make_llamaindex_tool
        tool = make_llamaindex_tool()
        agent = ReActAgent.from_tools([tool], llm=...)

    依存: ``pip install llama-index llama-index-core``
    """
    from llama_index.core.tools import FunctionTool  # type: ignore

    def web_extract(
        url: str,
        extraction_schema: str,
        prefer_dynamic: bool = False,
        respect_robots: bool = True,
        timeout_s: int = 30,
        max_chars: int = 60000,
        model: str | None = None,
        user_agent: str | None = None,
    ) -> str:
        """Extract structured JSON from a web page (returns JSON string)."""
        return extract_web_data(
            url,
            extraction_schema,
            model=model,
            timeout_s=timeout_s,
            max_chars=max_chars,
            prefer_dynamic=prefer_dynamic,
            respect_robots=respect_robots,
            user_agent=user_agent,
        )

    return FunctionTool.from_defaults(
        fn=web_extract,
        name="web_scraper_tool",
        description=(
            "Extract structured JSON from a web page. "
            "Use when the user wants you to fetch a URL and return a typed object."
        ),
    )


# ----------------------------------------------------------------------
# 3. 独自レジストリ（純粋 dict ベース）
# ----------------------------------------------------------------------


# OpenAI / Anthropic 互換の Function Calling 用 JSON Schema スキーマ。
# Hermes / 自前エージェントで「ツール一覧」を JSON 形式で渡したいときに使う。
WEB_SCRAPER_TOOL_SPEC = {
    "name": "web_scraper_tool",
    "description": (
        "Extract structured JSON from a web page. "
        "Returns a JSON string with success/data/error/metadata."
    ),
    "input_schema": {
        "type": "object",
        "required": ["url", "extraction_schema"],
        "properties": {
            "url": {
                "type": "string",
                "description": "HTTP(S) URL to fetch.",
            },
            "extraction_schema": {
                "type": "string",
                "description": (
                    "JSON Schema string or natural language description of "
                    "what to extract."
                ),
            },
            "model": {"type": ["string", "null"], "default": None},
            "timeout_s": {"type": "integer", "default": 30, "minimum": 1},
            "max_chars": {"type": "integer", "default": 60000, "minimum": 1},
            "prefer_dynamic": {"type": "boolean", "default": False},
            "respect_robots": {"type": "boolean", "default": True},
            "user_agent": {"type": ["string", "null"], "default": None},
        },
        "additionalProperties": False,
    },
}


def dispatch_tool_call(name: str, arguments: dict) -> str:
    """OpenAI 互換 Function Calling 経由のエントリ。

    あなたの LLM ラッパが「ツール呼び出し」を捕まえたら、この関数に
    ``name`` と ``arguments`` を渡せばよい。

    呼び出し側の ``arguments`` dict は破壊しない（コピーを取り扱う）。
    """
    if name != "web_scraper_tool":
        return json.dumps(
            {
                "success": False,
                "data": None,
                "error": {
                    "stage": "input_validation",
                    "message": f"unknown tool: {name}",
                    "details": {},
                    "retryable": False,
                    "recommended_next_action": "select a registered tool",
                },
                "metadata": {},
            }
        )
    # 呼び出し側 dict を破壊しないようコピーを取る（pop は本コピーに対して行う）。
    args = dict(arguments)
    url = args.pop("url", "")
    schema = args.pop("extraction_schema", "")
    return extract_web_data(url, schema, **args)


# ----------------------------------------------------------------------
# 4. Dify カスタムツール用 HTTP ラッパ (Flask 単一ファイル想定)
# ----------------------------------------------------------------------


def build_dify_flask_app():
    """Dify Custom Tool は OpenAPI スキーマで HTTP エンドポイントを呼ぶ。

    本関数を 別スクリプトで:

        from agent_registration_examples import build_dify_flask_app
        app = build_dify_flask_app()
        app.run(host="0.0.0.0", port=8088)

    して動かし、Dify の Custom Tool で
    ``POST http://<this-host>:8088/extract`` を登録する。

    依存: ``pip install flask``
    """
    from flask import Flask, jsonify, request  # type: ignore

    app = Flask("web_scraper_tool_bridge")

    @app.post("/extract")
    def _extract():
        raw = request.get_json(silent=True) or {}
        # 呼び出し側 / Flask キャッシュを破壊しないようコピーを取る。
        payload = dict(raw)
        url = payload.pop("url", "")
        schema = payload.pop("extraction_schema", "")
        # extract_web_data は JSON 文字列を返すので、HTTP では dict 化して返す
        return jsonify(json.loads(extract_web_data(url, schema, **payload)))

    @app.get("/health")
    def _health():
        return jsonify({"status": "ok"})

    return app


# Dify の Custom Tool 登録用 OpenAPI YAML 例（README からの抜粋）::
#
#   openapi: 3.0.0
#   info:
#     title: web_scraper_tool bridge
#     version: "1.0.0"
#   paths:
#     /extract:
#       post:
#         summary: Extract structured JSON from a web page
#         requestBody:
#           required: true
#           content:
#             application/json:
#               schema:
#                 type: object
#                 properties:
#                   url: {type: string}
#                   extraction_schema: {type: string}
#                   prefer_dynamic: {type: boolean}
#                   respect_robots: {type: boolean}
#                   timeout_s: {type: integer}
#                 required: [url, extraction_schema]
#         responses:
#           "200":
#             description: structured result (success/data/error/metadata)


__all__ = [
    "make_langchain_tool",
    "make_llamaindex_tool",
    "WEB_SCRAPER_TOOL_SPEC",
    "dispatch_tool_call",
    "build_dify_flask_app",
]
