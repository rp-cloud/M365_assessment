. "$PSScriptRoot\..\..\modules\reporting.ps1"
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

Export-ControlResult -ControlID "AAD.AR.01" -Data $FailureData -Result "$($FailureData.Count) failed sign-ins in the last 30 days" -Status $(if ($FailureData.Count -eq 0) { "PASS" } else { "WARNING" })

############################################################
# AAD.AR.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.02 Multiple geographies"

$GeoData = @(
    $SignIns |
    Where-Object { $_.UserPrincipalName -and $_.Location.CountryOrRegion } |
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

Export-ControlResult -ControlID "AAD.AR.02" -Data $GeoData -Result "$($GeoData.Count) users signed in from multiple geographies in the last 30 days" -Status $(if ($GeoData.Count -eq 0) { "PASS" } else { "WARNING" })

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

Export-ControlResult -ControlID "AAD.AR.03" -Data $Assignments -Result "$($Assignments.Count) current directory role assignments exported for review" -Status "INFO"

############################################################
# AAD.AR.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.AR.04 Risky sign-ins"

try {
    $RiskyData = @(
        Get-MgRiskySignIn -Filter "createdDateTime ge $((Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))" -All |
        Select-Object UserDisplayName, UserPrincipalName, RiskLevel, RiskState, RiskDetail, CreatedDateTime
    )
    $AR04Status = if ($RiskyData.Count -eq 0) { "PASS" } else { "WARNING" }
    $AR04Result = "$($RiskyData.Count) risky sign-ins detected in the last 30 days"
}
catch {
    $RiskyData = @(
        [PSCustomObject]@{
            Message = "Unable to read risky sign-ins through Microsoft Graph."
        }
    )
    $AR04Status = "MANUAL"
    $AR04Result = "Risky sign-ins could not be retrieved automatically"
}

Export-ControlResult -ControlID "AAD.AR.04" -Data $RiskyData -Result $AR04Result -Status $AR04Status

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

Export-ControlResult -ControlID "AAD.AR.05" -Data $Guests -Result "$($Guests.Count) guest accounts exported for monthly review" -Status "INFO"

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

Export-ControlResult -ControlID "AAD.AR.06" -Data $PrivAssignments -Result "$($PrivAssignments.Count) non-global privileged role assignments exported for review" -Status "INFO"

Export-SummaryReport "AAD_AlertingReporting"

Write-Host "Alerting & Reporting audit completed."

