. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running Conditional Access controls..."

$Global:AuditSummary = @()

$TotalControls = 10
$CurrentControl = 0

$Policies = @(Get-CachedCAPolicies)
$Locations = @(Get-CachedLocations)
$CAAvailability = Get-AuditFirstUnavailableState -Keys @("CAPolicies")
$LocationAvailability = Get-AuditFirstUnavailableState -Keys @("Locations")

############################################################
# AAD.CA.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.01 Trusted locations"

$Trusted = @(
    $Locations |
    Where-Object { $_.IsTrusted -eq $true } |
    Select-Object DisplayName, IsTrusted, ODataType, CreatedDateTime, ModifiedDateTime
)

if ($LocationAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.01" -AvailabilityState $LocationAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.01" -Data $Trusted -Result "$($Trusted.Count) trusted named locations found" -Status $(if ($Trusted.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.CA.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.02 Risky sign-in policies"

$RiskPolicies = @(
    $Policies |
    Where-Object {
        $_.State -eq "enabled" -and
        $_.Conditions.SignInRiskLevels -and
        $_.GrantControls.BuiltInControls -contains "block"
    } |
    Select-Object DisplayName, State,
        @{Name = "SignInRiskLevels"; Expression = { $_.Conditions.SignInRiskLevels -join "," } },
        @{Name = "GrantControls"; Expression = { $_.GrantControls.BuiltInControls -join "," } }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.02" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.02" -Data $RiskPolicies -Result "$($RiskPolicies.Count) enabled Conditional Access policies block risky sign-ins" -Status $(if ($RiskPolicies.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.CA.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.03 Exclusions"

$Exclusions = @(
    foreach ($Policy in $Policies) {
        $HasExclusion =
            @($Policy.Conditions.Users.ExcludeUsers).Count -gt 0 -or
            @($Policy.Conditions.Users.ExcludeGroups).Count -gt 0 -or
            @($Policy.Conditions.Applications.ExcludeApplications).Count -gt 0

        if ($HasExclusion) {
            [PSCustomObject]@{
                Policy               = $Policy.DisplayName
                ExcludedUsers        = @($Policy.Conditions.Users.ExcludeUsers) -join ","
                ExcludedGroups       = @($Policy.Conditions.Users.ExcludeGroups) -join ","
                ExcludedApplications = @($Policy.Conditions.Applications.ExcludeApplications) -join ","
            }
        }
    }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.03" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.03" -Data $Exclusions -Result "$($Exclusions.Count) Conditional Access policies contain exclusions" -Status $(if ($Exclusions.Count -eq 0) { "PASS" } else { "WARNING" })
}

############################################################
# AAD.CA.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.04 User scope"

$UserScopeIssues = @(
    foreach ($Policy in $Policies) {
        $IncludedUsers = @($Policy.Conditions.Users.IncludeUsers)
        $IncludedGroups = @($Policy.Conditions.Users.IncludeGroups)

        if (($IncludedUsers -notcontains "All") -and $IncludedGroups.Count -eq 0) {
            [PSCustomObject]@{
                Policy         = $Policy.DisplayName
                IncludedUsers  = $IncludedUsers -join ","
                IncludedGroups = $IncludedGroups -join ","
                State          = $Policy.State
            }
        }
    }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.04" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.04" -Data $UserScopeIssues -Result "$($UserScopeIssues.Count) policies have limited or unclear user scope" -Status $(if ($UserScopeIssues.Count -eq 0) { "PASS" } else { "WARNING" })
}

############################################################
# AAD.CA.05
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.05 Policies in use"

$EnabledPolicies = @($Policies | Where-Object { $_.State -eq "enabled" })
$PolicyInfo = @($Policies | Select-Object DisplayName, State)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.05" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.05" -Data $PolicyInfo -Result "$($EnabledPolicies.Count) enabled Conditional Access policies found" -Status $(if ($EnabledPolicies.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.CA.06
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.06 Platform targeting"

$PlatformPolicies = @(
    foreach ($Policy in $Policies) {
        $IncludePlatforms = @($Policy.Conditions.Platforms.IncludePlatforms)
        $ExcludePlatforms = @($Policy.Conditions.Platforms.ExcludePlatforms)

        if ($IncludePlatforms.Count -gt 0 -or $ExcludePlatforms.Count -gt 0) {
            [PSCustomObject]@{
                Policy            = $Policy.DisplayName
                IncludedPlatforms = $IncludePlatforms -join ","
                ExcludedPlatforms = $ExcludePlatforms -join ","
            }
        }
    }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.06" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.06" -Data $PlatformPolicies -Result "$($PlatformPolicies.Count) policies explicitly target or exclude device platforms" -Status $(if ($PlatformPolicies.Count -eq 0) { "PASS" } else { "WARNING" })
}

############################################################
# AAD.CA.07
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.07 Intune enrollment MFA"

$DeviceEnrollmentPolicies = @(
    $Policies |
    Where-Object {
        $_.State -eq "enabled" -and
        $_.Conditions.Applications.IncludeUserActions -contains "urn:user:registerdevice" -and
        $_.GrantControls.BuiltInControls -contains "mfa"
    } |
    Select-Object DisplayName, State,
        @{Name = "UserActions"; Expression = { $_.Conditions.Applications.IncludeUserActions -join "," } },
        @{Name = "GrantControls"; Expression = { $_.GrantControls.BuiltInControls -join "," } }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.07" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.07" -Data $DeviceEnrollmentPolicies -Result "$($DeviceEnrollmentPolicies.Count) enabled policies require MFA for device registration/enrollment" -Status $(if ($DeviceEnrollmentPolicies.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.CA.08
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.08 Security info registration MFA"

$RegistrationPolicies = @(
    $Policies |
    Where-Object {
        $_.State -eq "enabled" -and
        (
            @($_.Conditions.Applications.IncludeUserActions) -contains "urn:user:registersecurityinfo" -or
            @($_.Conditions.Applications.IncludeUserActions) -contains "registerSecurityInformation"
        ) -and
        $_.GrantControls.BuiltInControls -contains "mfa"
    } |
    Select-Object DisplayName, State,
        @{Name = "UserActions"; Expression = { $_.Conditions.Applications.IncludeUserActions -join "," } },
        @{Name = "GrantControls"; Expression = { $_.GrantControls.BuiltInControls -join "," } }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.08" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.08" -Data $RegistrationPolicies -Result "$($RegistrationPolicies.Count) enabled policies require MFA for security information registration" -Status $(if ($RegistrationPolicies.Count -gt 0) { "PASS" } else { "FAIL" })
}

############################################################
# AAD.CA.09
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.09 Application exclusions"

$AppScopingPolicies = @(
    foreach ($Policy in $Policies) {
        $IncludedApplications = @($Policy.Conditions.Applications.IncludeApplications)
        $ExcludedApplications = @($Policy.Conditions.Applications.ExcludeApplications)
        $HasSpecificIncludedApplications = $IncludedApplications.Count -gt 0 -and ($IncludedApplications -notcontains "All")

        if ($HasSpecificIncludedApplications -or $ExcludedApplications.Count -gt 0) {
            [PSCustomObject]@{
                Policy                = $Policy.DisplayName
                IncludedApplications  = $IncludedApplications -join ","
                ExcludedApplications  = $ExcludedApplications -join ","
                HasSpecificInclusions = if ($HasSpecificIncludedApplications) { "Yes" } else { "No" }
            }
        }
    }
)

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.09" -AvailabilityState $CAAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.09" -Data $AppScopingPolicies -Result "$($AppScopingPolicies.Count) policies include specific applications or exclude applications" -Status $(if ($AppScopingPolicies.Count -eq 0) { "PASS" } else { "WARNING" })
}

############################################################
# AAD.CA.10
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.CA.10 Technical accounts and trusted IPs"

$TechnicalAccountExclusions = @(
    foreach ($Policy in $Policies) {
        $ExcludedUsers = @($Policy.Conditions.Users.ExcludeUsers)

        if ($ExcludedUsers.Count -gt 0) {
            $CompensatingPolicies = @(
                $Policies |
                Where-Object {
                    $_.Id -ne $Policy.Id -and
                    $_.State -eq "enabled" -and
                    (
                        (@($_.Conditions.Users.IncludeUsers) | Where-Object { $_ -in $ExcludedUsers }).Count -gt 0 -or
                        @($_.Conditions.Users.IncludeGroups).Count -gt 0
                    ) -and
                    @($_.Conditions.Locations.ExcludeLocations).Count -gt 0
                } |
                Select-Object -ExpandProperty DisplayName
            )

            [PSCustomObject]@{
                Policy                    = $Policy.DisplayName
                ExcludedUsers             = $ExcludedUsers -join ","
                TrustedLocationsAvailable = if ($Trusted.Count -gt 0) { "Yes" } else { "No" }
                CompensatingPolicies      = $CompensatingPolicies -join ","
                CompensatingPolicyCount   = $CompensatingPolicies.Count
            }
        }
    }
)

$TechnicalExclusionsWithCompensation = @($TechnicalAccountExclusions | Where-Object { $_.CompensatingPolicyCount -gt 0 })
$CA10Status = if ($TechnicalAccountExclusions.Count -eq 0) {
    "PASS"
}
elseif ($Trusted.Count -gt 0 -and $TechnicalExclusionsWithCompensation.Count -eq $TechnicalAccountExclusions.Count) {
    "WARNING"
}
else {
    "FAIL"
}

if ($CAAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.10" -AvailabilityState $CAAvailability
}
elseif ($LocationAvailability) {
    Export-ControlUnavailableFromState -ControlID "AAD.CA.10" -AvailabilityState $LocationAvailability
}
else {
    Export-ControlResult -ControlID "AAD.CA.10" -Data $TechnicalAccountExclusions -Result "$($TechnicalAccountExclusions.Count) policies exclude users; $($TechnicalExclusionsWithCompensation.Count) exclusions have a potential compensating enabled policy" -Status $CA10Status
}

Export-SummaryReport "ConditionalAccess"

Write-Host "Conditional Access audit completed."

