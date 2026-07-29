# Routing design

[한국어](DESIGN.md)

## Goal

Expose one OpenAI-compatible `hermes-auto` endpoint to Hermes Agent while
selecting role-specific Ollama models by request characteristics.

Priorities are loopback-only inference, capability-safe tool and vision
routing, graceful behavior when optional models are absent, bounded retry, and
metadata-only logging.

## API

| Endpoint | Behavior |
|---|---|
| `GET /health` | Router identity, mode, and per-role installed state |
| `GET /v1/models` | `hermes-auto` plus configured role aliases |
| `POST /v1/chat/completions` | OpenAI-compatible chat-completions proxy |
| `POST /v1/embeddings` | Explicit HTTP 501; not currently supported |

Other paths return HTTP 404.

## Selection order

The first matching rule wins.

| Condition | Initial profile | Reason |
|---|---|---|
| Explicit role alias | requested profile | `explicit-model` |
| Manual GUI/config mode | selected profile | `settings-override` |
| Image content | `quality` | `vision` |
| Code signal | `coding` | `code` |
| Short tool action | `fast` | `short-tool-task` |
| Korean writing signal | `korean_writing` | `korean-writing` |
| Short structured Korean | `korean_fast` | `korean-short-structured` |
| Other Korean/general text | `fast` | `korean-general-fast` / `general-fast` |

Required tool calls never select a profile without `tools`. Image requests do
not silently fall back to an installed text-only model.

## Missing models and retry

The public default fallback order is:

```text
fast → coding → korean_writing → korean_fast → quality
```

Only installed candidates are added. Tool requests retain only tool-capable
profiles, and image requests retain only vision-capable profiles. The router
tries at most three models by default.

Fallback is limited to HTTP 408, 429, 5xx, connection failures, and timeouts.
Invalid 4xx requests are returned immediately. Once streaming bytes reach the
client, the router never switches models.

The default per-attempt timeout is 600 seconds and the whole-request budget is
900 seconds. Later attempts cannot outlive the remaining total budget.

## Text-only profiles

`korean_writing`, `korean_fast`, and experimental `korean` are text-only in the
public config. Optional `tools`, `tool_choice`, and `parallel_tool_calls` fields
are removed for Ollama compatibility. A `tool_choice=required` request is
reselected onto a tool-capable model.

## Config reload and validation

The router reloads `router-config.json` when its modification time changes. If
a GUI write is briefly incomplete, the last validated config remains active.

Config loading rejects non-loopback hosts, non-HTTP or credential-bearing
Ollama URLs, query/fragment URL data, invalid modes, unknown profiles, and
invalid timeouts.

## Privacy-aware logging

Rotating logs contain profile and alias, reason code, attempt and HTTP status,
stream flag, elapsed time, and exception **type**. They never contain prompts,
responses, tool arguments, or Authorization headers.

## Model-free tests

`tests/test_router.py` starts a fake Ollama HTTP server on a temporary loopback
port. It validates config safety, last-known-good behavior, model and health
contracts, capability filtering, text-only payload cleanup, retry policy,
timeout budgets, and real HTTP proxy fallback without credentials, external
network access, or model downloads.

Use `Test-Hermes-Local.ps1 -Generation` for real model generation and
`Test-Hermes-E2E.ps1` for Hermes integration.
