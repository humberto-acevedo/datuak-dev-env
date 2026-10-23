#!/bin/bash
# DEPRECATED: This script is no longer needed
# The Makefile now handles BuildKit registry caching automatically via:
#   make build        # Build with local cache
#   make build-cached # Build with ECR layer cache
#
# For details, see: docs/DOCKER_CACHE_OPTIMIZATION.md

echo "❌ ERROR: buildkit-cache.sh is deprecated."
echo ""
echo "Use instead:"
echo "  make build        # Build with local cache"
echo "  make build-cached # Build with ECR layer cache (30-60 sec)"
echo "  make push         # Push to ECR"
echo ""
echo "For details: docs/DOCKER_CACHE_OPTIMIZATION.md"
exit 1
