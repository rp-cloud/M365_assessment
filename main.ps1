Clear-Host

############################################################
# LOAD MODULES
############################################################

. "$PSScriptRoot\modules\reporting.ps1"
. "$PSScriptRoot\modules\cache.ps1"

############################################################
# INIT GLOBAL VARIABLES
############################################################

$Global:AuditSummary = @()

############################################################
# CONFIG
############################################################

$TenantId = "8c89bad5-dc8a-4e24-9873-0a6a9d8ba399"
$ClientId = "be3fb208-3add-47dc-87c8-5be8dae016b2"

$BasePath = $PSScriptRoot
$ReportsPath = "$BasePath\Reports"
$SummaryPath = "$ReportsPath\Summary"
$DetailedPath = "$ReportsPath\Detailed"

############################################################
# CHECK FOLDERS
############################################################

Write-Host "Checking folder structure..."

$Folders = @(
    $ReportsPath,
    $SummaryPath,
    $DetailedPath
)

foreach ($folder in $Folders) {

    if (!(Test-Path $folder)) {

        Write-Host "Creating folder $folder"

        New-Item -ItemType Directory -Path $folder | Out-Null

    }

}

############################################################
# CHECK GRAPH MODULE
############################################################

Write-Host "Checking Microsoft Graph module..."

$Module = Get-Module -ListAvailable -Name Microsoft.Graph

if (!$Module) {

    Write-Host "Microsoft.Graph module not found. Installing..."

    Install-Module Microsoft.Graph -Scope CurrentUser -Force

}

Import-Module Microsoft.Graph

############################################################
# LOGIN TO GRAPH
############################################################

Write-Host ""
Write-Host "==== Authentication ===="

Disconnect-MgGraph -ErrorAction SilentlyContinue

$ClientSecretCredential = Get-Credential -Credential $ClientId

Connect-MgGraph `
-TenantId $TenantId `
-ClientSecretCredential $ClientSecretCredential

Write-Host "Connected to Microsoft Graph"
Write-Host ""

############################################################
# PRELOAD GRAPH CACHE (OPTIMIZATION)
############################################################

Write-Host "Preloading Graph cache..."

Get-CachedUsers | Out-Null
Get-CachedCAPolicies | Out-Null
Get-CachedLocations | Out-Null
Get-CachedRoles | Out-Null

Write-Host "Graph cache ready"
Write-Host ""

############################################################
# MENU
############################################################

Write-Host ""
Write-Host "==== Microsoft EntraID Security Audit ===="
Write-Host ""
Write-Host "1 - Alerting and Reporting"
Write-Host "2 - Conditional Access"
Write-Host "3 - External Collaboration"
Write-Host "4 - Governance"
Write-Host "5 - Identity Management"
Write-Host "6 - Identity Protection"
Write-Host "7 - Privileged Access"
Write-Host "8 - Security Configuration"
Write-Host "9 - Run ALL controls"
Write-Host "0 - Exit"
Write-Host ""

$choice = Read-Host "Select option"

switch ($choice) {

    "1" { . "$BasePath\categories\alerting-reporting.ps1" }
    "2" { . "$BasePath\categories\conditional-access.ps1" }
    "3" { . "$BasePath\categories\external-collaboration.ps1" }
    "4" { . "$BasePath\categories\governance.ps1" }
    "5" { . "$BasePath\categories\identity-management.ps1" }
    "6" { . "$BasePath\categories\identity-protection.ps1" }
    "7" { . "$BasePath\categories\privileged-access.ps1" }
    "8" { . "$BasePath\categories\security-configuration.ps1" }
    "9" {
        . "$BasePath\categories\alerting-reporting.ps1"
        . "$BasePath\categories\conditional-access.ps1"
        . "$BasePath\categories\external-collaboration.ps1"
        . "$BasePath\categories\governance.ps1"
        . "$BasePath\categories\identity-management.ps1"
        . "$BasePath\categories\identity-protection.ps1"
        . "$BasePath\categories\privileged-access.ps1"
        . "$BasePath\categories\security-configuration.ps1"
    }
    "0" { exit }
    default { Write-Host "Invalid option" }

}