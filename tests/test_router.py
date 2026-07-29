from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from urllib import error, request


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

import router  # noqa: E402


class FakeOllamaHandler(router.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt: str, *args: object) -> None:
        return

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/api/tags":
            self._send_json(200, {"models": []})
            return
        self._send_json(404, {"error": "unsupported fake endpoint"})

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        self.server.requests_log.append(  # type: ignore[attr-defined]
            {"path": self.path, "payload": payload}
        )
        queue = self.server.response_queue  # type: ignore[attr-defined]
        if queue:
            status, response_payload = queue.pop(0)
            self._send_json(status, response_payload)
            return
        self._send_json(404, {"error": "unsupported fake endpoint"})


class RouterContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self._original_config_path = router._config_path
        self._temp_dir = tempfile.TemporaryDirectory()
        self.config_path = Path(self._temp_dir.name) / "router-config.json"
        self.ollama_server = router.ThreadingHTTPServer(
            ("127.0.0.1", 0), FakeOllamaHandler
        )
        self.ollama_server.requests_log = []  # type: ignore[attr-defined]
        self.ollama_server.response_queue = []  # type: ignore[attr-defined]
        self.ollama_thread = threading.Thread(
            target=self.ollama_server.serve_forever, daemon=True
        )
        self.ollama_thread.start()
        self.config = {
            "listen_host": "127.0.0.1",
            "listen_port": 0,
            "ollama_base_url": (
                f"http://127.0.0.1:{self.ollama_server.server_port}"
            ),
            "mode": "auto",
            "models": {
                "quality": "hermes-quality",
                "coding": "hermes-coder",
                "fast": "hermes-fast",
                "korean": "hermes-korean-agent",
                "korean_writing": "hermes-korean-writing",
                "korean_fast": "hermes-korean-fast",
            },
            "capabilities": {
                "quality": ["text", "vision", "tools"],
                "coding": ["text", "tools"],
                "fast": ["text", "tools"],
                "korean": ["text"],
                "korean_writing": ["text"],
                "korean_fast": ["text"],
            },
            "fallback_order": ["fast", "coding", "quality"],
        }
        self._write_config(self.config)
        router._config_path = self.config_path
        router._config_cache = None
        router._models_cache = (0.0, set())
        self.server = router.ThreadingHTTPServer(
            ("127.0.0.1", 0), router.RouterHandler
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.ollama_server.shutdown()
        self.ollama_server.server_close()
        self.ollama_thread.join(timeout=2)
        router._config_path = self._original_config_path
        router._config_cache = None
        router._models_cache = (0.0, set())
        self._temp_dir.cleanup()

    def _write_config(self, config: dict[str, object]) -> None:
        self.config_path.write_text(
            json.dumps(config, ensure_ascii=False), encoding="utf-8"
        )

    def _request_json(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: dict[str, object] | None = None,
    ) -> tuple[int, dict[str, object]]:
        body = None
        headers: dict[str, str] = {}
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = request.Request(
            self.base_url + path,
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with request.urlopen(req, timeout=5) as response:
                return response.status, json.loads(response.read().decode("utf-8"))
        except error.HTTPError as exc:
            return exc.code, json.loads(exc.read().decode("utf-8"))

    def test_load_config_rejects_non_loopback_ollama_base_url(self) -> None:
        self.config["ollama_base_url"] = "https://example.com"
        self._write_config(self.config)

        with self.assertRaisesRegex(ValueError, "Ollama.*loopback"):
            router.load_config()

    def test_load_config_keeps_last_good_config_during_partial_write(self) -> None:
        first = router.load_config()
        self.config_path.write_text('{"mode":', encoding="utf-8")

        try:
            second = router.load_config()
        except Exception as exc:  # pragma: no cover - assertion explains the contract
            self.fail(f"Partial config write escaped request handling: {exc}")

        self.assertEqual(first["models"], second["models"])
        self.assertEqual(first["mode"], second["mode"])

    def test_model_catalog_advertises_configured_model_names(self) -> None:
        status, payload = self._request_json("/v1/models")

        self.assertEqual(200, status)
        ids = {item["id"] for item in payload["data"]}
        self.assertTrue(set(self.config["models"].values()).issubset(ids))

    def test_embeddings_endpoint_is_explicitly_unsupported(self) -> None:
        status, payload = self._request_json(
            "/v1/embeddings",
            method="POST",
            payload={"model": "hermes-auto", "input": "hello"},
        )

        self.assertEqual(501, status)
        self.assertIn("not supported", payload["error"]["message"].lower())

    def test_health_identifies_router_instance(self) -> None:
        status, payload = self._request_json("/health")

        self.assertEqual(200, status)
        self.assertIn("router", payload)
        self.assertEqual(os.getpid(), payload["router"]["pid"])
        self.assertTrue(payload["router"]["instance_id"])

    def test_required_tools_do_not_route_to_non_tool_profile(self) -> None:
        payload = {
            "model": "hermes-auto",
            "messages": [
                {
                    "role": "user",
                    "content": "이 한국어 소개문을 자연스럽게 작성해 주세요.",
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "save_text",
                        "description": "Save text",
                        "parameters": {"type": "object", "properties": {}},
                    },
                }
            ],
            "tool_choice": "required",
        }

        profile, reason = router.choose_profile(payload, self.config)

        self.assertEqual("fast", profile)
        self.assertIn("required-tools", reason)

    def test_light_profile_fallback_prefers_fast_before_quality(self) -> None:
        router._models_cache = (
            time.monotonic(),
            set(self.config["models"].values()),
        )

        attempts = router.route_attempts(
            "korean_fast", "hermes-korean-fast", self.config
        )

        self.assertEqual("fast", attempts[1][0])

    def test_korean_fast_strips_optional_tools_for_ollama_compatibility(self) -> None:
        payload = {
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "noop",
                        "description": "No operation",
                        "parameters": {"type": "object", "properties": {}},
                    },
                }
            ],
            "tool_choice": "auto",
        }

        router.strip_unsupported_tools(payload, "korean_fast", self.config)

        self.assertNotIn("tools", payload)
        self.assertNotIn("tool_choice", payload)

    def test_korean_action_with_optional_tools_routes_to_tool_model(self) -> None:
        payload = {
            "model": "hermes-auto",
            "messages": [
                {
                    "role": "user",
                    "content": (
                        "terminal 도구로 echo HERMES_TOOL_OK를 실행하고 "
                        "그 결과만 정확히 답하세요."
                    ),
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "terminal",
                        "description": "Run a terminal command",
                        "parameters": {"type": "object", "properties": {}},
                    },
                }
            ],
            "tool_choice": "auto",
        }

        profile, reason = router.choose_profile(payload, self.config)

        self.assertEqual("fast", profile)
        self.assertEqual("short-tool-task", reason)

    def test_general_auto_request_uses_memory_safe_fast_profile(self) -> None:
        payload = {
            "model": "hermes-auto",
            "messages": [
                {
                    "role": "user",
                    "content": "Tell me a short story about a careful engineer.",
                }
            ],
        }

        profile, reason = router.choose_profile(payload, self.config)

        self.assertEqual("fast", profile)
        self.assertEqual("general-fast", reason)

    def test_deep_korean_request_uses_safe_general_profile(self) -> None:
        payload = {
            "model": "hermes-auto",
            "messages": [
                {
                    "role": "user",
                    "content": "한국 시장을 깊이 분석하고 실행 전략을 설명하세요.",
                }
            ],
        }

        profile, reason = router.choose_profile(payload, self.config)

        self.assertEqual("fast", profile)
        self.assertEqual("korean-general-fast", reason)

    def test_tool_capable_fallbacks_exclude_text_only_profiles(self) -> None:
        router._models_cache = (
            time.monotonic(),
            set(self.config["models"].values()),
        )

        attempts = router.route_attempts(
            "fast",
            "hermes-fast",
            self.config,
            required_capability="tools",
        )

        profiles = [profile for profile, _ in attempts]
        self.assertNotIn("korean_writing", profiles)
        self.assertNotIn("korean_fast", profiles)

    def test_missing_vision_model_does_not_fallback_to_text_only_model(self) -> None:
        router._models_cache = (
            time.monotonic(),
            {self.config["models"]["fast"]},
        )
        payload = {
            "model": "hermes-auto",
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Describe this image."},
                        {
                            "type": "image_url",
                            "image_url": {"url": "data:image/png;base64,AA=="},
                        },
                    ],
                }
            ],
        }

        profile, model, reason = router.resolve_model(payload, self.config)
        attempts = router.route_attempts(
            profile,
            model,
            self.config,
            required_capability="vision",
        )

        self.assertEqual("quality", profile)
        self.assertEqual("hermes-quality", model)
        self.assertIn("not-yet-installed", reason)
        self.assertEqual([("quality", "hermes-quality")], attempts)

    def test_missing_tool_model_resolution_skips_text_only_profiles(self) -> None:
        self.config["fallback_order"] = ["korean_writing", "quality"]
        router._models_cache = (
            time.monotonic(),
            {
                self.config["models"]["korean_writing"],
                self.config["models"]["quality"],
            },
        )
        payload = {
            "model": "hermes-auto",
            "messages": [
                {
                    "role": "user",
                    "content": "Run a terminal command and return its output.",
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "terminal",
                        "description": "Run a terminal command",
                        "parameters": {"type": "object", "properties": {}},
                    },
                }
            ],
            "tool_choice": "required",
        }

        profile, model, reason = router.resolve_model(payload, self.config)

        self.assertEqual("quality", profile)
        self.assertEqual("hermes-quality", model)
        self.assertIn("missing-fast", reason)

    def test_bad_request_does_not_trigger_model_fallback(self) -> None:
        self.assertFalse(router.is_retryable_upstream_status(400))
        self.assertFalse(router.is_retryable_upstream_status(401))
        self.assertFalse(router.is_retryable_upstream_status(422))

    def test_transient_upstream_errors_can_trigger_model_fallback(self) -> None:
        self.assertTrue(router.is_retryable_upstream_status(408))
        self.assertTrue(router.is_retryable_upstream_status(429))
        self.assertTrue(router.is_retryable_upstream_status(500))
        self.assertTrue(router.is_retryable_upstream_status(503))

    def test_attempt_timeout_respects_overall_request_budget(self) -> None:
        config = {
            "upstream_timeout_seconds": 600,
            "request_timeout_seconds": 900,
        }

        timeout = router.remaining_attempt_timeout(
            time.monotonic() - 850,
            config,
        )
        expired = router.remaining_attempt_timeout(
            time.monotonic() - 901,
            config,
        )

        self.assertIsNotNone(timeout)
        self.assertGreaterEqual(timeout, 1)
        self.assertLessEqual(timeout, 51)
        self.assertIsNone(expired)

    def test_proxy_does_not_fallback_after_bad_request(self) -> None:
        router._models_cache = (
            time.monotonic(),
            set(self.config["models"].values()),
        )
        self.ollama_server.response_queue.extend(  # type: ignore[attr-defined]
            [
                (400, {"error": {"message": "invalid request"}}),
                (
                    200,
                    {
                        "choices": [
                            {"message": {"role": "assistant", "content": "wrong"}}
                        ]
                    },
                ),
            ]
        )

        status, _ = self._request_json(
            "/v1/chat/completions",
            method="POST",
            payload={
                "model": "hermes-auto",
                "messages": [{"role": "user", "content": "Hello"}],
                "stream": False,
            },
        )

        self.assertEqual(400, status)
        requests_log = self.ollama_server.requests_log  # type: ignore[attr-defined]
        self.assertEqual(1, len(requests_log))
        self.assertEqual("hermes-fast", requests_log[0]["payload"]["model"])

    def test_proxy_falls_back_once_after_transient_error(self) -> None:
        router._models_cache = (
            time.monotonic(),
            set(self.config["models"].values()),
        )
        self.ollama_server.response_queue.extend(  # type: ignore[attr-defined]
            [
                (503, {"error": {"message": "temporarily unavailable"}}),
                (
                    200,
                    {
                        "choices": [
                            {
                                "message": {
                                    "role": "assistant",
                                    "content": "FALLBACK_OK",
                                }
                            }
                        ]
                    },
                ),
            ]
        )

        status, payload = self._request_json(
            "/v1/chat/completions",
            method="POST",
            payload={
                "model": "hermes-auto",
                "messages": [{"role": "user", "content": "Hello"}],
                "stream": False,
            },
        )

        self.assertEqual(200, status)
        self.assertEqual("FALLBACK_OK", payload["choices"][0]["message"]["content"])
        requests_log = self.ollama_server.requests_log  # type: ignore[attr-defined]
        self.assertEqual(
            ["hermes-fast", "hermes-coder"],
            [entry["payload"]["model"] for entry in requests_log],
        )

    def test_proxy_strips_optional_tools_for_text_only_profile(self) -> None:
        router._models_cache = (
            time.monotonic(),
            set(self.config["models"].values()),
        )
        self.ollama_server.response_queue.append(  # type: ignore[attr-defined]
            (
                200,
                {
                    "choices": [
                        {"message": {"role": "assistant", "content": "TEXT_ONLY_OK"}}
                    ]
                },
            )
        )

        status, payload = self._request_json(
            "/v1/chat/completions",
            method="POST",
            payload={
                "model": "hermes-korean-fast",
                "messages": [{"role": "user", "content": "Return one line"}],
                "tools": [
                    {
                        "type": "function",
                        "function": {
                            "name": "noop",
                            "description": "No operation",
                            "parameters": {"type": "object", "properties": {}},
                        },
                    }
                ],
                "tool_choice": "auto",
                "stream": False,
            },
        )

        self.assertEqual(200, status)
        self.assertEqual("TEXT_ONLY_OK", payload["choices"][0]["message"]["content"])
        outgoing = self.ollama_server.requests_log[0]["payload"]  # type: ignore[attr-defined]
        self.assertNotIn("tools", outgoing)
        self.assertNotIn("tool_choice", outgoing)


if __name__ == "__main__":
    unittest.main()
