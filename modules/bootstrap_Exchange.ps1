. "$PSScriptRoot\cache_Exchange.ps1"

function Initialize-ExchangeSession {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    if (-not $Global:ExchangeSessionInitialized) {
        $Global:ExchangeSessionInitialized = $false
    }

    if ($Global:ExchangeSessionInitialized) {
        return
    }

    Write-Host 'Checking ExchangeOnlineManagement module...'

    $module = Get-Module -ListAvailable -Name ExchangeOnlineManagement

    if (-not $module) {
        Write-Host 'ExchangeOnlineManagement module not found. Installing...'
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }

    Import-Module ExchangeOnlineManagement

    $connectionInfo = @()
    try {
        $connectionInfo = @(Get-ConnectionInformation -ErrorAction Stop | Where-Object { $_.State -eq 'Connected' })
    }
    catch {
        $connectionInfo = @()
    }

    if ($connectionInfo.Count -eq 0) {
        Write-Host ''
        Write-Host '==== Exchange Authentication ===='
        Connect-ExchangeOnline -ShowBanner:$false
        Write-Host 'Connected to Exchange Online'
        Write-Host ''
    }

    Write-Host 'Preloading Exchange cache...'
    Get-CachedExoOrganizationConfig | Out-Null
    Get-CachedExoOwaMailboxPolicies | Out-Null
    Get-CachedExoMailboxes | Out-Null
    Get-CachedExoCasMailboxes | Out-Null
    Get-CachedExoTransportConfig | Out-Null
    Get-CachedExoSharingPolicies | Out-Null
    Write-Host 'Exchange cache ready'
    Write-Host ''

    $Global:ExchangeSessionInitialized = $true
}
