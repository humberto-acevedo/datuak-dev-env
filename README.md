# Datuak Development Environment

A containerized polyglot development environment with AI CLI tools (Claude, Antigravity, Kiro) and cloud provider CLIs (AWS, GCP). Built for fast, reproducible development across machines.

## Quick Start

### First Time Setup

```bash
# 1. Build image (creates local cache)
make build

# 2. Verify everything works
make verify

# 3. Start working
make claude    # Launch Claude CLI in container
```

### Daily Usage

```bash
# Launch tools in container
make claude       # Claude Code CLI
make agy          # Antigravity CLI  
make kiro         # Kiro CLI
make shell        # Interactive bash shell

# Rebuild after changes (uses ECR cache automatically)
make build-cached # 30-60 sec rebuild with layer caching
```

## What's Included

### AI Development Tools
- **Claude Code** - Anthropic's AI coding assistant
- **Antigravity (AGY)** - Google's AI CLI
- **Kiro** - AWS Q CLI

### Cloud Provider CLIs
- **AWS CLI** - AWS services management
- **gcloud** - Google Cloud Platform CLI
- **Terraform** - Infrastructure as code (v1.6.0)
- **AWS CDK** - Cloud Development Kit

### Languages & Runtimes
- **Python 3.9+** (configurable, build-arg: `PYTHON_VERSION`)
- **Node.js 20+** (configurable, build-arg: `NODEJS_MAJOR`)
- **Rust** - System-wide installation

### Development Tools
- Git, GitHub CLI (gh), tig
- Vim, tmux
- Make, jq, curl, zip, unzip

## Container Features

### AWS Bedrock Integration
- **Claude models** via AWS Bedrock
- **Available models**: Haiku 5.5 (default), Sonnet 5.5, Opus 5.5
- **MCP Server**: AWS integration via mcp-proxy-for-aws
- **USAFacts MCP**: U.S. government data source

### Persistent Storage
Mounted volumes:
- `../../` → `/workspace` (your code)
- `~/Documents/Ideas` → `/workspace/Ideas` (optional)
- `~/Development/tools-code` → `/workspace/tools-code` (optional)
- `~/.ssh` → Read-only SSH keys
- `~/.config/gh` → Read-only GitHub CLI config

### Security
- Non-root user (`devuser`)
- AWS credentials passed via environment
- SSH keys mounted read-only
- SSH agent forwarding (macOS/Linux)
- Time synchronization via `--cap-add=SYS_TIME`

## Build Optimization

The image is **9.6GB** with optimized layer caching for fast rebuilds.

### Build Targets

```bash
make build              # Build with local cache (5-10 min)
make build-cached       # Build with ECR layer cache (30-60 sec) ← Use this
make rebuild            # Force clean build, no cache (10+ min)
make build-latest       # Build with latest Python/Node versions
make rebuild-latest     # Force rebuild with latest versions
```

### Performance

| Scenario | Time | Speedup |
|----------|------|----------|
| Fresh build (no cache) | 5-10 min | Baseline |
| With ECR cache (unchanged) | 30-60 sec | 5-20× faster |
| One npm package changed | 1-2 min | 3-10× faster |
| AI CLI update | 2-5 min | 1.5-3× faster |

### How Layer Caching Works

1. **BuildKit Registry Cache**: Uses `--cache-from/--cache-to type=registry`
2. **22 Optimized Layers**: Each layer independently cacheable
3. **No manual `make pull` needed**: `make build-cached` handles authentication
4. **Layer-Level Reuse**: Only changed layers rebuild

**Dockerfile Layer Strategy** (optimized for stability):

```
Layer 1:      Base system packages       [Stable - months]
Layers 2-3:   Python/Node version management [Stable - rarely changes]
Layer 4-5:    Node.js + npm packages     [Pinned versions]
Layer 6:      Rust                       [Stable - months]
Layer 7:      Non-root user setup        [Stable]
Layer 8-9:    Terraform, gcloud          [Moderate - weeks]
Layer 10:     GitHub CLI                 [Moderate - months]
Layers 11+:   Claude/AGY/Kiro CLIs       [Volatile - frequent]
```

When Claude CLI updates, only higher layers rebuild (~1-2 min), not the entire stack.

## Configuration

### Build Arguments

```bash
# Custom Python version
make build DOCKER_BUILD_ARGS="--build-arg PYTHON_VERSION=3.12"

# Custom Node.js version
make build DOCKER_BUILD_ARGS="--build-arg NODEJS_MAJOR=22"

# Build latest of everything
make build-latest
```

### AWS Configuration

```bash
# Set AWS profile (default: default)
make claude AWS_PROFILE=my-profile

# SSO login (interactive)
make sso-login AWS_PROFILE=my-profile

# Verify AWS credentials
make verify
```

### Environment Variables

Create `.env` file in workspace directory, or export before running:

```bash
AWS_PROFILE=AdministratorAccess-539247495490
AWS_REGION=us-east-1
ANTHROPIC_FEDERATION_RULE_ID=fdrl_...   # plus the org, service account, and workspace IDs
KIRO_API_KEY=your-key-here
GH_TOKEN=github_token_here
```

**Anthropic Authentication**: Uses Workload Identity Federation (WIF) — no API keys stored. Set up with `make wif-setup`, check with `make wif-test`. See [docs/ANTHROPIC_WIF_SETUP.md](docs/ANTHROPIC_WIF_SETUP.md).

## Make Commands

### Interactive Tools
```bash
make claude       # Launch Claude CLI
make agy          # Launch Antigravity (Gemini)
make antigravity  # Alias for `agy`
make kiro         # Launch Kiro CLI
make shell        # Interactive bash shell
make debug-shell  # Bash with entrypoint debugging
```

### Build & Image Management
```bash
make build              # Build with local cache
make build-cached       # Build with ECR layer cache (recommended)
make rebuild            # Force rebuild without cache
make build-latest       # Build with latest Python/Node versions
make rebuild-latest     # Force rebuild with latest versions
make push               # Push image + layers to ECR
make pull               # Pull image from ECR
make save               # Export image to tar.gz
make load               # Import image from tar.gz
```

### Configuration & Verification
```bash
make verify             # Verify all components (configs, MCP, models, tools, credentials)
make ensure-sso         # Refresh SSO credentials if expired
make ensure-buildx      # Ensure BuildKit builder exists
```

### Container Management
```bash
make ps                 # List all containers
make list-containers    # Alias for `ps`
make clean              # Remove stopped containers
```

## Architecture

### Data Flow

```
┌─────────────────────────────────────┐
│  Claude CLI / Antigravity (agy)     │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  MCP Server (mcp-proxy-for-aws)     │
│  • 300+ AWS services                │
│  • 15,000+ API actions              │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  AWS APIs (EC2, S3, Lambda, etc.)   │
│  • SSO credentials auto-refreshed    │
│  • CloudTrail audit logging         │
└─────────────────────────────────────┘
```

## Credentials & Security

### Automatic Credential Management
- **AWS**: SSO credentials auto-refresh via `make ensure-sso` (temporary, auto-expire)
- **Anthropic**: Workload Identity Federation (WIF) — AWS STS signs JWT tokens exchanged for Anthropic access tokens
- **Optional APIs**: Other API keys fetched from AWS Secrets Manager at runtime
- No hardcoded credentials stored

### Audit & Compliance
- CloudTrail logs all AWS API calls with `aws:ViaAWSMCPService` flag
- All requests tagged for compliance auditing
- Python scripts run in isolated sandbox

### Git Authentication

The container supports two authentication methods:

#### Desktop (SSH Keys)
```bash
docker run -v ~/.ssh:/home/devuser/.ssh:ro datuak-workspace
```
- **How it works:** Container detects mounted SSH key files and configures SSH mode
- **Git behavior:** Uses SSH (most secure, no token required)
- **Best for:** Local machines with persistent SSH key storage

#### Ephemeral Terminal (GitHub Token)
```bash
docker run -e GH_TOKEN=$(gh auth token) datuak-workspace
```
- **How it works:** Token passed as env var, written to `~/.git-credentials` at startup
- **Git behavior:** HTTPS with token
- **Accepted env vars:** `GH_TOKEN` or `GITHUB_TOKEN`
- **Best for:** CI/CD, temporary terminals, cloud shells

#### How Authentication Works

1. **Build time (Dockerfile):**
   - `credential.helper store` configured so `~/.git-credentials` is read automatically
   - SSH `StrictHostKeyChecking=accept-new` prevents interactive host-key prompts

2. **Runtime (entrypoint.sh):**
   - If `~/.ssh/id_*` key files exist → configure SSH mode
   - Otherwise → resolve token from `GH_TOKEN` → `GITHUB_TOKEN` → fallback to `gh auth token`
   - If token found → write `~/.git-credentials` and git works transparently
   - If neither → warn and exit; git will fail on private repos

### Troubleshooting Git Auth

| Issue | Solution |
|-------|----------|
| "Permission denied (publickey)" | Mount SSH keys: `docker run -v ~/.ssh:/home/devuser/.ssh:ro ...` |
| "Authentication failed" | Pass token: `docker run -e GH_TOKEN=$(gh auth token) ...` |
| "No SSH keys and no GH_TOKEN" | Ensure one of the above methods is configured |
| `gh auth token` returns nothing | Run `gh auth login` on the host first |

## AWS Agent Toolkit Features

### What You Can Do

✅ **Infrastructure Discovery**
- List EC2 instances, S3 buckets, Lambda functions
- Query security groups, VPCs, IAM policies

✅ **Security Auditing**
- Find resources without encryption
- Identify IAM users without MFA
- Audit S3 bucket permissions

✅ **Cost Analysis**
- Identify under-utilized resources
- Analyze Lambda function costs
- Compare data transfer across regions

✅ **Troubleshooting**
- Query CloudWatch logs
- Debug Lambda functions
- Check deployment status

✅ **Multi-Cloud** (Claude + Gemini)
- Fetch AWS data, process with Gemini AI
- Cross-cloud compliance checking
- Auto-generate documentation

### Usage Examples

**List S3 buckets:**
```bash
make claude
> List all S3 buckets in my account
```

**Find untagged resources:**
```bash
make claude
> Find all EC2 instances without a 'project' tag
```

**Multi-cloud analysis:**
```bash
make agy
> Fetch my AWS infrastructure, then summarize with Gemini
```

## Configuration Files

| File | Purpose |
|------|---------|
| **Dockerfile** | Generates Claude/AGY configs at build time |
| **Makefile** | Build, test, and launch targets |
| **entrypoint.sh** | Runtime initialization and validation |
| **.claude.json** | Claude MCP server configuration (auto-generated) |
| **.gemini/config/mcp_config.json** | AGY MCP server configuration (auto-generated) |
| **.kiro/settings/mcp.json** | Kiro MCP server configuration (auto-generated) |

## ECR Repository

### Created With
```bash
./scripts/setup-ecr.sh
```

### Details
- **Repository**: `datuak-workspace`
- **Region**: `us-east-1`
- **Lifecycle**: Keep last 10 images

### Sharing Cache with Team

**First-time setup (one person):**
```bash
make build              # Build locally (5-10 min)
make push               # Push image + all layers to ECR
```

**Team members (no `make pull` needed!):**
```bash
make build-cached       # Pulls layer cache from ECR (30-60 sec)
                        # No image download required
```

### Updating Shared Cache

When Dockerfile changes:
```bash
make build              # Rebuild locally
make push               # Updated cache automatically goes to ECR
# Notify team: "Cache updated"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "MCP server not connecting" | Run `make ensure-sso` then `make rebuild` |
| "AWS API calls failing" | Check IAM permissions; verify AWS region |
| "uv/skills not found" | Run `make rebuild` |
| "Claude not recognizing AWS" | Inside Claude: `/reload-plugins` then `/mcp restart` |
| "Credentials expired" | Run `make ensure-sso` before launching CLI |
| Build is slow | Use `make build-cached` to leverage ECR layer cache |
| AWS credentials issues | Run `make ensure-sso` to refresh SSO session |
| Container time sync issues | Time is synced automatically; if issues persist run `sync-time` inside container |
| Docker socket errors with `make push/pull` | Docker Desktop uses non-standard socket — Makefile auto-detects via `docker context inspect` |
| Out of disk space | Run `docker system prune -a` or `docker image prune -a` |

## Performance Characteristics

- **MCP cold start:** ~1-2 seconds
- **MCP warm start:** ~200-500ms
- **AWS API timeout:** 100 seconds (configurable)
- **Image size:** 9.61 GB total

## Security Best Practices

1. **Filter aggressively** — Don't query all resources
2. **Use tags to scope** — Tag resources for easier filtering
3. **Cache results** — Minimize redundant API calls
4. **Use CloudWatch Insights** — For efficient log filtering
5. **Review IAM policies** — Scope access to needed services

### Recommended IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*", "ec2:Describe*", "logs:FilterLogEvents"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ViaAWSMCPService": "true"
        }
      }
    }
  ]
}
```

## Directory Structure

```
datuak-dev-env/
├── README.md                 # This file
├── LICENSE
├── Dockerfile               # Build configuration
├── Makefile                 # Build & launch targets
├── workspace/
│   ├── entrypoint.sh        # Runtime initialization
│   ├── .claude.json         # Claude MCP config (auto-generated)
│   ├── .gemini/
│   │   └── config/
│   │       └── mcp_config.json  # AGY MCP config (auto-generated)
│   └── .kiro/
│       └── settings/
│           └── mcp.json     # Kiro MCP config (auto-generated)
├── docs/
│   ├── ARCHITECTURE.md      # Detailed architecture
│   ├── AWS_TOOLKIT_GUIDE.md # AWS integration guide
│   ├── bedrock-model-access-audit.md # Model access status
│   └── review-docker-env.md # Docker configuration details
└── scripts/
    └── setup-ecr.sh         # ECR repository setup
```

## References

- [AWS Agent Toolkit](https://aws.amazon.com/products/developer-tools/agent-toolkit-for-aws/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [Claude CLI Documentation](https://claude.com/claude-code)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)

## Support

1. Check troubleshooting section above
2. Review AWS CloudTrail logs for API failures
3. Verify credentials: `make ensure-sso`
4. Inspect configurations: `make verify`

## License

See LICENSE file for details.
