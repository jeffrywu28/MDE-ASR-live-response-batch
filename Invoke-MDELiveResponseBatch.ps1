<#
.SYNOPSIS
    Runs "run ASRv3.ps1" through MDE Live Response on many devices, using a CSV
    with Hostname and (optionally) MachineId columns.

    - If MachineId is filled in, that ID is used (most reliable; handles duplicate hostnames).
    - If MachineId is empty, the device is looked up by hostname (most recently seen match).
    - Actions are submitted in throttled waves, then polled; results go to a CSV + per-device logs.

.EXAMPLE
    $env:MDE_CLIENT_SECRET = "<new-secret>"
    .\Invoke-MDELiveResponseBatch.ps1 -CsvPath .\devices.csv

.EXAMPLE
    # Hostname only, no CSV
    .\Invoke-MDELiveResponseBatch.ps1 -Hostnames abcd,defg
#>
[CmdletBinding(DefaultParameterSetName = 'Csv')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Csv')]   [string]$CsvPath,
    [Parameter(Mandatory, ParameterSetName = 'Names')] [string[]]$Hostnames,

    [string]$ScriptName      = 'ASRv3.ps1',
    [string]$ScriptArgs      = '',
    [string]$TenantId        = 'abcd-efgh-abcd-12356', #change here
    [string]$ClientId        = 'abcd-efgh-abcd-12356', #change here
    [int]$MaxConcurrent      = 20,     # API allows max 25 concurrent Live Response sessions
    [int]$SubmitDelaySeconds = 7,      # API limit: 10 Live Response calls per minute
    [int]$TimeoutMinutes     = 30,
    [int]$PollSeconds        = 30,
    [string]$OutputDir       = ".\LR_Results_$(Get-Date -Format yyyyMMdd_HHmmss)"
)

$ErrorActionPreference = 'Stop'
$ApiBase = 'https://api.security.microsoft.com/api'
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# ---------- Auth ----------
$secret = 'abcd-efgh-abcd-12356' #change here
if ([string]::IsNullOrWhiteSpace($secret)) {
    $sec = Read-Host 'Enter client secret' -AsSecureString
    $secret = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
              [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$script:TokenExpiry = [datetime]::MinValue
function Get-Headers {
    if ((Get-Date) -ge $script:TokenExpiry) {
        $t = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body @{
            client_id = $ClientId; client_secret = $secret; grant_type = 'client_credentials'
            scope = 'https://api.securitycenter.microsoft.com/.default' }
        $script:TokenExpiry = (Get-Date).AddSeconds($t.expires_in - 300)
        $script:Headers = @{ Authorization = "Bearer $($t.access_token)"; 'Content-Type' = 'application/json' }
    }
    $script:Headers
}

function Invoke-Api {
    param([string]$Uri, [string]$Method = 'Get', $Body)
    for ($i = 1; $i -le 4; $i++) {
        try {
            $p = @{ Uri = $Uri; Method = $Method; Headers = (Get-Headers) }
            if ($Body) { $p.Body = $Body }
            return Invoke-RestMethod @p
        } catch {
            $code = $_.Exception.Response.StatusCode.value__
            if ($code -eq 429 -and $i -lt 4) { Write-Warning 'Throttled (429), waiting 60s...'; Start-Sleep 60; continue }
            throw
        }
    }
}

function Resolve-Machine([string]$Name) {
    $short  = ($Name -split '\.')[0].ToLower().Replace("'", "''")
    $filter = [uri]::EscapeDataString("startswith(computerDnsName,'$short')")
    $found  = (Invoke-Api "$ApiBase/machines?`$filter=$filter").value |
        Where-Object { $_.computerDnsName -ieq $Name -or ($_.computerDnsName -split '\.')[0] -ieq $short } |
        Sort-Object lastSeen -Descending
    if (($found | Measure-Object).Count -gt 1) {
        Write-Warning "$Name matches $($found.Count) devices; using most recently seen ($($found[0].id))."
    }
    $found | Select-Object -First 1
}

# ---------- Build target list ----------
if ($PSCmdlet.ParameterSetName -eq 'Csv') {
    $targets = Import-Csv $CsvPath | ForEach-Object {
        [pscustomobject]@{ Hostname = $_.Hostname.Trim(); MachineId = "$($_.MachineId)".Trim() } }
} else {
    $targets = $Hostnames | ForEach-Object { [pscustomobject]@{ Hostname = $_.Trim(); MachineId = '' } }
}
$targets = $targets | Where-Object Hostname | Sort-Object Hostname, MachineId -Unique

$jobs = foreach ($t in $targets) {
    $r = [pscustomobject]@{ Hostname = $t.Hostname; MachineId = $t.MachineId; ActionId = ''
                            Status = 'Queued'; ExitCode = ''; Error = '' }
    if (-not $r.MachineId) {
        try {
            $m = Resolve-Machine $t.Hostname
            if ($m) { $r.MachineId = $m.id } else { $r.Status = 'NotFound'; $r.Error = 'Hostname not found in MDE' }
        } catch { $r.Status = 'LookupFailed'; $r.Error = $_.Exception.Message }
    }
    $r
}
Write-Host "[*] $($jobs.Count) targets, $(@($jobs | ? Status -eq 'Queued').Count) ready." -ForegroundColor Cyan

# ---------- Submit + poll loop ----------
$params = @(@{ key = 'ScriptName'; value = $ScriptName })
if ($ScriptArgs) { $params += @{ key = 'Args'; value = $ScriptArgs } }
$body = @{ Commands = @(@{ type = 'RunScript'; params = $params })
           Comment  = "Batch run of $ScriptName by $env:USERNAME" } | ConvertTo-Json -Depth 5

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$active   = { @($jobs | Where-Object { $_.Status -in 'Pending','InProgress' }) }

while ((@($jobs | ? Status -eq 'Queued').Count + (& $active).Count) -gt 0 -and (Get-Date) -lt $deadline) {

    # Submit while under concurrency cap
    foreach ($j in @($jobs | ? Status -eq 'Queued')) {
        if ((& $active).Count -ge $MaxConcurrent) { break }
        try {
            $a = Invoke-Api "$ApiBase/machines/$($j.MachineId)/runliveresponse" 'Post' $body
            $j.ActionId = $a.id; $j.Status = $a.status
            Write-Host "  [>] $($j.Hostname) sent to device, waiting ($($a.id))"
        } catch {
            $j.Status = 'SubmitFailed'
            $j.Error  = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
            Write-Warning "$($j.Hostname): $($j.Error)"
        }
        Start-Sleep $SubmitDelaySeconds
    }

    Start-Sleep $PollSeconds

    # Poll running actions
    foreach ($j in (& $active)) {
        try {
            $a = Invoke-Api "$ApiBase/machineactions/$($j.ActionId)"
            if ($a.status -eq 'Succeeded') {
                # The result file can be briefly unavailable (404) right after success: retry
                $res = $null; $lastErr = ''
                for ($k = 1; $k -le 4 -and -not $res; $k++) {
                    try {
                        $link = (Invoke-Api "$ApiBase/machineactions/$($j.ActionId)/GetLiveResponseResultDownloadLink(index=0)").value
                        $res  = Invoke-RestMethod -Uri $link
                    } catch { $lastErr = $_.Exception.Message; Start-Sleep 15 }
                }
                $j.Status = 'Succeeded'
                if ($res) {
                    $j.ExitCode = $res.exit_code
                    "$($res.script_output)`n--- ERRORS ---`n$($res.script_errors)" |
                        Set-Content (Join-Path $OutputDir "$($j.Hostname)_$($j.MachineId.Substring(0,8)).txt")
                    Write-Host "`n===== $($j.Hostname) =====" -ForegroundColor Green
                    if ("$($res.script_output)".Trim()) { Write-Host $res.script_output }
                    else { Write-Host '(no output)' -ForegroundColor DarkGray }
                    if ("$($res.script_errors)".Trim()) { Write-Host $res.script_errors -ForegroundColor Red }
                    Write-Host ''
                } else {
                    $j.Status = 'SucceededNoOutput'
                    $j.Error  = "Ran, but output could not be downloaded: $lastErr"
                    Write-Warning "$($j.Hostname): ran, but output download failed ($lastErr). Check Action center, action $($j.ActionId)"
                }
            } else {
                $j.Status = $a.status
            }
            if ($a.status -in 'Failed','Cancelled','TimeOut') {
                $j.Error = ($a.commands.errors | Where-Object { $_ }) -join '; '
                Write-Warning "$($j.Hostname): $($a.status) $($j.Error)"
            }
        } catch { Write-Warning "$($j.Hostname) poll error: $($_.Exception.Message)" }
    }
    $done = @($jobs | ? { $_.Status -notin 'Queued','Pending','InProgress' }).Count
    Write-Host "[*] Progress: $done / $($jobs.Count)" -ForegroundColor Cyan
}

foreach ($j in $jobs | ? { $_.Status -in 'Queued','Pending','InProgress' }) { $j.Error = "Not finished within $TimeoutMinutes min" }
$secret = $null

$summary = Join-Path $OutputDir 'summary.csv'
$jobs | Export-Csv $summary -NoTypeInformation
$jobs | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize
Write-Host "Summary: $summary" -ForegroundColor Yellow
