Clear-Host

. "$PSScriptRoot\modules\reporting.ps1"
. "$PSScriptRoot\modules\availability.ps1"
. "$PSScriptRoot\modules\cache_EntraID.ps1"
. "$PSScriptRoot\modules\cache_Exchange.ps1"

$Global:AuditSummary = @()
$Global:EntraGraphInitialized = $false
$Global:ExchangeSessionInitialized = $false
$Global:OneDriveSessionInitialized = $false

$TenantId = '8c89bad5-dc8a-4e24-9873-0a6a9d8ba399'
$ClientId = 'be3fb208-3add-47dc-87c8-5be8dae016b2'
$CertificateThumbprint = ''
$ExchangeOrganization = ''
$ReportsPath = Join-Path $PSScriptRoot 'Reports'
$SummaryPath = Join-Path $ReportsPath 'Summary'
$DetailedPath = Join-Path $ReportsPath 'Detailed'
$EntraPath = Join-Path $PSScriptRoot 'categories\EntraID'
$ExchangePath = Join-Path $PSScriptRoot 'categories\Exchange'
$OneDrivePath = Join-Path $PSScriptRoot 'categories\OneDrive'

function Ensure-EntraSession {
    if ($Global:EntraGraphInitialized) {
        return
    }

    Write-Host 'Checking Graph module...'

    $graphModule = Get-Module -ListAvailable -Name Microsoft.Graph
    if (-not $graphModule) {
        Write-Host 'Installing Graph module...'
        Install-Module Microsoft.Graph -Scope CurrentUser -Force
    }

    Import-Module Microsoft.Graph

    Write-Host ''
    Write-Host '==== EntraID Login ===='

    Disconnect-MgGraph -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        throw 'Set $CertificateThumbprint in main.ps1.'
    }

    Connect-MgGraph `
        -TenantId $TenantId `
        -ClientId $ClientId `
        -CertificateThumbprint $CertificateThumbprint

    Write-Host 'Connected to Graph'
    Write-Host ''
    Write-Host 'Loading EntraID cache...'

    Get-CachedUsers | Out-Null
    Get-CachedCAPolicies | Out-Null
    Get-CachedLocations | Out-Null
    Get-CachedRoles | Out-Null

    Write-Host 'EntraID cache ready'
    Write-Host ''

    $Global:EntraGraphInitialized = $true
}

function Ensure-ExchangeSession {
    if ($Global:ExchangeSessionInitialized) {
        return
    }

    Write-Host 'Checking Exchange module...'

    $exchangeModule = Get-Module -ListAvailable -Name ExchangeOnlineManagement
    if (-not $exchangeModule) {
        Write-Host 'Installing Exchange module...'
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
        if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
            throw 'Set $CertificateThumbprint in main.ps1.'
        }

        if ([string]::IsNullOrWhiteSpace($ExchangeOrganization)) {
            throw 'Set $ExchangeOrganization in main.ps1.'
        }

        Write-Host ''
        Write-Host '==== Exchange Login ===='
        Connect-ExchangeOnline `
            -AppId $ClientId `
            -CertificateThumbprint $CertificateThumbprint `
            -Organization $ExchangeOrganization `
            -ShowBanner:$false
        Write-Host 'Connected to Exchange'
        Write-Host ''
    }

    Write-Host 'Loading Exchange cache...'
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

function Ensure-OneDriveSession {
    if ($Global:OneDriveSessionInitialized) {
        return
    }

    Write-Host ''
    Write-Host '==== OneDrive ===='
    Write-Host 'OneDrive module is still a placeholder.'
    Write-Host ''

    $Global:OneDriveSessionInitialized = $true
}

Write-Host 'Checking folder structure...'

foreach ($folder in @($ReportsPath, $SummaryPath, $DetailedPath)) {
    if (-not (Test-Path $folder)) {
        Write-Host "Creating folder $folder"
        New-Item -ItemType Directory -Path $folder | Out-Null
    }
}

$exitRequested = $false

while (-not $exitRequested) {
    Write-Host ''
    Write-Host '==== Microsoft 365 Security Audit ===='
    Write-Host ''
    Write-Host '1 - EntraID'
    Write-Host '2 - Exchange'
    Write-Host '3 - OneDrive'
    Write-Host '0 - Exit'
    Write-Host ''

    $choice = Read-Host 'Select option'

    switch ($choice) {
        '1' {
            Ensure-EntraSession
            Set-ControlCatalogPath -Path (Join-Path $EntraPath 'm365_entraID.json')

            . (Join-Path $EntraPath 'alerting-reporting.ps1')
            . (Join-Path $EntraPath 'conditional-access.ps1')
            . (Join-Path $EntraPath 'external-collaboration.ps1')
            . (Join-Path $EntraPath 'governance.ps1')
            . (Join-Path $EntraPath 'identity-management.ps1')
            . (Join-Path $EntraPath 'identity-protection.ps1')
            . (Join-Path $EntraPath 'privileged-access.ps1')
            . (Join-Path $EntraPath 'security-configuration.ps1')
        }
        '2' {
            Ensure-ExchangeSession
            Set-ControlCatalogPath -Path (Join-Path $ExchangePath 'm365_exchange.json')
            . (Join-Path $ExchangePath 'mail-flow.ps1')
        }
        '3' {
            Ensure-OneDriveSession
            . (Join-Path $OneDrivePath 'sharing.ps1')
        }
        '0' {
            $exitRequested = $true
        }
        default {
            Write-Host 'Invalid option'
        }
    }
}
