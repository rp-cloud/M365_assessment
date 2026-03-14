Clear-Host

. "$PSScriptRoot\modules\reporting.ps1"
. "$PSScriptRoot\modules\cache_EntraID.ps1"
. "$PSScriptRoot\modules\framework.ps1"
. "$PSScriptRoot\modules\bootstrap_EntraID.ps1"
. "$PSScriptRoot\modules\bootstrap_Exchange.ps1"
. "$PSScriptRoot\modules\bootstrap_OneDrive.ps1"
. "$PSScriptRoot\modules\navigation.ps1"

$Global:AuditSummary = @()
$Global:EntraGraphInitialized = $false
$Global:ExchangeSessionInitialized = $false
$Global:OneDriveSessionInitialized = $false

$context = New-AppContext `
    -BasePath $PSScriptRoot `
    -TenantId '8c89bad5-dc8a-4e24-9873-0a6a9d8ba399' `
    -ClientId 'be3fb208-3add-47dc-87c8-5be8dae016b2'

Ensure-FrameworkFolders -Context $context
Start-MainMenu -Context $context
