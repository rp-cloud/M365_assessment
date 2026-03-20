. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running Privileged Access controls..."

$Global:AuditSummary = @()

$TotalControls = 7
$CurrentControl = 0

$UsersById = Get-CachedUsersById
$Roles = @(Get-CachedRoles)
$RoleMembers = Get-CachedRoleMembers
$UsersAvailability = Get-AuditFirstUnavailableState -Keys @("Users")
$RolesAvailability = Get-AuditFirstUnavailableState -Keys @("Roles")

$GARole = $Roles | Where-Object { $_.DisplayName -eq "Global Administrator" } | Select-Object -First 1
$GAUsers = @()
$PIMGAUsers = @()
$PIMForPA01Warning = $null

if ($GARole) {
    foreach ($Member in $RoleMembers[$GARole.Id]) {
        $User = $UsersById[$Member.Id]
        if ($User) {
            $GAUsers += [PSCustomObject]@{
                PrincipalId           = $User.Id
                DisplayName           = $User.DisplayName
                UserPrincipalName     = $User.UserPrincipalName
                UserType              = $User.UserType
                AccountEnabled        = $User.AccountEnabled
                OnPremisesSyncEnabled = $User.OnPremisesSyncEnabled
                AssignedLicenses      = @($User.AssignedLicenses).Count
                AssignmentSource      = "DirectoryRole"
                AssignmentType        = "Active"
            }
        }
    }

    try {
        $GlobalAdminRoleDefinition = @(
            Get-MgRoleManagementDirectoryRoleDefinition -All -ErrorAction Stop |
            Where-Object { $_.DisplayName -eq "Global Administrator" } |
            Select-Object -First 1
        )

        if ($GlobalAdminRoleDefinition) {
            $EligibilitySchedules = @(Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All -ErrorAction Stop)
            $AssignmentSchedules = @(Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All -ErrorAction Stop)

            $PIMGAUsers = @(
                foreach ($Schedule in ($EligibilitySchedules | Where-Object { $_.RoleDefinitionId -eq $GlobalAdminRoleDefinition.Id })) {
                    $User = $UsersById[$Schedule.PrincipalId]
                    if ($User) {
                        [PSCustomObject]@{
                            PrincipalId           = $User.Id
                            DisplayName           = $User.DisplayName
                            UserPrincipalName     = $User.UserPrincipalName
                            UserType              = $User.UserType
                            AccountEnabled        = $User.AccountEnabled
                            OnPremisesSyncEnabled = $User.OnPremisesSyncEnabled
                            AssignedLicenses      = @($User.AssignedLicenses).Count
                            AssignmentSource      = "PIM"
                            AssignmentType        = "Eligible"
                        }
                    }
                }

                foreach ($Schedule in ($AssignmentSchedules | Where-Object { $_.RoleDefinitionId -eq $GlobalAdminRoleDefinition.Id })) {
                    $User = $UsersById[$Schedule.PrincipalId]
                    if ($User) {
                        [PSCustomObject]@{
                            PrincipalId           = $User.Id
                            DisplayName           = $User.DisplayName
                            UserPrincipalName     = $User.UserPrincipalName
                            UserType              = $User.UserType
                            AccountEnabled        = $User.AccountEnabled
                            OnPremisesSyncEnabled = $User.OnPremisesSyncEnabled
                            AssignedLicenses      = @($User.AssignedLicenses).Count
                            AssignmentSource      = "PIM"
                            AssignmentType        = "Active"
                        }
                    }
                }
            )
        }
    }
    catch {
        $PIMForPA01Warning = "PIM Global Administrator assignments could not be retrieved"
    }
}

$PA01Data = @($GAUsers + $PIMGAUsers)
$PA01UniquePrincipalIds = @($PA01Data | Where-Object { $_.PrincipalId } | Select-Object -ExpandProperty PrincipalId -Unique)
$PA01UniqueCount = $PA01UniquePrincipalIds.Count
$PA01DirectCount = @($GAUsers | Select-Object -ExpandProperty PrincipalId -Unique).Count
$PA01PIMEligibleCount = @($PIMGAUsers | Where-Object { $_.AssignmentType -eq "Eligible" } | Select-Object -ExpandProperty PrincipalId -Unique).Count
$PA01PIMActiveCount = @($PIMGAUsers | Where-Object { $_.AssignmentType -eq "Active" } | Select-Object -ExpandProperty PrincipalId -Unique).Count

############################################################
# AAD.PA.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.01 Global Administrator count"

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.01" -AvailabilityState $UsersAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.01" -AvailabilityState $RolesAvailability
}
else {
    $PA01Result = "$PA01UniqueCount unique Global Administrator accounts found ($PA01DirectCount direct, $PA01PIMEligibleCount PIM eligible, $PA01PIMActiveCount PIM active)"
    if ($PIMForPA01Warning) {
        $PA01Result = "$PA01Result. $PIMForPA01Warning."
    }

    Export-ControlResult -ControlID "AAD.PA.01" -Data $PA01Data -Result $PA01Result -Status $(if ($PA01UniqueCount -ge 2 -and $PA01UniqueCount -le 4) { "PASS" } else { "FAIL" })
}

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

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.02" -AvailabilityState $UsersAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.02" -AvailabilityState $RolesAvailability
}
else {
    Export-ControlResult -ControlID "AAD.PA.02" -Data $BreakGlassCandidates -Result "$($BreakGlassCandidates.Count) cloud-only enabled Global Administrator accounts found as break-glass candidates" -Status "INFO"
}

############################################################
# AAD.PA.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.03 PIM usage"

$PIMUnavailableState = $null
try {
    $RoleDefinitions = @(Get-MgRoleManagementDirectoryRoleDefinition -All)
    $EligibilitySchedules = @(Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All)
}
catch {
    $RoleDefinitions = @()
    $EligibilitySchedules = @()
    $UnavailableStatus = Resolve-AuditUnavailableStatus -ErrorRecord $_
    if ($UnavailableStatus) {
        $PIMUnavailableState = [PSCustomObject]@{
            Status = $UnavailableStatus
            Reason = "PIM role eligibility data could not be retrieved"
            Source = "RoleManagement Directory"
        }
    }
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

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.03" -AvailabilityState $UsersAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.03" -AvailabilityState $RolesAvailability
}
elseif ($PIMUnavailableState) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.03" -AvailabilityState $PIMUnavailableState
}
else {
    Export-ControlResult -ControlID "AAD.PA.03" -Data $EligibleUsers -Result "$($EligibleUsers.Count) eligible role assignments found in PIM" -Status $(if ($EligibleUsers.Count -gt 0) { "PASS" } else { "FAIL" })
}

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

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.04" -AvailabilityState $UsersAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.04" -AvailabilityState $RolesAvailability
}
else {
    Export-ControlResult -ControlID "AAD.PA.04" -Data $DeviceAdmins -Result "$($DeviceAdmins.Count) users are assigned to the Device Administrator role" -Status $(if ($DeviceAdmins.Count -eq 0) { "PASS" } else { "WARNING" })
}

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

$AzureRoleUnavailableState = $null
try {
    $AzureRoleDefinitions = @(Get-MgRoleManagementAzureResourceRoleDefinition -All)
}
catch {
    $AzureRoleDefinitions = @()
    $UnavailableStatus = Resolve-AuditUnavailableStatus -ErrorRecord $_
    if ($UnavailableStatus) {
        $AzureRoleUnavailableState = [PSCustomObject]@{
            Status = $UnavailableStatus
            Reason = "Azure resource role definitions could not be retrieved"
            Source = "RoleManagement AzureResource"
        }
    }
}

$LockRoles = @(
    $AzureRoleDefinitions |
    Where-Object {
        $_.IsBuiltIn -eq $false -and
        ($_.Permissions.Actions -match "Microsoft.Authorization/locks")
    } |
    Select-Object DisplayName, Id, IsBuiltIn
)

if ($AzureRoleUnavailableState) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.06" -AvailabilityState $AzureRoleUnavailableState
}
else {
    Export-ControlResult -ControlID "AAD.PA.06" -Data $LockRoles -Result "$($LockRoles.Count) custom Azure roles found with resource lock permissions" -Status $(if ($LockRoles.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.PA.07
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.PA.07 Account separation"

$LicensedAdmins = @($GAUsers | Where-Object { $_.AssignedLicenses -gt 0 })

if ($UsersAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.07" -AvailabilityState $UsersAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.PA.07" -AvailabilityState $RolesAvailability
}
else {
    Export-ControlResult -ControlID "AAD.PA.07" -Data $LicensedAdmins -Result "$($LicensedAdmins.Count) Global Administrator accounts also look like regular licensed user accounts" -Status $(if ($LicensedAdmins.Count -eq 0) { "PASS" } else { "WARNING" })
}

Export-SummaryReport "PrivilegedAccess"

Write-Host "Privileged Access audit completed."
