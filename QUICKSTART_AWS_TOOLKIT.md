# AWS Agent Toolkit Quick Start

## One-Liner Setup

```bash
make rebuild && make verify-aws-toolkit && make claude
```

## What You Can Do

```bash
# Inside Claude CLI
make claude

# Then try:
> List all S3 buckets
> Find EC2 instances without a 'environment' tag  
> Show me RDS databases that don't have backups
> Query CloudWatch for errors in the last hour
> Find IAM users without MFA enabled
```

## Verify Installation

```bash
make verify-aws-toolkit
```

Output should show:
- uv installed ✅
- skills CLI installed ✅
- MCP Server: mcp-proxy-for-aws@1.6.3

## Test with Antigravity

```bash
make antigravity

# Inside agy CLI, try:
> Fetch my AWS S3 bucket list, then create documentation
> Use AWS to find untagged resources, summarize with Gemini
```

## Credentials Auto-Refresh

The SSO flow handles credential management:

```bash
make claude         # Auto-refreshes if expired
make antigravity    # Auto-refreshes if expired  
make ensure-sso     # Manual refresh if needed
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "MCP server not connecting" | Run `make ensure-sso` then `make rebuild` |
| "AWS API calls failing" | Check IAM permissions or try different AWS region |
| "uv not found" | Run `make rebuild` |
| "Claude not recognizing AWS" | Inside Claude: `/reload-plugins` then `/mcp restart` |

## Configuration Files

- `.claude/settings.json` - Claude MCP configuration
- `.gemini/config/mcp_config.json` - Antigravity (AGY) MCP configuration
- `.claude/kiro-mcp-settings.json` - Kiro CLI MCP configuration
- `Dockerfile` - Installs uv + skills CLI and copies Claude/AGY configs
- `Makefile` - Diagnostic and inspection targets

## Key Settings

- **MCP Endpoint:** `https://aws-mcp.us-east-1.api.aws/mcp`
- **AWS Region:** `us-east-1` (override: `AWS_REGION=us-west-2 make claude`)
- **Timeout:** 100 seconds for long operations
- **Services:** 300+ AWS services available

## Next Steps

1. ✅ Run `make rebuild`
2. ✅ Run `make verify-aws-toolkit`
3. ✅ Run `make claude` and test AWS commands
4. 📖 Read `AWS_TOOLKIT_IMPLEMENTATION.md` for details
5. 🔒 Set up IAM policies with MCP conditions

## Full Documentation

- **Quick Reference:** This file
- **Implementation Guide:** `AWS_TOOLKIT_IMPLEMENTATION.md`
- **Architecture Review:** `AWS_AGENT_TOOLKIT_REVIEW.md`
- **Summary:** `AWS_TOOLKIT_SUMMARY.md`

---

**Ready?** `make rebuild` then `make claude` 🚀
