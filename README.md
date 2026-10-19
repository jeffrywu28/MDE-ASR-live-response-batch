# MDE-ASR-live-response-batch

Push ASR rules to all your MDE devices in one batch, with no Intune or GPO needed. This PowerShell script runs your company's ASR policy script on every device through the MDE Live Response API, handles API limits, clears stuck actions and saves each device's output, so you never have to configure devices one by one. 

Note: This script is not limited to pushing ASR policies only. It is designed to be flexible and can be modified to support additional use cases based on operational needs. For example, in the event of a malware incident, it can be combined with KAPE deployment for forensic artifact collection. It can also be used to push custom remediation scripts or triage scripts in PowerShell (.ps1) format, enabling automated incident response, investigation, and remediation activities across affected endpoints.

---

## Who is this for?

- **No device management tool:** Teams that use Microsoft Defender for Endpoint but don't have Intune, GPO or another device management tool to deploy ASR rules.
- **Tired of manual work:** Admins who currently open a Live Response session and type `run ASRv3.ps1` on each device, one at a time.
- **Company-specific ASR policy:** Organizations that keep their ASR policy in their own PowerShell script and want every device to get exactly those rules.

The tool works with any script in the Live Response library, not only ASR scripts.

---

## Quick start

1. **Upload `ASRv3.ps1` to the Live Response library** in the Defender portal.
2. **Configure** `Invoke-MDELiveResponseBatch.ps1` with your tenant ID, client ID and secret.
3. **Prepare** `devices.csv` with your target devices.
4. **Run** `.\Invoke-MDELiveResponseBatch.ps1 -CsvPath .\devices.csv`.

---

## Features

- **Hostname or Machine ID targeting.** It uses a CSV of `Hostname,MachineId`. If `MachineId` is empty, the device is looked up by hostname. When a hostname matches more than one device, the most recently seen one is used.
- **Pending-action pre-check.** Before sending anything, the script finds actions that are still `Pending` or `InProgress` on the target devices and cancels them. Old actions like these are what cause `400 ActiveRequestAlreadyExists`.
- **Throttling-aware.** It stays under the API limits of 10 Live Response calls per minute and 25 concurrent sessions. When it gets `429` it waits a minute and retries.
- **Automatic token refresh** for long runs.
- **Live output.** Each device's script output (and errors, in red) is printed to the console as soon as that device finishes.
- **Result files.** It saves one `.txt` file per device plus a `summary.csv` with the status of every device.
- **Clear error messages.** It shows the real API error code and message instead of a generic `(400) Bad Request`.
- **Retry on result download.** It retries the download when the output isn't available yet and the API returns `404`.

---

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | Windows PowerShell 5.1 or PowerShell 7+ |
| Entra ID app registration | Application (not delegated) permissions on **WindowsDefenderATP**:<br>• `Machine.Read.All`<br>• `Machine.LiveResponse`<br>Admin consent granted. |
| Defender settings | **Settings → Endpoints → Advanced features**<br>• *Live Response* = On<br>• *Live Response unsigned script execution* = On (if your script is not signed) |
| Live Response library | `ASRv3.ps1` (or the script you want to run) must be uploaded to the library **before** you run the batch. |
| Devices | Onboarded to MDE and **online**. Live Response cannot reach offline devices. |

---

## Setup

### 1. Create the app registration
1. In **Entra ID → App registrations → New registration**, create an app.
2. Under **API permissions → Add a permission → APIs my organization uses → WindowsDefenderATP → Application permissions**, add `Machine.Read.All` and `Machine.LiveResponse`.
3. Click **Grant admin consent**.
4. Under **Certificates & secrets**, create a client secret and copy its **value**.

<img width="805" height="228" alt="image" src="https://github.com/user-attachments/assets/eb06ec8b-9552-4af7-a34d-bc501c5c639d" />

### 2. Upload `ASRv3.ps1` to the Live Response library
The batch script doesn't copy `ASRv3.ps1` to the devices itself. It tells each device to run the copy stored in your tenant's Live Response library, so the script must be there first.

1. In the Microsoft Defender portal, go to **Settings → Endpoints → Library management**.
2. Select **Upload**, then choose `ASRv3.ps1`.
3. Optionally add a file description (e.g. `Applies company ASR policy`).
4. If you're updating an existing version, select **Overwrite file**.
5. Select **Submit**. `ASRv3.ps1` now appears in the library list.

### 3. Configure the script
Set your tenant and app IDs in the script parameters, or pass them on the command line:

```powershell
[string]$TenantId = '<your-tenant-id>',
[string]$ClientId = '<your-app-client-id>',
$secret = "<your-secret-from-app-regist>"
```

### 4. Prepare the device list
Create `devices.csv`:

```csv
Hostname,MachineId
pc-001.contoso.com,abcdefghea9d52451f4e755cc4cc603d6a1ebd
pc-002.contoso.com,13af32b0abcdefghabc60a858043e7c8207a4d
```

- `MachineId` is optional, but recommended. It's the most reliable way to target a device, especially when two devices share a hostname (e.g. after a reimage).
- You can get machine IDs from the device page URL in the Defender portal (`/machines/v2/<MachineId>/overview`) or from the API.

---

## Usage

```powershell
# Run against a CSV
.\Invoke-MDELiveResponseBatch.ps1 -CsvPath .\devices.csv

# Run against hostnames directly
.\Invoke-MDELiveResponseBatch.ps1 -Hostnames pc-001,pc-002,pc-003

# Run a different library script
.\Invoke-MDELiveResponseBatch.ps1 -CsvPath .\devices.csv -ScriptName 'Collect-Logs.ps1'

# Skip the pending-action pre-check
.\Invoke-MDELiveResponseBatch.ps1 -CsvPath .\devices.csv -SkipPendingCheck
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-CsvPath` | — | CSV with `Hostname` and optional `MachineId` columns |
| `-Hostnames` | — | Hostnames to target (instead of a CSV) |
| `-ScriptName` | `ASRv3.ps1` | Script name in the Live Response library |
| `-ScriptArgs` | *(empty)* | Arguments passed to the script |
| `-TenantId` | — | Entra ID tenant ID |
| `-ClientId` | — | App registration client ID |
| `-MaxConcurrent` | `20` | Max devices with a running action at the same time (API max 25) |
| `-SubmitDelaySeconds` | `7` | Delay between submissions (keeps under 10 calls/min) |
| `-TimeoutMinutes` | `30` | Overall time limit for the run |
| `-PollSeconds` | `30` | How often to check action status |
| `-SkipPendingCheck` | off | Don't cancel old pending actions before submitting |
| `-OutputDir` | `.\LR_Results_<timestamp>` | Where results are saved |

---

## How it works

API endpoints used:

| Step | Endpoint |
|---|---|
| Token | `POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token` |
| Look up device | `GET /api/machines?$filter=startswith(computerDnsName,'...')` |
| Find pending actions | `GET /api/machineactions?$filter=status eq 'Pending'` |
| Cancel action | `POST /api/machineactions/{id}/cancel` |
| Run script | `POST /api/machines/{id}/runliveresponse` |
| Check status | `GET /api/machineactions/{id}` |
| Get output | `GET /api/machineactions/{id}/GetLiveResponseResultDownloadLink(index=0)` |

---

## Output
<img width="1515" height="847" alt="image" src="https://github.com/user-attachments/assets/41df1b48-b66f-402c-9eba-3ee2f9d8d255" />
<img width="415" height="146" alt="image" src="https://github.com/user-attachments/assets/3f74fd05-cfa2-4012-b651-cd63b10596a3" />



### Console
```
[*] 52 targets, 52 ready.
[*] Pre-check: looking for old pending/in-progress actions...
[!] Found 2 old action(s); cancelling...
  [x] pc-002 : cancelled LiveResponse 797d05b4-... (Pending, created 2026-10-19T02:30:11Z)
[*] Waiting 30s for cancellations to apply...
  [>] pc-001 sent to device, waiting (19b580a0-...)

===== pc-001 =====
<output printed by ASRv3.ps1>

[*] Progress: 12 / 52
```

### Files
```
LR_Results_20261019_093000/
├── pc-001_3b308892.txt     # script output + errors
├── pc-003_13af32b0.txt
└── summary.csv             # one row per device
```

### `summary.csv` status values

| Status | Meaning |
|---|---|
| `Succeeded` | Script ran and the output was downloaded |
| `SucceededNoOutput` | Script ran, but the output couldn't be downloaded. Check **Action center** using the action ID. |
| `Failed` / `Cancelled` / `TimeOut` | The action didn't finish on the device (often because the device is offline) |
| `SubmitFailed` | The API rejected the request (see the `Error` column) |
| `NotFound` | The hostname wasn't found in MDE |
| `Pending` / `InProgress` | Still running when `-TimeoutMinutes` was reached |

---

## Troubleshooting

| Problem | Likely cause / fix |
|---|---|
| `400 ActiveRequestAlreadyExists` | An old action is still pending on the device. Let the pre-check cancel it (don't use `-SkipPendingCheck`), or cancel it in **Action center**. |
| `400` with another message | Read the message: `ASRv3.ps1` may not be in the library (see [Setup step 2](#2-upload-asrv3ps1-to-the-live-response-library)), unsigned scripts may not be allowed, or Live Response may be off. |
| `403 Forbidden` | Missing `Machine.LiveResponse` / `Machine.Read.All`, or admin consent hasn't been granted. |
| `404` when downloading the result | The output isn't ready yet. The script retries this automatically. |
| `429 Too Many Requests` | API throttling. The script waits and retries. Lower `-MaxConcurrent` or raise `-SubmitDelaySeconds` if it keeps happening. |
| Many `Failed` / `TimeOut` | The devices are offline. Make a new CSV from the failed rows in `summary.csv` and run again later. |
| `(no output)` | The library script doesn't print anything. Add `Write-Output` to it. |

---

## Security notes

- **Live Response gives remote code execution on your endpoints.** Treat this app registration as highly privileged.
- **Store the client secret safely.** Keep it in a vault (Azure Key Vault, SecretManagement) or an environment variable, **never in the repo**. If you'd rather not use a secret, use a certificate credential.
- **Keep secrets short-lived.** Rotate secrets regularly and delete them right away if one is exposed.
- **Keep the pre-check scope in mind.** It cancels **any** pending action (scans, isolation, etc.) on the target devices, not only Live Response.
- **Check the audit trail.** Every action is recorded in **Action center** with the comment `Batch run of <script> by <user>`.
- **Don't commit internal data.** Add these to `.gitignore`:
  ```gitignore
  devices.csv
  retry.csv
  LR_Results_*/
  ```

---

## ASR rules applied by `ASRv3.ps1`

This section explains which **Attack Surface Reduction (ASR) rules** `ASRv3.ps1` applies, in which mode, and what to watch out for. It's based on Microsoft's [Attack surface reduction (ASR) rules reference](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference).

`ASRv3.ps1` is the library script that `Invoke-MDELiveResponseBatch.ps1` runs on every device through MDE Live Response. Upload it to the library first (see [Setup step 2](#2-upload-asrv3ps1-to-the-live-response-library)).

---

### What the script does

1. **Applies 17 ASR rules.** 16 are set to **Block**, and 1 is set to **Audit**.
2. **Reads back the configuration** from the device with `Get-MpPreference`.
3. **Prints every configured rule** with its GUID, name and mode, so the Live Response output shows exactly what is active on each device.

Example output:
```
================= Current ASR Rule Configuration =================

=> 56a863a9-875e-4185-98a7-b882c64b5ce5 **Block abuse of exploited vulnerable signed drivers** Action: Block
=> 01443614-cd74-433a-b99e-2ecdc07bfc25 **Block executables unless trusted/prevalent** Action: Audit
...
```

---

### Rule modes

| Value | Mode | Effect |
|---|---|---|
| `0` | Disabled | Rule is off |
| `1` | **Block** | Behavior is blocked and logged |
| `2` | **Audit** | Behavior is only logged, not blocked |
| `6` | Warn | Blocked, but the user can choose to allow it |

---

### Rules in this script

#### Standard protection rules
Microsoft recommends always enabling these three. You can usually turn them on in Block mode without testing in Audit first.

| GUID | Rule | Mode | Notes |
|---|---|---|---|
| `56a863a9-875e-4185-98a7-b882c64b5ce5` | Block abuse of exploited vulnerable signed drivers | Block | Stops new vulnerable drivers from being written. It doesn't unload drivers that are already loaded. |
| `9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2` | Block credential stealing from the Windows local security authority subsystem (lsass.exe) | Block | Has no Warn mode. |
| `e6db77e5-3df2-4cf1-b95a-636979351e5b` | Block persistence through WMI event subscription | Block | Not supported on Windows Server 2016 or 2012 R2. |

Check the reference page for the current rule list and status, because Microsoft adds rules over time.
https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference
---

## References

- [Run Live Response commands on a device (Microsoft Learn)](https://learn.microsoft.com/defender-endpoint/api/run-live-response)
- [Get Live Response result (Microsoft Learn)](https://learn.microsoft.com/defender-endpoint/api/get-live-response-result)
- [Cancel machine action (Microsoft Learn)](https://learn.microsoft.com/defender-endpoint/api/cancel-machine-action)
- [Manage the live response file library (Microsoft Learn)](https://learn.microsoft.com/en-us/defender-endpoint/configure-libraries-live-response)
- [Attack surface reduction (ASR) rules reference (Microsoft Learn)](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference)
- [ASR rules deployment guide (Microsoft Learn)](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-deployment)
- [Troubleshoot ASR rules (Microsoft Learn)](https://learn.microsoft.com/en-us/defender-endpoint/troubleshoot-asr)

---

## Disclaimer

Provided as-is, without warranty. Test on a small set of devices before running it across your fleet.
