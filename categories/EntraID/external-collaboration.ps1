. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\cache_EntraID.ps1"

Write-Host "Running External Collaboration controls..."

$Global:AuditSummary = @()

$TotalControls = 4
$CurrentControl = 0

$Users = Get-CachedUsers
$SignIns90 = Get-CachedSignIns -Days 90
$GuestUsers = @($Users | Where-Object { $_.UserType -eq "Guest" })

$LastSignInByUser = @{}
foreach ($Entry in ($SignIns90 | Where-Object { $_.UserPrincipalName })) {
    if (-not $LastSignInByUser.ContainsKey($Entry.UserPrincipalName) -or $Entry.CreatedDateTime -gt $LastSignInByUser[$Entry.UserPrincipalName]) {
        $LastSignInByUser[$Entry.UserPrincipalName] = $Entry.CreatedDateTime
    }
}

############################################################
# AAD.EC.01
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.EC.01 External accounts inactive >30 days"

$Threshold30 = (Get-Date).AddDays(-30)
$InactiveExternal30 = @(
    $GuestUsers |
    Where-Object {
        (-not $LastSignInByUser.ContainsKey($_.UserPrincipalName)) -or
        $LastSignInByUser[$_.UserPrincipalName] -lt $Threshold30
    } |
    Select-Object DisplayName, UserPrincipalName, AccountEnabled, CreatedDateTime,
        @{Name = "LastSignInDateTime"; Expression = { if ($LastSignInByUser.ContainsKey($_.UserPrincipalName)) { $LastSignInByUser[$_.UserPrincipalName] } else { $null } } }
)

Export-ControlResult -ControlID "AAD.EC.01" -Data $InactiveExternal30 -Result "$($InactiveExternal30.Count) guest accounts show no sign-in activity in the last 30 days" -Status $(if ($InactiveExternal30.Count -eq 0) { "PASS" } else { "WARNING" })

############################################################
# AAD.EC.02
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.EC.02 Guest accounts inactive >90 days"

$Threshold90 = (Get-Date).AddDays(-90)
$InactiveExternal90 = @(
    $GuestUsers |
    Where-Object {
        (-not $LastSignInByUser.ContainsKey($_.UserPrincipalName)) -or
        $LastSignInByUser[$_.UserPrincipalName] -lt $Threshold90
    } |
    Select-Object DisplayName, UserPrincipalName, AccountEnabled, CreatedDateTime,
        @{Name = "LastSignInDateTime"; Expression = { if ($LastSignInByUser.ContainsKey($_.UserPrincipalName)) { $LastSignInByUser[$_.UserPrincipalName] } else { $null } } }
)

Export-ControlResult -ControlID "AAD.EC.02" -Data $InactiveExternal90 -Result "$($InactiveExternal90.Count) guest accounts show no sign-in activity in the last 90 days" -Status $(if ($InactiveExternal90.Count -eq 0) { "PASS" } else { "FAIL" })

############################################################
# AAD.EC.03
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.EC.03 Customer Lockbox"

$Organization = @(Get-CachedOrganization)
$Lockbox = @(
    $Organization |
    Select-Object DisplayName, CustomerLockboxAccess,
        @{Name = "LockboxEnabled"; Expression = { if ($_.CustomerLockboxAccess -eq "enabled") { "Yes" } else { "No" } } }
)

$LockboxEnabled = ($Lockbox | Where-Object { $_.LockboxEnabled -eq "Yes" }).Count -gt 0
Export-ControlResult -ControlID "AAD.EC.03" -Data $Lockbox -Result $(if ($LockboxEnabled) { "Customer Lockbox is enabled" } else { "Customer Lockbox is not enabled" }) -Status $(if ($LockboxEnabled) { "PASS" } else { "FAIL" })

############################################################
# AAD.EC.04
############################################################

$CurrentControl++
Write-Host "[$CurrentControl/$TotalControls] AAD.EC.04 Delegated administration partners"

try {
    $Partners = @(
        Get-MgTenantRelationshipDelegatedAdminRelationship -ErrorAction Stop |
        Select-Object DisplayName, Status, CreatedDateTime, LastModifiedDateTime, EndDateTime
    )
    $EC04Status = $null
    $EC04Result = $null
}
catch {
    $Partners = @(
        [PSCustomObject]@{
            Message = "Delegated administration relationships could not be retrieved automatically."
        }
    )
    $EC04Status = "MANUAL"
    $EC04Result = "Delegated administration relationships require manual verification"
}

if (-not $EC04Status) {
    $ExpiredPartners = @($Partners | Where-Object { $_.EndDateTime -and $_.EndDateTime -lt (Get-Date) })
    $EC04Status = if ($ExpiredPartners.Count -eq 0) { "PASS" } else { "WARNING" }
    $EC04Result = "$($ExpiredPartners.Count) delegated admin partner relationships are expired"
}

Export-ControlResult -ControlID "AAD.EC.04" -Data $Partners -Result $EC04Result -Status $EC04Status

Export-SummaryReport "ExternalCollaboration"

Write-Host "External Collaboration audit completed."

