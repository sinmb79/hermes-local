# Third-party notices

This repository contains integration code and Modelfiles, not model weights,
tokenizers, GGUF blobs, or code copied from the projects below. A user who runs
an installation command downloads models directly from the referenced
distribution service to that user's own computer.

The repository's MIT License applies only to this repository's original code
and documentation. It does **not** replace any upstream software, model,
quantization, usage-policy, trademark, or acceptable-use terms. Recheck the
terms at download time because tags and files can change.

## Runtime integrations

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) —
  MIT License. Hermes Agent is installed separately.
- [Ollama](https://github.com/ollama/ollama) — MIT License. Ollama is installed
  separately.

Their names are used only to describe compatibility. This project is not
affiliated with or endorsed by either project.

## Referenced models

### OpenAI gpt-oss 20B

- Local tag: `gpt-oss:20b`
- Official model: [openai/gpt-oss-20b](https://huggingface.co/openai/gpt-oss-20b)
- License: [Apache License 2.0](https://huggingface.co/openai/gpt-oss-20b/blob/main/LICENSE)
- Additional terms: [gpt-oss Usage Policy](https://huggingface.co/openai/gpt-oss-20b/blob/main/USAGE_POLICY)

### Qwen3-Coder 30B-A3B

- Local tag: `qwen3-coder:30b`
- Official model: [Qwen/Qwen3-Coder-30B-A3B-Instruct](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct)
- License: [Apache License 2.0](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct/blob/main/LICENSE)

### Qwen3.6 35B-A3B

- Local tag: `qwen3.6:35b`
- Official model: [Qwen/Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- License: [Apache License 2.0](https://huggingface.co/Qwen/Qwen3.6-35B-A3B/blob/main/LICENSE)

### KT Mi:dm 2.0 Base Instruct

- Referenced GGUF: [mykor/Midm-2.0-Base-Instruct-gguf](https://huggingface.co/mykor/Midm-2.0-Base-Instruct-gguf)
- Official base model: [K-intelligence/Midm-2.0-Base-Instruct](https://huggingface.co/K-intelligence/Midm-2.0-Base-Instruct)
- License: [MIT License](https://huggingface.co/K-intelligence/Midm-2.0-Base-Instruct/blob/main/LICENSE.txt)
- Copyright notice in the upstream license: Copyright (c) 2025 KT Corporation.

If you redistribute a downloaded model or substantial portion, retain the
upstream copyright and MIT permission notice.

### SK Telecom A.X 4.0 Light

- Referenced GGUF: [mykor/A.X-4.0-Light-gguf](https://huggingface.co/mykor/A.X-4.0-Light-gguf)
- Official base model: [skt/A.X-4.0-Light](https://huggingface.co/skt/A.X-4.0-Light)
- License and NOTICE: [Apache License 2.0 with attribution](https://huggingface.co/skt/A.X-4.0-Light/blob/main/LICENSE)

The upstream notice identifies Qwen 2.5 as a base and reserves SK Telecom
trademark rights. Do not imply sponsorship or trademark permission.

### Kakao Kanana 2 30B-A3B Instruct (experimental)

- Referenced GGUF: [deul/Kanana-2-30b-a3b-instruct-2601-GGUF](https://huggingface.co/deul/Kanana-2-30b-a3b-instruct-2601-GGUF)
- Official base model: [kakaocorp/kanana-2-30b-a3b-instruct-2601](https://huggingface.co/kakaocorp/kanana-2-30b-a3b-instruct-2601)
- License: [Kanana License Agreement](https://huggingface.co/kakaocorp/kanana-2-30b-a3b-instruct-2601/blob/main/LICENSE)

**Powered by Kanana.**

Kanana is licensed in accordance with the Kanana License Agreement.
Copyright © KAKAO Corp. All Rights Reserved.

Kanana is excluded from `Core`, `Developer`, and `Korean`. The `Full` preset
requires the explicit `-AcceptKananaLicense` switch. The license includes
responsible-use, notice, naming/display, redistribution, and conditional
commercial-license requirements. In particular, certain paid API/cloud access,
resale, systems integration/on-premise offerings, on-device distribution, and
large-scale services may require a separate license from Kakao. Read the full
current agreement before use or distribution.

## No legal advice

This notice is a practical inventory, not legal advice. Anyone distributing
models, derivatives, or a commercial product is responsible for reviewing the
complete current terms and obtaining professional advice where appropriate.
