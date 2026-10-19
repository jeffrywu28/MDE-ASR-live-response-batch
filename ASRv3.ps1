# Apply ASR Rules with Action: Block (or Audit for one rule)
$asrRules = @(
    @{Id="56a863a9-875e-4185-98a7-b882c64b5ce5"; Action="1"}
    @{Id="7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c"; Action="1"}
    @{Id="d4f940ab-401b-4efc-aadc-ad5f3c50688a"; Action="1"}
    @{Id="9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2"; Action="1"}
    @{Id="be9ba2d9-53ea-4cdc-84e5-9b1eeee46550"; Action="1"}
    @{Id="5beb7efe-fd9a-4556-801d-275e5ffc04cc"; Action="1"}
    @{Id="d3e037e1-3eb8-44c8-a917-57927947596d"; Action="1"}
    @{Id="3b576869-a4ec-4529-8536-b80a7769e899"; Action="1"}
    @{Id="75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84"; Action="1"}
    @{Id="26190899-1602-49e8-8b27-eb1d0a1ce869"; Action="1"}
    @{Id="e6db77e5-3df2-4cf1-b95a-636979351e5b"; Action="1"}
    @{Id="d1e49aac-8f56-4280-b9ba-993a6d77406c"; Action="1"}
    @{Id="b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4"; Action="1"}
    @{Id="a8f5898e-1dc8-49a9-9878-85004b8a61e6"; Action="1"}
    @{Id="92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b"; Action="1"}
    @{Id="c1db55ab-c21a-4637-bb3f-a12568109d35"; Action="1"}
    @{Id="01443614-cd74-433a-b99e-2ecdc07bfc25"; Action="2"}
)

# Apply ASR Rules
foreach ($rule in $asrRules) {
    Write-Host "Applying ASR Rule ID: $($rule.Id) with Action: $($rule.Action)"
    Add-MpPreference -AttackSurfaceReductionRules_Ids $rule.Id -AttackSurfaceReductionRules_Actions $rule.Action
}

# Verify Current ASR Configuration
$RulesIdsArray = Get-MpPreference | Select-Object -ExpandProperty AttackSurfaceReductionRules_Ids
$RulesActions  = Get-MpPreference | Select-Object -ExpandProperty AttackSurfaceReductionRules_Actions

# ASR Rule Descriptions Map
$asrDescriptions = @{
    "56a863a9-875e-4185-98a7-b882c64b5ce5" = "Block abuse of exploited vulnerable signed drivers"
    "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c" = "Block Adobe Reader from creating child processes"
    "d4f940ab-401b-4efc-aadc-ad5f3c50688a" = "Block all Office applications from creating child processes"
    "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2" = "Block credential stealing from lsass.exe"
    "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550" = "Block executable content from email client and webmail"
    "5beb7efe-fd9a-4556-801d-275e5ffc04cc" = "Block execution of potentially obfuscated scripts"
    "d3e037e1-3eb8-44c8-a917-57927947596d" = "Block JavaScript/VBScript from launching executables"
    "3b576869-a4ec-4529-8536-b80a7769e899" = "Block Office apps from creating executables"
    "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84" = "Block Office apps from injecting into other processes"
    "26190899-1602-49e8-8b27-eb1d0a1ce869" = "Block Office communication apps from child processes"
    "e6db77e5-3df2-4cf1-b95a-636979351e5b" = "Block persistence through WMI event subscription"
    "d1e49aac-8f56-4280-b9ba-993a6d77406c" = "Block process creations from PSExec and WMI"
    "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4" = "Block unsigned processes from USB"
    "a8f5898e-1dc8-49a9-9878-85004b8a61e6" = "Block Webshell creation for Servers"
    "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b" = "Block Win32 API calls from Office macros"
    "c1db55ab-c21a-4637-bb3f-a12568109d35" = "Use advanced protection against ransomware"
    "01443614-cd74-433a-b99e-2ecdc07bfc25" = "Block executables unless trusted/prevalent"
}

# Output Current Configuration with Descriptions
Write-Host "`n================= Current ASR Rule Configuration =================`n"
for ($i = 0; $i -lt $RulesIdsArray.Count; $i++) {
    $id = $RulesIdsArray[$i].ToLower()
    $actionCode = $RulesActions[$i]

    if ($asrDescriptions.ContainsKey($id)) {
        $ruleName = $asrDescriptions[$id]
    } else {
        $ruleName = "UNKNOWN ASR rule name"
    }

    switch ($actionCode) {
        0 { $action = "Disabled" }
        1 { $action = "Block" }
        2 { $action = "Audit" }
        6 { $action = "Warn" }
        default { $action = "Unknown" }
    }

    Write-Host "=> $id **$ruleName** Action: $action"
}
