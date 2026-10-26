#!/bin/bash
# Setup Docker Buildx for Linux hosts
# Configures docker buildx with docker-container driver to support registry-based cache export

set -e

echo "🔧 Setting up Docker Buildx for ECR cache support..."

# Check if docker buildx is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! docker buildx version &> /dev/null; then
    echo "❌ docker buildx plugin is not installed."
    echo "Install it with: curl https://github.com/docker/buildx/releases/download/v0.13.1/buildx-v0.13.1.linux-amd64 -o ~/.docker/cli-plugins/docker-buildx && chmod +x ~/.docker/cli-plugins/docker-buildx"
    exit 1
fi

echo "✅ docker buildx is installed"

# Check current builders
echo ""
echo "📋 Current builders:"
docker buildx ls

# Create buildkit-builder if it doesn't exist
if docker buildx ls | grep -q "buildkit-builder"; then
    echo ""
    echo "✅ buildkit-builder already exists"
else
    echo ""
    echo "🚀 Creating buildkit-builder with docker-container driver..."
    docker buildx create --name buildkit-builder --driver docker-container
fi

# Set as active builder
echo ""
echo "🎯 Setting buildkit-builder as active builder..."
docker buildx use buildkit-builder

# Bootstrap the builder (spin up the BuildKit container)
echo ""
echo "⚙️  Bootstrapping buildkit-builder..."
docker buildx inspect buildkit-builder --bootstrap

echo ""
echo "✅ Setup complete!"
echo ""
echo "Verify with:"
echo "  docker buildx ls"
echo ""
echo "Test with:"
echo "  make build-cached"
