. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running Governance controls..."

$Global:AuditSummary = @()

$TotalControls = 7
$CurrentControl = 0

$Policies = @(Get-CachedCAPolicies)
$TermsOfUse = @(Get-CachedTermsOfUse)

############################################################
# AAD.GV.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.GV.01 Session governance"

$ReauthPolicies = @(
    $Policies |
    Where-Object { $_.SessionControls.SignInFrequency } |
    Select-Object DisplayName, State,
        @{Name = "SignInFrequency"; Expression = { $_.SessionControls.SignInFrequency.Value } },
        @{Name = "FrequencyType"; Expression = { $_.SessionControls.SignInFrequency.Type } }
)

Export-ControlResult -ControlID "AAD.GV.01" -Data $ReauthPolicies -Result "$($ReauthPolicies.Count) Conditional Access policies define sign-in frequency/session governance" -Status $(if ($ReauthPolicies.Count -gt 0) { "PASS" } else { "WARNING" })

############################################################
# AAD.GV.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.GV.02 Hybrid identity revocation"

$HybridInfo = @(
    [PSCustomObject]@{
        Verification = "Manual"
        Scope        = "Hybrid identity compromise process"
        Evidence     = "Verify incident response can revoke refresh tokens and reset passwords for synced identities"
    }
)

Export-ControlResult -ControlID "AAD.GV.02" -Data $HybridInfo -Result "Manual verification required for hybrid identity revocation process" -Status "MANUAL"

############################################################
# AAD.GV.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.GV.03 Inactive groups"

$LifecyclePolicies = @(Get-CachedGroupLifecyclePolicies)
$GroupGovernanceData = if ($LifecyclePolicies.Count -gt 0) {
    @(
        $LifecyclePolicies |
        Select-Object Id, GroupLifetimeInDays, ManagedGroupTypes,
            @{Name = "AlternateNotificationEmails"; Expression = { $_.AlternateNotificationEmails -join "," } }
    )
}
else {
    @(
        [PSCustomObject]@{
            Verification = "Manual"
            Scope        = "Inactive M365 groups and SharePoint sites"
            Evidence     = "No lifecycle policy returned; verify whether alternative governance exists"
        }
    )
}

Export-ControlResult -ControlID "AAD.GV.03" -Data $GroupGovernanceData -Result $(if ($LifecyclePolicies.Count -gt 0) { "$($LifecyclePolicies.Count) lifecycle policies found for group governance" } else { "No lifecycle policy found; manual review required for inactive groups/sites" }) -Status $(if ($LifecyclePolicies.Count -gt 0) { "WARNING" } else { "MANUAL" })

############################################################
# AAD.GV.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.GV.04 Service outage notifications"

$ServiceHealthInfo = @(
    [PSCustomObject]@{
        Verification = "Manual"
        Scope        = "Azure Service Health notifications"
        Evidence     = "Review configured notification emails/action groups for service outages"
    }
)

Export-ControlResult -ControlID "AAD.GV.04" -Data $ServiceHealthInfo -Result "Manual verification required for Azure Service Health notification recipients" -Status "MANUAL"

############################################################
# AAD.GV.05
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.GV.05 Users at risk alerts"

$RiskAlertInfo = @(
    [PSCustomObject]@{
        Verification = "Manual"
        Scope        = "Users at risk detected alerts"
        Evidence     = "Review alert recipient list and confirm no external identities are included"
    }
)

Export-ControlResult -ControlID "AAD.GV.05" -Data $RiskAlertInfo -Result "Manual verification required for 'Users at risk detected' alert recipients" -Status "MANUAL"

############################################################
# AAD.GV.06
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.GV.06 Terms of Use"

$TermsData = @(
    $TermsOfUse |
    Select-Object DisplayName, Id, CreatedDateTime, ModifiedDateTime
)

Export-ControlResult -ControlID "AAD.GV.06" -Data $TermsData -Result "$($TermsData.Count) Terms of Use documents found" -Status $(if ($TermsData.Count -gt 0) { "PASS" } else { "FAIL" })

############################################################
# AAD.GV.07
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.GV.07 Weekly digest recipients"

$WeeklyDigestInfo = @(
    [PSCustomObject]@{
        Verification = "Manual"
        Scope        = "Identity Protection weekly digest"
        Evidence     = "Review weekly digest recipients and confirm no external identities are included"
    }
)

Export-ControlResult -ControlID "AAD.GV.07" -Data $WeeklyDigestInfo -Result "Manual verification required for weekly digest recipients" -Status "MANUAL"

Export-SummaryReport "Governance"

Write-Host "Governance audit completed."

