# Anthropic Workload Identity Federation (WIF) Setup

## Overview

**Workload Identity Federation** allows your AWS workloads to authenticate to Anthropic's API **without storing long-lived API keys**. Instead:

1. Your AWS workload uses **IAM credentials** (temporary from EC2 instance role or STS)
2. AWS STS signs a JWT token with an Anthropic-specific audience claim
3. Token is sent to `https://api.anthropic.com/v1/oauth/token`
4. Anthropic validates the JWT and returns a short-lived access token (~1 hour)
5. Access token is used to call the Claude API

## Architecture

```
┌─────────────┐
│ AWS Workload│
│  (Container)│
└──────┬──────┘
       │ AWS_ROLE_ARN
       ▼
┌──────────────────┐
│ IAM Role         │
│ (AssumeRole)     │ ◄─── Assume role via STS
└──────┬───────────┘
       │ Generate JWT
       │ audience: https://api.anthropic.com
       ▼
┌─────────────────────────────────┐
│ Anthropic Token Exchange API    │
│ POST /v1/oauth/token            │
│ (validate AWS STS JWT)          │
└──────┬────────────────────────────┘
       │ Short-lived token (1h)
       ▼
┌───────────────────┐
│ Claude API        │
│ (authenticated)   │
└───────────────────┘
```

## What's Deployed

The CDK stack creates:

1. **IAM Role**: `anthropic-workload-identity`
   - Allows STS AssumeRole with external ID (`anthropic-wif`)
   - Policy: Invoke Bedrock Claude models (if using Bedrock instead of first-party API)
   - Role ARN: Exported as `AnthropicRoleArn` CloudFormation output

2. **No API key stored** in Secrets Manager or environment

## Setup

### Step 1: Deploy CDK Stack

```bash
cd /workspace/datuak-dev-env/infra
npm install
npx cdk deploy AnthropicWIFStack
```

Output will show:
```
Outputs:
AnthropicWIFStack.RoleArn = arn:aws:iam::539247495490:role/anthropic-workload-identity
AnthropicWIFStack.AccountId = 539247495490
```

### Step 2: Configure Environment

In `.env` or `.env.local`:

```bash
# Remove ANTHROPIC_API_KEY (no longer needed!)

# Add WIF configuration
AWS_ROLE_ARN=arn:aws:iam::539247495490:role/anthropic-workload-identity
```

### Step 3: Authenticate

**On Mac (local):**
```bash
# Authenticate once per session
aws sso login

# Verify you have a role attached
aws sts get-caller-identity
```

**In Docker container:**
- Container inherits IAM role from ECS task/EC2 instance automatically
- No `aws sso login` needed inside container

### Step 4: Test WIF Authentication

```bash
# Test via AWS CLI
aws sts get-caller-identity

# Test via Python (Claude SDK auto-detects WIF)
python3 -c "
import anthropic
client = anthropic.Anthropic(
    api_key=None,  # Not needed with WIF
    aws_role_arn='arn:aws:iam::539247495490:role/anthropic-workload-identity'
)
msg = client.messages.create(
    model='claude-3-5-sonnet-20241022',
    max_tokens=100,
    messages=[{'role': 'user', 'content': 'Hello'}]
)
print(msg.content[0].text)
"
```

## Security Benefits

| Aspect | API Key | WIF |
|--------|---------|-----|
| **Storage** | Secrets Manager | AWS IAM only |
| **Lifetime** | Months/years | 1 hour |
| **Rotation** | Manual | Automatic |
| **Audit Trail** | Limited | Full CloudTrail |
| **Risk if Compromised** | Full API access | 1-hour window |

## Usage in Docker Containers

### Docker on Mac (with Docker Desktop)

```dockerfile
FROM python:3.11

WORKDIR /app

RUN pip install anthropic

# Set AWS credentials from host environment
ENV AWS_PROFILE=default
ENV AWS_ROLE_ARN=arn:aws:iam::539247495490:role/anthropic-workload-identity

COPY . .
CMD ["python", "main.py"]
```

Run with:
```bash
docker run --rm \
  -e AWS_PROFILE=default \
  -e AWS_ROLE_ARN=arn:aws:iam::539247495490:role/anthropic-workload-identity \
  -v ~/.aws/credentials:/root/.aws/credentials:ro \
  -v ~/.aws/config:/root/.aws/config:ro \
  my-app:latest
```

### ECS Task (Recommended for AWS)

```json
{
  "taskRoleArn": "arn:aws:iam::539247495490:role/anthropic-workload-identity",
  "containerDefinitions": [
    {
      "environment": [
        {
          "name": "AWS_ROLE_ARN",
          "value": "arn:aws:iam::539247495490:role/anthropic-workload-identity"
        }
      ]
    }
  ]
}
```

ECS automatically injects AWS credentials → no manual setup needed.

## Troubleshooting

### "UnrecognizedClientException: The security token included in the request is invalid"

- Ensure `aws sso login` was run recently (tokens expire in ~12 hours)
- Verify `AWS_ROLE_ARN` is correct
- Check IAM policy allows `sts:AssumeRole`

### "InvalidParameterException: audience must be https://api.anthropic.com"

- SDK is auto-discovering WIF (correct behavior)
- Verify Anthropic SDK version is >= 0.20.0

### "AccessDenied: User is not authorized to perform: sts:AssumeRole"

- Role trust relationship may be misconfigured
- Run: `aws sts assume-role --role-arn <role-arn> --role-session-name test`
- Check role policy includes `sts:AssumeRole` action

## Disabling WIF (Fallback to API Keys)

If WIF fails, the SDK falls back to `ANTHROPIC_API_KEY`:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
# SDK tries WIF first, then falls back to API key
```

To explicitly disable WIF:
```bash
unset AWS_ROLE_ARN
export ANTHROPIC_API_KEY="sk-ant-..."
```

## References

- [Anthropic WIF Documentation](https://platform.claude.com/docs/en/manage-claude/wif-providers/aws)
- [AWS STS GetCallerIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_GetCallerIdentity.html)
- [Anthropic Python SDK](https://github.com/anthropics/anthropic-sdk-python)
