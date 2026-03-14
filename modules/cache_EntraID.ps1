############################################################
# Graph Data Cache Module
############################################################

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

        $Users = Get-MgUser -All -Property `
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
        return $Users
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
        Get-MgIdentityConditionalAccessPolicy
    }
}

function Get-CachedLocations {
    return Get-CacheItem -Key "Locations" -Loader {
        Write-Host "Loading Named Locations..."

        $Locations = @(Get-MgIdentityConditionalAccessNamedLocation -All)

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
}

function Get-CachedRoles {
    return Get-CacheItem -Key "Roles" -Loader {
        Write-Host "Loading directory roles..."
        Get-MgDirectoryRole
    }
}

function Get-CachedRoleMembers {
    if (-not $Global:GraphCache.ContainsKey("RoleMembers")) {
        Write-Host "Loading directory role memberships..."

        $RoleMembers = @{}

        foreach ($Role in (Get-CachedRoles)) {
            try {
                $RoleMembers[$Role.Id] = @(Get-MgDirectoryRoleMember -DirectoryRoleId $Role.Id -All)
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
        Invoke-MgGraphRequest -Method GET -Uri "/beta/policies/authenticationMethodsPolicy/passwordProtection"
    }
}

function Get-CachedAuthorizationPolicy {
    return Get-CacheItem -Key "AuthorizationPolicy" -Loader {
        Write-Host "Loading authorization policy..."
        Get-MgPolicyAuthorizationPolicy
    }
}

function Get-CachedOrganization {
    return Get-CacheItem -Key "Organization" -Loader {
        Write-Host "Loading organization details..."
        Get-MgOrganization
    }
}

function Get-CachedDomains {
    return Get-CacheItem -Key "Domains" -Loader {
        Write-Host "Loading domains..."
        Get-MgDomain
    }
}

function Get-CachedSecurityDefaults {
    return Get-CacheItem -Key "SecurityDefaults" -Loader {
        Write-Host "Loading security defaults policy..."
        try {
            Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy
        }
        catch {
            $null
        }
    }
}

function Get-CachedGroupLifecyclePolicies {
    return Get-CacheItem -Key "GroupLifecyclePolicies" -Loader {
        Write-Host "Loading group lifecycle policies..."
        try {
            @(Get-MgGroupLifecyclePolicy)
        }
        catch {
            @()
        }
    }
}

function Get-CachedAccessReviewDefinitions {
    return Get-CacheItem -Key "AccessReviewDefinitions" -Loader {
        Write-Host "Loading access review definitions..."
        try {
            @(Get-MgIdentityGovernanceAccessReviewDefinition -All)
        }
        catch {
            @()
        }
    }
}

function Get-CachedTermsOfUse {
    return Get-CacheItem -Key "TermsOfUse" -Loader {
        Write-Host "Loading Terms of Use..."
        try {
            @(Get-MgIdentityGovernanceTermsOfUse -All)
        }
        catch {
            @()
        }
    }
}

function Get-CachedUserRegistrationDetails {
    return Get-CacheItem -Key "UserRegistrationDetails" -Loader {
        Write-Host "Loading authentication registration details..."
        try {
            @(Get-MgReportAuthenticationMethodUserRegistrationDetail -All)
        }
        catch {
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
                @(Get-MgAuditLogSignIn -Filter "createdDateTime ge $Since" -Top $Top)
            }
            else {
                @(Get-MgAuditLogSignIn -Filter "createdDateTime ge $Since" -All)
            }
        }
        catch {
            @()
        }
    }
}
