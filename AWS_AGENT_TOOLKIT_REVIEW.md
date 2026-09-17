# AWS Agent Toolkit Configuration Review

## Executive Summary

Your current setup has excellent foundations:
- ✅ Claude CLI installed and configured for Bedrock
- ✅ Antigravity (agy) CLI installed
- ✅ AWS credentials management (SSO-based)
- ✅ Docker environment with proper volume/env sharing
- ✅ Entrypoint automation for API key fetching

**Gap:** AWS Agent Toolkit MCP server integration is not yet configured.

---

## Current Setup Review

### Dockerfile Analysis
**Strengths:**
- Claude CLI installed with Bedrock configuration (lines 59-71)
- Environment variables properly set for Bedrock models (Haiku, Sonnet)
- Antigravity CLI installed (line 57)
- Kiro CLI for AWS integration (lines 73-79)
- Node.js, Python, AWS CLI pre-installed
- Proper PATH setup for local binaries

**Missing for AWS Agent Toolkit:**
- AWS Agent Toolkit MCP server package (requires npm/pip installation)
- AWS SDK for Node.js (may need explicit v3 installation)

### Makefile Analysis
**Strengths:**
- SSO credential management (ensure-sso target)
- Proper environment variable export for Claude, agy, kiro
- Volume mounting for SSH keys and GitHub config
- Proper SYS_TIME capability for clock sync

**Considerations:**
- agy credentials handled via Secrets Manager (good pattern)
- Could add AWS Agent Toolkit-specific targets

### Entrypoint Script Analysis
**Strengths:**
- API key management for agy/Gemini (lines 36-53)
- SSH setup and GitHub integration (lines 55-67)
- Time sync utility for credential expiration handling
- Git identity configuration

**Enhancement Opportunity:**
- Could add AWS Agent Toolkit initialization if needed

---

## AWS Agent Toolkit Integration Points

### 1. **MCP Server Installation & Configuration**

The AWS Agent Toolkit provides an MCP (Model Context Protocol) server: `mcp-proxy-for-aws`

**What you need:**
```bash
# uv (Python package manager) is required
pip install uv

# MCP proxy is installed on-demand via:
uvx mcp-proxy-for-aws@1.6.3
```

**Configuration in Claude/Kiro:**
MCP servers are configured in `.claude/settings.json` or `~/.kiro/settings/mcp.json`

**Key Features:**
- Access to 300+ AWS services and 15,000+ API actions
- Supports full AWS SDK capabilities
- Python scripts run in isolated sandbox
- CloudTrail audit logging for compliance

### 2. **Environment Variables Needed**
The toolkit requires AWS credentials (already handled by your SSO setup):
- `AWS_ACCESS_KEY_ID` ✅ (already exported)
- `AWS_SECRET_ACCESS_KEY` ✅ (already exported)
- `AWS_SESSION_TOKEN` ✅ (already exported)
- `AWS_REGION` ✅ (already exported)

### 3. **Claude CLI Configuration**
Claude CLI can use MCP servers to extend its capabilities. The `.claude/settings.json` file configures:
- Available MCP servers
- Tool permissions
- Model preferences
- Output token limits

---

## Recommended Configuration Changes

### 1. Update Dockerfile

Add Python package manager and MCP proxy dependencies:

```dockerfile
# After Python installation (line 18), add:
# Install uv (Python package manager for MCP proxy)
RUN pip3 install --upgrade uv

# Install skills CLI for AWS toolkit
RUN pip3 install skills
```

### 2. Create Claude MCP Configuration

Create `.claude/settings.json` with AWS Agent Toolkit MCP server config:

```json
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "transport": "stdio",
      "args": [
        "mcp-proxy-for-aws@1.6.3",
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--metadata",
        "AWS_REGION=${AWS_REGION:-us-east-1}"
      ]
    }
  },
  "permissions": {
    "aws:*": "allow"
  },
  "modelSettings": {
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "maxOutputTokens": 4096
  }
}
```

### 3. Create Kiro MCP Configuration

For Antigravity (agy) users, create Kiro configuration:

```json
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "transport": "stdio",
      "args": [
        "mcp-proxy-for-aws@1.6.3",
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--metadata",
        "AWS_REGION=${AWS_REGION:-us-east-1}"
      ]
    }
  }
}
```

### 4. Update Makefile (Optional)

Add diagnostic targets:

```makefile
claude-info:
	@echo "Claude MCP Server Status:"
	@docker run --rm $(DOCKER_VOLUMES) $(IMAGE_NAME) claude info || true

verify-aws-toolkit:
	@docker run --rm $(IMAGE_NAME) pip3 show uv || echo "uv not installed"
	@docker run --rm $(IMAGE_NAME) pip3 show skills || echo "skills CLI not installed"
```

### 5. Enhance Entrypoint Script

Add AWS Agent Toolkit validation:

```bash
# After Gemini API key setup (after line 53)
# Verify AWS Agent Toolkit dependencies are available
if command -v uv &> /dev/null; then
  echo "✅ AWS MCP dependencies available (uv installed)"
else
  echo "⚠️  uv not found in PATH - AWS MCP may not work"
fi
```

---

## Installation Steps

### Step 1: Update Dockerfile
```bash
# Add MCP server installation to Dockerfile
```

### Step 2: Build new image
```bash
make rebuild
```

### Step 3: Create Claude configuration
```bash
# Copy Claude settings into the image
# or mount from host ~/.claude/ directory
```

### Step 4: Test the integration
```bash
make claude
# Inside Claude shell:
# Use AWS-aware commands like describing S3 buckets, listing EC2 instances, etc.
```

---

## What This Enables

With AWS Agent Toolkit MCP integration, Claude can:

✅ **AWS Service Access:**
- Query EC2 instances, S3 buckets, Lambda functions
- Create, modify, delete AWS resources (with proper IAM)
- Read logs from CloudWatch
- Query RDS databases
- Inspect VPC, security groups, IAM policies

✅ **Integration with agy (Antigravity/Gemini):**
- Use AWS data with Google Gemini via agy
- Cross-cloud AI operations

✅ **Development Workflows:**
- Infrastructure as Code (CDK already installed)
- Troubleshooting AWS issues with AI assistance
- Cost analysis and optimization

---

## Testing & Validation

### Test 1: MCP Server Loads
```bash
make claude
claude> # Try invoking AWS-related commands
```

### Test 2: Credentials Work
```bash
make claude
claude> # AWS operations should use your SSO credentials
```

### Test 3: Cross-Tool Integration
```bash
make antigravity
# agy can use Claude's AWS context for multi-cloud operations
```

---

## Security Considerations

✅ **Already Covered:**
- Credentials via SSO (no hardcoded keys)
- Temporary credentials with session tokens
- SSH keys mounted as read-only
- API keys fetched from Secrets Manager at runtime

⚠️ **Best Practices to Maintain:**
- Never commit `.env` files with credentials
- Use IAM roles/policies to scope AWS access
- Rotate credentials regularly
- Review MCP permissions (they can be restrictive)

---

## Next Steps

1. **Review this analysis** - confirm the approach aligns with your needs
2. **Update Dockerfile** - add AWS Agent Toolkit MCP server installation
3. **Create `.claude/settings.json`** - configure MCP server and permissions
4. **Rebuild image** - `make rebuild`
5. **Test integration** - `make claude` and verify AWS commands work
6. **Document in team wiki** - share setup with teammates

---

## Files Affected

- `Dockerfile` - add MCP server installation
- `.claude/settings.json` - new file with MCP configuration
- `entrypoint.sh` - optional enhancement for validation
- `Makefile` - optional diagnostic targets

**Total impact:** Minimal, additive changes. No breaking changes to existing setup.
