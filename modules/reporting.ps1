############################################################
# Reporting module for EntraID Audit
############################################################

$script:AuditBasePath = Split-Path -Parent $PSScriptRoot
$script:DetailedReportPath = Join-Path $script:AuditBasePath "Reports\Detailed"
$script:SummaryReportPath = Join-Path $script:AuditBasePath "Reports\Summary"
$script:ControlCatalogPath = Join-Path $script:AuditBasePath "m365_controls.json"

if (-not $Global:ControlCatalog) {
    $Global:ControlCatalog = @{}
}

function Initialize-ControlCatalog {
    if ($Global:ControlCatalog.Count -gt 0) {
        return
    }

    if (-not (Test-Path $script:ControlCatalogPath)) {
        throw "Control catalog not found: $script:ControlCatalogPath"
    }

    $RawCatalog = Get-Content -Raw $script:ControlCatalogPath

    # The source file contains a few broken strings like te"N/A"t/gouver"N/A"ce.
    # Repair only the invalid quoted fragment inside words and keep standalone "N/A" values untouched.
    $SanitizedCatalog = [regex]::Replace($RawCatalog, '(?<=[A-Za-z])"N/A"(?=[A-Za-z])', 'n')

    $Definitions = $SanitizedCatalog | ConvertFrom-Json

    foreach ($Definition in $Definitions) {
        $Global:ControlCatalog[$Definition.Control_ID] = $Definition
    }
}

function Get-ControlDefinition {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID
    )

    Initialize-ControlCatalog

    if (-not $Global:ControlCatalog.ContainsKey($ControlID)) {
        throw "Control definition not found for $ControlID"
    }

    return $Global:ControlCatalog[$ControlID]
}

function Add-SummaryEntry {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [Parameter(Mandatory)]
        [string]$Result,
        [Parameter(Mandatory)]
        [ValidateSet("PASS", "FAIL", "WARNING", "INFO", "MANUAL", "ERROR")]
        [string]$Status
    )

    $Definition = Get-ControlDefinition -ControlID $ControlID

    $Global:AuditSummary += [PSCustomObject]@{
        Contrl_ID       = $Definition.Control_ID
        Descryption     = $Definition.M365_Control
        Result          = $Result
        Status          = $Status
        Expected_Value  = $Definition.Expected_Value
        Recommencdation = $Definition.Recommendation
        Comment         = $Definition.Comment
    }
}

function Export-ControlDetails {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [object]$Data
    )

    $Date = Get-Date -Format "yyyy-MM-dd"
    $Path = Join-Path $script:DetailedReportPath "$ControlID`_$Date.csv"

    if ($null -eq $Data -or ($Data | Measure-Object).Count -eq 0) {
        $Data = [PSCustomObject]@{
            Message = "No data returned"
        }
    }

    $Data | Export-Csv $Path -NoTypeInformation -Encoding UTF8
}

function Export-SummaryReport {
    param(
        [Parameter(Mandatory)]
        [string]$CategoryName
    )

    $Date = Get-Date -Format "yyyy-MM-dd"

    $CSVPath = Join-Path $script:SummaryReportPath "$CategoryName`_Summary_$Date.csv"
    $HTMLPath = Join-Path $script:SummaryReportPath "$CategoryName`_Summary_$Date.html"

    $Global:AuditSummary | Export-Csv $CSVPath -NoTypeInformation -Encoding UTF8

    $Style = @"
<style>
body {
font-family: Segoe UI, Arial, sans-serif;
background-color: #f5f5f5;
color: #222;
}

h1 {
color: #333333;
}

table {
border-collapse: collapse;
width: 100%;
background-color: white;
}

th {
background-color: #2f5597;
color: white;
padding: 8px;
text-align: left;
}

td {
padding: 6px;
border-bottom: 1px solid #ddd;
vertical-align: top;
}

.status-pass {
background-color: #c6efce;
color: #006100;
font-weight: bold;
}

.status-warning {
background-color: #ffeb9c;
color: #9c6500;
font-weight: bold;
}

.status-fail {
background-color: #ffc7ce;
color: #9c0006;
font-weight: bold;
}

.status-info {
background-color: #d9e1f2;
color: #1f4e79;
font-weight: bold;
}

.status-manual {
background-color: #ddebf7;
color: #1f4e79;
font-weight: bold;
}

.status-error {
background-color: #f4cccc;
color: #7f0000;
font-weight: bold;
}
</style>
"@

    $Rows = foreach ($Entry in $Global:AuditSummary) {
        switch ($Entry.Status) {
            "PASS" { $Class = "status-pass" }
            "WARNING" { $Class = "status-warning" }
            "FAIL" { $Class = "status-fail" }
            "INFO" { $Class = "status-info" }
            "MANUAL" { $Class = "status-manual" }
            "ERROR" { $Class = "status-error" }
            default { $Class = "" }
        }

        "<tr><td>$($Entry.Contrl_ID)</td><td>$($Entry.Descryption)</td><td>$($Entry.Result)</td><td class='$Class'>$($Entry.Status)</td><td>$($Entry.Expected_Value)</td><td>$($Entry.Recommencdation)</td><td>$($Entry.Comment)</td></tr>"
    }

    $Table = @"
<table>
<tr>
<th>Contrl_ID</th>
<th>Descryption</th>
<th>Result</th>
<th>Status</th>
<th>Expected_Value</th>
<th>Recommencdation</th>
<th>Comment</th>
</tr>
$($Rows -join "`n")
</table>
"@

    $HTML = @"
<html>
<head>
<title>$CategoryName Audit Summary</title>
$Style
</head>
<body>
<h1>$CategoryName Security Audit</h1>
$Table
</body>
</html>
"@

    $HTML | Out-File $HTMLPath -Encoding UTF8

    Write-Host "Summary saved:"
    Write-Host $CSVPath
    Write-Host $HTMLPath
}

function Export-ControlResult {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [object]$Data,
        [Parameter(Mandatory)]
        [string]$Result,
        [Parameter(Mandatory)]
        [ValidateSet("PASS", "FAIL", "WARNING", "INFO", "MANUAL", "ERROR")]
        [string]$Status
    )

    Export-ControlDetails -ControlID $ControlID -Data $Data
    Add-SummaryEntry -ControlID $ControlID -Result $Result -Status $Status
}
