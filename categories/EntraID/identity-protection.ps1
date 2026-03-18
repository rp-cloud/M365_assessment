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

if ($PasswordProtectionAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.08" -AvailabilityState $PasswordProtectionAvailability
}
else {
    $LockoutThresholdData = @(
        [PSCustomObject]@{
            LockoutThreshold       = $PasswordProtection.lockoutThreshold
            LockoutDurationSeconds = $PasswordProtection.lockoutDurationInSeconds
            ObservationWindow      = $PasswordProtection.observationWindowInSeconds
        }
    )

    $ThresholdCompliant = $null -ne $PasswordProtection -and $null -ne $PasswordProtection.lockoutThreshold -and $PasswordProtection.lockoutThreshold -eq 10
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

if ($PasswordProtectionAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.10" -AvailabilityState $PasswordProtectionAvailability
}
else {
    $DurationCompliant = $null -ne $PasswordProtection -and $null -ne $PasswordProtection.lockoutDurationInSeconds -and $PasswordProtection.lockoutDurationInSeconds -ge 1800
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

if ($PasswordProtectionAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.11" -AvailabilityState $PasswordProtectionAvailability
}
else {
    Export-ControlResult -ControlID "AAD.IP.11" -Data $BannedPasswordData -Result "$($CustomBannedPasswords.Count) custom banned passwords configured" -Status $(if ($CustomBannedPasswords.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.IP.12
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.IP.12 Phishing-resistant MFA"

$AdminsWithoutPhishingResistantMFA = @()
$IP12UnavailableState = $null

try {
    $AdminRoles = @($Roles | Where-Object { $_.DisplayName -match "Administrator|Admin" })

    foreach ($Role in $AdminRoles) {
        foreach ($Member in $RoleMembers[$Role.Id]) {
            $User = $UsersById[$Member.Id]
            if (-not $User) {
                continue
            }

            $Methods = @(Get-MgUserAuthenticationMethod -UserId $User.Id -ErrorAction Stop)
            $HasPhishingResistant = $false

            foreach ($Method in $Methods) {
                if ($Method.AdditionalProperties.'@odata.type' -in @(
                    "#microsoft.graph.fido2AuthenticationMethod",
                    "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod",
                    "#microsoft.graph.x509CertificateAuthenticationMethod"
                )) {
                    $HasPhishingResistant = $true
                }
            }

            if (-not $HasPhishingResistant) {
                $AdminsWithoutPhishingResistantMFA += [PSCustomObject]@{
                    UserPrincipalName = $User.UserPrincipalName
                    DisplayName       = $User.DisplayName
                    Role              = $Role.DisplayName
                }
            }
        }
    }
}
catch {
    $UnavailableStatus = Resolve-AuditUnavailableStatus -ErrorRecord $_
    if ($UnavailableStatus) {
        $IP12UnavailableState = [PSCustomObject]@{
            Status = $UnavailableStatus
            Reason = "Authentication methods for privileged users could not be retrieved"
            Source = "Get-MgUserAuthenticationMethod"
        }
    }
    else {
        $IP12UnavailableState = [PSCustomObject]@{
            Status  = "ERROR"
            Reason  = "Authentication methods for privileged users could not be retrieved"
            Source  = "Get-MgUserAuthenticationMethod"
            Message = $_.Exception.Message
        }
    }
}

if ($RolesAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.12" -AvailabilityState $RolesAvailability
}
elseif ($IP12UnavailableState) {
    Export-ControlUnavailableFromState -ControlID "AAD.IP.12" -AvailabilityState $IP12UnavailableState
}
else {
    Export-ControlResult -ControlID "AAD.IP.12" -Data $AdminsWithoutPhishingResistantMFA -Result "$($AdminsWithoutPhishingResistantMFA.Count) privileged accounts do not have phishing-resistant MFA methods detected" -Status $(if ($AdminsWithoutPhishingResistantMFA.Count -eq 0) { "PASS" } else { "FAIL" })
}
Export-SummaryReport "IdentityProtection"

Write-Host "Identity Protection audit completed."






