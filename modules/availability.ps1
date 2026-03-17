############################################################
# Availability and endpoint support model
############################################################

$script:AuditUnavailableStatuses = @(
    "NO_ACCESS",
    "LICENSE_REQUIRED",
    "NOT_SUPPORTED"
)

if (-not $Global:AuditAvailabilityState) {
    $Global:AuditAvailabilityState = @{}
}

function Get-AuditUnavailableStatuses {
    return $script:AuditUnavailableStatuses
}

function Test-AuditUnavailableStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    return $script:AuditUnavailableStatuses -contains $Status
}

function Resolve-AuditUnavailableStatus {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = @(
        $ErrorRecord.Exception.Message
        $ErrorRecord.ErrorDetails.Message
    ) -join " "

    $normalizedMessage = $message.ToLowerInvariant()

    if (
        $normalizedMessage -match "insufficient privileges" -or
        $normalizedMessage -match "insufficient privileges to complete the operation" -or
        $normalizedMessage -match "forbidden" -or
        $normalizedMessage -match "authorization_requestdenied" -or
        $normalizedMessage -match "access denied" -or
        $normalizedMessage -match "permission"
    ) {
        return "NO_ACCESS"
    }

    if (
        $normalizedMessage -match "license" -or
        $normalizedMessage -match "licensed" -or
        $normalizedMessage -match "subscription" -or
        $normalizedMessage -match "not available for this tenant" -or
        $normalizedMessage -match "requires aad premium" -or
        $normalizedMessage -match "requires azure ad premium"
    ) {
        return "LICENSE_REQUIRED"
    }

    if (
        $normalizedMessage -match "resource not found" -or
        $normalizedMessage -match "not supported" -or
        $normalizedMessage -match "unknown error" -or
        $normalizedMessage -match "not implemented" -or
        $normalizedMessage -match "request_unsupportedquery" -or
        $normalizedMessage -match "no odata route exists"
    ) {
        return "NOT_SUPPORTED"
    }

    return $null
}

function Set-AuditAvailabilityState {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [string]$Status,
        [string]$Reason,
        [string]$Source,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = if ($ErrorRecord) {
        $ErrorRecord.Exception.Message
    }
    else {
        $null
    }

    $Global:AuditAvailabilityState[$Key] = [PSCustomObject]@{
        Key     = $Key
        Status  = $Status
        Reason  = $Reason
        Source  = $Source
        Message = $message
    }
}

function Get-AuditAvailabilityState {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if ($Global:AuditAvailabilityState.ContainsKey($Key)) {
        return $Global:AuditAvailabilityState[$Key]
    }

    return $null
}

function Get-AuditFirstUnavailableState {
    param(
        [Parameter(Mandatory)]
        [string[]]$Keys
    )

    foreach ($key in $Keys) {
        $state = Get-AuditAvailabilityState -Key $key

        if ($state -and $state.Status -and $state.Status -ne "AVAILABLE") {
            return $state
        }
    }

    return $null
}

function New-AuditUnavailableData {
    param(
        [Parameter(Mandatory)]
        [string]$Status,
        [string]$Reason,
        [string]$Source,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = if ($ErrorRecord) {
        $ErrorRecord.Exception.Message
    }
    else {
        $null
    }

    return [PSCustomObject]@{
        Status  = $Status
        Reason  = $Reason
        Source  = $Source
        Message = $message
    }
}

function Export-ControlUnavailable {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [Parameter(Mandatory)]
        [ValidateSet("NO_ACCESS", "LICENSE_REQUIRED", "NOT_SUPPORTED")]
        [string]$Status,
        [Parameter(Mandatory)]
        [string]$Reason,
        [string]$Source,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $data = New-AuditUnavailableData -Status $Status -Reason $Reason -Source $Source -ErrorRecord $ErrorRecord

    Export-ControlResult -ControlID $ControlID -Data $data -Result $Reason -Status $Status
}

function Export-ControlUnavailableFromState {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [Parameter(Mandatory)]
        [object]$AvailabilityState
    )

    if (Test-AuditUnavailableStatus -Status $AvailabilityState.Status) {
        Export-ControlUnavailable `
            -ControlID $ControlID `
            -Status $AvailabilityState.Status `
            -Reason $AvailabilityState.Reason `
            -Source $AvailabilityState.Source
        return
    }

    $details = [PSCustomObject]@{
        Status  = $AvailabilityState.Status
        Reason  = $AvailabilityState.Reason
        Source  = $AvailabilityState.Source
        Message = $AvailabilityState.Message
    }

    $result = $AvailabilityState.Reason
    if ($AvailabilityState.Message) {
        $result = "$result Message: $($AvailabilityState.Message)"
    }

    Export-ControlResult -ControlID $ControlID -Data $details -Result $result -Status "ERROR"
}
