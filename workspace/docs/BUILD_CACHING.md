# Docker Build Caching with ECR

This dev environment image is ~9.6GB with a 10+ minute build time. Using ECR for layer caching can reduce rebuilds to **1-3 minutes** when only top layers change.

## Quick Start

```bash
# First time: build and push with inline cache
./scripts/buildkit-cache.sh
make push

# Subsequent builds: use cached layers from ECR
make build-cached
```

## Caching Strategies

### 1. **Make target: `build-cached`** (Simple)
```bash
make build-cached
```
- Pulls latest image from ECR
- Uses it as cache source with `--cache-from`
- **Pros**: Easy, works with standard Docker
- **Cons**: Slower than BuildKit inline cache

### 2. **BuildKit Inline Cache** (Recommended)
```bash
./scripts/buildkit-cache.sh
make push
```
- Embeds cache metadata directly in the image
- Future builds automatically use this metadata
- **Pros**: Fastest, automatic cache propagation
- **Cons**: Requires DOCKER_BUILDKIT=1

### 3. **Manual Cache-From**
```bash
./scripts/build-with-cache.sh
```
- Explicit cache control
- **Pros**: Works without BuildKit
- **Cons**: Manual cache management

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

## Best Practices

1. **Always push after building** to share cache with team/machines
2. **Order Dockerfile from stable → volatile** (already done)
3. **Use BuildKit inline cache** for best performance
4. **Keep a base image** in ECR even if you delete local images

## Workflow Example

```bash
# Developer A: First build with cache metadata
./scripts/buildkit-cache.sh
make push

# Developer B: Fast rebuild using A's cache
make build-cached  # Uses ECR layers, much faster!

# Same machine, later: Local + ECR cache
make build-cached  # Uses both local and ECR layers
```

## Storage Costs

ECR lifecycle policy keeps last 10 images (~96GB max).
Cost: ~$9.60/month for storage in us-east-1.

## Troubleshooting

### "No space left on device"
```bash
docker system prune -a  # Clean old images
```

### Cache not being used
```bash
# Verify BuildKit is enabled
export DOCKER_BUILDKIT=1

# Check cache-from syntax
docker build --cache-from IMAGE:TAG ...
```

### Slow after Dockerfile changes
Cache invalidated. Normal. Use base image pattern for better isolation.
