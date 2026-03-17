. "$PSScriptRoot\..\..\modules\reporting.ps1"
. "$PSScriptRoot\..\..\modules\availability.ps1"
. "$PSScriptRoot\..\..\modules\cache_Exchange.ps1"

Set-ControlCatalogPath -Path (Join-Path $PSScriptRoot 'm365_exchange.json')

Write-Host 'Running Exchange controls...'

$Global:AuditSummary = @()

$OrganizationConfig = Get-CachedExoOrganizationConfig
$OwaPolicies = @(Get-CachedExoOwaMailboxPolicies)
$Mailboxes = @(Get-CachedExoMailboxes)
$CasMailboxes = @(Get-CachedExoCasMailboxes)
$TransportConfig = Get-CachedExoTransportConfig
$SharingPolicies = @(Get-CachedExoSharingPolicies)

$OrgAvailability = Get-AuditFirstUnavailableState -Keys @('ExoOrganizationConfig')
$OwaAvailability = Get-AuditFirstUnavailableState -Keys @('ExoOwaMailboxPolicies')
$MailboxAvailability = Get-AuditFirstUnavailableState -Keys @('ExoMailboxes')
$CasAvailability = Get-AuditFirstUnavailableState -Keys @('ExoCasMailboxes')
$TransportAvailability = Get-AuditFirstUnavailableState -Keys @('ExoTransportConfig')
$SharingAvailability = Get-AuditFirstUnavailableState -Keys @('ExoSharingPolicies')

function Export-ExchangeManualControl {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [Parameter(Mandatory)]
        [string]$Result,
        [string]$Scope,
        [string]$Evidence
    )

    Export-ControlResult -ControlID $ControlID -Data @([PSCustomObject]@{
        Verification = 'Manual'
        Scope = $Scope
        Evidence = $Evidence
    }) -Result $Result -Status 'MANUAL'
}

############################################################
# EXCH.AR.01
############################################################
Export-ExchangeManualControl -ControlID 'EXCH.AR.01' -Result 'Manual verification required for weekly review of account provisioning activity' -Scope 'Exchange audit / provisioning reports' -Evidence 'Confirm that weekly review of account provisioning activity is documented and evidenced'

############################################################
# EXCH.AR.02
############################################################
Export-ExchangeManualControl -ControlID 'EXCH.AR.02' -Result 'Manual verification required for weekly review of mailbox forwarding rules' -Scope 'Mail flow rules and mailbox forwarding review process' -Evidence 'Confirm that forwarding-related reviews are performed weekly and retained as evidence'

############################################################
# EXCH.ON.01
############################################################
Export-ExchangeManualControl -ControlID 'EXCH.ON.01' -Result 'Manual verification required for default role assignment policy controlling Outlook add-ins' -Scope 'Default Role Assignment Policy' -Evidence 'Validate that user self-service Outlook add-in roles are removed from the default assignment policy'

############################################################
# EXCH.ON.02
############################################################
if ($OrgAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.02' -AvailabilityState $OrgAvailability
}
else {
    $modernAuthEnabled = $null -ne $OrganizationConfig -and $OrganizationConfig.OAuth2ClientProfileEnabled -eq $true
    $data = @([PSCustomObject]@{ OAuth2ClientProfileEnabled = if ($null -ne $OrganizationConfig) { $OrganizationConfig.OAuth2ClientProfileEnabled } else { $null } })
    Export-ControlResult -ControlID 'EXCH.ON.02' -Data $data -Result "OAuth2ClientProfileEnabled = $($data[0].OAuth2ClientProfileEnabled)" -Status $(if ($modernAuthEnabled) { 'PASS' } else { 'FAIL' })
}

############################################################
# EXCH.ON.03
############################################################
Export-ExchangeManualControl -ControlID 'EXCH.ON.03' -Result 'Manual review required for FullAccess delegation governance' -Scope 'Mailbox delegation (FullAccess)' -Evidence 'Review delegated mailboxes and confirm approval process exists for FullAccess permissions'

############################################################
# EXCH.ON.04
############################################################
$externalStorageEnabledPolicies = @(
    $OwaPolicies |
    Where-Object { $_.AdditionalStorageProvidersAvailable -eq $true } |
    Select-Object Name, AdditionalStorageProvidersAvailable
)
if ($OwaAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.04' -AvailabilityState $OwaAvailability
}
else {
    Export-ControlResult -ControlID 'EXCH.ON.04' -Data $(if ($externalStorageEnabledPolicies.Count -gt 0) { $externalStorageEnabledPolicies } else { @($OwaPolicies | Select-Object Name, AdditionalStorageProvidersAvailable) }) -Result "$($externalStorageEnabledPolicies.Count) OWA policies allow external storage providers" -Status $(if ($externalStorageEnabledPolicies.Count -eq 0 -and $OwaPolicies.Count -gt 0) { 'PASS' } else { 'FAIL' })
}

############################################################
# EXCH.ON.05
############################################################
Export-ExchangeManualControl -ControlID 'EXCH.ON.05' -Result 'Manual verification required for Outlook offline access policy' -Scope 'OWA mailbox policy offline access settings' -Evidence 'Confirm offline access is set to Never in the effective OWA policy used by users'

############################################################
# EXCH.ON.06
############################################################
$activeSyncEnabledMailboxes = @(
    $CasMailboxes |
    Where-Object { $_.ActiveSyncEnabled -eq $true } |
    Select-Object DisplayName, PrimarySmtpAddress, ActiveSyncEnabled
)
if ($CasAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.06' -AvailabilityState $CasAvailability
}
else {
    Export-ControlResult -ControlID 'EXCH.ON.06' -Data $activeSyncEnabledMailboxes -Result "$($activeSyncEnabledMailboxes.Count) mailboxes still have Exchange ActiveSync enabled" -Status $(if ($activeSyncEnabledMailboxes.Count -eq 0 -and $CasMailboxes.Count -gt 0) { 'PASS' } else { 'WARNING' })
}

############################################################
# EXCH.ON.07
############################################################
Export-ExchangeManualControl -ControlID 'EXCH.ON.07' -Result 'Manual verification required for restricting mail apps to Outlook and protected mobile apps' -Scope 'Intune app protection and Conditional Access' -Evidence 'Validate that desktop and mobile Exchange access is constrained to approved Outlook clients or explicitly authorized alternatives'

############################################################
# EXCH.ON.08
############################################################
$mailboxesWithoutAudit = @(
    $Mailboxes |
    Where-Object { $_.AuditEnabled -ne $true } |
    Select-Object DisplayName, PrimarySmtpAddress, AuditEnabled
)
if ($MailboxAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.08' -AvailabilityState $MailboxAvailability
}
else {
    Export-ControlResult -ControlID 'EXCH.ON.08' -Data $mailboxesWithoutAudit -Result "$($mailboxesWithoutAudit.Count) mailboxes do not have auditing enabled" -Status $(if ($mailboxesWithoutAudit.Count -eq 0 -and $Mailboxes.Count -gt 0) { 'PASS' } else { 'FAIL' })
}

############################################################
# EXCH.ON.09
############################################################
if ($SharingAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.09' -AvailabilityState $SharingAvailability
}
else {
    $sharingData = @(
        $SharingPolicies |
        Select-Object Name,
            @{Name = 'Domains'; Expression = { @($_.Domains) -join '; ' } },
            Enabled
    )
    $externalSharingPolicies = @($SharingPolicies | Where-Object { @($_.Domains) -match 'Anonymous|CalendarSharingFreeBusy(Simple|Detail)?' })
    Export-ControlResult -ControlID 'EXCH.ON.09' -Data $sharingData -Result "$($externalSharingPolicies.Count) sharing policies expose external calendar sharing entries that require review" -Status $(if ($externalSharingPolicies.Count -eq 0 -and $SharingPolicies.Count -gt 0) { 'PASS' } else { 'WARNING' })
}

############################################################
# EXCH.ON.10
############################################################
$imapEnabledMailboxes = @(
    $CasMailboxes |
    Where-Object { $_.ImapEnabled -eq $true } |
    Select-Object DisplayName, PrimarySmtpAddress, ImapEnabled
)
if ($CasAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.10' -AvailabilityState $CasAvailability
}
else {
    Export-ControlResult -ControlID 'EXCH.ON.10' -Data $imapEnabledMailboxes -Result "$($imapEnabledMailboxes.Count) mailboxes still have IMAP enabled" -Status $(if ($imapEnabledMailboxes.Count -eq 0 -and $CasMailboxes.Count -gt 0) { 'PASS' } else { 'FAIL' })
}

############################################################
# EXCH.ON.12
############################################################
$popEnabledMailboxes = @(
    $CasMailboxes |
    Where-Object { $_.PopEnabled -eq $true } |
    Select-Object DisplayName, PrimarySmtpAddress, PopEnabled
)
if ($CasAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.12' -AvailabilityState $CasAvailability
}
else {
    Export-ControlResult -ControlID 'EXCH.ON.12' -Data $popEnabledMailboxes -Result "$($popEnabledMailboxes.Count) mailboxes still have POP3 enabled" -Status $(if ($popEnabledMailboxes.Count -eq 0 -and $CasMailboxes.Count -gt 0) { 'PASS' } else { 'FAIL' })
}

############################################################
# EXCH.ON.13
############################################################
$sendOnBehalfAssignments = @(
    $Mailboxes |
    Where-Object { @($_.GrantSendOnBehalfTo).Count -gt 0 } |
    Select-Object DisplayName, PrimarySmtpAddress,
        @{Name = 'GrantSendOnBehalfTo'; Expression = { @($_.GrantSendOnBehalfTo) -join '; ' } }
)
if ($MailboxAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.13' -AvailabilityState $MailboxAvailability
}
else {
    Export-ControlResult -ControlID 'EXCH.ON.13' -Data $sendOnBehalfAssignments -Result "$($sendOnBehalfAssignments.Count) mailboxes have SendOnBehalfOf delegates that should be reviewed" -Status $(if ($sendOnBehalfAssignments.Count -eq 0) { 'PASS' } else { 'WARNING' })
}

############################################################
# EXCH.ON.14
############################################################
$smtpEnabledMailboxes = @(
    $CasMailboxes |
    Where-Object { $_.SmtpClientAuthenticationDisabled -ne $true } |
    Select-Object DisplayName, PrimarySmtpAddress, SmtpClientAuthenticationDisabled
)
if ($TransportAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.14' -AvailabilityState $TransportAvailability
}
elseif ($CasAvailability) {
    Export-ControlUnavailableFromState -ControlID 'EXCH.ON.14' -AvailabilityState $CasAvailability
}
else {
    $orgSmtpDisabled = $null -ne $TransportConfig -and $TransportConfig.SmtpClientAuthenticationDisabled -eq $true
    $data = @(
        [PSCustomObject]@{
            OrganizationSmtpClientAuthenticationDisabled = if ($null -ne $TransportConfig) { $TransportConfig.SmtpClientAuthenticationDisabled } else { $null }
            MailboxesWithSmtpAuthEnabled = $smtpEnabledMailboxes.Count
        }
    ) + $smtpEnabledMailboxes
    $status = if ($orgSmtpDisabled -and $smtpEnabledMailboxes.Count -eq 0) { 'PASS' } elseif ($orgSmtpDisabled) { 'WARNING' } else { 'FAIL' }
    Export-ControlResult -ControlID 'EXCH.ON.14' -Data $data -Result "Organization SMTP AUTH disabled: $orgSmtpDisabled; mailboxes with SMTP AUTH enabled: $($smtpEnabledMailboxes.Count)" -Status $status
}

############################################################
# EXCH.ON.15
############################################################
Export-ExchangeManualControl -ControlID 'EXCH.ON.15' -Result 'Manual verification required for SendAs delegate approval workflow' -Scope 'Mailbox delegation (SendAs)' -Evidence 'Review SendAs assignments and confirm approval and periodic review process exists'

Export-SummaryReport 'Exchange'

Write-Host 'Exchange audit completed.'
