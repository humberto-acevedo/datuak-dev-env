# Datuak Development Environment

A containerized polyglot development environment with AI CLI tools (Claude, Antigravity, Kiro) and cloud provider CLIs (AWS, GCP). Built for fast, reproducible development across machines.

## Quick Start

### First Time Setup

```bash
# 1. Build image (creates local cache)
make build

# 2. Push to ECR (shares cache with team)
make push

# 3. Verify everything works
make verify

# 4. Start working
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

## What's Inside

### AI Development Tools
- **Claude Code** - Anthropic's AI coding assistant
- **Antigravity (AGY)** - Google's AI CLI
- **Kiro** - AWS Q CLI

### Cloud Provider CLIs
- **AWS CLI** - AWS services management
- **gcloud** - Google Cloud Platform CLI
- **Terraform** - Infrastructure as code
- **AWS CDK** - Cloud Development Kit

### Languages & Runtimes
- **Python 3.9+** (configurable, latest: 3.12)
- **Node.js 20+** (configurable, latest: 22)
- **Rust** - System-wide installation

### Development Tools
- Git, GitHub CLI (gh)
- Vim, tmux
- Make, jq, curl, zip

## Container Features

### AWS Bedrock Integration
- **Claude models** via AWS Bedrock
- **Available**: Haiku 4.5 (fast, cost-effective)
- **Sales-gated** (unavailable): Sonnet 5.5, Opus 5.5 — see [bedrock-model-access-audit.md](../docs/bedrock-model-access-audit.md)
- **MCP Server**: AWS integration via mcp-proxy-for-aws@1.6.3

### Persistent Storage
Mounted volumes:
- `../../` → `/workspace` (your code)
- `~/Documents/Ideas` → `/workspace/Ideas`
- `~/Development/tools-code` → `/workspace/tools-code`
- `~/.ssh` → Read-only SSH keys
- `~/.config/gh` → Read-only GitHub CLI config

### Security
- Non-root user (`devuser`)
- AWS credentials passed via environment
- SSH keys mounted read-only
- Time synchronization via `sync-time` command

## Build Optimization

The image is **9.6GB** with optimized layer caching for fast rebuilds.

### Performance

| Scenario | Time | Speedup |
|----------|------|----------|
| Fresh build (no cache) | 5-10 min | 3-6× faster |
| With ECR cache (unchanged code) | 30-60 sec | 30-60× faster |
| One package changed | 1-2 min | 15-30× faster |
| Dockerfile only changed | Varies | Layer-specific |

### How It Works

1. **BuildKit Registry Cache**: `--cache-from/--cache-to type=registry`
2. **22 Optimized Layers**: Each layer independently cacheable
3. **No `make pull` needed**: `make build-cached` handles authentication automatically
4. **Layer-Level Reuse**: Only changed layers rebuild

### Build Targets

```bash
make build              # Build with local cache (5-10 min)
make build-cached       # Build with ECR layer cache (30-60 sec) ← Use this
make rebuild            # Force clean build, no cache (10+ min)
make build-latest       # Build with latest Python/Node versions
```

**See [../docs/BUILD_CACHE_OPTIMIZATION.md](../docs/BUILD_CACHE_OPTIMIZATION.md) for detailed caching architecture.**

## Architecture

### Dockerfile Layer Strategy

Optimized 22-layer structure for maximum cache reuse:

```
Layer 1:      Base system packages       [Stable - months]
Layer 2-4:    Python/uv setup            [Stable - rarely changes]
Layer 5-6:    Node.js + npm packages     [Pinned versions]
Layer 7-11:   Rust, Terraform, gcloud    [Moderate - weeks]
Layer 12-14:  GitHub CLI, Git config     [Moderate - months]
Layer 15-17:  Claude/AGY/Kiro CLIs       [Volatile - frequent]
Layer 18:     MCP config                 [Volatile - development]
Layer 19-22:  Environment & runtime      [Volatile - development]
```

**Key Optimization**: ARGs placed at top, pinned versions throughout, split layers by logical concern. When Claude CLI updates, only layers 15-17 rebuild (~1-2 min), not the entire stack.

## Configuration

### Build Args

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

# SSO login
make sso-login AWS_PROFILE=my-profile

# Verify AWS credentials
make verify
```

### Environment Variables

Create `.env` file in workspace directory:

```bash
AWS_PROFILE=default
REGION=us-east-1
ANTHROPIC_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
KIRO_API_KEY=your-key-here
```

## Scripts

### Container Commands
```bash
make claude      # Claude Code CLI
make agy         # Antigravity CLI
make kiro        # Kiro CLI
make shell       # Bash shell
```

### Management Commands
```bash
make build       # Build image with local cache (5-10 min)
make build-cached # Build with ECR layer cache (30-60 sec) ← recommended
make push        # Push image + layers to ECR
make pull        # Pull image from ECR (optional)
make verify      # Verify environment
make clean       # Clean stopped containers
make test        # Run validation tests
```

**Note**: Deprecated scripts `buildkit-cache.sh` and `build-with-cache.sh` are no longer needed. Use `make build` and `make build-cached` instead.

## ECR Repository

### Created With
```bash
./scripts/setup-ecr.sh
```

### Details
- **Repository**: `datuak-workspace`
- **Region**: `us-east-1`
- **Account**: `539247495490`
- **URI**: `539247495490.dkr.ecr.us-east-1.amazonaws.com/datuak-workspace`
- **Lifecycle**: Keep last 10 images

## Team Collaboration

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

**Note**: `make build-cached` handles ECR authentication automatically via `ensure-sso`. No separate `make pull` needed.

## Troubleshooting

### Build is slow
```bash
# Use ECR cache (30-60 sec with layer reuse)
make build-cached

# Verify BuildKit and registry cache are enabled
grep -A 5 "^build-cached:" Makefile  # Should show: --cache-from type=registry

# Check cache status
docker buildx du  # Shows build cache usage
```

### AWS credentials issues
```bash
# Refresh SSO
make ensure-sso

# Verify credentials
aws sts get-caller-identity
```

### Container time sync issues
```bash
# Inside container
sync-time

# Or run with time sync capability
docker run --cap-add=SYS_TIME ...
```

### `make push` / `make pull` fails with "no such file or directory"

```
failed to connect to the docker API at unix:///var/run/docker.sock
```

Docker Desktop uses a non-standard socket path. The Makefile detects the active Docker context automatically via `docker context inspect`, so this should be transparent. If it still fails:

```bash
# Check which context and socket path Docker is using
docker context show
docker context inspect $(docker context show) --format '{{.Endpoints.docker.Host}}'

# Ensure Docker Desktop is running and the context is active
docker info
```

### Out of disk space
```bash
# Clean Docker resources
docker system prune -a

# Or just images
docker image prune -a
```

## Performance

### Build Times

| Scenario | Time | Speedup |
|----------|------|----------|
| First build (no cache) | 5-10 min | 3-6× |
| With ECR cache (no changes) | 30-60 sec | **30-60×** |
| One npm package added | 1-2 min | 15-30× |
| AI CLI update | 2-5 min | 6-15× |
| Language runtime change | 5-10 min | 3-6× |
| Dockerfile only change | 30-60 sec | **30-60×** |

### Image Size
- **Total**: 9.61 GB
- **Base layers**: ~6 GB (OS, languages, cloud CLIs)
- **AI CLIs**: ~2 GB (Claude, AGY, Kiro)
- **Configs**: ~1 GB (MCP, scripts, tools)

## Documentation

- **[BUILD_CACHE_OPTIMIZATION.md](../docs/BUILD_CACHE_OPTIMIZATION.md)** - Detailed cache architecture, root cause analysis, optimization guide
- **[bedrock-model-access-audit.md](../docs/bedrock-model-access-audit.md)** - AWS Bedrock model access status

## Requirements

- **Docker** 20.10+ (BuildKit support)
- **AWS CLI** v2
- **AWS Account** with ECR access
- **Disk Space** ~20 GB (image + build cache)

## Contributing

### Making Changes

1. Edit `Dockerfile` or configs
2. Test locally: `make build`
3. Update cache: `./scripts/buildkit-cache.sh && make push`
4. Commit changes
5. Notify team if Dockerfile changed

### Testing

```bash
# Run full test suite
make test

# Manual verification
make verify
```

## License

Internal development environment for Datuak team.

## Support

Issues or questions? Check:
1. [BUILD_CACHE_OPTIMIZATION.md](../docs/BUILD_CACHE_OPTIMIZATION.md) - Build and cache troubleshooting
2. `make verify` - Environment validation
3. Container logs: `docker logs <container-id>`
