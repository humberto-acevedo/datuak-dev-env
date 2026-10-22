#!/bin/bash
# Advanced BuildKit caching using inline cache metadata
# This is the fastest option - embeds cache info directly in the image
set -e

IMAGE_NAME="${IMAGE_NAME:-datuak-workspace}"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
REGION="${REGION:-us-east-1}"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}"

echo "🚀 Building with BuildKit inline cache (fastest)..."

# Enable BuildKit
export DOCKER_BUILDKIT=1

# Build with inline cache metadata
docker build \
    --cache-from "${ECR_URI}:latest" \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    ${DOCKER_BUILD_ARGS} \
    -t "${IMAGE_NAME}:latest" \
    -t "${ECR_URI}:latest" \
    .

echo "✅ Build complete with inline cache metadata!"
echo ""
echo "📝 Next steps:"
echo "   1. Push to ECR: make push"
echo "   2. Future builds will be much faster using this cache"
