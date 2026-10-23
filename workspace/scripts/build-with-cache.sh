#!/bin/bash
# DEPRECATED: This script is no longer needed
# The Makefile now handles ECR layer caching automatically via BuildKit registry backend.
#
# Previous approach: --cache-from type=registry (pull only)
# New approach:      --cache-from type=registry + --cache-to type=registry (persistent)
#
# Use instead:
#   make build        # Build with local cache
#   make build-cached # Build with ECR layer cache (30-60 sec)
#   make push         # Push to ECR

echo "❌ ERROR: build-with-cache.sh is deprecated."
echo ""
echo "Use instead:"
echo "  make build        # Build with local cache"
echo "  make build-cached # Build with ECR layer cache (30-60 sec)"
echo "  make push         # Push to ECR"
echo ""
echo "For details: docs/DOCKER_CACHE_OPTIMIZATION.md"
exit 1
