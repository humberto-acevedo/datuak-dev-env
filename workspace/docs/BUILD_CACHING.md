# Docker Build Caching with ECR

This dev environment image is ~9.6GB with a 10+ minute build time. Using ECR for layer caching can reduce rebuilds to **1-3 minutes** when only top layers change.

## Quick Start

### First Time Setup (One Person on Team)
```bash
# Build with inline cache metadata embedded
./scripts/buildkit-cache.sh

# Push to ECR (image + metadata)
make push
```

### Using the Cache (Everyone Else / Future Builds)
```bash
# Smart cache - pulls only needed layers
make build-cached

# Or if you want the full image locally anyway
make build-cached-full
```

## How Inline Cache Works

### The Magic of `BUILDKIT_INLINE_CACHE=1`

When you build with `./scripts/buildkit-cache.sh`, it embeds cache metadata **inside the image manifest**. This metadata tells Docker:
- Which layers are in the image
- How those layers were built
- Dependencies between layers

### Does the Cache Metadata Travel?

**YES!** When you push/pull the image, the metadata travels with it.

**BUT** you must tell Docker to use it with `--cache-from`:

```bash
# On Host A: Build and push
./scripts/buildkit-cache.sh
make push

# On Host B: Use the cache
make build-cached  # Docker reads metadata, pulls only needed layers
```

### Why This Is Fast

**Without inline cache:**
```
Host B: docker pull image (downloads all 9.6GB)
Host B: docker build (uses local layers)
Total: 9.6GB download + build time
```

**With inline cache:**
```
Host B: docker build --cache-from ECR
Docker: Reads metadata from ECR
Docker: Pulls only layers that changed (~100MB - 2GB typically)
Docker: Builds using cached layers
Total: Minimal download + fast build
```

## Build Targets Explained

### `make build-cached` (Recommended)
```makefile
docker build --cache-from ECR:latest -t IMAGE .
```
- Points directly at ECR repository
- Docker reads inline cache metadata
- Pulls only needed layers (smart)
- **Best for clean machines / CI/CD**

### `make build-cached-full` (Legacy)
```makefile
docker pull ECR:latest       # Downloads all 9.6GB
docker build --cache-from IMAGE:latest -t IMAGE .
```
- Pulls entire image first
- Uses local image as cache source
- **Use when you want the image locally anyway**

### `./scripts/buildkit-cache.sh` (Initial Setup)
```bash
docker build --build-arg BUILDKIT_INLINE_CACHE=1 ...
```
- **Run this once** to create the cache-enabled image
- Embeds metadata in the image
- Push to ECR after this
- **Everyone else benefits automatically**

## How It Works

Docker builds in layers:
```
Layer 1: Base OS + dnf packages     ← Changes rarely
Layer 2: Python/Node/Rust install   ← Changes rarely  
Layer 3: Cloud CLIs                 ← Changes sometimes
Layer 4: AI CLIs (Claude/AGY/Kiro)  ← Changes often
Layer 5: Configs & entrypoint       ← Changes often
```

When you rebuild:
- **Without cache**: Rebuilds all layers (10+ min)
- **With cache**: Reuses unchanged layers (1-3 min)

## Cache Invalidation

Layers rebuild when:
- Dockerfile changes at that line or above
- Build args change (`--build-arg`)
- Base image updates

To force full rebuild:
```bash
make rebuild  # No cache
```

## Layer Ordering Optimization

The Dockerfile is ordered from most stable → most volatile:

```
Lines 1-84:   Base OS + Python + Node.js + Rust         [VERY STABLE]
Lines 86-91:  User creation                              [STABLE]  
Lines 93-128: Cloud tools (CDK, Terraform, gcloud, gh)  [MODERATELY STABLE]
Lines 132-144: ENV variables                             [MODERATELY STABLE]
Lines 146-168: AI CLIs (Antigravity, Claude, Kiro)      [VOLATILE]
Lines 170+:   MCP configs + entrypoint scripts           [VOLATILE]
```

**Why this matters**: When you update Claude CLI (happens frequently), only layers 153+ rebuild (~2 min), not the entire gcloud/terraform stack (~5 min).

## Team Workflow

### Initial Setup (Do Once)
**Designate one person** to create the cached image:

```bash
# Person A: Create cache-enabled image
./scripts/buildkit-cache.sh
make push

# Share with team: "Cache is ready in ECR!"
```

### Daily Development (Everyone)
```bash
# Clean machine or after pulling latest Dockerfile changes
make build-cached

# Make your changes to code/configs
# Test your changes

# Rebuild if needed
make build-cached  # Fast rebuild using existing cache
```

### Updating the Cached Image (Periodically)
When Dockerfile changes significantly:

```bash
# Rebuild with inline cache
./scripts/buildkit-cache.sh
make push

# Notify team: "New cache available"
```

## Common Scenarios

### Scenario 1: New Team Member Setup
```bash
# Clone repo
git clone <repo>
cd workspace

# Build using team's cache
make build-cached  # Fast! Uses cached layers from ECR

# Start working
make claude
```

### Scenario 2: Updating Claude CLI Version
```bash
# Edit Dockerfile (change Claude version)
vim Dockerfile

# Rebuild - only AI CLI layers rebuild
make build-cached  # ~2-3 min instead of 10+ min

# Push new cache for team
./scripts/buildkit-cache.sh
make push
```

### Scenario 3: CI/CD Pipeline
```yaml
# .github/workflows/build.yml
- name: Build with ECR cache
  run: make build-cached  # No full image pull needed!
```

### Scenario 4: Multiple Machines
```bash
# Laptop: Build and push
./scripts/buildkit-cache.sh
make push

# Desktop: Use the cache (no local image)
make build-cached  # Fast! Pulls only needed layers

# Both machines stay in sync with minimal data transfer
```

## Best Practices

1. **Always use `buildkit-cache.sh` when pushing** - ensures metadata is embedded
2. **Push after Dockerfile changes** - share cache improvements with team
3. **Use `build-cached` for daily work** - leverage existing cache
4. **Clean old images periodically** - `docker system prune -a`
5. **BuildKit is enabled by default** - already configured in Makefile

## Storage Costs

ECR lifecycle policy keeps last 10 images (~96GB max).
Cost: ~$9.60/month for storage in us-east-1.

## Troubleshooting

### "No space left on device"
```bash
# Clean all unused Docker resources
docker system prune -a

# Or just remove old images
docker image prune -a
```

### Cache not being used / Still slow
```bash
# 1. Verify BuildKit is enabled (should be automatic)
grep DOCKER_BUILDKIT Makefile  # Should show: export DOCKER_BUILDKIT=1

# 2. Verify inline cache exists in ECR
aws ecr describe-images --repository-name datuak-workspace --region us-east-1

# 3. Test cache explicitly
docker build --cache-from 539247495490.dkr.ecr.us-east-1.amazonaws.com/datuak-workspace:latest -t test .
```

### Build is slow after Dockerfile changes
**This is normal!** Cache invalidates when Dockerfile changes. The layer where you made changes, and all layers after it, must rebuild.

**Example**: If you edit line 100, layers 100+ rebuild.

**Solution**: The Dockerfile is already ordered to minimize this impact.

### "Repository not found" error
```bash
# Create ECR repository first
./scripts/setup-ecr.sh

# Or manually
aws ecr create-repository --repository-name datuak-workspace --region us-east-1
```

### Can't authenticate to ECR
```bash
# Refresh SSO credentials
make ensure-sso

# Or login manually
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 539247495490.dkr.ecr.us-east-1.amazonaws.com
```

## FAQ

### Q: Do I need to pull the full image to use the cache?
**A:** No! With inline cache, Docker reads metadata from ECR and pulls only needed layers. Use `make build-cached` to leverage this.

### Q: If I pull the image on another host, will the cache work automatically?
**A:** The metadata travels with the image, but you must use `--cache-from` in your build command. Our `make build-cached` target does this for you.

### Q: How much faster is it really?
**A:** Depends on what changed:
- No changes: 10-30 seconds (pure cache hit)
- ENV variable change: 1-2 minutes
- AI CLI update: 2-3 minutes
- Python version change: 8-9 minutes
- Full rebuild: 10+ minutes

### Q: Does everyone need to run `buildkit-cache.sh`?
**A:** No! Only run it:
1. First time (create the cached image)
2. After significant Dockerfile changes (update the cache)
3. Periodically to refresh the cache

Everyone else just uses `make build-cached`.

### Q: What happens if I use regular `make build` instead?
**A:** It still works, but won't automatically use ECR cache. BuildKit is enabled, so it will use local cache if available. Use `make build-cached` to leverage ECR cache.

### Q: Can I delete my local image and still benefit from cache?
**A:** Yes! That's the power of inline cache. Docker pulls cache metadata from ECR without needing the full local image.

### Q: How do I know if inline cache is embedded in my image?
```bash
# Pull image and inspect
docker pull 539247495490.dkr.ecr.us-east-1.amazonaws.com/datuak-workspace:latest
docker image inspect datuak-workspace:latest | grep -i cache

# If built correctly with buildkit-cache.sh, cache info is in manifest
```

### Q: Does this work with Docker Compose?
**A:** Yes, but you need to add `cache_from` to your compose file or use the build scripts directly.

## Quick Reference

### Commands Cheat Sheet

```bash
# === Initial Setup (Once) ===
./scripts/buildkit-cache.sh    # Build with inline cache
make push                       # Push to ECR

# === Daily Development ===
make build-cached               # Build with ECR cache (smart)
make build                      # Standard build (local cache only)
make claude                     # Run Claude CLI in container

# === When Dockerfile Changes ===
./scripts/buildkit-cache.sh    # Rebuild with cache
make push                       # Share new cache with team

# === Maintenance ===
make pull                       # Pull latest image from ECR
make rebuild                    # Force full rebuild (no cache)
docker system prune -a          # Clean old images

# === ECR Management ===
./scripts/setup-ecr.sh          # Create ECR repository
make verify                     # Verify environment setup
```

### Build Target Quick Reference

| Target | Use When | What It Does |
|--------|----------|--------------|
| `make build` | Local development | Standard build, uses local cache |
| `make build-cached` | **Most common** | Smart ECR cache (recommended) |
| `make build-cached-full` | Want image locally | Pulls full image, then builds |
| `make rebuild` | Force clean build | No cache, full rebuild |
| `./scripts/buildkit-cache.sh` | Creating cache | Builds with inline cache metadata |

### File Reference

| File | Purpose |
|------|---------|
| `Dockerfile` | Image definition, layer-optimized |
| `Makefile` | Build targets, DOCKER_BUILDKIT=1 enabled |
| `scripts/buildkit-cache.sh` | Build with inline cache (run this first) |
| `scripts/build-with-cache.sh` | Alternative cache approach |
| `scripts/setup-ecr.sh` | Create ECR repository |
| `docs/BUILD_CACHING.md` | This document |

## Additional Resources

- **Dockerfile optimization**: See layer order at lines 1-84, 86-91, 93-168
- **ECR lifecycle policy**: Keeps last 10 images, auto-cleanup
- **BuildKit docs**: https://docs.docker.com/build/buildkit/
- **Docker cache**: https://docs.docker.com/build/cache/
