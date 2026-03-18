############################################################
# Graph Data Cache Module
############################################################

. "$PSScriptRoot\availability.ps1"

if (-not $Global:GraphCache) {
    $Global:GraphCache = @{}
}

function Get-CacheItem {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [scriptblock]$Loader
    )

    if (-not $Global:GraphCache.ContainsKey($Key)) {
        $Global:GraphCache[$Key] = & $Loader
    }

    return $Global:GraphCache[$Key]
}

function Get-CachedUsers {
    return Get-CacheItem -Key "Users" -Loader {
        Write-Host "Loading users from Graph..."
        try {
            $Users = Get-MgUser -All -ErrorAction Stop -Property `
                Id,
                DisplayName,
                UserPrincipalName,
                UserType,
                AccountEnabled,
                AssignedLicenses,
                OnPremisesSyncEnabled,
                CreatedDateTime

            $UsersById = @{}

            foreach ($User in $Users) {
                $UsersById[$User.Id] = $User
            }

            $Global:GraphCache["UsersById"] = $UsersById
            Set-AuditAvailabilityState -Key "Users" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgUser -All"
            return $Users
        }
        catch {
            Set-AuditAvailabilityState -Key "Users" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Users could not be retrieved" -Source "Get-MgUser -All" -ErrorRecord $_
            $Global:GraphCache["UsersById"] = @{}
            return @()
        }
    }
}

function Get-CachedUsersById {
    if (-not $Global:GraphCache.ContainsKey("UsersById")) {
        Get-CachedUsers | Out-Null
    }

    return $Global:GraphCache["UsersById"]
}

function Get-CachedCAPolicies {
    return Get-CacheItem -Key "CAPolicies" -Loader {
        Write-Host "Loading Conditional Access policies..."
        try {
            $result = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "CAPolicies" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgIdentityConditionalAccessPolicy -All"
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key "CAPolicies" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Conditional Access policies could not be retrieved" -Source "Get-MgIdentityConditionalAccessPolicy -All" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedLocations {
    return Get-CacheItem -Key "Locations" -Loader {
        Write-Host "Loading Named Locations..."
        try {
            $Locations = @(Get-MgIdentityConditionalAccessNamedLocation -All -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "Locations" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgIdentityConditionalAccessNamedLocation -All"

            @(
                foreach ($Location in $Locations) {
                    $AdditionalProperties = $Location.AdditionalProperties
                    $ResolvedIsTrusted = $false
                    $ResolvedType = $null

                    if ($Location.PSObject.Properties.Name -contains "IsTrusted" -and $null -ne $Location.IsTrusted) {
                        $ResolvedIsTrusted = [bool]$Location.IsTrusted
                    }
                    elseif ($AdditionalProperties -and $AdditionalProperties.ContainsKey("isTrusted")) {
                        $ResolvedIsTrusted = [bool]$AdditionalProperties["isTrusted"]
                    }

                    if ($AdditionalProperties -and $AdditionalProperties.ContainsKey("@odata.type")) {
                        $ResolvedType = $AdditionalProperties["@odata.type"]
                    }

                    [PSCustomObject]@{
                        Id               = $Location.Id
                        DisplayName      = $Location.DisplayName
                        CreatedDateTime  = $Location.CreatedDateTime
                        ModifiedDateTime = $Location.ModifiedDateTime
                        ODataType        = $ResolvedType
                        IsTrusted        = $ResolvedIsTrusted
                    }
                }
            )
        }
        catch {
            Set-AuditAvailabilityState -Key "Locations" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Named locations could not be retrieved" -Source "Get-MgIdentityConditionalAccessNamedLocation -All" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedRoles {
    return Get-CacheItem -Key "Roles" -Loader {
        Write-Host "Loading directory roles..."
        try {
            $result = @(Get-MgDirectoryRole -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "Roles" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgDirectoryRole"
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key "Roles" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Directory roles could not be retrieved" -Source "Get-MgDirectoryRole" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedRoleMembers {
    if (-not $Global:GraphCache.ContainsKey("RoleMembers")) {
        Write-Host "Loading directory role memberships..."

        $RoleMembers = @{}

        foreach ($Role in (Get-CachedRoles)) {
            try {
                $RoleMembers[$Role.Id] = @(Get-MgDirectoryRoleMember -DirectoryRoleId $Role.Id -All -ErrorAction Stop)
            }
            catch {
                $RoleMembers[$Role.Id] = @()
            }
        }

        $Global:GraphCache["RoleMembers"] = $RoleMembers
    }

    return $Global:GraphCache["RoleMembers"]
}

function Get-CachedPasswordProtectionPolicy {
    return Get-CacheItem -Key "PasswordProtection" -Loader {
        Write-Host "Loading password protection policy..."
        try {
            $result = Invoke-MgGraphRequest -Method GET -Uri "/beta/policies/authenticationMethodsPolicy/passwordProtection" -ErrorAction Stop
            Set-AuditAvailabilityState -Key "PasswordProtection" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Invoke-MgGraphRequest /beta/policies/authenticationMethodsPolicy/passwordProtection"
            $result
        }
        catch {
            $status = Resolve-AuditUnavailableStatus -ErrorRecord $_
            Set-AuditAvailabilityState -Key "PasswordProtection" -Status $(if ($status) { $status } else { "ERROR" }) -Reason "Password protection policy could not be retrieved" -Source "Invoke-MgGraphRequest /beta/policies/authenticationMethodsPolicy/passwordProtection" -ErrorRecord $_
            $null
        }
    }
}

function Get-CachedAuthorizationPolicy {
    return Get-CacheItem -Key "AuthorizationPolicy" -Loader {
        Write-Host "Loading authorization policy..."
        try {
            $result = Get-MgPolicyAuthorizationPolicy -ErrorAction Stop
            Set-AuditAvailabilityState -Key "AuthorizationPolicy" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgPolicyAuthorizationPolicy"
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key "AuthorizationPolicy" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Authorization policy could not be retrieved" -Source "Get-MgPolicyAuthorizationPolicy" -ErrorRecord $_
            $null
        }
    }
}

function Get-CachedOrganization {
    return Get-CacheItem -Key "Organization" -Loader {
        Write-Host "Loading organization details..."
        try {
            $result = @(Get-MgOrganization -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "Organization" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgOrganization"
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key "Organization" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Organization details could not be retrieved" -Source "Get-MgOrganization" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedDomains {
    return Get-CacheItem -Key "Domains" -Loader {
        Write-Host "Loading domains..."
        try {
            $result = @(Get-MgDomain -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "Domains" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgDomain"
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key "Domains" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Domains could not be retrieved" -Source "Get-MgDomain" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedSecurityDefaults {
    return Get-CacheItem -Key "SecurityDefaults" -Loader {
        Write-Host "Loading security defaults policy..."
        try {
            $result = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy -ErrorAction Stop
            Set-AuditAvailabilityState -Key "SecurityDefaults" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy"
            $result
        }
        catch {
            $status = Resolve-AuditUnavailableStatus -ErrorRecord $_
            Set-AuditAvailabilityState -Key "SecurityDefaults" -Status $(if ($status) { $status } else { "ERROR" }) -Reason "Security defaults policy could not be retrieved" -Source "Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy" -ErrorRecord $_
            $null
        }
    }
}

function Get-CachedGroupLifecyclePolicies {
    return Get-CacheItem -Key "GroupLifecyclePolicies" -Loader {
        Write-Host "Loading group lifecycle policies..."
        try {
            $result = @(Get-MgGroupLifecyclePolicy -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "GroupLifecyclePolicies" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgGroupLifecyclePolicy"
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key "GroupLifecyclePolicies" -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Group lifecycle policies could not be retrieved" -Source "Get-MgGroupLifecyclePolicy" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedAccessReviewDefinitions {
    return Get-CacheItem -Key "AccessReviewDefinitions" -Loader {
        Write-Host "Loading access review definitions..."
        try {
            $result = @(Get-MgIdentityGovernanceAccessReviewDefinition -All -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "AccessReviewDefinitions" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgIdentityGovernanceAccessReviewDefinition -All"
            $result
        }
        catch {
            $status = Resolve-AuditUnavailableStatus -ErrorRecord $_
            Set-AuditAvailabilityState -Key "AccessReviewDefinitions" -Status $(if ($status) { $status } else { "ERROR" }) -Reason "Access review definitions could not be retrieved" -Source "Get-MgIdentityGovernanceAccessReviewDefinition -All" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedTermsOfUse {
    return Get-CacheItem -Key "TermsOfUse" -Loader {
        Write-Host "Loading Terms of Use..."
        try {
            $result = @(Get-MgIdentityGovernanceTermsOfUse -All -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "TermsOfUse" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgIdentityGovernanceTermsOfUse -All"
            $result
        }
        catch {
            $status = Resolve-AuditUnavailableStatus -ErrorRecord $_
            Set-AuditAvailabilityState -Key "TermsOfUse" -Status $(if ($status) { $status } else { "ERROR" }) -Reason "Terms of Use could not be retrieved" -Source "Get-MgIdentityGovernanceTermsOfUse -All" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedUserRegistrationDetails {
    return Get-CacheItem -Key "UserRegistrationDetails" -Loader {
        Write-Host "Loading authentication registration details..."
        try {
            $result = @(Get-MgReportAuthenticationMethodUserRegistrationDetail -All -ErrorAction Stop)
            Set-AuditAvailabilityState -Key "UserRegistrationDetails" -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgReportAuthenticationMethodUserRegistrationDetail -All"
            $result
        }
        catch {
            $status = Resolve-AuditUnavailableStatus -ErrorRecord $_
            Set-AuditAvailabilityState -Key "UserRegistrationDetails" -Status $(if ($status) { $status } else { "ERROR" }) -Reason "Authentication registration details could not be retrieved" -Source "Get-MgReportAuthenticationMethodUserRegistrationDetail -All" -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedSignIns {
    param(
        [int]$Days = 90,
        [int]$Top = 0
    )

    $Key = if ($Top -gt 0) { "SignIns_${Days}_Top$Top" } else { "SignIns_$Days" }

    return Get-CacheItem -Key $Key -Loader {
        Write-Host "Loading sign-in logs for last $Days days..."

        $Since = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        try {
            if ($Top -gt 0) {
                $result = @(Get-MgAuditLogSignIn -Filter "createdDateTime ge $Since" -Top $Top -ErrorAction Stop)
            }
            else {
                $result = @(Get-MgAuditLogSignIn -Filter "createdDateTime ge $Since" -All -ErrorAction Stop)
            }

            Set-AuditAvailabilityState -Key $Key -Status "AVAILABLE" -Reason "Loaded successfully" -Source "Get-MgAuditLogSignIn"
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key $Key -Status $(if ($status = Resolve-AuditUnavailableStatus -ErrorRecord $_) { $status } else { "ERROR" }) -Reason "Sign-in logs could not be retrieved" -Source "Get-MgAuditLogSignIn" -ErrorRecord $_
            @()
        }
    }
}
