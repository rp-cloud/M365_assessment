. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running Identity Protection controls..."

$Global:AuditSummary = @()

$TotalControls = 12
$CurrentControl = 0

$UsersById = Get-CachedUsersById
$Roles = @(Get-CachedRoles)
$RoleMembers = Get-CachedRoleMembers
$RegistrationDetails = @(Get-CachedUserRegistrationDetails)
$CAPolicies = @(Get-CachedCAPolicies)
$Domains = @(Get-CachedDomains)
$PasswordProtection = Get-CachedPasswordProtectionPolicy
$RegistrationAvailability = Get-AuditFirstUnavailableState -Keys @("UserRegistrationDetails")
$PasswordProtectionAvailability = Get-AuditFirstUnavailableState -Keys @("PasswordProtection")
$RolesAvailability = Get-AuditFirstUnavailableState -Keys @("Roles")
$DomainsAvailability = Get-AuditFirstUnavailableState -Keys @("Domains")
$CAAvailability = Get-AuditFirstUnavailableState -Keys @("CAPolicies")

############################################################
# AAD.IP.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.01 MFA for Global Administrators"

$GlobalAdminRole = $Roles | Where-Object { $_.DisplayName -eq "Global Administrator" } | Select-Object -First 1
$GlobalAdminUsers = @()

if ($GlobalAdminRole) {
    foreach ($Member in $RoleMembers[$GlobalAdminRole.Id]) {
        $User = $UsersById[$Member.Id]
        if ($User) {
            $Registration = $RegistrationDetails | Where-Object { $_.Id -eq $User.Id -or $_.UserPrincipalName -eq $User.UserPrincipalName } | Select-Object -First 1
            $GlobalAdminUsers += [PSCustomObject]@{
                DisplayName       = $User.DisplayName
                UserPrincipalName = $User.UserPrincipalName
                IsMfaRegistered   = if ($Registration) { $Registration.IsMfaRegistered } else { $null }
            }
        }
    }
}

$AdminsWithoutMfa = @($GlobalAdminUsers | Where-Object { $_.IsMfaRegistered -ne $true })
if ($RegistrationAvailability -and (Test-AuditUnavailableStatus -Status $RegistrationAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IP.01" -Status $RegistrationAvailability.Status -Reason $RegistrationAvailability.Reason -Source $RegistrationAvailability.Source
}
else {
    Export-ControlResult -ControlID "AAD.IP.01" -Data $GlobalAdminUsers -Result "$($AdminsWithoutMfa.Count) Global Administrators are not MFA-registered" -Status $(if ($GlobalAdminUsers.Count -gt 0 -and $AdminsWithoutMfa.Count -eq 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.02 Alternate contact info"

$AltContactData = @(
    $RegistrationDetails |
    Select-Object UserDisplayName, UserPrincipalName, IsSsprRegistered, IsMfaRegistered, MethodsRegistered
)

$UsersMissingRecovery = @($RegistrationDetails | Where-Object { $_.IsSsprRegistered -ne $true })
if ($RegistrationAvailability -and (Test-AuditUnavailableStatus -Status $RegistrationAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IP.02" -Status $RegistrationAvailability.Status -Reason $RegistrationAvailability.Reason -Source $RegistrationAvailability.Source
}
else {
    Export-ControlResult -ControlID "AAD.IP.02" -Data $AltContactData -Result "$($UsersMissingRecovery.Count) users are not registered for SSPR/recovery information" -Status $(if ($UsersMissingRecovery.Count -eq 0 -and $AltContactData.Count -gt 0) { "PASS" } else { "WARNING" })
}

############################################################
# AAD.IP.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.03 MFA for all users"

$UsersWithoutMFA = @(
    $RegistrationDetails |
    Where-Object { $_.IsMfaRegistered -ne $true } |
    Select-Object UserDisplayName, UserPrincipalName, IsMfaRegistered, IsSsprEnabled
)

if ($RegistrationAvailability -and (Test-AuditUnavailableStatus -Status $RegistrationAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IP.03" -Status $RegistrationAvailability.Status -Reason $RegistrationAvailability.Reason -Source $RegistrationAvailability.Source
}
else {
    Export-ControlResult -ControlID "AAD.IP.03" -Data $UsersWithoutMFA -Result "$($UsersWithoutMFA.Count) users are not MFA-registered" -Status $(if ($UsersWithoutMFA.Count -eq 0 -and $RegistrationDetails.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.04 Password expiration"

$PasswordPolicy = @(
    $Domains |
    Select-Object Id, PasswordValidityPeriodInDays,
        @{Name = "Compliant"; Expression = { $_.PasswordValidityPeriodInDays -eq 0 -or $_.PasswordValidityPeriodInDays -ge 365 } }
)

$NonCompliantPasswordDomains = @($PasswordPolicy | Where-Object { $_.Compliant -ne $true })
if ($DomainsAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.04" -AvailabilityState $DomainsAvailability
}
else {
    Export-ControlResult -ControlID "AAD.IP.04" -Data $PasswordPolicy -Result "$($NonCompliantPasswordDomains.Count) verified domains do not meet the 365 days / never expire requirement" -Status $(if ($NonCompliantPasswordDomains.Count -eq 0 -and $PasswordPolicy.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.05
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.05 Password complexity"

$PasswordComplexityData = @(
    [PSCustomObject]@{
        Verification = "Manual"
        Scope        = "Password complexity and hybrid AD policy"
        Evidence     = "Validate on-premises/domain password complexity configuration against Microsoft recommendations"
    }
)

Export-ControlResult -ControlID "AAD.IP.05" -Data $PasswordComplexityData -Result "Manual verification required for password complexity policy" -Status "MANUAL"

############################################################
# AAD.IP.06
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.06 Sign-in risk policies"

$SignInRiskPolicies = @(
    $CAPolicies |
    Where-Object { $_.State -eq "enabled" -and $_.Conditions.SignInRiskLevels } |
    Select-Object DisplayName, State,
        @{Name = "SignInRiskLevels"; Expression = { $_.Conditions.SignInRiskLevels -join "," } }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.06" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.IP.06" -Data $SignInRiskPolicies -Result "$($SignInRiskPolicies.Count) enabled policies handle sign-in risk" -Status $(if ($SignInRiskPolicies.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.07
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.07 User risk policies"

$UserRiskPolicies = @(
    $CAPolicies |
    Where-Object { $_.State -eq "enabled" -and $_.Conditions.UserRiskLevels } |
    Select-Object DisplayName, State,
        @{Name = "UserRiskLevels"; Expression = { $_.Conditions.UserRiskLevels -join "," } }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.07" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.IP.07" -Data $UserRiskPolicies -Result "$($UserRiskPolicies.Count) enabled policies handle user risk" -Status $(if ($UserRiskPolicies.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.08
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.08 Lockout threshold"

$LockoutThresholdData = @(
    [PSCustomObject]@{
        LockoutThreshold       = $PasswordProtection.lockoutThreshold
        LockoutDurationSeconds = $PasswordProtection.lockoutDurationInSeconds
        ObservationWindow      = $PasswordProtection.observationWindowInSeconds
    }
)

$ThresholdCompliant = $null -ne $PasswordProtection -and $PasswordProtection.lockoutThreshold -eq 10
if ($PasswordProtectionAvailability -and (Test-AuditUnavailableStatus -Status $PasswordProtectionAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IP.08" -Status $PasswordProtectionAvailability.Status -Reason $PasswordProtectionAvailability.Reason -Source $PasswordProtectionAvailability.Source
}
else {
    Export-ControlResult -ControlID "AAD.IP.08" -Data $LockoutThresholdData -Result "Current lockout threshold: $($PasswordProtection.lockoutThreshold)" -Status $(if ($ThresholdCompliant) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.09
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.09 Self-service password reset"

$UsersWithoutSSPR = @(
    $RegistrationDetails |
    Where-Object { $_.IsSsprRegistered -ne $true } |
    Select-Object UserDisplayName, UserPrincipalName, IsSsprRegistered, IsSsprEnabled
)

if ($RegistrationAvailability -and (Test-AuditUnavailableStatus -Status $RegistrationAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IP.09" -Status $RegistrationAvailability.Status -Reason $RegistrationAvailability.Reason -Source $RegistrationAvailability.Source
}
else {
    Export-ControlResult -ControlID "AAD.IP.09" -Data $UsersWithoutSSPR -Result "$($UsersWithoutSSPR.Count) users are not registered for self-service password reset" -Status $(if ($UsersWithoutSSPR.Count -eq 0 -and $RegistrationDetails.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.10
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.10 Lockout duration"

$LockoutDurationData = @(
    [PSCustomObject]@{
        LockoutDurationSeconds = $PasswordProtection.lockoutDurationInSeconds
    }
)

$DurationCompliant = $null -ne $PasswordProtection -and $PasswordProtection.lockoutDurationInSeconds -ge 1800
if ($PasswordProtectionAvailability -and (Test-AuditUnavailableStatus -Status $PasswordProtectionAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IP.10" -Status $PasswordProtectionAvailability.Status -Reason $PasswordProtectionAvailability.Reason -Source $PasswordProtectionAvailability.Source
}
else {
    Export-ControlResult -ControlID "AAD.IP.10" -Data $LockoutDurationData -Result "Current lockout duration: $($PasswordProtection.lockoutDurationInSeconds) seconds" -Status $(if ($DurationCompliant) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.11
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.11 Custom banned passwords"

$CustomBannedPasswords = @($PasswordProtection.customBannedPasswords)
$BannedPasswordData = @(
    foreach ($Entry in $CustomBannedPasswords) {
        [PSCustomObject]@{
            CustomBannedPassword = $Entry
        }
    }
)

if ($PasswordProtectionAvailability -and (Test-AuditUnavailableStatus -Status $PasswordProtectionAvailability.Status)) {
    Export-ControlUnavailable -ControlID "AAD.IP.11" -Status $PasswordProtectionAvailability.Status -Reason $PasswordProtectionAvailability.Reason -Source $PasswordProtectionAvailability.Source
}
else {
    Export-ControlResult -ControlID "AAD.IP.11" -Data $BannedPasswordData -Result "$($CustomBannedPasswords.Count) custom banned passwords configured" -Status $(if ($CustomBannedPasswords.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.12
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.12 Phishing-resistant MFA"

$AdminRoles = @($Roles | Where-Object { $_.DisplayName -match "Administrator|Admin" })
$PrivilegedAccounts = @()
foreach ($Role in $AdminRoles) {
    foreach ($Member in $RoleMembers[$Role.Id]) {
        $User = $UsersById[$Member.Id]
        if ($User) {
            $PrivilegedAccounts += [PSCustomObject]@{
                Role              = $Role.DisplayName
                DisplayName       = $User.DisplayName
                UserPrincipalName = $User.UserPrincipalName
            }
        }
    }
}

$PrivilegedAccounts = @($PrivilegedAccounts | Sort-Object UserPrincipalName, Role -Unique)
$PhishingResistantPolicy = @(
    $CAPolicies |
    Where-Object {
        $_.State -eq "enabled" -and
        $_.GrantControls.AuthenticationStrength.Id
    } |
    Select-Object DisplayName, State,
        @{Name = "AuthenticationStrengthId"; Expression = { $_.GrantControls.AuthenticationStrength.Id } }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.12" -AvailabilityState $CAAvailability
}
elseif ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.12" -AvailabilityState $RolesAvailability
}
else {
    Export-ControlResult -ControlID "AAD.IP.12" -Data $(if ($PhishingResistantPolicy.Count -gt 0) { $PhishingResistantPolicy } else { $PrivilegedAccounts }) -Result $(if ($PhishingResistantPolicy.Count -gt 0) { "$($PhishingResistantPolicy.Count) authentication strength policies found for strong MFA" } else { "No phishing-resistant MFA policy evidence found for privileged users" }) -Status $(if ($PhishingResistantPolicy.Count -gt 0) { "WARNING" } else { "FAIL" })
}

Export-SummaryReport "IdentityProtection"

Write-Host "Identity Protection audit completed."




