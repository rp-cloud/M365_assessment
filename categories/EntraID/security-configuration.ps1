. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running Security Configuration controls..."

$Global:AuditSummary = @()

$TotalControls = 18
$CurrentControl = 0

$CAPolicies = @(Get-CachedCAPolicies)
$AuthPolicy = Get-CachedAuthorizationPolicy
$Organization = @(Get-CachedOrganization)
$Domains = @(Get-CachedDomains)
$SecurityDefaults = Get-CachedSecurityDefaults
$LifecyclePolicies = @(Get-CachedGroupLifecyclePolicies)

$CAAvailability = Get-AuditFirstUnavailableState -Keys @("CAPolicies")
$AuthPolicyAvailability = Get-AuditFirstUnavailableState -Keys @("AuthorizationPolicy")
$OrganizationAvailability = Get-AuditFirstUnavailableState -Keys @("Organization")
$DomainsAvailability = Get-AuditFirstUnavailableState -Keys @("Domains")
$SecurityDefaultsAvailability = Get-AuditFirstUnavailableState -Keys @("SecurityDefaults")
$LifecycleAvailability = Get-AuditFirstUnavailableState -Keys @("GroupLifecyclePolicies")

############################################################
# AAD.SC.01
############################################################

$CurrentControl++
$SC01Data = @([PSCustomObject]@{ AllowedToCreateTenants = $AuthPolicy.DefaultUserRolePermissions.AllowedToCreateTenants })
if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.01" -AvailabilityState $AuthPolicyAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.01" -Data $SC01Data -Result "AllowedToCreateTenants = $($AuthPolicy.DefaultUserRolePermissions.AllowedToCreateTenants)" -Status $(if ($AuthPolicy.DefaultUserRolePermissions.AllowedToCreateTenants -eq $false) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.02
############################################################

$CurrentControl++
$LegacyPolicies = @(
    $CAPolicies |
    Where-Object {
        $_.State -eq "enabled" -and
        @($_.Conditions.ClientAppTypes) -contains "exchangeActiveSync" -and
        @($_.GrantControls.BuiltInControls) -contains "block"
    } |
    Select-Object DisplayName, State,
        @{Name = "ClientAppTypes"; Expression = { $_.Conditions.ClientAppTypes -join "," } }
)
$LegacyProtected = $LegacyPolicies.Count -gt 0 -or ($SecurityDefaults -and $SecurityDefaults.IsEnabled)
if ($CAAvailability -and $LegacyPolicies.Count -eq 0) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.02" -AvailabilityState $CAAvailability
}
elseif ($SecurityDefaultsAvailability -and $LegacyPolicies.Count -eq 0) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.02" -AvailabilityState $SecurityDefaultsAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.02" -Data $(if ($LegacyPolicies.Count -gt 0) { $LegacyPolicies } else { @([PSCustomObject]@{ SecurityDefaultsEnabled = if ($SecurityDefaults) { $SecurityDefaults.IsEnabled } else { $false } }) }) -Result $(if ($LegacyProtected) { "Legacy authentication is blocked by Conditional Access or Security Defaults" } else { "No evidence that legacy authentication is blocked" }) -Status $(if ($LegacyProtected) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.03
############################################################

$CurrentControl++
$SC03Data = @([PSCustomObject]@{ AllowedToGrantConsent = $AuthPolicy.DefaultUserRolePermissions.AllowedToGrantConsent })
if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.03" -AvailabilityState $AuthPolicyAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.03" -Data $SC03Data -Result "AllowedToGrantConsent = $($AuthPolicy.DefaultUserRolePermissions.AllowedToGrantConsent)" -Status $(if ($AuthPolicy.DefaultUserRolePermissions.AllowedToGrantConsent -eq $false) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.04
############################################################

$CurrentControl++
$SC04Data = @([PSCustomObject]@{ AllowedToCreateApps = $AuthPolicy.DefaultUserRolePermissions.AllowedToCreateApps })
if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.04" -AvailabilityState $AuthPolicyAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.04" -Data $SC04Data -Result "AllowedToCreateApps = $($AuthPolicy.DefaultUserRolePermissions.AllowedToCreateApps)" -Status $(if ($AuthPolicy.DefaultUserRolePermissions.AllowedToCreateApps -eq $false) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.05
############################################################

$CurrentControl++
$GuestRoleName = "Unknown"
if ($AuthPolicy -and $AuthPolicy.GuestUserRoleId) {
    try {
        $GuestRoleTemplate = @(Get-MgDirectoryRoleTemplate -ErrorAction Stop | Where-Object { $_.Id -eq $AuthPolicy.GuestUserRoleId } | Select-Object -First 1)
        if ($GuestRoleTemplate) {
            $GuestRoleName = $GuestRoleTemplate.DisplayName
        }
    }
    catch {
        $GuestRoleName = "Unknown"
    }
}

$SC05Data = @([PSCustomObject]@{ GuestUserRoleId = $AuthPolicy.GuestUserRoleId; GuestRoleName = $GuestRoleName; ExpectedRole = "Guest User" })
if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.05" -AvailabilityState $AuthPolicyAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.05" -Data $SC05Data -Result "Guest user access role configured: $GuestRoleName" -Status "MANUAL"
}

############################################################
# AAD.SC.06
############################################################

$CurrentControl++
$SC06Data = @([PSCustomObject]@{ AllowInvitesFrom = $AuthPolicy.AllowInvitesFrom })
$SC06Compliant = $AuthPolicy.AllowInvitesFrom -eq "adminsOnly"
if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.06" -AvailabilityState $AuthPolicyAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.06" -Data $SC06Data -Result "AllowInvitesFrom = $($AuthPolicy.AllowInvitesFrom)" -Status $(if ($SC06Compliant) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.07
############################################################

$CurrentControl++
$SC07Data = @([PSCustomObject]@{ Verification = "Manual"; Scope = "Management group creation permissions"; Evidence = "Verify whether Azure management group creation requires elevated permissions" })
Export-ControlResult -ControlID "AAD.SC.07" -Data $SC07Data -Result "Manual verification required for management group creation permissions" -Status "MANUAL"

############################################################
# AAD.SC.08
############################################################

$CurrentControl++
$CAEnabledCount = @($CAPolicies | Where-Object { $_.State -eq "enabled" }).Count
$SC08Data = @([PSCustomObject]@{ ConditionalAccessEnabledPolicies = $CAEnabledCount; SecurityDefaultsEnabled = if ($SecurityDefaults) { $SecurityDefaults.IsEnabled } else { $false } })
$SC08Pass = ($CAEnabledCount -gt 0 -and $SecurityDefaults.IsEnabled -ne $true) -or ($CAEnabledCount -eq 0 -and $SecurityDefaults -and $SecurityDefaults.IsEnabled)
if ($CAAvailability -and $CAEnabledCount -eq 0) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.08" -AvailabilityState $CAAvailability
}
elseif ($SecurityDefaultsAvailability -and $CAEnabledCount -eq 0) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.08" -AvailabilityState $SecurityDefaultsAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.08" -Data $SC08Data -Result "Enabled CA policies: $CAEnabledCount; Security Defaults enabled: $(if ($SecurityDefaults) { $SecurityDefaults.IsEnabled } else { $false })" -Status $(if ($SC08Pass) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.09
############################################################

$CurrentControl++
$SC09Data = @([PSCustomObject]@{ Verification = "Manual"; Scope = "My Groups access"; Evidence = "Confirm non-admin users cannot access My Groups management features" })
Export-ControlResult -ControlID "AAD.SC.09" -Data $SC09Data -Result "Manual verification required for My Groups restrictions" -Status "MANUAL"

############################################################
# AAD.SC.10
############################################################

$CurrentControl++
$SC10Data = @([PSCustomObject]@{ AllowedToCreateSecurityGroups = $AuthPolicy.DefaultUserRolePermissions.AllowedToCreateSecurityGroups })
if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.10" -AvailabilityState $AuthPolicyAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.10" -Data $SC10Data -Result "AllowedToCreateSecurityGroups = $($AuthPolicy.DefaultUserRolePermissions.AllowedToCreateSecurityGroups)" -Status $(if ($AuthPolicy.DefaultUserRolePermissions.AllowedToCreateSecurityGroups -eq $false) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.11
############################################################

$CurrentControl++
$SC11Data = @([PSCustomObject]@{ Verification = "Manual"; Scope = "Membership requests in Access Panel"; Evidence = "Review group settings controlling owner approval for membership requests" })
Export-ControlResult -ControlID "AAD.SC.11" -Data $SC11Data -Result "Manual verification required for owner-managed membership requests" -Status "MANUAL"

############################################################
# AAD.SC.12
############################################################

$CurrentControl++
$DirectorySettingsUnavailableState = $null
try {
    $DirectorySettingsResponse = Invoke-MgGraphRequest -Method GET -Uri "/beta/settings"
    $UnifiedSetting = $DirectorySettingsResponse.value | Where-Object { $_.displayName -eq "Group.Unified" } | Select-Object -First 1
}
catch {
    $UnifiedSetting = $null
    $UnavailableStatus = Resolve-AuditUnavailableStatus -ErrorRecord $_
    if ($UnavailableStatus) {
        $DirectorySettingsUnavailableState = [PSCustomObject]@{ Status = $UnavailableStatus; Reason = "Directory settings could not be retrieved"; Source = "Invoke-MgGraphRequest /beta/settings" }
    }
}

$EnableGroupCreation = $null
if ($UnifiedSetting) {
    $EnableGroupCreation = ($UnifiedSetting.values | Where-Object { $_.name -eq "EnableGroupCreation" } | Select-Object -ExpandProperty value -First 1)
}

$SC12Data = @([PSCustomObject]@{ AllowedToCreateGroups = $AuthPolicy.DefaultUserRolePermissions.AllowedToCreateGroups; EnableGroupCreation = $EnableGroupCreation })
$SC12Pass = $AuthPolicy.DefaultUserRolePermissions.AllowedToCreateGroups -eq $false -or $EnableGroupCreation -eq "false"
if ($AuthPolicyAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.12" -AvailabilityState $AuthPolicyAvailability
}
elseif ($DirectorySettingsUnavailableState) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.12" -AvailabilityState $DirectorySettingsUnavailableState
}
else {
    Export-ControlResult -ControlID "AAD.SC.12" -Data $SC12Data -Result "AllowedToCreateGroups = $($AuthPolicy.DefaultUserRolePermissions.AllowedToCreateGroups); Group.Unified.EnableGroupCreation = $EnableGroupCreation" -Status $(if ($SC12Pass) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.13
############################################################

$CurrentControl++
$SC13Data = @([PSCustomObject]@{ Verification = "Manual"; Scope = "Access to Entra administration portal"; Evidence = "Validate portal access is restricted to administrators only" })
Export-ControlResult -ControlID "AAD.SC.13" -Data $SC13Data -Result "Manual verification required for Entra admin portal restriction" -Status "MANUAL"

############################################################
# AAD.SC.14
############################################################

$CurrentControl++
$SC14Data = @([PSCustomObject]@{ Verification = "Manual"; Scope = "Administrative session timeout"; Evidence = "Validate inactivity timeout for administrative portal sessions is set to 1 hour" })
Export-ControlResult -ControlID "AAD.SC.14" -Data $SC14Data -Result "Manual verification required for administrative session timeout" -Status "MANUAL"

############################################################
# AAD.SC.15
############################################################

$CurrentControl++
$BrandingUnavailableState = $null
try {
    $OrgBranding = @(Get-MgOrganizationBranding -OrganizationId $Organization[0].Id -ErrorAction Stop)
}
catch {
    $OrgBranding = @()
    $UnavailableStatus = Resolve-AuditUnavailableStatus -ErrorRecord $_
    if ($UnavailableStatus) {
        $BrandingUnavailableState = [PSCustomObject]@{ Status = $UnavailableStatus; Reason = "Organization branding could not be retrieved"; Source = "Get-MgOrganizationBranding" }
    }
}

$SC15Data = if ($OrgBranding.Count -gt 0) {
    @($OrgBranding | Select-Object DisplayName, SignInPageText, UsernameHintText)
}
else {
    @([PSCustomObject]@{ BrandingConfigured = $false })
}

if ($OrganizationAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.15" -AvailabilityState $OrganizationAvailability
}
elseif ($BrandingUnavailableState) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.15" -AvailabilityState $BrandingUnavailableState
}
else {
    Export-ControlResult -ControlID "AAD.SC.15" -Data $SC15Data -Result $(if ($OrgBranding.Count -gt 0) { "Company branding is configured" } else { "Company branding is not configured" }) -Status $(if ($OrgBranding.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.SC.16
############################################################

$CurrentControl++
$SC16Data = if ($LifecyclePolicies.Count -gt 0) {
    @($LifecyclePolicies | Select-Object Id, GroupLifetimeInDays, ManagedGroupTypes, @{Name = "AlternateNotificationEmails"; Expression = { $_.AlternateNotificationEmails -join "," } })
}
else {
    @([PSCustomObject]@{ PolicyConfigured = $false })
}

$SC16Pass = $false
if ($LifecyclePolicies.Count -gt 0) {
    $SC16Pass = @($LifecyclePolicies | Where-Object { $_.GroupLifetimeInDays -eq 90 -and @($_.AlternateNotificationEmails).Count -gt 0 }).Count -gt 0
}

if ($LifecycleAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.16" -AvailabilityState $LifecycleAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.16" -Data $SC16Data -Result $(if ($LifecyclePolicies.Count -gt 0) { "$($LifecyclePolicies.Count) group lifecycle policies found" } else { "No group lifecycle policy found" }) -Status $(if ($SC16Pass) { "PASS" } elseif ($LifecyclePolicies.Count -gt 0) { "WARNING" } else { "FAIL" })
}

############################################################
# AAD.SC.17
############################################################

$CurrentControl++
$ExpiredDomains = @($Domains | Where-Object { $_.IsVerified -eq $false -and $_.IsDefault -eq $false } | Select-Object Id, IsVerified, AuthenticationType)
if ($DomainsAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.SC.17" -AvailabilityState $DomainsAvailability
}
else {
    Export-ControlResult -ControlID "AAD.SC.17" -Data $ExpiredDomains -Result "$($ExpiredDomains.Count) non-default unverified domains found" -Status $(if ($ExpiredDomains.Count -eq 0) { "PASS" } else { "WARNING" })
}

############################################################
# AAD.SC.18
############################################################

$CurrentControl++
$SC18Data = @([PSCustomObject]@{ Verification = "Manual"; Scope = "LinkedIn account integration"; Evidence = "Verify users cannot connect work or school account with LinkedIn" })
Export-ControlResult -ControlID "AAD.SC.18" -Data $SC18Data -Result "Manual verification required for LinkedIn integration setting" -Status "MANUAL"

Export-SummaryReport "SecurityConfiguration"

Write-Host "Security Configuration audit completed."
