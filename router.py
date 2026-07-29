from __future__ import annotations

import argparse
import copy
import ipaddress
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib import error, request
from urllib.parse import urlsplit


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG = BASE_DIR / "router-config.json"
LOGGER = logging.getLogger("hermes_local_router")
_config_path = DEFAULT_CONFIG
_models_cache: tuple[float, set[str]] = (0.0, set())
_models_lock = threading.Lock()
_config_cache: tuple[Path, dict[str, Any]] | None = None
_config_lock = threading.Lock()
PROCESS_ID = os.getpid()
INSTANCE_ID = uuid.uuid4().hex
STARTED_AT = int(time.time())


def is_loopback_host(host: str) -> bool:
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return host.lower() == "localhost"


def validate_loopback_url(value: str, label: str) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme.lower() != "http"
        or not parsed.hostname
        or not is_loopback_host(parsed.hostname)
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError(f"{label} must use an HTTP loopback URL.")
    return value.rstrip("/")


def load_config() -> dict[str, Any]:
    global _config_cache
    active_path = _config_path.resolve()
    try:
        with active_path.open("r", encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError):
        with _config_lock:
            cached = _config_cache
            if cached and cached[0] == active_path:
                LOGGER.warning("config_read_failed_using_last_good path=%s", active_path)
                return copy.deepcopy(cached[1])
        raise
    host = str(config.get("listen_host", "127.0.0.1"))
    if not is_loopback_host(host):
        raise ValueError("The router must be bound to a loopback address.")
    config["ollama_base_url"] = validate_loopback_url(
        str(config.get("ollama_base_url", "")), "Ollama endpoint"
    )
    with _config_lock:
        _config_cache = (active_path, copy.deepcopy(config))
    return config


def normalize_model_name(name: str) -> str:
    return name[:-7] if name.endswith(":latest") else name


def fetch_installed_models(config: dict[str, Any], max_age: float = 10.0) -> set[str]:
    global _models_cache
    now = time.monotonic()
    with _models_lock:
        cached_at, cached = _models_cache
        if cached and now - cached_at < max_age:
            return set(cached)
        url = str(config["ollama_base_url"]).rstrip("/") + "/api/tags"
        try:
            with request.urlopen(url, timeout=3) as response:
                payload = json.loads(response.read().decode("utf-8"))
            models = {
                normalize_model_name(str(item.get("name", "")))
                for item in payload.get("models", [])
                if item.get("name")
            }
        except Exception:
            models = set()
        _models_cache = (now, models)
        return set(models)


def content_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict) and item.get("type") in {"text", "input_text"}:
                parts.append(str(item.get("text", "")))
        return "\n".join(parts)
    return ""


def last_user_text(messages: list[dict[str, Any]]) -> str:
    for message in reversed(messages):
        if message.get("role") == "user":
            return content_text(message.get("content"))
    return ""


def has_image(messages: list[dict[str, Any]]) -> bool:
    for message in messages:
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for item in content:
            if isinstance(item, dict) and item.get("type") in {
                "image",
                "image_url",
                "input_image",
            }:
                return True
    return False


def hangul_ratio(text: str) -> float:
    meaningful = re.findall(r"[A-Za-z가-힣]", text)
    if not meaningful:
        return 0.0
    hangul = re.findall(r"[가-힣]", text)
    return len(hangul) / len(meaningful)


CODE_RE = re.compile(
    r"(```|Traceback|Exception|stack trace|"
    r"\b(?:code|coding|debug|refactor|repository|function|class|typescript|javascript|"
    r"python|powershell|sql|api|regex|docker|kubernetes|git|test|compile)\b|"
    r"코드|코딩|디버그|리팩터|버그|함수|클래스|저장소|레포|테스트|컴파일|스크립트)",
    re.IGNORECASE,
)
KOREAN_WRITING_RE = re.compile(
    r"번역|교정|윤문|다듬|문체|한국어|한글|소개문|보도자료|보고서|편지|"
    r"이메일|문장|글을|글쓰기|작성|요약|설명|한국 문화|한국 사회|국내 맥락",
    re.IGNORECASE,
)
ACTION_RE = re.compile(
    r"실행|설치|삭제|수정해|변경해|열어|검색해|찾아봐|다운로드|업로드|배포|"
    r"파일|폴더|터미널|브라우저|도구|명령|execute|install|delete|edit|"
    r"deploy|download|upload|open the|search the|run ",
    re.IGNORECASE,
)
FAST_RE = re.compile(
    r"\bjson\b|분류|추출|목록|한\s*줄|형식만|정확히|체크리스트|"
    r"classify|extract|return exactly|one line|list only|schema",
    re.IGNORECASE,
)
DEEP_RE = re.compile(
    r"깊이|상세|종합|비교|분석|추론|전략|설계|연구|검증|"
    r"deep|detailed|comprehensive|analy[sz]e|reason|strategy|architect|research",
    re.IGNORECASE,
)


def profile_for_requested_model(
    requested_model: str, config: dict[str, Any]
) -> str | None:
    if requested_model in {"", "hermes-auto", "auto"}:
        return None
    models = config.get("models", {})
    for profile, model in models.items():
        aliases = {
            profile,
            f"hermes-{profile}",
            f"hermes-{profile.replace('_', '-')}",
            str(model),
            normalize_model_name(str(model)),
        }
        if requested_model in aliases:
            return profile
    return None


def profile_supports(
    profile: str, capability: str, config: dict[str, Any]
) -> bool:
    capabilities = config.get("capabilities", {})
    declared = capabilities.get(profile, [])
    return capability in declared


def required_tools_requested(payload: dict[str, Any]) -> bool:
    if not payload.get("tools"):
        return False
    tool_choice = payload.get("tool_choice")
    return tool_choice == "required" or isinstance(tool_choice, dict)


def enforce_required_tool_profile(
    payload: dict[str, Any],
    profile: str,
    reason: str,
    text: str,
    config: dict[str, Any],
) -> tuple[str, str]:
    if not required_tools_requested(payload) or profile_supports(
        profile, "tools", config
    ):
        return profile, reason

    candidates: list[str] = list(config.get("fallback_order", []))
    candidates.extend(["quality", "fast", "coding"])
    for candidate in dict.fromkeys(candidates):
        if profile_supports(str(candidate), "tools", config):
            return str(candidate), f"{reason}:required-tools"
    return profile, f"{reason}:required-tools-unavailable"


def choose_profile(payload: dict[str, Any], config: dict[str, Any]) -> tuple[str, str]:
    messages = payload.get("messages") or []
    if not isinstance(messages, list):
        messages = []
    text = last_user_text(messages)

    def finalize(profile: str, reason: str) -> tuple[str, str]:
        return enforce_required_tool_profile(
            payload, profile, reason, text, config
        )

    requested = str(payload.get("model") or "hermes-auto")
    explicit = profile_for_requested_model(requested, config)
    if explicit:
        return finalize(explicit, "explicit-model")

    mode = str(config.get("mode", "auto")).lower()
    if mode in config.get("models", {}) and mode != "auto":
        return finalize(mode, "settings-override")

    route_cfg = config.get("routing", {})
    simple_limit = int(route_cfg.get("simple_max_chars", 600))

    if has_image(messages):
        return finalize("quality", "vision")
    if CODE_RE.search(text):
        return finalize("coding", "code")
    if payload.get("tools") and ACTION_RE.search(text) and len(text) <= simple_limit:
        return finalize("fast", "short-tool-task")

    korean_ratio = hangul_ratio(text)
    korean_limit = int(route_cfg.get("korean_max_chars", 24000))
    korean_threshold = float(route_cfg.get("korean_min_ratio", 0.22))
    if korean_ratio >= korean_threshold and len(text) <= korean_limit:
        if KOREAN_WRITING_RE.search(text) and not ACTION_RE.search(text):
            return finalize("korean_writing", "korean-writing")
        if len(text) <= simple_limit and FAST_RE.search(text):
            return finalize("korean_fast", "korean-short-structured")
        return finalize("fast", "korean-general-fast")

    if len(text) <= simple_limit and FAST_RE.search(text) and not DEEP_RE.search(text):
        return finalize("fast", "short-structured")

    if ACTION_RE.search(text) and len(text) <= simple_limit:
        return finalize("fast", "short-tool-task")
    return finalize("fast", "general-fast")


def resolve_model(
    payload: dict[str, Any], config: dict[str, Any]
) -> tuple[str, str, str]:
    profile, reason = choose_profile(payload, config)
    configured = config.get("models", {})
    target = str(configured.get(profile, configured.get("quality", "hermes-quality")))
    installed = fetch_installed_models(config)
    if normalize_model_name(target) in installed:
        return profile, target, reason

    fallback_capability = None
    messages = payload.get("messages") or []
    if isinstance(messages, list) and has_image(messages):
        fallback_capability = "vision"
    elif payload.get("tools") and profile_supports(profile, "tools", config):
        fallback_capability = "tools"
    for fallback_profile in config.get("fallback_order", []):
        if fallback_capability and not profile_supports(
            str(fallback_profile), fallback_capability, config
        ):
            continue
        fallback_model = str(configured.get(fallback_profile, ""))
        if fallback_model and normalize_model_name(fallback_model) in installed:
            return fallback_profile, fallback_model, f"{reason}:missing-{profile}"
    return profile, target, f"{reason}:not-yet-installed"


def route_attempts(
    profile: str,
    target: str,
    config: dict[str, Any],
    required_capability: str | None = None,
) -> list[tuple[str, str]]:
    attempts = [(profile, target)]
    models = config.get("models", {})
    installed = fetch_installed_models(config)
    for fallback_profile in config.get("fallback_order", []):
        if required_capability and not profile_supports(
            str(fallback_profile), required_capability, config
        ):
            continue
        fallback_model = str(models.get(fallback_profile, ""))
        candidate = (str(fallback_profile), fallback_model)
        if (
            fallback_model
            and normalize_model_name(fallback_model) in installed
            and candidate not in attempts
        ):
            attempts.append(candidate)
    return attempts


def strip_unsupported_tools(
    payload: dict[str, Any], profile: str, config: dict[str, Any]
) -> None:
    if profile_supports(profile, "tools", config):
        return
    if required_tools_requested(payload):
        return
    payload.pop("tools", None)
    payload.pop("tool_choice", None)
    payload.pop("parallel_tool_calls", None)


def is_retryable_upstream_status(status: int) -> bool:
    return status in {408, 425, 429} or 500 <= status <= 599


def remaining_attempt_timeout(
    started: float, config: dict[str, Any]
) -> float | None:
    upstream_timeout = max(
        30.0,
        min(float(config.get("upstream_timeout_seconds", 600)), 1800.0),
    )
    request_budget = max(
        30.0,
        min(float(config.get("request_timeout_seconds", 900)), 3600.0),
    )
    remaining = request_budget - (time.monotonic() - started)
    if remaining <= 0:
        return None
    return max(1.0, min(upstream_timeout, remaining))


def setup_logging() -> None:
    log_dir = BASE_DIR / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(
        log_dir / "router.log",
        maxBytes=2_000_000,
        backupCount=3,
        encoding="utf-8",
    )
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    LOGGER.setLevel(logging.INFO)
    LOGGER.handlers.clear()
    LOGGER.addHandler(handler)


class RouterHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "HermesLocalRouter/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        LOGGER.debug(fmt, *args)

    def send_json(
        self, status: int, payload: Any, extra_headers: dict[str, str] | None = None
    ) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise ValueError("Invalid Content-Length") from exc
        if length <= 0 or length > 16 * 1024 * 1024:
            raise ValueError("Invalid request size")
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_GET(self) -> None:
        config = load_config()
        if self.path.rstrip("/") in {"", "/health", "/route/status"}:
            installed = fetch_installed_models(config, max_age=0)
            model_status = {
                profile: normalize_model_name(str(model)) in installed
                for profile, model in config.get("models", {}).items()
            }
            self.send_json(
                200,
                {
                    "status": "ok",
                    "mode": config.get("mode", "auto"),
                    "ollama": config.get("ollama_base_url"),
                    "models": model_status,
                    "router": {
                        "pid": PROCESS_ID,
                        "instance_id": INSTANCE_ID,
                        "started_at": STARTED_AT,
                        "version": self.server_version,
                    },
                },
            )
            return
        if self.path.rstrip("/") == "/v1/models":
            now = int(time.time())
            model_ids = ["hermes-auto"]
            for profile, configured_model in config.get("models", {}).items():
                model_ids.extend(
                    [
                        str(configured_model),
                        f"hermes-{profile.replace('_', '-')}",
                    ]
                )
            data = []
            for model_id in dict.fromkeys(model_ids):
                data.append(
                    {
                        "id": model_id,
                        "object": "model",
                        "created": now,
                        "owned_by": "local-router",
                    }
                )
            self.send_json(200, {"object": "list", "data": data})
            return
        self.send_json(404, {"error": {"message": "Not found"}})

    def do_POST(self) -> None:
        try:
            payload = self.read_json()
        except Exception as exc:
            self.send_json(400, {"error": {"message": str(exc)}})
            return

        if self.path.rstrip("/") == "/api/show":
            self.proxy_show(payload)
            return
        if self.path.rstrip("/") == "/v1/embeddings":
            self.send_json(
                501,
                {
                    "error": {
                        "message": (
                            "Embeddings are not supported by this text-generation "
                            "router."
                        )
                    }
                },
            )
            return
        if self.path.rstrip("/") not in {
            "/v1/chat/completions",
            "/v1/responses",
        }:
            self.send_json(404, {"error": {"message": "Not found"}})
            return
        self.proxy_openai(payload)

    def proxy_show(self, payload: dict[str, Any]) -> None:
        config = load_config()
        requested = str(payload.get("model") or payload.get("name") or "hermes-auto")
        probe = {"model": requested, "messages": []}
        profile, target, reason = resolve_model(probe, config)
        outgoing = dict(payload)
        outgoing["model"] = target
        outgoing["name"] = target
        url = str(config["ollama_base_url"]).rstrip("/") + "/api/show"
        try:
            req = request.Request(
                url,
                data=json.dumps(outgoing).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with request.urlopen(req, timeout=10) as upstream:
                result = json.loads(upstream.read().decode("utf-8"))
            result["hermes_route"] = {
                "profile": profile,
                "model": target,
                "reason": reason,
            }
            self.send_json(200, result)
        except Exception as exc:
            self.send_json(502, {"error": {"message": f"Ollama show failed: {exc}"}})

    def proxy_openai(self, payload: dict[str, Any]) -> None:
        config = load_config()
        profile, target, reason = resolve_model(payload, config)
        stream = bool(payload.get("stream", False))
        endpoint = self.path
        url = str(config["ollama_base_url"]).rstrip("/") + endpoint
        started = time.monotonic()
        headers = {
            "Content-Type": "application/json",
            "Accept": "text/event-stream" if stream else "application/json",
        }
        fallback_capability = None
        messages = payload.get("messages") or []
        if isinstance(messages, list) and has_image(messages):
            fallback_capability = "vision"
        elif payload.get("tools") and profile_supports(profile, "tools", config):
            fallback_capability = "tools"
        attempts = route_attempts(
            profile,
            target,
            config,
            required_capability=fallback_capability,
        )
        max_attempts = max(1, int(config.get("fallback_max_attempts", 3)))
        attempts = attempts[:max_attempts]
        last_http_error: tuple[int, bytes, str] | None = None
        last_exception: Exception | None = None
        budget_exhausted = False

        for attempt_index, (attempt_profile, attempt_target) in enumerate(attempts):
            attempt_timeout = remaining_attempt_timeout(started, config)
            if attempt_timeout is None:
                budget_exhausted = True
                LOGGER.warning(
                    "route=%s model=%s reason=%s request_budget_exhausted=true",
                    attempt_profile,
                    attempt_target,
                    reason,
                )
                break
            response_started = False
            upstream = None
            outgoing = copy.deepcopy(payload)
            outgoing["model"] = attempt_target
            strip_unsupported_tools(outgoing, attempt_profile, config)
            encoded = json.dumps(outgoing, ensure_ascii=False).encode("utf-8")
            req = request.Request(url, data=encoded, headers=headers, method="POST")
            try:
                upstream = request.urlopen(req, timeout=attempt_timeout)
                content_type = upstream.headers.get(
                    "Content-Type",
                    "text/event-stream" if stream else "application/json",
                )
                if stream:
                    self.send_response(upstream.status)
                    self.send_header("Content-Type", content_type)
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Connection", "close")
                    self.send_header("X-Hermes-Route", attempt_profile)
                    self.send_header("X-Hermes-Model", attempt_target)
                    self.end_headers()
                    response_started = True
                    while True:
                        chunk = upstream.readline()
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        self.wfile.flush()
                        if remaining_attempt_timeout(started, config) is None:
                            LOGGER.warning(
                                "route=%s model=%s reason=%s "
                                "stream_request_budget_exhausted=true",
                                attempt_profile,
                                attempt_target,
                                reason,
                            )
                            self.close_connection = True
                            upstream.close()
                            return
                else:
                    body = upstream.read()
                    self.send_response(upstream.status)
                    self.send_header("Content-Type", content_type)
                    self.send_header("Content-Length", str(len(body)))
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Connection", "close")
                    self.send_header("X-Hermes-Route", attempt_profile)
                    self.send_header("X-Hermes-Model", attempt_target)
                    self.end_headers()
                    response_started = True
                    self.wfile.write(body)
                upstream.close()
                LOGGER.info(
                    "route=%s model=%s reason=%s attempt=%s stream=%s elapsed=%.2fs",
                    attempt_profile,
                    attempt_target,
                    reason,
                    attempt_index + 1,
                    stream,
                    time.monotonic() - started,
                )
                return
            except error.HTTPError as exc:
                if upstream is not None:
                    upstream.close()
                body = exc.read()
                content_type = exc.headers.get("Content-Type", "application/json")
                last_http_error = (exc.code, body, content_type)
                LOGGER.warning(
                    "route=%s model=%s reason=%s attempt=%s upstream_status=%s",
                    attempt_profile,
                    attempt_target,
                    reason,
                    attempt_index + 1,
                    exc.code,
                )
                if not is_retryable_upstream_status(exc.code):
                    self.send_response(exc.code)
                    self.send_header("Content-Type", content_type)
                    self.send_header("Content-Length", str(len(body)))
                    self.send_header("X-Hermes-Route", attempt_profile)
                    self.end_headers()
                    self.wfile.write(body)
                    return
            except Exception as exc:
                if upstream is not None:
                    upstream.close()
                last_exception = exc
                LOGGER.warning(
                    "route=%s model=%s reason=%s attempt=%s proxy_error=%s",
                    attempt_profile,
                    attempt_target,
                    reason,
                    attempt_index + 1,
                    type(exc).__name__,
                )
                if response_started:
                    self.close_connection = True
                    return

        if budget_exhausted:
            self.send_json(
                504,
                {"error": {"message": "Local model request time budget exhausted."}},
                {"X-Hermes-Route": profile},
            )
            return

        if last_http_error:
            status, body, content_type = last_http_error
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Hermes-Route", profile)
            self.end_headers()
            self.wfile.write(body)
            return

        error_name = type(last_exception).__name__ if last_exception else "UnknownError"
        self.send_json(
            502,
            {"error": {"message": f"Local model endpoint failed: {error_name}"}},
            {"X-Hermes-Route": profile},
        )


def main() -> None:
    global _config_path
    parser = argparse.ArgumentParser(description="Loopback-only Hermes model router")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    _config_path = args.config.resolve()
    setup_logging()
    config = load_config()
    host = str(config.get("listen_host", "127.0.0.1"))
    port = int(config.get("listen_port", 11435))
    server = ThreadingHTTPServer((host, port), RouterHandler)
    LOGGER.info("router_started host=%s port=%s", host, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        LOGGER.info("router_stopped")


if __name__ == "__main__":
    main()
