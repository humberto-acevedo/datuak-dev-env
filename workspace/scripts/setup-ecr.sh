#!/bin/bash
set -e

REPOSITORY_NAME="${1:-datuak-workspace}"
REGION="${2:-us-east-1}"
KEEP_IMAGES="${3:-10}"

echo "Creating ECR repository: $REPOSITORY_NAME in $REGION"

# Create repository
aws ecr create-repository \
  --repository-name "$REPOSITORY_NAME" \
  --region "$REGION" \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

echo "Repository created successfully"

# Add lifecycle policy
echo "Adding lifecycle policy (keep last $KEEP_IMAGES images)"
aws ecr put-lifecycle-policy \
  --repository-name "$REPOSITORY_NAME" \
  --region "$REGION" \
  --lifecycle-policy-text "{
  \"rules\": [
    {
      \"rulePriority\": 1,
      \"description\": \"Keep last $KEEP_IMAGES images\",
      \"selection\": {
        \"tagStatus\": \"any\",
        \"countType\": \"imageCountMoreThan\",
        \"countNumber\": $KEEP_IMAGES
      },
      \"action\": {
        \"type\": \"expire\"
      }
    }
  ]
}"

echo "✅ ECR repository setup complete"
echo "Repository URI: $(aws ecr describe-repositories --repository-names "$REPOSITORY_NAME" --region "$REGION" --query 'repositories[0].repositoryUri' --output text)"
