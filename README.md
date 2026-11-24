[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/cccc?utm_medium=integration&utm_source=button&utm_campaign=cccc)

# CCCC on Railway

One-click Railway template for [CCCC](https://github.com/ChesterRa/cccc) **v0.4.60**, the coordinator for AI coding agents (Claude Code, Codex, Pi, OpenCode and more) with a Web UI.

- **Image:** `node:24.19.0-bookworm-slim@sha256:a9f5f7c91a432850b2a8a7797adf5eadb6c733ceed61167806cee7ea7fbc29df` plus the official release binary `cccc-v0.4.60-x86_64-unknown-linux-gnu.tar.gz` (sha256 `2a57d0341e8a92c79cdc230fba1eac7b14a24521811c502ec15525727358a709`, checked at build time). Upstream publishes no container image.
- **Agent CLIs:** Claude Code 2.1.325, Codex 0.172.0, Pi 1.6.0 (pinned npm versions).
- **Volume:** `/data` (CCCC home, agent logins, project folders).
- **Port / health:** `PORT` (8848), `/api/v1/health`.

## Variables

| Variable | Default | What it is |
|---|---|---|
| `CCCC_ADMIN_TOKEN` | generated (`${{secret(40)}}`) | Admin Access Token for the Web UI sign-in. |
| `LLM_API_KEY` | *(you enter it)* | API key for an OpenAI-compatible LLM provider, used by the Pi agent. |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | Provider endpoint. |
| `LLM_MODEL` | `gpt-5.4-mini` | Default model for Pi. |
| `PORT` | `8848` | Web port. |

## How it works

`start.sh` lays out `/data`, writes the admin token into CCCC's own token store (`/data/cccc/access_tokens.yaml`) so the Web UI is locked before it gets a public URL, seeds Pi's provider from the variables (the key stays in the environment, not on disk), caps thread pools to the service's CPUs, and runs `cccc --headless` as the unprivileged `node` user. If CCCC stops on its own, the script exits non-zero so Railway's restart policy brings it back. Upstream's `CCCC_WEB_ALLOW_UNAUTHENTICATED=1` is never set.


**Services.** One service, `CCCC`, built from `aalfath/cccc-railway-template`. It runs `cccc --headless` (daemon and Web UI) as an unprivileged user on Railway's `PORT`, behind Railway's HTTPS domain. Health check: `/api/v1/health`.

**After deploy.**

1. Open the service's variables and copy `CCCC_ADMIN_TOKEN`.
2. Open the public URL and paste the token into the sign-in form. The browser keeps a session cookie for 30 days.
3. Choose **New**, create a Group in a folder under `/data/workspace` (for example `/data/workspace/myproject`; clone your repo there from an agent's terminal), then **Add an agent** and pick a runtime. **Pi** is already set up with your `LLM_API_KEY`, `LLM_BASE_URL` and `LLM_MODEL`. For **Claude Code** or **Codex**, sign in once from the agent's terminal, or add `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` to the service variables.

**Variables.** `CCCC_ADMIN_TOKEN` is generated. `LLM_API_KEY` is the only prompt. `LLM_BASE_URL` (default `https://api.openai.com/v1`) and `LLM_MODEL` (default `gpt-5.4-mini`) point Pi at any OpenAI-compatible provider, such as OpenRouter, DeepSeek or a self-hosted gateway. Changing `CCCC_ADMIN_TOKEN` adds the new value as an admin token on the next start; remove old tokens in **Settings > This instance > Web Access**.

**Security.** Agents run with their approval prompts bypassed and can run any command inside the container, and anyone with the admin token controls them. Keep the token private, and give agents only the credentials they need. Docker-in-Docker and CCCC's projected browser are not available on Railway.

**Resources.** CCCC with one Pi agent running a tool job peaked under 100 MB in our tests at a 0.5 GB limit, so one agent fits the Free plan. We did not measure Claude Code or Codex under load: for those, or for several agents at once, choose Hobby or higher and raise the service's memory limit.

**Updates.** This template builds from a public GitHub repo. When we publish a new CCCC version there, Railway shows you an "update available" notice and you choose when to apply it. Read the repo's `CHANGELOG.md` first. Your data on `/data` is kept.

## Updates

Railway sends an "update available" notice to everyone who deployed this template when we merge a change to `main` here. Every version bump gets an entry in [CHANGELOG.md](CHANGELOG.md), with breaking changes listed first. Your `/data` volume is kept.

## Licence

CCCC is Apache-2.0 (c) its authors. This wrapper is Apache-2.0 as well.
