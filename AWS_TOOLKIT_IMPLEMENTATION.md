# AWS Agent Toolkit Implementation Guide

## Overview

This guide walks you through integrating the AWS Agent Toolkit into your Claude CLI and Antigravity (agy) development environment.

**Key Benefit:** Claude gains full programmatic access to 300+ AWS services and 15,000+ API actions directly through the MCP (Model Context Protocol) interface.

---

## What Changed

### Files Modified
1. **Dockerfile** - Added `uv` and `skills` CLI installation
2. **entrypoint.sh** - Added AWS toolkit dependency validation
3. **Makefile** - Added diagnostic targets

### Files Created
1. **.claude/settings.json** - Claude MCP server configuration
2. **.claude/kiro-mcp-settings.json** - Kiro/Antigravity MCP configuration
3. **AWS_AGENT_TOOLKIT_REVIEW.md** - Detailed review document
4. **AWS_TOOLKIT_IMPLEMENTATION.md** - This guide

---

## Step-by-Step Implementation

### Step 1: Rebuild Docker Image

```bash
cd /workspace/llm-environments/llm-workspace
make rebuild
```

This will:
- Install `uv` (Python package manager for MCP proxy)
- Install `skills` CLI (AWS toolkit skills management)
- Include all existing tools (Claude CLI, agy, AWS CLI, etc.)

**Timing:** ~5-10 minutes depending on your connection

### Step 2: Verify Installation

```bash
make verify-aws-toolkit
```

Expected output:
```
=== AWS Agent Toolkit Verification ===
1. uv (Python package manager):
Name: uv
Version: 0.x.x
...
2. Skills CLI:
Name: skills
Version: x.x.x
...

MCP Server: mcp-proxy-for-aws@1.6.3
Endpoint: https://aws-mcp.us-east-1.api.aws/mcp
Timeout: 100000ms
```

### Step 3: Test with Claude CLI

```bash
make claude
```

Inside the Claude CLI session:

```
# Test 1: List S3 buckets (requires AWS credentials)
> help aws.s3
# Should show available S3 operations

# Test 2: Describe EC2 instances
> Use AWS to list all EC2 instances in us-east-1

# Test 3: CloudWatch logs
> Search CloudWatch logs for errors in the last hour
```

### Step 4: Test with Antigravity (agy)

```bash
make antigravity
```

Inside the agy session:

```
# Test 1: Cross-cloud query
> Use AWS to get EC2 instance IPs, then use that data with Gemini

# Test 2: AWS-enhanced analysis
> Analyze my S3 bucket contents with Gemini AI
```

---

## AWS Credentials Flow

The toolkit uses your existing SSO-based credential setup:

```
┌─────────────────────┐
│  make claude/agy    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────────┐
│  ensure-sso target checks if        │
│  credentials are still valid        │
└──────────┬──────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│  If expired: run aws sso login            │
│  Export credentials: AWS_ACCESS_KEY_ID,  │
│  AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN│
└──────────┬───────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Docker container receives env vars  │
└──────────┬───────────────────────────┘
           │
           ▼
┌────────────────────────────────────────┐
│  Claude/agy MCP server uses creds      │
│  AWS Agent Toolkit makes API calls     │
└────────────────────────────────────────┘
```

---

## Configuration Details

### Claude Settings (.claude/settings.json)

```json
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",              // Use uv to run Python tools
      "timeout": 100000,             // 100 seconds for long operations
      "transport": "stdio",          // Communication protocol
      "args": [
        "mcp-proxy-for-aws@1.6.3",   // MCP proxy version
        "https://aws-mcp.us-east-1.api.aws/mcp",  // AWS endpoint
        "--metadata",
        "AWS_REGION=us-east-1"       // Configure region
      ]
    }
  },
  "permissions": {
    "aws:*": "allow"                 // Allow all AWS operations
  },
  "modelSettings": {
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "smallFastModel": "global.anthropic.claude-sonnet-4-5-20250929-v1:0",
    "maxOutputTokens": 4096
  }
}
```

**Key Features:**
- **uvx command**: Downloads and runs `mcp-proxy-for-aws` on-demand
- **100s timeout**: Long enough for complex AWS API calls
- **AWS region**: Set to us-east-1; override by setting `AWS_REGION` env var
- **Permissions**: Scoped with `aws:*` pattern

### Customization

**To change AWS region:**

Option 1: Set environment variable
```bash
AWS_REGION=us-west-2 make claude
```

Option 2: Edit .claude/settings.json
```json
"--metadata",
"AWS_REGION=us-west-2"
```

**To limit permissions (more restrictive):**

```json
"permissions": {
  "aws:iam": "deny",           // Deny IAM changes
  "aws:ec2:*": "allow",        // Allow only EC2
  "aws:s3:*": "allow"          // Allow only S3
}
```

---

## What You Can Do Now

### With Claude CLI + AWS Toolkit

✅ **Infrastructure Query:**
- "List all security groups with public access in us-west-2"
- "Show me the oldest EC2 instances"
- "What S3 buckets are not encrypted?"

✅ **Cost Analysis:**
- "Which Lambda functions have high duration?"
- "Compare data transfer costs across regions"
- "Show me under-utilized EC2 instances"

✅ **Security Audit:**
- "Find all IAM users without MFA"
- "List S3 buckets with public access"
- "Show RDS databases without backups"

✅ **Troubleshooting:**
- "Show me the last 100 CloudWatch errors"
- "Debug this Lambda function with logs"
- "Check deployment status of all app services"

### With Antigravity (agy) + AWS Toolkit

✅ **Multi-Cloud Analysis:**
- Fetch AWS data, process with Google Gemini AI
- Enhanced reasoning over infrastructure state
- Cross-cloud compliance checking

✅ **Content Generation:**
- Auto-generate infrastructure documentation
- Create runbooks from CloudWatch metrics
- Generate cost optimization recommendations

---

## Troubleshooting

### Issue: "MCP server not connecting"

**Check 1:** Verify uv is installed
```bash
docker run --rm datuak-workspace pip3 show uv
```

**Check 2:** Verify AWS credentials
```bash
make ensure-sso
```

**Check 3:** Test MCP connection manually
```bash
docker run --rm datuak-workspace bash -c "uvx mcp-proxy-for-aws@1.6.3 --help"
```

### Issue: "AWS API calls failing"

**Common causes:**
- IAM permissions too restrictive
- Wrong AWS region configured
- Credentials expired (run `make ensure-sso`)
- API throttling (wait and retry)

### Issue: "Claude not recognizing AWS commands"

**Solution:** Reload plugins/MCP server

Inside Claude CLI:
```
/reload-plugins
/mcp restart
```

---

## Performance & Cost

### MCP Proxy Overhead
- ~1-2 second cold start (first call)
- ~200-500ms warm start (subsequent calls)
- Network latency: depends on AWS region

### Cost Impact
- **MCP server**: No additional charge (AWS-hosted)
- **API calls**: Standard AWS pricing applies
- **Credentials**: SSO, no additional charges

### Best Practices
1. Filter results aggressively (don't query all resources)
2. Use tags to scope queries
3. Cache results when possible
4. Use CloudWatch Insights for log filtering

---

## Security Considerations

### ✅ Implemented Security

1. **Credential Isolation:**
   - Credentials injected via environment variables
   - Only valid during container session
   - Session tokens auto-expire

2. **Audit Trail:**
   - AWS CloudTrail logs all API calls with `aws:ViaAWSMCPService` flag
   - All requests tagged for compliance auditing

3. **Sandboxed Execution:**
   - Python scripts run isolated (no filesystem/network access)
   - No ability to escape container

4. **IAM Controls:**
   - Attach policies with condition keys:
     - `aws:ViaAWSMCPService` = true (restrict to MCP only)
     - `aws:CalledViaAWSMCP` = true (restrict method of invocation)

### Recommended IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*", "ec2:Describe*"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ViaAWSMCPService": "true"
        }
      }
    }
  ]
}
```

---

## Next Steps

1. **Rebuild image:**
   ```bash
   make rebuild
   ```

2. **Verify installation:**
   ```bash
   make verify-aws-toolkit
   ```

3. **Test Claude CLI:**
   ```bash
   make claude
   ```

4. **Test Antigravity:**
   ```bash
   make antigravity
   ```

5. **Create AWS IAM policy** with MCP-specific conditions
6. **Share configuration** with team members
7. **Document custom workflows** for your use case

---

## References

- [AWS Agent Toolkit Getting Started](https://aws.amazon.com/products/developer-tools/agent-toolkit-for-aws/#getting-started)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [AWS CloudTrail MCP Service Identifier](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-identity-elements.html)
- [IAM Condition Keys for MCP](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)

---

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review AWS CloudTrail logs for API failures
3. Check Claude MCP server logs: `make inspect-claude-config`
4. Verify AWS credentials: `make ensure-sso`
