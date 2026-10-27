# SSM Connection Fix — WorkSpace ws-ccwyrjx09

**Date:** 2026-10-10  
**Workspace:** `ws-ccwyrjx09` (`U-2KAQXKNADEN1B`, IP `172.16.0.84`)  
**User:** `humberto.acevedo`  
**Region:** `us-west-2`  
**Profile:** `AdministratorAccess-539247495490`

---

## Summary

The `start-and-connect.sh` script fails at Step 4 (SSM connect) because the workspace never appears in `aws ssm describe-instance-information`. The SSM agent is installed and running on the workspace but cannot obtain IAM credentials, so it never completes registration with the SSM service.

---

## Investigation Findings

### 1. Workspace is healthy

```
State    : AVAILABLE
OS       : Ubuntu 22.04
Bundle   : wsb-208l8k46h (PERFORMANCE)
Protocol : WSP
Subnet   : subnet-043ee8aed5df1ab8d  →  vpc-00bdde50562397717
```

### 2. Networking is fine

The workspace subnet has a direct internet gateway route:

| Destination   | Gateway                  |
|---------------|--------------------------|
| 172.16.0.0/16 | local                    |
| 0.0.0.0/0     | igw-0aad2c795ba571c26    |

No VPC endpoints for SSM are needed (and none are configured — that's fine given the IGW).

### 3. IAM role is correctly configured

`workspaces_DefaultRole` has `AmazonSSMManagedInstanceCore` attached as a managed policy.
This is the correct policy for SSM registration.

### 4. SSM agent is installed and running — but failing to get credentials

```
systemd unit : snap.amazon-ssm-agent.amazon-ssm-agent.service
Status       : active (running) since 2026-10-10 08:57:21 PDT
PID          : 929
```

Agent log errors:

```
ERROR EC2RoleProvider Failed to connect to ...  status code: 404
ERROR [CredentialRefresher] Retrieve crede...   status code: 400
```

### 5. Root cause

The SSM agent is attempting to obtain credentials via the **EC2 Instance Metadata Service (IMDS)** at `169.254.169.254`. WorkSpaces Personal on Ubuntu do not expose IMDS the same way EC2 instances do — the endpoint either doesn't respond or returns 404/400 for IAM credential requests.

Without credentials, the agent cannot authenticate to the SSM service and therefore never registers as a managed instance. This is why `InstanceInformationList` is always empty.

### 6. No hybrid activation exists

```
aws ssm describe-activations → ActivationList: []
```

The workspace has never been registered via hybrid activation.

---

## Proposed Fix

Register the workspace as an SSM **hybrid managed instance** using an activation code. This bypasses IMDS entirely and gives the agent explicit credentials to register with SSM.

### Step 1 — Create a hybrid activation (run on your Mac)

```bash
aws ssm create-activation \
  --profile AdministratorAccess-539247495490 \
  --region us-west-2 \
  --description "WorkSpace ws-ccwyrjx09 (U-2KAQXKNADEN1B)" \
  --iam-role workspaces_DefaultRole \
  --registration-limit 1 \
  --expiration-date "$(date -u -v+1d '+%Y-%m-%dT%H:%M:%SZ')" \
  --tags "Key=WorkspaceId,Value=ws-ccwyrjx09"
```

This returns:

```json
{
    "ActivationId": "<activation-id>",
    "ActivationCode": "<activation-code>"
}
```

Save both values — the activation code is shown only once.

### Step 2 — Re-register the SSM agent (run on the workspace)

```bash
# Stop the agent first
sudo snap stop amazon-ssm-agent

# Register using the activation credentials
sudo /snap/amazon-ssm-agent/current/amazon-ssm-agent -register \
  -code "<ActivationCode>" \
  -id "<ActivationId>" \
  -region us-west-2

# Restart the agent
sudo snap start amazon-ssm-agent
```

### Step 3 — Verify registration

On the workspace, confirm no more credential errors:

```bash
sudo journalctl -u snap.amazon-ssm-agent.amazon-ssm-agent.service -n 30 --no-pager
```

On your Mac, confirm the instance appears:

```bash
aws ssm describe-instance-information \
  --profile AdministratorAccess-539247495490 \
  --region us-west-2 \
  --query 'InstanceInformationList[*].{ID:InstanceId,Name:ComputerName,Ping:PingStatus}' \
  --output table
```

The instance will appear with an `mi-xxxxxxxxxx` ID (managed instance format).
The `start-and-connect.sh` script matches by `ComputerName`, so this format is handled automatically.

---

## Script Changes Made

`start-and-connect.sh` was updated alongside this investigation to handle delayed SSM registration more gracefully:

- Added `SSM_WAIT_TIMEOUT=300` (5 min) and `SSM_POLL_INTERVAL=15` to the defaults block.
- Extracted SSM matching logic into a reusable `_try_match_ssm_instance()` helper.
- Added a **Step 3 polling loop**: after the workspace reaches AVAILABLE, the script now retries SSM lookup every 15 seconds for up to 5 minutes before falling through to the manual prompt.
- Added `--ssm-timeout <seconds>` CLI flag to override the SSM wait duration.
- Manual instance selection is now Step 4 (fallback only if polling times out).

These changes mean that once the hybrid activation fix is applied, the script will handle normal SSM startup delays automatically on future runs.

---

## Notes

- The activation code expires after 1 day by default. If step 2 isn't completed in time, re-run step 1 to get a new code.
- Once registered, the hybrid activation itself can be deleted — registration is persistent in `/etc/amazon/ssm/registration` on the workspace.
- If the workspace is rebuilt or re-provisioned, steps 1–3 will need to be repeated.
- To make this permanent across rebuilds, consider adding the registration commands to a WorkSpaces bootstrap/provisioning script.
