# Environment Configuration for Anthropic WIF

After deploying the CDK stack, configure your environment:

## 1. Get Role ARN from CloudFormation

```bash
AWS_PROFILE=AdministratorAccess-539247495490 aws cloudformation describe-stacks \
  --stack-name AnthropicWIFStack \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text
```

Example output:
```
arn:aws:iam::539247495490:role/anthropic-workload-identity
```

## 2. Update .env

In `/workspace/datuak-dev-env/workspace/.env` (create if missing):

```bash
# Anthropic WIF Configuration (no API key needed!)
AWS_ROLE_ARN=arn:aws:iam::539247495490:role/anthropic-workload-identity
```

**Remove** any `ANTHROPIC_API_KEY` lines.

## 3. Authenticate AWS on Your Mac

```bash
# One-time setup or refresh
aws sso login --profile AdministratorAccess-539247495490

# Verify credentials work
aws sts get-caller-identity --profile AdministratorAccess-539247495490
```

## 4. In Docker Container

The Makefile automatically passes AWS credentials:

```bash
make claude
```

Inside the container, Anthropic SDK will:
1. Read `AWS_ROLE_ARN` from environment
2. Use AWS credentials (from volume-mounted `~/.aws/`)
3. Call `sts:GetCallerIdentity` to get current identity
4. Generate JWT signed by AWS STS
5. Exchange JWT at Anthropic for access token
6. Use token to call Claude API

## 5. Verify WIF Works

```bash
# Inside container
python3 -c "
import anthropic
client = anthropic.Anthropic()
msg = client.messages.create(
    model='claude-3-5-sonnet-20241022',
    max_tokens=100,
    messages=[{'role': 'user', 'content': 'Say hello'}]
)
print('✅ WIF works:', msg.content[0].text[:50])
"
```

## Troubleshooting

**Error: "AccessDenied: User is not authorized to perform: sts:AssumeRole"**
- Run `aws sso login` to refresh credentials
- Verify you're using the correct profile

**Error: "InvalidParameterException: audience must be https://api.anthropic.com"**
- Anthropic SDK is auto-detecting WIF (correct!)
- Verify Anthropic SDK >= 0.20.0

**Error: "NoCredentialsError"**
- Check `AWS_PROFILE` is set or credentials in `~/.aws/credentials`
- Inside container, verify `-e AWS_PROFILE` is passed to `docker run`

## Fallback to API Key

If WIF fails, set `ANTHROPIC_API_KEY` as fallback:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
# SDK tries WIF first, then falls back to API key
```
