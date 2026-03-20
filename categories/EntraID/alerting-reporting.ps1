. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running AAD Alerting & Reporting checks..."

$Global:AuditSummary = @()

$TotalControls = 6
$CurrentControl = 0

$Users = Get-CachedUsers
$UsersById = Get-CachedUsersById
$Roles = Get-CachedRoles
$RoleMembers = Get-CachedRoleMembers
$SignIns = Get-CachedSignIns -Days 30 -Top 40000
$UsersAvailability = Get-AuditFirstUnavailableState -Keys @("Users")
$RolesAvailability = Get-AuditFirstUnavailableState -Keys @("Roles")
$SignInsAvailability = Get-AuditFirstUnavailableState -Keys @("SignIns_30_Top40000")

############################################################
# AAD.AR.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.01 Sign-in failures"

$FailureData = @(
    $SignIns |
    Where-Object { $_.Status.ErrorCode -ne 0 } |
    Select-Object UserPrincipalName, AppDisplayName, CreatedDateTime, IPAddress,
        @{Name = "Country"; Expression = { $_.Location.CountryOrRegion } },
        @{Name = "ErrorCode"; Expression = { $_.Status.ErrorCode } },
        @{Name = "FailureReason"; Expression = { $_.Status.FailureReason } }
)

if ($SignInsAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.AR.01" -AvailabilityState $SignInsAvailability
}
else {
    Export-ControlResult -ControlID "AAD.AR.01" -Data $FailureData -Result "$($FailureData.Count) failed sign-ins in the last 30 days" -Status "INFO"
}

############################################################
# AAD.AR.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.02 Multiple geographies"

$GeoData = @(
    $SignIns |
    Where-Object { $_.Location -and $_.Location.CountryOrRegion } |
    Group-Object UserPrincipalName |
    ForEach-Object {
        $Countries = @($_.Group.Location.CountryOrRegion | Sort-Object -Unique)

        if ($Countries.Count -gt 1) {
            [PSCustomObject]@{
                UserPrincipalName = $_.Name
                Countries         = $Countries -join ", "
                SignInCount       = $_.Count
            }
        }
    }
)

if ($SignInsAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.AR.02" -AvailabilityState $SignInsAvailability
}
else {
    Export-ControlResult -ControlID "AAD.AR.02" -Data $GeoData -Result "$($GeoData.Count) users signed in from multiple geographies in the last 30 days" -Status "INFO"
}

############################################################
# AAD.AR.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.03 Azure AD role assignments"

$Assignments = @(
    foreach ($Role in $Roles) {
        foreach ($Member in $RoleMembers[$Role.Id]) {
            $User = $UsersById[$Member.Id]

            [PSCustomObject]@{
                Role              = $Role.DisplayName
                DisplayName       = if ($User) { $User.DisplayName } else { "Unknown object" }
                UserPrincipalName = if ($User) { $User.UserPrincipalName } else { $null }
                UserType          = if ($User) { $User.UserType } else { $null }
                AccountEnabled    = if ($User) { $User.AccountEnabled } else { $null }
            }
        }
    }
)

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.AR.03" -AvailabilityState $UsersAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.AR.03" -AvailabilityState $RolesAvailability
}
else {
    Export-ControlResult -ControlID "AAD.AR.03" -Data $Assignments -Result "$($Assignments.Count) current directory role assignments exported for review" -Status "INFO"
}

############################################################
# AAD.AR.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.04 Risky sign-ins"

$AR04UnavailableHandled = $false

try {
    $RiskyData = @(
        Get-MgRiskySignIn -Filter "createdDateTime ge $((Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))" -All |
        Select-Object UserDisplayName, UserPrincipalName, RiskLevel, RiskState, RiskDetail, CreatedDateTime
    )
    $AR04Status = "INFO"
    $AR04Result = "$($RiskyData.Count) risky sign-ins detected in the last 30 days"
}
catch {
    $UnavailableStatus = Resolve-AuditUnavailableStatus -ErrorRecord $_

    if ($UnavailableStatus) {
        Export-ControlUnavailable `
            -ControlID "AAD.AR.04" `
            -Status $UnavailableStatus `
            -Reason "Risky sign-ins could not be retrieved automatically" `
            -Source "Get-MgRiskySignIn" `
            -ErrorRecord $_

        $AR04UnavailableHandled = $true
    }
    else {
        $RiskyData = @(
            [PSCustomObject]@{
                Message = "Unable to read risky sign-ins through Microsoft Graph."
            }
        )
        $AR04Status = "INFO"
        $AR04Result = "Risky sign-ins could not be retrieved automatically"
    }
}

if (-not $AR04UnavailableHandled) {
    Export-ControlResult -ControlID "AAD.AR.04" -Data $RiskyData -Result $AR04Result -Status $AR04Status
}

############################################################
# AAD.AR.05
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.05 External users inventory"

$Guests = @(
    $Users |
    Where-Object { $_.UserType -eq "Guest" } |
    Select-Object DisplayName, UserPrincipalName, AccountEnabled, CreatedDateTime
)

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.AR.05" -AvailabilityState $UsersAvailability
}
else {
    Export-ControlResult -ControlID "AAD.AR.05" -Data $Guests -Result "$($Guests.Count) guest accounts exported for monthly review" -Status "INFO"
}

############################################################
# AAD.AR.06
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.06 Non-global administrators"

$PrivAssignments = @(
    foreach ($Role in ($Roles | Where-Object { $_.DisplayName -ne "Global Administrator" })) {
        foreach ($Member in $RoleMembers[$Role.Id]) {
            $User = $UsersById[$Member.Id]

            if ($User) {
                [PSCustomObject]@{
                    Role              = $Role.DisplayName
                    DisplayName       = $User.DisplayName
                    UserPrincipalName = $User.UserPrincipalName
                    UserType          = $User.UserType
                    AccountEnabled    = $User.AccountEnabled
                }
            }
        }
    }
)

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.AR.06" -AvailabilityState $UsersAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.AR.06" -AvailabilityState $RolesAvailability
}
else {
    Export-ControlResult -ControlID "AAD.AR.06" -Data $PrivAssignments -Result "$($PrivAssignments.Count) non-global privileged role assignments exported for review" -Status "INFO"
}

Export-SummaryReport "AAD_AlertingReporting"

Write-Host "Alerting & Reporting audit completed."
