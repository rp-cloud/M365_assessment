. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running Identity Management controls..."

$Global:AuditSummary = @()

$TotalControls = 5
$CurrentControl = 0

$Users = Get-CachedUsers
$SignIns30 = Get-CachedSignIns -Days 30
$AccessReviews = @(Get-CachedAccessReviewDefinitions)
$AuthorizationPolicy = Get-CachedAuthorizationPolicy
$AccessReviewAvailability = Get-AuditFirstUnavailableState -Keys @("AccessReviewDefinitions")
$UsersAvailability = Get-AuditFirstUnavailableState -Keys @("Users")
$SignInsAvailability = Get-AuditFirstUnavailableState -Keys @("SignIns_30")
$AuthPolicyAvailability = Get-AuditFirstUnavailableState -Keys @("AuthorizationPolicy")

$ActiveUsers30 = @($SignIns30 | Where-Object { $_.UserPrincipalName } | Select-Object -ExpandProperty UserPrincipalName -Unique)
$InternalUsers = @($Users | Where-Object { $_.UserType -eq "Member" })

############################################################
# AAD.IM.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IM.01 Inactive internal accounts"

$InactiveUsers = @(
    $InternalUsers |
    Where-Object { $_.UserPrincipalName -notin $ActiveUsers30 } |
    Select-Object DisplayName, UserPrincipalName, AccountEnabled, OnPremisesSyncEnabled, CreatedDateTime
)

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IM.01" -AvailabilityState $UsersAvailability
}
elseif ($SignInsAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IM.01" -AvailabilityState $SignInsAvailability
}
else {
    Export-ControlResult -ControlID "AAD.IM.01" -Data $InactiveUsers -Result "$($InactiveUsers.Count) internal member accounts show no sign-in activity in the last 30 days" -Status $(if ($InactiveUsers.Count -eq 0) { "PASS" } else { "WARNING" })
}

############################################################
# AAD.IM.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IM.02 Identity lifecycle governance"

$LifecycleData = @(
    [PSCustomObject]@{
        Verification = "Manual"
        Scope        = "Identity lifecycle and entitlement governance"
        Evidence     = "Review joiner-mover-leaver process, deprovisioning evidence and entitlement ownership"
    }
)

Export-ControlResult -ControlID "AAD.IM.02" -Data $LifecycleData -Result "Manual verification required for lifecycle and entitlement governance process" -Status "MANUAL"

############################################################
# AAD.IM.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IM.03 Access reviews"

if ($AccessReviewAvailability -and (Test-AuditUnavailableStatus -Status $AccessReviewAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IM.03" -Status $AccessReviewAvailability.Status -Reason $AccessReviewAvailability.Reason -Source $AccessReviewAvailability.Source
}
else {
    $AccessReviewData = @(
        $AccessReviews |
        Select-Object DisplayName, Id, Status, CreatedDateTime
    )

    $ManualAccessReviewData = if ($AccessReviewData.Count -gt 0) { $AccessReviewData } else {
        @(
            [PSCustomObject]@{
                Verification = "Manual"
                Scope        = "Periodic user access reviews"
                Evidence     = "No access review definitions returned; verify alternative recurring review process"
            }
        )
    }

    Export-ControlResult -ControlID "AAD.IM.03" -Data $ManualAccessReviewData -Result $(if ($AccessReviewData.Count -gt 0) { "$($AccessReviewData.Count) access review definitions found" } else { "No access review definitions found; manual verification required" }) -Status $(if ($AccessReviewData.Count -gt 0) { "WARNING" } else { "MANUAL" })
}

############################################################
# AAD.IM.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IM.04 Teams and M365 Groups access reviews"

if ($AccessReviewAvailability -and (Test-AuditUnavailableStatus -Status $AccessReviewAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IM.04" -Status $AccessReviewAvailability.Status -Reason $AccessReviewAvailability.Reason -Source $AccessReviewAvailability.Source
}
else {
    $GroupReviews = @(
        $AccessReviews |
        Where-Object {
            $_.Scope.ResourceType -eq "group" -or
            $_.DisplayName -match "Teams|Group|M365|Microsoft 365"
        } |
        Select-Object DisplayName, Id, Status, CreatedDateTime
    )

    Export-ControlResult -ControlID "AAD.IM.04" -Data $GroupReviews -Result "$($GroupReviews.Count) access review definitions found for Teams/Microsoft 365 groups" -Status $(if ($GroupReviews.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IM.05
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IM.05 Guest invite settings"

$InviteSettingData = @(
    [PSCustomObject]@{
        AllowInvitesFrom = $AuthorizationPolicy.AllowInvitesFrom
        Compliant        = if ($AuthorizationPolicy.AllowInvitesFrom -eq "adminsAndMembers") { "Yes" } else { "No" }
    }
)

if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IM.05" -AvailabilityState $AuthPolicyAvailability
}
else {
    Export-ControlResult -ControlID "AAD.IM.05" -Data $InviteSettingData -Result "Guest invite setting is '$($AuthorizationPolicy.AllowInvitesFrom)'" -Status $(if ($AuthorizationPolicy.AllowInvitesFrom -eq "adminsAndMembers") { "PASS" } else { "FAIL" })
}

Export-SummaryReport "IdentityManagement"

Write-Host "Identity Management audit completed."




