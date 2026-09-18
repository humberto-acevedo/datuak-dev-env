# Code Review: Docker Dev Environment

**Date:** 2026-09-18  
**Files reviewed:** `Dockerfile`, `Makefile`, `entrypoint.sh`, `.env`, `.gitignore`

**Overall verdict:** Solid foundation for a multi-CLI AI development workspace. The design intent is clear and the Makefile ergonomics are thoughtful. Below are findings organized by severity.

---

## 🔴 Critical — Security

### 1. Piping remote scripts to shell (Dockerfile L30, L34, L63, L66)

```dockerfile
RUN curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
RUN curl -fsSL https://claude.ai/install.sh | sh
```

Each of these is a **supply-chain attack vector**. A compromised CDN or DNS hijack executes arbitrary code as root during the build. Mitigations:

- **Verify checksums/signatures** where available (Rust provides SHA256 hashes, NodeSource has GPG).
- **Pin to a known commit/tag** when curling from Git-hosted installers.
- **Download to file → inspect → execute** in separate `RUN` steps so caching reveals tampering.
- At minimum add `--proto '=https' --tlsv1.2` to all curl invocations (only the Kiro install does this).

### 2. Container runs everything as root

There is **no non-root user** anywhere in the Dockerfile. All tool installs, config files, and the entrypoint run as UID 0. If the container is ever exposed on a network, or an AI tool runs untrusted code, it has full root inside the container.

**Recommendation:** Create a `devuser`, install tools globally, then switch with `USER devuser` for runtime. Tools that genuinely need root (e.g., `date -s` for time sync) can use `--cap-add=SYS_TIME` + `sudo` for just that command.

### 3. AWS account ID committed to `.env` (tracked by Makefile)

`.env` contains:
```
AWS_ACCOUNT=539247495490
AWS_PROFILE=AdministratorAccess-539247495490
```

While `.env` is in `.gitignore`, the **profile name itself contains the account ID** and is used directly in the Makefile's `AWS_PROFILE ?= default` override mechanism. The Makefile's `-include .env` + `export` pattern means _every_ variable in `.env` becomes an environment variable — including any future secrets accidentally added to that file.

**Recommendation:** Add a `.env.example` with placeholder values instead. Document the expected variables.

### 4. Host SSH keys mounted read-write (Makefile L21)

```makefile
-v "$(HOME)/.ssh:/root/.ssh"
```

The container can **modify your host's SSH keys** (add new keys, modify `authorized_keys`, etc.). Use `:ro` mount:

```makefile
-v "$(HOME)/.ssh:/root/.ssh:ro"
```

The entrypoint's `chmod` on L69-71 and `ssh-keyscan >> known_hosts` on L75 would fail with a read-only mount, which is the correct behavior — these should write to a _copy_ instead.

### 5. GitHub CLI config mounted read-write (Makefile L22)

```makefile
-v "$(HOME)/.config/gh:/root/.config/gh"
```

Same issue — a rogue process inside the container could exfiltrate or modify your `gh` auth tokens. Mount `:ro`.

---

## 🟠 High — Design & Reliability

### 6. No `.dockerignore` file

Without a `.dockerignore`, `docker build` sends the **entire context directory** to the daemon, including `.env` (with your AWS account ID), `.git/`, `docs/`, `scripts/`, etc. This slows builds and risks leaking sensitive files into the build context.

**Create `.dockerignore`:**
```
.env
.git
.gitignore
docs/
scripts/
*.tar.gz
*.md
```

### 7. No image layer caching strategy — single monolithic `dnf install`

The Dockerfile installs ~20 packages in one `RUN` layer. Any change to the package list invalidates the entire layer. Consider splitting into:
1. **Base OS + core utils** (rarely changes)
2. **Language runtimes** (Node, Rust, Python)
3. **CLI tools** (aws, gh, cdk, gcloud — changes more often)
4. **AI agent CLIs** (agy, claude, kiro — most volatile)

### 8. No pinned versions for most tools

| Tool | Pinned? | Risk |
|------|---------|------|
| Node.js | `setup_20.x` (major only) | Minor version drift |
| Rust | No | Any version on any build |
| AWS CDK | No (`npm install -g aws-cdk`) | Major breaking changes |
| gcloud CLI | No | Version drift |
| GitHub CLI | No | Version drift |
| Antigravity CLI | No | Version drift |
| Claude Code CLI | No | Version drift |
| `uv` | No | Version drift |
| `skills` | No | Version drift |
| `mcp-proxy-for-aws` | ✅ `@1.6.3` | Good |

Unpinned tools mean **builds are not reproducible**. A build today ≠ a build tomorrow.

### 9. Hardcoded git identity in entrypoint.sh (L83-84)

```bash
git config --global user.email "humberto.acevedo@datuak.ai"
git config --global user.name "Humberto Acevedo"
```

This makes the image **single-user only**. If anyone else uses the container, all commits will be attributed to the wrong person. Make these configurable:

```bash
git config --global user.email "${GIT_USER_EMAIL:-humberto.acevedo@datuak.ai}"
git config --global user.name "${GIT_USER_NAME:-Humberto Acevedo}"
```

### 10. Hardcoded secret name and API endpoint (entrypoint.sh L51, Dockerfile L97-98)

The secret name `GoogleGeminiAPIKeyiMac` and the MCP endpoint `https://aws-mcp.us-east-1.api.aws/mcp` are hardcoded in multiple places. Extract these to `ARG`/`ENV` so the image is reusable across environments.

### 11. Time sync relies on parsing HTTP headers from `aws.amazon.com`

entrypoint.sh L10:
```bash
REMOTE_DATE=$(curl -sI --max-time 4 https://aws.amazon.com 2>/dev/null | grep -i '^date:' | ...)
```

This is fragile — Amazon could change their response headers, HTTPS may fail behind corporate proxies, and `date -s` parsing is locale-dependent. Consider using NTP (`chronyc` or `ntpdate`) if time accuracy matters, or simply document that the host is expected to have correct time.

### 12. Test target doesn't actually fail on errors (Makefile L89-106)

The `test` target uses patterns like:
```makefile
@docker run --rm ... && echo "✅ ..." || echo "❌ ..."
```

But the `||` branch **always exits 0**, so `make test` always "passes" even when checks fail. The final `echo "✅ All tests passed"` runs unconditionally. Fix by accumulating failures or using `set -e` in a bash script.

---

## 🟡 Medium — Improvements

### 13. `DOCKER_RUN` uses `--cap-add=SYS_TIME`

`SYS_TIME` is a **Linux kernel capability** that lets the container change the host's clock (not just the container's). This is a privilege escalation vector. If time sync is truly needed, document why and consider alternatives.

### 14. Entrypoint creates `sync-time` at runtime (L7-24)

The script is generated inside the entrypoint every time the container starts. This should be baked into the image at build time (via a `COPY` or a `RUN cat << EOF > ...` in the Dockerfile), making the entrypoint faster and idempotent.

### 15. Duplicate MCP config blocks

The Claude MCP config (Dockerfile L88-112) and the Gemini MCP config (Dockerfile L115-134) contain nearly identical `mcp-proxy-for-aws` entries. If the version or endpoint changes, you need to update both. Consider generating both from a single template or shared `ARG`.

### 16. Model names duplicated in ENV and JSON config

`ANTHROPIC_MODEL` is set both as an ENV var (L70) and inside `settings.json` (L107). Same for `ANTHROPIC_SMALL_FAST_MODEL`. This is a maintenance risk — use `envsubst` at build time to generate `settings.json` from the ENV vars, or vice versa.

### 17. `ensure-sso` doesn't export credentials

The `ensure-sso` target refreshes the SSO session but doesn't export credentials to env vars. The `_run-with-creds` function does the export separately. This means if `ensure-sso` triggers a login, there's a small race condition where the session token hasn't fully propagated. Consider combining them.

### 18. Missing `HEALTHCHECK` instruction

No `HEALTHCHECK` in the Dockerfile. While this is a dev container (not a service), adding one helps tools like Docker Desktop and Compose surface container health status.

---

## 🟢 Positive Observations

| What | Why it's good |
|------|---------------|
| `set -euo pipefail` in entrypoint | Proper error handling — fails fast on errors |
| `exec "$@"` at end of entrypoint | Correct PID 1 handoff — signals reach the process |
| SSO credential flow | Credentials are ephemeral, not baked into the image |
| Secrets Manager for API keys | API keys never touch disk or env files |
| `.gitignore` covers `.env` | Prevents accidental credential commits |
| `ENTRYPOINT` + `CMD` split | Clean separation of setup vs. default command |
| Makefile aliases (`agy`, `claude`, `kiro`) | Good developer ergonomics |
| SSH `known_hosts` auto-population | Prevents interactive prompts in automation |

---

## Recommended Priority Order

1. Add `.dockerignore`
2. Mount `.ssh` and `gh` as `:ro`
3. Pin tool versions
4. Add checksum verification for `curl | bash` installs
5. Create non-root user
6. Parameterize git identity & secret names
7. Fix `make test` to actually fail on errors
8. Deduplicate MCP configs
9. Bake `sync-time` into image
