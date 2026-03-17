############################################################
# Exchange Online Cache Module
############################################################

. "$PSScriptRoot\availability.ps1"

if (-not $Global:ExchangeCache) {
    $Global:ExchangeCache = @{}
}

function Get-ExchangeCacheItem {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [scriptblock]$Loader
    )

    if (-not $Global:ExchangeCache.ContainsKey($Key)) {
        $Global:ExchangeCache[$Key] = & $Loader
    }

    return $Global:ExchangeCache[$Key]
}

function Get-CachedExoOrganizationConfig {
    return Get-ExchangeCacheItem -Key 'ExoOrganizationConfig' -Loader {
        Write-Host 'Loading Exchange organization configuration...'
        try {
            $result = Get-OrganizationConfig -ErrorAction Stop
            Set-AuditAvailabilityState -Key 'ExoOrganizationConfig' -Status 'AVAILABLE' -Reason 'Loaded successfully' -Source 'Get-OrganizationConfig'
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key 'ExoOrganizationConfig' -Status 'ERROR' -Reason 'Exchange organization configuration could not be retrieved' -Source 'Get-OrganizationConfig' -ErrorRecord $_
            $null
        }
    }
}

function Get-CachedExoOwaMailboxPolicies {
    return Get-ExchangeCacheItem -Key 'ExoOwaMailboxPolicies' -Loader {
        Write-Host 'Loading OWA mailbox policies...'
        try {
            $result = @(Get-OwaMailboxPolicy -ErrorAction Stop)
            Set-AuditAvailabilityState -Key 'ExoOwaMailboxPolicies' -Status 'AVAILABLE' -Reason 'Loaded successfully' -Source 'Get-OwaMailboxPolicy'
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key 'ExoOwaMailboxPolicies' -Status 'ERROR' -Reason 'OWA mailbox policies could not be retrieved' -Source 'Get-OwaMailboxPolicy' -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedExoMailboxes {
    return Get-ExchangeCacheItem -Key 'ExoMailboxes' -Loader {
        Write-Host 'Loading Exchange mailboxes...'
        try {
            $result = @(Get-EXOMailbox -ResultSize Unlimited -Properties DisplayName,PrimarySmtpAddress,AuditEnabled,GrantSendOnBehalfTo -ErrorAction Stop)
            Set-AuditAvailabilityState -Key 'ExoMailboxes' -Status 'AVAILABLE' -Reason 'Loaded successfully' -Source 'Get-EXOMailbox'
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key 'ExoMailboxes' -Status 'ERROR' -Reason 'Exchange mailboxes could not be retrieved' -Source 'Get-EXOMailbox' -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedExoCasMailboxes {
    return Get-ExchangeCacheItem -Key 'ExoCasMailboxes' -Loader {
        Write-Host 'Loading Exchange CAS mailbox settings...'
        try {
            $result = @(Get-EXOCASMailbox -ResultSize Unlimited -Properties DisplayName,PrimarySmtpAddress,ImapEnabled,PopEnabled,SmtpClientAuthenticationDisabled,ActiveSyncEnabled -ErrorAction Stop)
            Set-AuditAvailabilityState -Key 'ExoCasMailboxes' -Status 'AVAILABLE' -Reason 'Loaded successfully' -Source 'Get-EXOCASMailbox'
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key 'ExoCasMailboxes' -Status 'ERROR' -Reason 'Exchange CAS mailbox settings could not be retrieved' -Source 'Get-EXOCASMailbox' -ErrorRecord $_
            @()
        }
    }
}

function Get-CachedExoTransportConfig {
    return Get-ExchangeCacheItem -Key 'ExoTransportConfig' -Loader {
        Write-Host 'Loading Exchange transport configuration...'
        try {
            $result = Get-TransportConfig -ErrorAction Stop
            Set-AuditAvailabilityState -Key 'ExoTransportConfig' -Status 'AVAILABLE' -Reason 'Loaded successfully' -Source 'Get-TransportConfig'
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key 'ExoTransportConfig' -Status 'ERROR' -Reason 'Exchange transport configuration could not be retrieved' -Source 'Get-TransportConfig' -ErrorRecord $_
            $null
        }
    }
}

function Get-CachedExoSharingPolicies {
    return Get-ExchangeCacheItem -Key 'ExoSharingPolicies' -Loader {
        Write-Host 'Loading Exchange sharing policies...'
        try {
            $result = @(Get-SharingPolicy -ErrorAction Stop)
            Set-AuditAvailabilityState -Key 'ExoSharingPolicies' -Status 'AVAILABLE' -Reason 'Loaded successfully' -Source 'Get-SharingPolicy'
            $result
        }
        catch {
            Set-AuditAvailabilityState -Key 'ExoSharingPolicies' -Status 'ERROR' -Reason 'Exchange sharing policies could not be retrieved' -Source 'Get-SharingPolicy' -ErrorRecord $_
            @()
        }
    }
}
