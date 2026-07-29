# Changelog

All notable changes to this project are documented here.

## [0.1.0] - 2026-07-30

### Added

- Loopback-only OpenAI-compatible router for Hermes Agent and Ollama
- Automatic routing for general, coding, Korean, tool, and vision requests
- Capability-aware model fallback with bounded timeouts
- `Core`, `Developer`, `Korean`, and opt-in `Full` installation presets
- PowerShell setup, lifecycle, GUI, health, generation, and E2E checks
- Korean-first and English documentation
- Model-free unit tests and public-release privacy checks
- Explicit third-party model and Kanana licensing notices

### Security

- No model weights, personal config, logs, conversations, or credentials
- Prompt/response-free rotating router logs
- Public manifest, relative-link, secret-pattern, and private-path checks
