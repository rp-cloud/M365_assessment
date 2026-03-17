. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running Conditional Access diagnostics..."

$Global:AuditSummary = @()

$Policies = @(Get-CachedCAPolicies)
$Locations = @(Get-CachedLocations)
$CAAvailability = Get-AuditAvailabilityState -Key "CAPolicies"
$LocationAvailability = Get-AuditAvailabilityState -Key "Locations"
$MgContext = Get-MgContext

$DiagnosticData = @(
    [PSCustomObject]@{
        CapturedAt               = Get-Date -Format "s"
        TenantId                 = if ($MgContext) { $MgContext.TenantId } else { $null }
        ClientId                 = if ($MgContext) { $MgContext.ClientId } else { $null }
        AuthType                 = if ($MgContext) { $MgContext.AuthType } else { $null }
        ContextScopes            = if ($MgContext) { $MgContext.Scopes -join "," } else { $null }
        CAPoliciesCount          = $Policies.Count
        NamedLocationsCount      = $Locations.Count
        CAPoliciesStatus         = if ($CAAvailability) { $CAAvailability.Status } else { "UNKNOWN" }
        CAPoliciesReason         = if ($CAAvailability) { $CAAvailability.Reason } else { "No availability state recorded" }
        CAPoliciesSource         = if ($CAAvailability) { $CAAvailability.Source } else { $null }
        CAPoliciesMessage        = if ($CAAvailability) { $CAAvailability.Message } else { $null }
        LocationsStatus          = if ($LocationAvailability) { $LocationAvailability.Status } else { "UNKNOWN" }
        LocationsReason          = if ($LocationAvailability) { $LocationAvailability.Reason } else { "No availability state recorded" }
        LocationsSource          = if ($LocationAvailability) { $LocationAvailability.Source } else { $null }
        LocationsMessage         = if ($LocationAvailability) { $LocationAvailability.Message } else { $null }
        SamplePolicyNames        = (@($Policies | Select-Object -First 10 -ExpandProperty DisplayName) -join " | ")
        SampleLocationNames      = (@($Locations | Select-Object -First 10 -ExpandProperty DisplayName) -join " | ")
        PoliciesWithUserActions  = @($Policies | Where-Object { @($_.Conditions.Applications.IncludeUserActions).Count -gt 0 }).Count
        PoliciesWithAppIncludes  = @($Policies | Where-Object { @($_.Conditions.Applications.IncludeApplications).Count -gt 0 }).Count
        PoliciesWithExclusions   = @($Policies | Where-Object { @($_.Conditions.Users.ExcludeUsers).Count -gt 0 -or @($_.Conditions.Users.ExcludeGroups).Count -gt 0 -or @($_.Conditions.Applications.ExcludeApplications).Count -gt 0 }).Count
    }
)

Export-ControlDetails -ControlID "CA.DIAG.01" -Data $DiagnosticData
Export-ControlDetails -ControlID "CA.DIAG.POLICIES" -Data @(
    $Policies |
    Select-Object -First 100 DisplayName, Id, State,
        @{Name = "IncludeUsers"; Expression = { @($_.Conditions.Users.IncludeUsers) -join "," } },
        @{Name = "ExcludeUsers"; Expression = { @($_.Conditions.Users.ExcludeUsers) -join "," } },
        @{Name = "IncludeGroups"; Expression = { @($_.Conditions.Users.IncludeGroups) -join "," } },
        @{Name = "ExcludeGroups"; Expression = { @($_.Conditions.Users.ExcludeGroups) -join "," } },
        @{Name = "IncludeApplications"; Expression = { @($_.Conditions.Applications.IncludeApplications) -join "," } },
        @{Name = "ExcludeApplications"; Expression = { @($_.Conditions.Applications.ExcludeApplications) -join "," } },
        @{Name = "IncludeUserActions"; Expression = { @($_.Conditions.Applications.IncludeUserActions) -join "," } },
        @{Name = "SignInRiskLevels"; Expression = { @($_.Conditions.SignInRiskLevels) -join "," } },
        @{Name = "UserRiskLevels"; Expression = { @($_.Conditions.UserRiskLevels) -join "," } },
        @{Name = "IncludePlatforms"; Expression = { @($_.Conditions.Platforms.IncludePlatforms) -join "," } },
        @{Name = "ExcludePlatforms"; Expression = { @($_.Conditions.Platforms.ExcludePlatforms) -join "," } },
        @{Name = "BuiltInControls"; Expression = { @($_.GrantControls.BuiltInControls) -join "," } },
        @{Name = "AuthenticationStrengthId"; Expression = { $_.GrantControls.AuthenticationStrength.Id } }
)
Export-ControlDetails -ControlID "CA.DIAG.LOCATIONS" -Data @(
    $Locations |
    Select-Object -First 100 DisplayName, Id, IsTrusted, ODataType, CreatedDateTime, ModifiedDateTime
)

Write-Host "Conditional Access diagnostics exported to Reports/Detailed"
