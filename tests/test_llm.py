"""LLM client behaviour for the local Qwen/vLLM endpoint."""

import json

import httpx
import pytest

import config as _cfg
import llm


def _completion(content: str = '{"ok": true}') -> dict:
    return {
        "choices": [
            {
                "message": {"content": content},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 5,
            "total_tokens": 15,
        },
    }


def test_normalize_base_url_accepts_both_forms():
    assert llm.normalize_base_url("http://host:18020") == "http://host:18020/v1"
    assert llm.normalize_base_url("http://host:18020/") == "http://host:18020/v1"
    assert llm.normalize_base_url("http://host:18020/v1") == "http://host:18020/v1"
    assert llm.normalize_base_url("http://host:18020/v1/") == "http://host:18020/v1"


def test_canonical_llm_env_wins_over_legacy_saved_value(monkeypatch):
    monkeypatch.setattr(_cfg, "_saved", {"llamacpp_base_url": "http://old:8080"})
    monkeypatch.setenv("LLM_BASE_URL", "http://new:18020/v1")
    value = _cfg._first_setting(
        (
            ("llm_base_url", "LLM_BASE_URL"),
            ("llamacpp_base_url", "LLAMACPP_BASE_URL"),
        ),
        "http://default",
    )
    assert value == "http://new:18020/v1"


def test_strip_thinking_removes_blocks_and_tags():
    text = "<think>hidden reasoning</think>\n{\"a\": 1}\n<think>more</think>"
    assert llm.strip_thinking(text) == '{"a": 1}'


def test_extract_json_tolerates_think_prose_and_fences():
    raw = (
        "<think>je réfléchis</think>\n"
        "Voici le résultat :\n```json\n{\"type\": \"facture\", \"tags\": [\"a\",]}\n```"
    )
    parsed = llm._extract_json(raw, "{")
    assert parsed == {"type": "facture", "tags": ["a"]}


def test_model_listing_and_match():
    data = {"data": [{"id": "qwen3.8-27b"}, {"id": "other"}]}
    models = llm._models_from_response(data)
    assert models == ["qwen3.8-27b", "other"]
    assert llm._model_is_listed("qwen3.8-27b", models)
    assert llm._model_is_listed("qwen3.8-27b", ["qwen3.8-27b:latest"])
    assert not llm._model_is_listed("missing", models)


def test_init_llm_client_adds_bearer_and_v1(monkeypatch):
    monkeypatch.setattr(_cfg, "AI_PROVIDER", "llamacpp")
    monkeypatch.setattr(_cfg, "LLM_BASE_URL", "http://host:18020")
    monkeypatch.setattr(_cfg, "LLM_MODEL", "qwen3.8-27b")
    monkeypatch.setattr(_cfg, "LLM_API_KEY", "secret-key")

    client = llm.init_llm_client()
    try:
        assert str(client.base_url).rstrip("/") == "http://host:18020/v1"
        assert client.headers["Authorization"] == "Bearer secret-key"
    finally:
        client.close()


def test_init_llm_client_requires_api_key(monkeypatch):
    monkeypatch.setattr(_cfg, "AI_PROVIDER", "llamacpp")
    monkeypatch.setattr(_cfg, "LLM_API_KEY", "")
    with pytest.raises(ValueError, match="LLM_API_KEY"):
        llm.init_llm_client()


def test_call_llm_never_sends_images_in_text_only_mode(monkeypatch):
    monkeypatch.setattr(_cfg, "LLM_TEXT_ONLY", True)
    monkeypatch.setattr(_cfg, "LLM_DISABLE_THINKING", True)
    monkeypatch.setattr(_cfg, "AI_PROVIDER", "llamacpp")
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["payload"] = json.loads(request.content)
        return httpx.Response(200, json=_completion())

    with httpx.Client(
        base_url="http://host/v1", transport=httpx.MockTransport(handler)
    ) as client:
        content = llm._call_llm(
            client, "system", "hello", images=["base64-image"], max_tokens=128
        )

    assert content == '{"ok": true}'
    payload = captured["payload"]
    assert payload["messages"][1]["content"] == "hello"
    assert "image_url" not in json.dumps(payload)
    assert payload["chat_template_kwargs"] == {"enable_thinking": False}
    assert payload["max_tokens"] == 128


def test_call_llm_preserves_images_for_vision_provider(monkeypatch):
    monkeypatch.setattr(_cfg, "LLM_TEXT_ONLY", False)
    monkeypatch.setattr(_cfg, "AI_PROVIDER", "openrouter")
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["payload"] = json.loads(request.content)
        return httpx.Response(200, json=_completion("ok"))

    with httpx.Client(
        base_url="http://host/v1", transport=httpx.MockTransport(handler)
    ) as client:
        llm._call_llm(client, "system", "hello", images=["base64-image"])

    payload = captured["payload"]
    assert isinstance(payload["messages"][1]["content"], list)
    assert payload["messages"][1]["content"][1]["type"] == "image_url"


def test_call_llm_raises_clear_auth_error(monkeypatch):
    monkeypatch.setattr(_cfg, "LLM_TEXT_ONLY", True)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, text="invalid token")

    with httpx.Client(
        base_url="http://host/v1", transport=httpx.MockTransport(handler)
    ) as client:
        with pytest.raises(llm.LLMAuthError, match="LLM_API_KEY"):
            llm._call_llm(client, "system", "hello")


def test_call_llm_retries_without_json_mode_on_400(monkeypatch):
    monkeypatch.setattr(_cfg, "LLM_TEXT_ONLY", True)
    monkeypatch.setattr(_cfg, "LLM_JSON_MODE", True)
    calls: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        payload = json.loads(request.content)
        calls.append(payload)
        if "response_format" in payload:
            return httpx.Response(400, text="response_format is not supported")
        return httpx.Response(200, json=_completion())

    with httpx.Client(
        base_url="http://host/v1", transport=httpx.MockTransport(handler)
    ) as client:
        content = llm._call_llm(client, "system", "hello", json_mode=True)

    assert content == '{"ok": true}'
    assert len(calls) == 2
    assert "response_format" in calls[0]
    assert "response_format" not in calls[1]
