function Initialize-EntraGraphSession {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    if (-not $Global:EntraGraphInitialized) {
        $Global:EntraGraphInitialized = $false
    }

    if ($Global:EntraGraphInitialized) {
        return
    }

    Write-Host 'Checking Microsoft Graph module...'

    $module = Get-Module -ListAvailable -Name Microsoft.Graph

    if (-not $module) {
        Write-Host 'Microsoft.Graph module not found. Installing...'
        Install-Module Microsoft.Graph -Scope CurrentUser -Force
    }

    Import-Module Microsoft.Graph

    Write-Host ''
    Write-Host '==== EntraID Authentication ===='

    Disconnect-MgGraph -ErrorAction SilentlyContinue

    $clientSecretCredential = Get-Credential -Credential $Context.ClientId

    Connect-MgGraph `
    -TenantId $Context.TenantId `
    -ClientSecretCredential $clientSecretCredential

    Write-Host 'Connected to Microsoft Graph'
    Write-Host ''

    Write-Host 'Preloading EntraID Graph cache...'

    Get-CachedUsers | Out-Null
    Get-CachedCAPolicies | Out-Null
    Get-CachedLocations | Out-Null
    Get-CachedRoles | Out-Null

    Write-Host 'EntraID Graph cache ready'
    Write-Host ''

    $Global:EntraGraphInitialized = $true
}
