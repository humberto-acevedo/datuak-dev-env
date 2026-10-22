#!/bin/bash
set -e

IMAGE_NAME="${IMAGE_NAME:-datuak-workspace}"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
REGION="${REGION:-us-east-1}"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}"

echo "🔨 Building with ECR layer cache..."
echo "Cache source: ${ECR_URI}:latest"

# Enable BuildKit for better caching
export DOCKER_BUILDKIT=1

# Try to pull latest for local cache
echo "📥 Pulling latest image for cache..."
if docker pull "${ECR_URI}:latest" 2>/dev/null; then
    echo "✅ Using cached layers from ECR"
    CACHE_FROM="--cache-from ${ECR_URI}:latest --cache-from ${IMAGE_NAME}:latest"
else
    echo "⚠️  No remote image found, building from scratch"
    CACHE_FROM="--cache-from ${IMAGE_NAME}:latest"
fi

# Build with cache
echo "🏗️  Building image..."
docker build \
    ${CACHE_FROM} \
    ${DOCKER_BUILD_ARGS} \
    -t "${IMAGE_NAME}:latest" \
    .

echo "✅ Build complete!"
