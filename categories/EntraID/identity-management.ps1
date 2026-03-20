. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

function Get-AuditObjectValue {
    param(
        [Parameter(Mandatory)]
        $Object,
        [Parameter(Mandatory)]
        [string[]]$Path
    )

    $current = $Object

    foreach ($segment in $Path) {
        if ($null -eq $current) {
            return $null
        }

        if ($current -is [System.Collections.IDictionary] -and $current.Contains($segment)) {
            $current = $current[$segment]
            continue
        }

        if ($current.PSObject.Properties.Name -contains $segment) {
            $current = $current.$segment
            continue
        }

        if (($current.PSObject.Properties.Name -contains 'AdditionalProperties') -and $current.AdditionalProperties) {
            $additional = $current.AdditionalProperties
            if ($additional -is [System.Collections.IDictionary] -and $additional.Contains($segment)) {
                $current = $additional[$segment]
                continue
            }
        }

        return $null
    }

    return $current
}

function Get-AccessReviewAssessment {
    param(
        [Parameter(Mandatory)]
        $Review
    )

    $displayName = Get-AuditObjectValue -Object $Review -Path @('DisplayName')
    $reviewId = Get-AuditObjectValue -Object $Review -Path @('Id')
    $status = Get-AuditObjectValue -Object $Review -Path @('Status')
    $createdDateTime = Get-AuditObjectValue -Object $Review -Path @('CreatedDateTime')

    $scopeResourceType = Get-AuditObjectValue -Object $Review -Path @('Scope', 'ResourceType')
    $scopeQuery = Get-AuditObjectValue -Object $Review -Path @('Scope', 'Query')
    $scopeQueryType = Get-AuditObjectValue -Object $Review -Path @('Scope', 'QueryType')
    $instanceEnumerationScope = Get-AuditObjectValue -Object $Review -Path @('InstanceEnumerationScope')

    $reviewers = @(Get-AuditObjectValue -Object $Review -Path @('Reviewers'))
    $reviewersCount = $reviewers.Count

    $recurrencePattern = Get-AuditObjectValue -Object $Review -Path @('Settings', 'Recurrence', 'Pattern', 'Type')
    $recurrenceRangeType = Get-AuditObjectValue -Object $Review -Path @('Settings', 'Recurrence', 'Range', 'Type')
    $recurrenceConfigured = ($null -ne $recurrencePattern) -or ($null -ne $recurrenceRangeType)

    $looksGroupScoped =
        $scopeResourceType -eq 'group' -or
        $scopeQueryType -match 'MicrosoftGraph' -or
        $scopeQuery -match 'group' -or
        $instanceEnumerationScope -match 'group' -or
        $displayName -match 'Teams|Group|M365|Microsoft 365|SharePoint'

    $statusText = if ($status) { [string]$status } else { 'Unknown' }
    $statusIndicatesDisabled = $statusText -match 'disable|inactive'

    [PSCustomObject]@{
        DisplayName          = $displayName
        Id                   = $reviewId
        Status               = $statusText
        CreatedDateTime      = $createdDateTime
        ScopeResourceType    = $scopeResourceType
        ScopeQueryType       = $scopeQueryType
        ScopeQuery           = $scopeQuery
        InstanceScope        = $instanceEnumerationScope
        ReviewersCount       = $reviewersCount
        RecurrenceConfigured = if ($recurrenceConfigured) { 'Yes' } else { 'No' }
        GroupScoped          = if ($looksGroupScoped) { 'Yes' } else { 'No' }
        IsQualifiedGeneral   = if ($recurrenceConfigured -and -not $statusIndicatesDisabled) { 'Yes' } else { 'No' }
        IsQualifiedGroup     = if ($looksGroupScoped -and $recurrenceConfigured -and -not $statusIndicatesDisabled) { 'Yes' } else { 'No' }
    }
}

Write-Host "Running Identity Management controls..."

$Global:AuditSummary = @()

$TotalControls = 5
$CurrentControl = 0

$Users = Get-CachedUsers
$SignIns30 = Get-CachedSignIns -Days 30 -Top 40000
$AccessReviews = @(Get-CachedAccessReviewDefinitions)
$AuthorizationPolicy = Get-CachedAuthorizationPolicy
$AccessReviewAvailability = Get-AuditFirstUnavailableState -Keys @("AccessReviewDefinitions")
$UsersAvailability = Get-AuditFirstUnavailableState -Keys @("Users")
$SignInsAvailability = Get-AuditFirstUnavailableState -Keys @("SignIns_30_Top40000")
$AuthPolicyAvailability = Get-AuditFirstUnavailableState -Keys @("AuthorizationPolicy")

$ActiveUsers30 = @($SignIns30 | Where-Object { $_.UserPrincipalName } | Select-Object -ExpandProperty UserPrincipalName -Unique)
$InternalUsers = @($Users | Where-Object { $_.UserType -eq "Member" })
$AccessReviewAssessments = @($AccessReviews | ForEach-Object { Get-AccessReviewAssessment -Review $_ })

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
    Export-ControlResult -ControlID "AAD.IM.01" -Data $InactiveUsers -Result "$($InactiveUsers.Count) internal member accounts show no sign-in activity in the last 30 days" -Status $(if ($InactiveUsers.Count -eq 0) { "PASS" } else { "FAIL" })
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

$QualifiedAccessReviews = @($AccessReviewAssessments | Where-Object { $_.IsQualifiedGeneral -eq 'Yes' })

if ($AccessReviewAvailability -and (Test-AuditUnavailableStatus -Status $AccessReviewAvailability.Status)) {
    Export-ControlResult -ControlID "AAD.IM.03" -Data @(
        [PSCustomObject]@{
            Verification = "Manual"
            Scope        = "Periodic user access reviews"
            Evidence     = "Access review definitions could not be retrieved automatically from the tenant"
        }
    ) -Result "Manual verification required for periodic access review process" -Status "MANUAL"
}
else {
    Export-ControlResult -ControlID "AAD.IM.03" -Data $AccessReviewAssessments -Result "$($QualifiedAccessReviews.Count) recurring access review definitions found" -Status $(if ($QualifiedAccessReviews.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IM.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IM.04 Teams and M365 Groups access reviews"

$GroupReviews = @($AccessReviewAssessments | Where-Object { $_.GroupScoped -eq 'Yes' })
$QualifiedGroupReviews = @($GroupReviews | Where-Object { $_.IsQualifiedGroup -eq 'Yes' })

if ($AccessReviewAvailability -and (Test-AuditUnavailableStatus -Status $AccessReviewAvailability.Status)) {
    Export-ControlResult -ControlID "AAD.IM.04" -Data @(
        [PSCustomObject]@{
            Verification = "Manual"
            Scope        = "Teams and Microsoft 365 Groups access reviews"
            Evidence     = "Access review definitions could not be retrieved automatically from the tenant"
        }
    ) -Result "Manual verification required for Teams and Microsoft 365 Groups access review process" -Status "MANUAL"
}
else {
    Export-ControlResult -ControlID "AAD.IM.04" -Data $GroupReviews -Result "$($QualifiedGroupReviews.Count) recurring Teams or Microsoft 365 Groups access review definitions found" -Status $(if ($QualifiedGroupReviews.Count -gt 0) { "PASS" } else { "FAIL" })
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
