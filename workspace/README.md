# Datuak Development Environment

A containerized polyglot development environment with AI CLI tools (Claude, Antigravity, Kiro) and cloud provider CLIs (AWS, GCP). Built for fast, reproducible development across machines.

## Quick Start

### First Time Setup

```bash
# 1. Build image with inline cache metadata
./scripts/buildkit-cache.sh

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

# Rebuild after changes
make build-cached # Fast rebuild with ECR cache
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
- **Claude 5.5 models** via AWS Bedrock cross-region inference
- **Default**: Haiku 5.5 (fast, cost-effective)
- **Available**: Sonnet 5.5, Opus 5.5
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

The image is **9.6GB** with a **10+ minute** clean build time. We use ECR caching to reduce rebuilds to **1-3 minutes**.

### How It Works

1. **Inline Cache**: Image embeds cache metadata
2. **Layer Ordering**: Dockerfile ordered stable → volatile
3. **Smart Pulling**: Only changed layers download

### Build Targets

```bash
make build              # Standard build (local cache)
make build-cached       # Smart ECR cache (recommended)
make build-cached-full  # Pull full image, then build
make rebuild            # Force clean build (no cache)
```

**See [docs/BUILD_CACHING.md](docs/BUILD_CACHING.md) for complete caching guide.**

## Architecture

### Dockerfile Layer Strategy

```
Layers 1-84:   Base OS + Language Runtimes    [Stable - months]
Layers 86-91:  User creation                   [Stable - rarely changes]
Layers 93-128: Cloud CLIs (aws, gcloud, tf)   [Moderate - weeks]
Layers 132-144: ENV variables                  [Moderate - weeks]
Layers 146-168: AI CLIs (claude, agy, kiro)   [Volatile - frequent updates]
Layers 170+:   Configs & scripts               [Volatile - development]
```

**Why?** When Claude CLI updates (frequent), only the last few layers rebuild (~2 min), not the entire stack (~10 min).

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
ANTHROPIC_MODEL=us.anthropic.claude-haiku-5-5
KIRO_API_KEY=your-key-here
```

## Scripts

### Build Scripts
- `scripts/buildkit-cache.sh` - Build with inline cache metadata
- `scripts/build-with-cache.sh` - Standard ECR caching
- `scripts/setup-ecr.sh` - Create ECR repository

### Container Commands
```bash
make claude      # Claude Code CLI
make agy         # Antigravity CLI
make kiro        # Kiro CLI
make shell       # Bash shell
```

### Management Commands
```bash
make build       # Build image
make push        # Push to ECR
make pull        # Pull from ECR
make verify      # Verify environment
make clean       # Clean stopped containers
make test        # Run validation tests
```

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

**One person does this once:**
```bash
./scripts/buildkit-cache.sh  # Build with cache metadata
make push                     # Share with team
```

**Everyone else:**
```bash
make build-cached            # Fast build using shared cache
```

### Updating Shared Cache

When Dockerfile changes significantly:
```bash
./scripts/buildkit-cache.sh  # Rebuild with new cache
make push                     # Share updated cache
# Notify team: "New cache available!"
```

## Troubleshooting

### Build is slow
```bash
# Use ECR cache
make build-cached

# Verify BuildKit is enabled
grep DOCKER_BUILDKIT Makefile  # Should show: export DOCKER_BUILDKIT=1
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

### Out of disk space
```bash
# Clean Docker resources
docker system prune -a

# Or just images
docker image prune -a
```

## Performance

### Build Times

| Scenario | Time | Notes |
|----------|------|-------|
| First build (no cache) | 10+ min | One-time cost |
| With ECR cache | 1-3 min | Typical rebuild |
| No changes | 10-30 sec | Pure cache hit |
| ENV variable change | 1-2 min | Only top layers |
| AI CLI update | 2-3 min | Volatile layers only |
| Language runtime change | 8-9 min | Invalidates many layers |

### Image Size
- **Total**: 9.61 GB
- **Base layers**: ~6 GB (OS, languages, cloud CLIs)
- **AI CLIs**: ~2 GB (Claude, AGY, Kiro)
- **Configs**: ~1 GB (MCP, scripts, tools)

## Documentation

- **[BUILD_CACHING.md](docs/BUILD_CACHING.md)** - Complete caching guide, FAQ, troubleshooting
- **[BEDROCK_MODEL_ACCESS.md](docs/BEDROCK_MODEL_ACCESS.md)** - AWS Bedrock model access status

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
1. [BUILD_CACHING.md](docs/BUILD_CACHING.md) - Build and cache troubleshooting
2. `make verify` - Environment validation
3. Container logs: `docker logs <container-id>`
