# AWS Agent Toolkit Integration Guide

Complete guide to using AWS Agent Toolkit with Claude CLI and Antigravity (Gemini).

## Quick Setup

```bash
# 1. Build the image (first time or after changes)
make rebuild

# 2. Verify all components installed
make verify-aws-toolkit

# 3. Launch Claude CLI with AWS access
make claude

# 4. Test AWS commands
> List all S3 buckets in my account
> Show EC2 instances without a 'project' tag
> Find RDS databases without backups
```

## What's Enabled

The AWS Agent Toolkit provides Claude and agy with access to:

- **300+ AWS Services:** EC2, S3, Lambda, RDS, DynamoDB, CloudWatch, IAM, etc.
- **15,000+ API Actions:** Full AWS SDK capabilities
- **Sandboxed Execution:** Isolated Python script runtime
- **Audit Logging:** CloudTrail tracks all operations
- **Credential Management:** Automatic SSO integration

## Available Commands

### Infrastructure Discovery

**List resources:**
```
Claude> List all S3 buckets in the account
Claude> Show me all EC2 instances in us-east-1
Claude> Get all Lambda functions grouped by runtime
```

**Find patterns:**
```
Claude> Find all EC2 instances without a 'project' tag
Claude> Show S3 buckets that don't have encryption enabled
Claude> List IAM users that have never used their access keys
```

**Query data:**
```
Claude> Show RDS databases with less than 30 days backup retention
Claude> Get the top 10 most expensive Lambda functions by duration
Claude> Find security groups with public access (0.0.0.0/0)
```

### Security Auditing

```
Claude> Find all IAM users without MFA enabled
Claude> Show RDS instances without encryption
Claude> List S3 buckets with public ACLs
Claude> Identify VPCs with overly permissive security groups
```

### Cost Analysis

```
Claude> Show me the most expensive EC2 instances
Claude> Which Lambda functions are rarely invoked?
Claude> Compare data transfer costs across regions
Claude> Find stopped EC2 instances that are still accumulating charges
```

### Troubleshooting

```
Claude> Show CloudWatch logs for errors in the last 2 hours
Claude> Debug why this Lambda function is timing out
Claude> Check the deployment status of my application
Claude> What changed in my infrastructure in the last day?
```

### Multi-Cloud (Claude + Gemini)

```bash
# Launch Antigravity with AWS access
make agy
```

Then:
```
agy> Fetch my AWS S3 buckets and generate documentation for each
agy> Analyze my infrastructure costs and create a cost optimization report
agy> Find all unencrypted resources and create a remediation plan
```

## Configuration Details

### Claude Configuration (.claude/settings.json)

**MCP Server Setup:**
```json
{
  "command": "uvx",              // Use uv to run tools on-demand
  "timeout": 100000,             // 100 seconds (suitable for AWS operations)
  "transport": "stdio",          // Communication protocol
  "args": [
    "mcp-proxy-for-aws@1.6.3",   // AWS Agent Toolkit version
    "https://aws-mcp.us-east-1.api.aws/mcp",  // AWS endpoint
    "--metadata",
    "AWS_REGION=us-east-1"       // Default region
  ]
}
```

**Permissions:**
```json
{
  "permissions": {
    "aws:*": "allow"             // Allow all AWS operations
  }
}
```

**Model Settings:**
```json
{
  "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
  "smallFastModel": "global.anthropic.claude-sonnet-4-5-20250929-v1:0",
  "maxOutputTokens": 4096
}
```

### Antigravity Configuration (.gemini/config/mcp_config.json)

Similar setup for Gemini/agy:
```json
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": ["mcp-proxy-for-aws@1.6.3", "https://aws-mcp.us-east-1.api.aws/mcp", ...]
    }
  }
}
```

## Customization

### Change AWS Region

Option 1: Environment variable
```bash
AWS_REGION=us-west-2 make claude
```

Option 2: Edit configuration (apply globally)
Edit the Dockerfile to regenerate config with different region.

### Restrict Permissions

Make AWS access more restrictive for production:

```json
{
  "permissions": {
    "aws:iam": "deny",              // Deny IAM changes
    "aws:ec2:TerminateInstances": "deny",  // Deny instance termination
    "aws:ec2:Describe*": "allow",   // Allow EC2 read-only
    "aws:s3:Get*": "allow",         // Allow S3 read-only
    "aws:s3:List*": "allow"
  }
}
```

### Add IAM Policy Conditions

For maximum security, attach IAM policy with MCP conditions:

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

This ensures MCP calls are separately audited and can be restricted independently.

## Usage Patterns

### Pattern 1: Quick Queries

Ideal for one-off lookups:
```bash
make claude
> What are my top 5 most expensive RDS instances?
> [Claude returns analysis immediately]
```

### Pattern 2: Analysis & Investigation

Use Claude to investigate issues:
```bash
make claude
> My Lambda function is failing. Show me the errors from the last hour and suggest fixes.
```

Claude will:
1. Query CloudWatch logs
2. Parse the errors
3. Analyze the patterns
4. Suggest root causes
5. Recommend fixes

### Pattern 3: Automation Design

Have Claude design automation:
```bash
make claude
> Design an automated cost optimization system for my EC2 instances.
> What AWS services would you use? Create a detailed architecture.
```

### Pattern 4: Multi-Cloud Synthesis

Combine AWS data with Gemini analysis:
```bash
make agy
> Fetch my AWS account summary (costs, resource counts, security status),
> then create a executive summary for my team.
```

### Pattern 5: Compliance Checking

Automated compliance verification:
```bash
make claude
> Check our infrastructure against these compliance requirements:
> 1. All data at rest must be encrypted
> 2. All public resources must have logging
> 3. All databases must have backups
> Generate a compliance report.
```

## Performance Tuning

### Optimize Query Performance

**Filter by tag:**
```
Claude> Find all EC2 instances tagged with 'project=myapp'
# Faster than querying all instances
```

**Use region filtering:**
```
Claude> List S3 buckets in us-east-1 only
# Focused query, faster response
```

**Batch queries:**
```
Claude> Get EC2 instance count, storage usage, and cost for each region in one query
# Better than three separate queries
```

### Results Caching

Claude naturally caches results within a session:
```bash
make claude
> Get list of all EC2 instances
[Claude retrieves and displays]
> Now show which ones are in VPC-A
# Uses cached results, no new API call
```

### Timeout Configuration

Default 100-second timeout handles:
- ✅ Listing 1000s of resources
- ✅ Complex filtering operations
- ✅ Multi-step queries
- ✅ Report generation

For specific workloads, timeout can be adjusted in config.

## Troubleshooting

### "MCP server not connecting"

**Check 1: Verify uv is installed**
```bash
docker run --rm datuak-workspace pip3 show uv
```

**Check 2: Verify AWS credentials**
```bash
make ensure-sso
make claude
> help aws.iam
```

**Check 3: Test MCP proxy**
```bash
docker run --rm datuak-workspace bash -c \
  "uvx mcp-proxy-for-aws@1.6.3 https://aws-mcp.us-east-1.api.aws/mcp --help"
```

### "AWS API calls failing"

**Check 1: IAM permissions**
- Verify your IAM user/role has necessary permissions
- Check CloudTrail for denied actions

**Check 2: AWS region**
```bash
# Try a different region
AWS_REGION=us-west-2 make claude
```

**Check 3: Credentials expired**
```bash
# Refresh credentials
make ensure-sso
```

**Check 4: API throttling**
- Wait a few moments and retry
- AWS has rate limits; spread queries over time

### "Claude not recognizing AWS commands"

Inside Claude:
```
/reload-plugins
/mcp restart
```

Then try AWS command again.

### "Strange characters or encoding issues"

```bash
# Set proper terminal encoding
export LANG=en_US.UTF-8
make claude
```

## Best Practices

### 1. **Query Efficiently**
```
❌ Poor:  "List all resources in all regions"
✅ Good: "List all S3 buckets in us-east-1"
```

### 2. **Filter Early**
```
❌ Poor:  Get all EC2 instances, then filter manually
✅ Good: Use tags to pre-filter: "Find all EC2 with project=myapp"
```

### 3. **Use Structured Output**
```
❌ Poor:  Unstructured text reports
✅ Good: CSV/JSON tables for processing
```

### 4. **Document Queries**
```bash
# Good practice: save useful queries
# docs/useful-queries.md

## Find All Untagged EC2 Instances
make claude
> Find all EC2 instances that don't have a 'project' tag
```

### 5. **Review Sensitive Operations**
```
❌ Avoid: "Delete all unattached volumes"
✅ Better: "List all unattached volumes and ask for confirmation"
```

## Security Considerations

### ✅ Already Implemented

- **Credentials via SSO** — No hardcoded keys
- **Session tokens** — Temporary, auto-expiring
- **CloudTrail audit** — All operations logged
- **Sandboxed execution** — Python scripts isolated
- **SSH read-only** — Keys mounted as read-only

### ⚠️ Practices to Maintain

1. **Never commit credentials** — Check .env files
2. **Scope IAM policies** — Least privilege principle
3. **Rotate credentials regularly** — SSO handles this
4. **Review CloudTrail logs** — Audit operations
5. **Use MCP conditions** — Restrict MCP calls separately

### 🔒 Recommended Setup

1. Create dedicated IAM role for MCP
2. Attach policies with `aws:ViaAWSMCPService` condition
3. Enable CloudTrail logging with MCP tagging
4. Regular audit of API calls
5. Alert on suspicious patterns

## Examples by Use Case

### For DevOps

```bash
make claude

# Deployment verification
> Show me all EC2 instances deployed in the last 24 hours

# Scaling analysis  
> Which RDS instances are approaching capacity?

# Backup verification
> List all production databases and confirm backups are recent
```

### For Security

```bash
make claude

# Compliance checking
> Audit our infrastructure for encryption gaps

# Access review
> Show all IAM users and their last login time

# Network security
> Find security groups with overly permissive rules
```

### For Finance

```bash
make claude

# Cost analysis
> Show monthly spending by service for the last 6 months

# Optimization
> Identify resources that can be right-sized to save costs

# Forecasting
> Based on current usage, project next quarter's costs
```

### For Site Reliability

```bash
make claude

# Incident response
> My application is down. Show me recent CloudWatch logs and API calls

# Performance analysis
> Why is this Lambda function slow? Analyze execution patterns

# Capacity planning
> Project when we'll hit limits for each service
```

## Advanced Topics

### Cross-Account Access

To access multiple AWS accounts:
```bash
# Use different AWS profile for each account
AWS_PROFILE=account-1 make claude
AWS_PROFILE=account-2 make claude
```

### Custom IAM Roles

Scope MCP access per use case:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOnlyEC2",
      "Effect": "Allow",
      "Action": ["ec2:Describe*"],
      "Resource": "*",
      "Condition": {"StringEquals": {"aws:ViaAWSMCPService": "true"}}
    }
  ]
}
```

### Custom MCP Servers

Future enhancement: Add custom MCP servers alongside AWS:

```json
{
  "mcpServers": {
    "aws-mcp": { ... },
    "custom-api": { ... }
  }
}
```

## Support & Resources

- **AWS Agent Toolkit:** https://aws.amazon.com/products/developer-tools/agent-toolkit-for-aws/
- **MCP Protocol:** https://modelcontextprotocol.io/
- **Claude Documentation:** https://claude.ai/
- **AWS API Reference:** https://docs.aws.amazon.com/
- **CloudTrail Documentation:** https://docs.aws.amazon.com/cloudtrail/

## Next Steps

1. ✅ Run `make rebuild`
2. ✅ Run `make verify-aws-toolkit`
3. ✅ Run `make claude` and test AWS commands
4. 📖 Read docs/ARCHITECTURE.md for internals
5. 🔒 Set up IAM policies with MCP conditions
6. 📊 Create custom queries for your workflows
7. 🤖 Share workflows with team members
