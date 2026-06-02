# MoonCraft Runtime Service

This package builds the official MoonCraft Runtime Protocol v3 HTTP service.

It is compiled to a native binary and embedded in the official Runtime image.
The service exposes `/health`, `/init`, `/exec`, `/runs/:run_id`,
`/runs/:run_id/events`, `/preview/start`, and `/preview/...` on port `8080`.

## Official Runtime ABI

Runtime Protocol v3 treats `env` and `secrets` as opaque name/value data. The
names below are private ABI for the official Codex Runtime image only.

`env`:

- `MODEL`: Codex model name. Defaults to `gpt-5.4-mini`.
- `OPENAI_BASE_URL`: optional OpenAI-compatible endpoint. Only valid with
  `secrets.OPENAI_API_KEY`.

`secrets`:

- `CODEX_AUTH_JSON`: complete Codex `auth.json` content.
- `CODEX_API_KEY`: API key for Codex/OpenAI default endpoint.
- `OPENAI_API_KEY`: OpenAI-compatible API key. May be combined with
  `env.OPENAI_BASE_URL`.
- `OPENROUTER_API_KEY`: OpenRouter API key. The endpoint is fixed to
  `https://openrouter.ai/api/v1`.

Exactly one authentication secret must be provided during `/init`. Zero or
multiple authentication secrets fail initialization. API keys are never read
from environment variables; use `secrets` for authentication material.
