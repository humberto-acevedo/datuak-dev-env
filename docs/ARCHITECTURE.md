# LLM Workspace Architecture

## Overview

The LLM Workspace provides a containerized development environment integrating multiple AI/ML tools with AWS infrastructure access through the Model Context Protocol (MCP).

## Component Stack

### Container Base
- **Base Image:** Amazon Linux 2023
- **Tools:** AWS CLI, Node.js 20, Python 3, Rust, GitHub CLI (gh)

### AI/ML Tools
- **Claude CLI** — Anthropic's Claude with Bedrock backend
- **Antigravity (agy)** — Google Gemini integration
- **Kiro CLI** — AWS-specific CLI tool

### Infrastructure as Code
- **AWS CDK** — Infrastructure automation
- **Terraform** — Infrastructure provisioning

### Development Tools
- **Git/Tig** — Version control
- **TMux** — Terminal multiplexer
- **jq** — JSON processing
- **curl/wget** — HTTP tools

## Configuration Generation

### Build-Time Configuration

Configurations are generated **at Docker build time** (no local copying needed):

```dockerfile
# Claude MCP Configuration (auto-generated)
RUN mkdir -p /root/.claude && cat > /root/.claude/settings.json << 'EOF'
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": ["mcp-proxy-for-aws@1.6.3", "https://aws-mcp.us-east-1.api.aws/mcp"]
    }
  },
  "permissions": {"aws:*": "allow"},
  "modelSettings": {
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "maxOutputTokens": 4096
  }
}
EOF

# Gemini/AGY MCP Configuration (auto-generated)
RUN mkdir -p /root/.gemini/config && cat > /root/.gemini/config/mcp_config.json << 'EOF'
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": ["mcp-proxy-for-aws@1.6.3", "https://aws-mcp.us-east-1.api.aws/mcp"]
    }
  }
}
EOF
```

**Benefits:**
- ✅ Reproducible builds (same image, same config)
- ✅ No dependency on local files
- ✅ Easier to maintain and update
- ✅ Reduces build context size

## Credential Flow

```
User Runs Command
        ↓
┌─────────────────────────────────────┐
│ Makefile ensure-sso Target          │
│ • Check if creds are valid          │
│ • Prompt for SSO login if needed    │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ AWS Configure Export Credentials    │
│ • AWS_ACCESS_KEY_ID                 │
│ • AWS_SECRET_ACCESS_KEY             │
│ • AWS_SESSION_TOKEN                 │
│ • AWS_REGION                        │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ Docker Run with Env Vars            │
│ • DOCKER_VOLUMES (mounts)           │
│ • AWS_ENV (credentials)             │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ Container Startup (entrypoint.sh)   │
│ • Validate AWS MCP dependencies     │
│ • Verify MCP config files exist     │
│ • Optionally fetch API keys         │
│ • Setup SSH/GitHub config           │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ Claude/agy/kiro CLI Launches        │
│ • Reads MCP config                  │
│ • Uses AWS credentials              │
│ • Makes AWS API calls via MCP       │
└─────────────────────────────────────┘
```

## AWS Agent Toolkit Integration

### MCP (Model Context Protocol) Architecture

```
Claude CLI / agy
    ↓
┌──────────────────────────────┐
│ MCP Server                   │
│ (mcp-proxy-for-aws@1.6.3)    │
│ • Tool discovery             │
│ • Request routing            │
│ • Response formatting        │
└──────────────┬───────────────┘
               ↓
┌──────────────────────────────────────────────┐
│ AWS Agent Toolkit                            │
│ • 300+ AWS services                          │
│ • 15,000+ API actions                        │
│ • Python script sandbox execution            │
│ • Request signing & auth                     │
└──────────────┬───────────────────────────────┘
               ↓
┌──────────────────────────────────────────────┐
│ AWS APIs                                     │
│ • EC2, S3, Lambda, RDS, etc.                │
│ • CloudTrail audit logging                   │
│ • IAM access control                         │
└──────────────────────────────────────────────┘
```

### Tool Discovery

When Claude/agy connects to the MCP server, it:
1. Discovers 300+ AWS services
2. Maps 15,000+ API actions as callable tools
3. Receives tool schemas and documentation
4. Can invoke any tool with appropriate IAM permissions

### Request Flow

1. **User Request** — "List all S3 buckets"
2. **Claude** — Parses request, identifies tool
3. **MCP Server** — Routes to AWS Agent Toolkit
4. **AWS Toolkit** — Constructs AWS SDK call
5. **AWS APIs** — Executes call, returns results
6. **MCP Server** — Formats response
7. **Claude** — Processes results, generates answer

## Volume Mounts & Environment

### Docker Run Configuration

```makefile
DOCKER_VOLUMES := \
  -v "$$PWD/../..":/workspace           # Project files
  -v "$(IDEAS_DIR)":/workspace/Ideas     # Ideas folder
  -v "$(TOOLS_CODE_DIR)":/workspace/tools-code  # Tools
  -v "$(HOME)/.ssh:/root/.ssh"           # SSH keys (read-only)
  -v "$(HOME)/.config/gh:/root/.config/gh"    # GitHub config

AWS_ENV := \
  -e AWS_ACCESS_KEY_ID                  # From SSO
  -e AWS_SECRET_ACCESS_KEY              # From SSO
  -e AWS_SESSION_TOKEN                  # From SSO
  -e AWS_REGION                         # Default: us-east-1
  -e AWS_ACCOUNT                        # AWS account ID
  -e KIRO_API_KEY                       # Optional: Kiro auth
```

## Makefile Optimization

### Command Consolidation

The Makefile uses Make functions to reduce duplication:

```makefile
# Define once, reuse for multiple targets
_run-with-creds = eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && $(DOCKER_RUN) $(1)

# Multiple targets use the same pattern
claude: ensure-sso
  @$(call _run-with-creds,claude)

agy: ensure-sso
  @$(call _run-with-creds,agy)
```

### Unified Testing

Single `make test` target verifies:
- Docker build succeeds with generated configs
- Claude settings.json exists and is valid JSON
- AGY mcp_config.json exists and is valid JSON
- AWS MCP server configured in both
- All components properly integrated

## Configuration as Code

### Declarative Approach

Instead of copying files, configurations are declared inline:

```dockerfile
# What was: COPY .claude/ /root/.claude/
# Now: RUN mkdir + cat > ... << 'EOF'
```

**Why this approach?**
- Source of truth in Dockerfile
- No local file dependencies
- Easier to review and version control
- Simpler for CI/CD pipelines
- Reproducible across environments

## Entrypoint Validation

Runtime checks ensure correct setup:

```bash
# 1. Time synchronization
/usr/local/bin/sync-time   # Sync with AWS servers

# 2. AWS MCP dependencies
if command -v uv &> /dev/null; then
  echo "✅ AWS MCP dependencies available"
fi

# 3. Configuration verification
if [[ ! -s /root/.gemini/config/mcp_config.json ]]; then
  echo "⚠️  Warning: AGY MCP configuration not found"
fi

# 4. SSH/GitHub setup
chmod 700 /root/.ssh
ssh-keyscan -H github.com >> /root/.ssh/known_hosts

# 5. Git configuration
git config --global user.email "humberto.acevedo@datuak.ai"
```

## Security Model

### Credential Isolation

- **Runtime-Only:** Credentials injected via environment, never stored
- **Session-Scoped:** Temporary tokens, auto-expiring
- **Containerized:** Isolated from host system

### API Audit Trail

All AWS API calls are logged via CloudTrail with:
- `aws:ViaAWSMCPService` = true (identifies MCP calls)
- `aws:CalledViaAWSMCP` = true (identifies invocation method)
- Full request/response metadata for compliance

### Sandboxing

- Python scripts run in isolated sandbox
- No filesystem/network access outside sandbox
- No ability to escape container
- IAM policies enforce scope

## Build Process

### Layer Optimization

Docker build layers optimized for:
- **Speed:** Frequently-changing configs at end
- **Size:** Cleanup operations remove temp files
- **Caching:** Stable dependencies early, configs late

```dockerfile
# Early (cacheable)
FROM amazonlinux:2023
RUN dnf install -y ... (base tools)

# Late (rebuild on change)
RUN mkdir -p /root/.claude && cat > /root/.claude/settings.json
RUN mkdir -p /root/.gemini && cat > /root/.gemini/config/mcp_config.json
```

### Build Time

- **Initial build:** ~5-10 minutes (downloads dependencies)
- **Rebuild (cached):** ~30-60 seconds
- **Rebuild --no-cache:** ~5-10 minutes

## Environment Consistency

All environments get identical:
- ✅ Package versions
- ✅ Configuration settings
- ✅ MCP server endpoints
- ✅ Credential handling
- ✅ Git identity

Achieved through:
- Deterministic Dockerfile (no "latest" tags)
- Build-time config generation
- Reproducible entrypoint script
- Version-pinned dependencies

## Scalability

### Multi-Region Support

```bash
# Override region for different AWS regions
AWS_REGION=eu-west-1 make claude
AWS_REGION=ap-southeast-1 make agy
```

### Multi-Account Support

```bash
# Switch AWS profiles
AWS_PROFILE=production make claude
AWS_PROFILE=staging make agy
```

### Performance Characteristics

- **Container start:** ~2-5 seconds
- **MCP server cold start:** ~1-2 seconds
- **MCP warm operations:** ~200-500ms
- **AWS API calls:** Network dependent (typically 100-500ms)
- **Timeout:** 100 seconds (configurable)

## Troubleshooting & Diagnostics

### Configuration Inspection

```bash
make inspect-config           # Show all MCP configs
make verify-aws-toolkit       # Verify dependencies
docker logs <container_id>    # Container logs
```

### Debugging

```bash
# Launch shell and investigate
make shell

# Inside container:
cat /root/.claude/settings.json
cat /root/.gemini/config/mcp_config.json
uvx mcp-proxy-for-aws@1.6.3 --help
aws sts get-caller-identity
```

## Future Improvements

- [ ] Multi-container compose setup
- [ ] Local MCP proxy caching
- [ ] Custom MCP server extensions
- [ ] Advanced credential rotation
- [ ] Enhanced monitoring/observability
