. "$PSScriptRoot\..\modules\reporting.ps1"
. "$PSScriptRoot\..\modules\cache.ps1"

Write-Host "Running Privileged Access controls..."

$Global:AuditSummary = @()

$TotalControls = 7
$CurrentControl = 0

$UsersById = Get-CachedUsersById
$Roles = @(Get-CachedRoles)
$RoleMembers = Get-CachedRoleMembers

$GARole = $Roles | Where-Object { $_.DisplayName -eq "Global Administrator" } | Select-Object -First 1
$GAUsers = @()

if ($GARole) {
    foreach ($Member in $RoleMembers[$GARole.Id]) {
        $User = $UsersById[$Member.Id]
        if ($User) {
            $GAUsers += [PSCustomObject]@{
                DisplayName          = $User.DisplayName
                UserPrincipalName    = $User.UserPrincipalName
                UserType             = $User.UserType
                AccountEnabled       = $User.AccountEnabled
                OnPremisesSyncEnabled = $User.OnPremisesSyncEnabled
                AssignedLicenses     = @($User.AssignedLicenses).Count
            }
        }
    }
}

############################################################
# AAD.PA.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.01 Global Administrator count"

Export-ControlResult -ControlID "AAD.PA.01" -Data $GAUsers -Result "$($GAUsers.Count) Global Administrator accounts found" -Status $(if ($GAUsers.Count -ge 2 -and $GAUsers.Count -le 4) { "PASS" } else { "FAIL" })

############################################################
# AAD.PA.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.02 Break Glass cloud-only"

$BreakGlassCandidates = @(
    $GAUsers |
    Where-Object {
        $_.AccountEnabled -eq $true -and
        $_.OnPremisesSyncEnabled -ne $true
    }
)

Export-ControlResult -ControlID "AAD.PA.02" -Data $BreakGlassCandidates -Result "$($BreakGlassCandidates.Count) cloud-only enabled Global Administrator accounts found as break-glass candidates" -Status $(if ($BreakGlassCandidates.Count -gt 0) { "WARNING" } else { "FAIL" })

############################################################
# AAD.PA.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.03 PIM usage"

try {
    $RoleDefinitions = @(Get-MgRoleManagementDirectoryRoleDefinition -All)
    $EligibilitySchedules = @(Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All)
}
catch {
    $RoleDefinitions = @()
    $EligibilitySchedules = @()
}

$EligibleUsers = @(
    foreach ($Schedule in $EligibilitySchedules) {
        $Role = $RoleDefinitions | Where-Object { $_.Id -eq $Schedule.RoleDefinitionId } | Select-Object -First 1
        $User = $UsersById[$Schedule.PrincipalId]

        if ($Role -and $User) {
            [PSCustomObject]@{
                DisplayName       = $User.DisplayName
                UserPrincipalName = $User.UserPrincipalName
                RoleName          = $Role.DisplayName
                AssignmentType    = "Eligible"
            }
        }
    }
)

Export-ControlResult -ControlID "AAD.PA.03" -Data $EligibleUsers -Result "$($EligibleUsers.Count) eligible role assignments found in PIM" -Status $(if ($EligibleUsers.Count -gt 0) { "PASS" } else { "FAIL" })

############################################################
# AAD.PA.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.04 Device Administrators"

$DeviceRole = $Roles | Where-Object { $_.DisplayName -eq "Azure AD Joined Device Local Administrator" } | Select-Object -First 1
$DeviceAdmins = @()

if ($DeviceRole) {
    foreach ($Member in $RoleMembers[$DeviceRole.Id]) {
        $User = $UsersById[$Member.Id]
        if ($User) {
            $DeviceAdmins += [PSCustomObject]@{
                DisplayName       = $User.DisplayName
                UserPrincipalName = $User.UserPrincipalName
                UserType          = $User.UserType
                AccountEnabled    = $User.AccountEnabled
            }
        }
    }
}

Export-ControlResult -ControlID "AAD.PA.04" -Data $DeviceAdmins -Result "$($DeviceAdmins.Count) users are assigned to the Device Administrator role" -Status $(if ($DeviceAdmins.Count -eq 0) { "PASS" } else { "WARNING" })

############################################################
# AAD.PA.05
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.05 Privileged Access Workstations"

$PAWInfo = @(
    [PSCustomObject]@{
        Verification = "Manual"
        Scope        = "Privileged Access Workstations"
        Evidence     = "Confirm administrators use dedicated hardened workstations for admin tasks"
    }
)

Export-ControlResult -ControlID "AAD.PA.05" -Data $PAWInfo -Result "Manual verification required for privileged workstation usage" -Status "MANUAL"

############################################################
# AAD.PA.06
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.06 Resource Lock custom role"

try {
    $AzureRoleDefinitions = @(Get-MgRoleManagementAzureResourceRoleDefinition -All)
}
catch {
    $AzureRoleDefinitions = @()
}

$LockRoles = @(
    $AzureRoleDefinitions |
    Where-Object {
        $_.IsBuiltIn -eq $false -and
        ($_.Permissions.Actions -match "Microsoft.Authorization/locks")
    } |
    Select-Object DisplayName, Id, IsBuiltIn
)

Export-ControlResult -ControlID "AAD.PA.06" -Data $LockRoles -Result "$($LockRoles.Count) custom Azure roles found with resource lock permissions" -Status $(if ($LockRoles.Count -gt 0) { "PASS" } else { "FAIL" })

############################################################
# AAD.PA.07
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.07 Account separation"

$LicensedAdmins = @($GAUsers | Where-Object { $_.AssignedLicenses -gt 0 })
Export-ControlResult -ControlID "AAD.PA.07" -Data $LicensedAdmins -Result "$($LicensedAdmins.Count) Global Administrator accounts also look like regular licensed user accounts" -Status $(if ($LicensedAdmins.Count -eq 0) { "PASS" } else { "WARNING" })

Export-SummaryReport "PrivilegedAccess"

Write-Host "Privileged Access audit completed."
