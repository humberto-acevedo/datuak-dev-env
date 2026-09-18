# LLM Workspace Documentation

Datuak LLM development environment with Claude CLI, Antigravity (Gemini), and AWS Agent Toolkit integration.

## Quick Start

```bash
# Build the Docker image
make rebuild

# Verify all components
make verify-aws-toolkit

# Launch Claude CLI
make claude

# Launch Antigravity (AGY/Gemini)
make agy
```

## What's Included

| Tool | Purpose | Command |
|------|---------|---------|
| **Claude CLI** | Bedrock-based Claude with AWS MCP access | `make claude` |
| **Antigravity (agy)** | Google Gemini with AWS MCP access | `make agy` / `make antigravity` |
| **Kiro CLI** | AWS integration CLI | `make kiro` |
| **AWS CLI** | Command-line AWS access | `make shell` |

## Architecture

```
┌─────────────────────────────────────┐
│  Claude CLI / Antigravity (agy)     │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  MCP Server (mcp-proxy-for-aws)     │
│  • 300+ AWS services                │
│  • 15,000+ API actions              │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  AWS APIs (EC2, S3, Lambda, etc.)   │
│  • SSO credentials auto-refreshed   │
│  • CloudTrail audit logging         │
└─────────────────────────────────────┘
```

## Credentials & Security

**Automatic Credential Management:**
- SSO credentials auto-refresh via `ensure-sso` check
- Temporary session tokens (auto-expire)
- API keys fetched from AWS Secrets Manager at runtime
- No hardcoded credentials

**Audit & Compliance:**
- CloudTrail logs all AWS API calls with `aws:ViaAWSMCPService` flag
- All requests tagged for compliance auditing
- Python scripts run in isolated sandbox

## Key Commands

### Development
- `make build` — Build Docker image
- `make rebuild` — Force rebuild without cache
- `make test` — Run configuration tests
- `make clean` — Clean stopped containers
- `make ps` — List all containers

### Configuration
- `make inspect-config` — Show MCP configurations
- `make verify-aws-toolkit` — Verify all dependencies

### Interactive Tools
- `make claude` — Launch Claude CLI
- `make agy` — Launch Antigravity (Gemini)
- `make antigravity` — Alias for `agy`
- `make kiro` — Launch Kiro CLI
- `make shell` — Interactive bash shell

### Image Management
- `make save` — Export image to tar.gz
- `make load` — Import image from tar.gz

## Configuration Files

| File | Purpose |
|------|---------|
| **Dockerfile** | Generates Claude/AGY configs at build time |
| **Makefile** | Build, test, and launch targets |
| **entrypoint.sh** | Runtime initialization and validation |
| **.claude/settings.json** | Claude MCP server configuration (auto-generated) |
| **.gemini/config/mcp_config.json** | AGY MCP server configuration (auto-generated) |

## AWS Agent Toolkit Features

### What You Can Do

✅ **Infrastructure Discovery**
- List EC2 instances, S3 buckets, Lambda functions
- Query security groups, VPCs, IAM policies

✅ **Security Auditing**
- Find resources without encryption
- Identify IAM users without MFA
- Audit S3 bucket permissions

✅ **Cost Analysis**
- Identify under-utilized resources
- Analyze Lambda function costs
- Compare data transfer across regions

✅ **Troubleshooting**
- Query CloudWatch logs
- Debug Lambda functions
- Check deployment status

✅ **Multi-Cloud** (Claude + Gemini)
- Fetch AWS data, process with Gemini AI
- Cross-cloud compliance checking
- Auto-generate documentation

### Usage Examples

**List S3 buckets:**
```bash
make claude
> List all S3 buckets in my account
```

**Find untagged resources:**
```bash
make claude
> Find all EC2 instances without a 'project' tag
```

**Multi-cloud analysis:**
```bash
make agy
> Fetch my AWS infrastructure, then summarize with Gemini
```

## Environment Variables

Override defaults:

```bash
# Change AWS region
AWS_REGION=us-west-2 make claude

# Change AWS profile
AWS_PROFILE=staging make claude

# Set custom directories
IDEAS_DIR=/path/to/ideas TOOLS_CODE_DIR=/path/to/tools make claude
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "MCP server not connecting" | Run `make ensure-sso` then `make rebuild` |
| "AWS API calls failing" | Check IAM permissions; verify AWS region |
| "uv/skills not found" | Run `make rebuild` |
| "Claude not recognizing AWS" | Inside Claude: `/reload-plugins` then `/mcp restart` |
| "Credentials expired" | Run `make ensure-sso` before launching CLI |

## Performance

- **MCP cold start:** ~1-2 seconds
- **MCP warm start:** ~200-500ms
- **AWS API timeout:** 100 seconds (configurable)

## Security Best Practices

1. **Filter aggressively** — Don't query all resources
2. **Use tags to scope** — Tag resources for easier filtering
3. **Cache results** — Minimize redundant API calls
4. **Use CloudWatch Insights** — For efficient log filtering
5. **Review IAM policies** — Scope access to needed services

### Recommended IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*", "ec2:Describe*", "logs:FilterLogEvents"],
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

## Files & Locations

```
llm-environments/llm-workspace/
├── Dockerfile                    # Build configuration
├── Makefile                      # Build & launch targets
├── entrypoint.sh                 # Runtime initialization
├── .claude/
│   └── settings.json            # Claude MCP config (auto-generated)
├── .gemini/config/
│   └── mcp_config.json          # AGY MCP config (auto-generated)
├── docs/
│   ├── README.md                # This file
│   ├── ARCHITECTURE.md          # Detailed architecture
│   └── AWS_TOOLKIT_GUIDE.md     # AWS integration guide
└── manage-workspaces.sh         # Workspace management
```

## References

- [AWS Agent Toolkit](https://aws.amazon.com/products/developer-tools/agent-toolkit-for-aws/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [Claude CLI Documentation](https://claude.ai/claude-code)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)

## Support

1. Check troubleshooting section above
2. Review AWS CloudTrail logs for API failures
3. Verify credentials: `make ensure-sso`
4. Inspect configurations: `make inspect-config`
