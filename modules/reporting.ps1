############################################################
# Reporting module for Microsoft 365 Audit
############################################################

$script:AuditBasePath = Split-Path -Parent $PSScriptRoot
$script:DetailedReportPath = Join-Path $script:AuditBasePath "Reports\Detailed"
$script:SummaryReportPath = Join-Path $script:AuditBasePath "Reports\Summary"
$script:DefaultControlCatalogPath = Join-Path $script:AuditBasePath "categories\EntraID\m365_entraID.json"

if (-not $Global:ControlCatalogStore) {
    $Global:ControlCatalogStore = @{}
}

if (-not $Global:ActiveControlCatalogPath) {
    $Global:ActiveControlCatalogPath = $script:DefaultControlCatalogPath
}

function Set-ControlCatalogPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path $Path).Path
    $Global:ActiveControlCatalogPath = $resolvedPath
}

function Get-ControlCatalogPath {
    if (-not $Global:ActiveControlCatalogPath) {
        $Global:ActiveControlCatalogPath = $script:DefaultControlCatalogPath
    }

    return $Global:ActiveControlCatalogPath
}

function Initialize-ControlCatalog {
    $catalogPath = Get-ControlCatalogPath

    if ($Global:ControlCatalogStore.ContainsKey($catalogPath)) {
        return
    }

    if (-not (Test-Path $catalogPath)) {
        throw "Control catalog not found: $catalogPath"
    }

    $rawCatalog = Get-Content -Raw $catalogPath

    # The source file may contain a few broken strings like te"N/A"t/gover"N/A"ce.
    # Repair only the invalid quoted fragment inside words and keep standalone "N/A" values untouched.
    $sanitizedCatalog = [regex]::Replace($rawCatalog, '(?<=[A-Za-z])"N/A"(?=[A-Za-z])', 'n')
    $definitions = $sanitizedCatalog | ConvertFrom-Json
    $catalog = @{}

    foreach ($definition in $definitions) {
        $catalog[$definition.Control_ID] = $definition
    }

    $Global:ControlCatalogStore[$catalogPath] = $catalog
}

function Get-ControlDefinition {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID
    )

    Initialize-ControlCatalog

    $catalogPath = Get-ControlCatalogPath
    $catalog = $Global:ControlCatalogStore[$catalogPath]

    if (-not $catalog.ContainsKey($ControlID)) {
        throw "Control definition not found for $ControlID in $catalogPath"
    }

    return $catalog[$ControlID]
}

function Add-SummaryEntry {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [Parameter(Mandatory)]
        [string]$Result,
        [Parameter(Mandatory)]
        [ValidateSet("PASS", "FAIL", "WARNING", "INFO", "MANUAL", "ERROR", "NO_ACCESS", "LICENSE_REQUIRED", "NOT_SUPPORTED")]
        [string]$Status
    )

    $definition = Get-ControlDefinition -ControlID $ControlID

    $Global:AuditSummary += [PSCustomObject]@{
        Contrl_ID       = $definition.Control_ID
        Descryption     = $definition.M365_Control
        Result          = $Result
        Status          = $Status
        Expected_Value  = $definition.Expected_Value
        Recommencdation = $definition.Recommendation
        Comment         = $definition.Comment
    }
}

function Export-ControlDetails {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [object]$Data
    )

    $date = Get-Date -Format "yyyy-MM-dd"
    $path = Join-Path $script:DetailedReportPath "$ControlID`_$date.csv"

    if ($null -eq $Data -or ($Data | Measure-Object).Count -eq 0) {
        $Data = [PSCustomObject]@{
            Message = "No data returned"
        }
    }

    $Data | Export-Csv $path -NoTypeInformation -Encoding UTF8
}

function Export-SummaryReport {
    param(
        [Parameter(Mandatory)]
        [string]$CategoryName
    )

    $date = Get-Date -Format "yyyy-MM-dd"

    $csvPath = Join-Path $script:SummaryReportPath "$CategoryName`_Summary_$date.csv"
    $htmlPath = Join-Path $script:SummaryReportPath "$CategoryName`_Summary_$date.html"

    $Global:AuditSummary | Export-Csv $csvPath -NoTypeInformation -Encoding UTF8

    $style = @"
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

.status-no-access {
background-color: #fce5cd;
color: #7f6000;
font-weight: bold;
}

.status-license-required {
background-color: #fff2cc;
color: #7f6000;
font-weight: bold;
}

.status-not-supported {
background-color: #ead1dc;
color: #741b47;
font-weight: bold;
}
</style>
"@

    $rows = foreach ($entry in $Global:AuditSummary) {
        switch ($entry.Status) {
            "PASS" { $class = "status-pass" }
            "WARNING" { $class = "status-warning" }
            "FAIL" { $class = "status-fail" }
            "INFO" { $class = "status-info" }
            "MANUAL" { $class = "status-manual" }
            "ERROR" { $class = "status-error" }
            "NO_ACCESS" { $class = "status-no-access" }
            "LICENSE_REQUIRED" { $class = "status-license-required" }
            "NOT_SUPPORTED" { $class = "status-not-supported" }
            default { $class = "" }
        }

        "<tr><td>$($entry.Contrl_ID)</td><td>$($entry.Descryption)</td><td>$($entry.Result)</td><td class='$class'>$($entry.Status)</td><td>$($entry.Expected_Value)</td><td>$($entry.Recommencdation)</td><td>$($entry.Comment)</td></tr>"
    }

    $table = @"
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
$($rows -join "`n")
</table>
"@

    $html = @"
<html>
<head>
<title>$CategoryName Audit Summary</title>
$style
</head>
<body>
<h1>$CategoryName Security Audit</h1>
$table
</body>
</html>
"@

    $html | Out-File $htmlPath -Encoding UTF8

    Write-Host "Summary saved:"
    Write-Host $csvPath
    Write-Host $htmlPath
}

function Export-ControlResult {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,
        [object]$Data,
        [Parameter(Mandatory)]
        [string]$Result,
        [Parameter(Mandatory)]
        [ValidateSet("PASS", "FAIL", "WARNING", "INFO", "MANUAL", "ERROR", "NO_ACCESS", "LICENSE_REQUIRED", "NOT_SUPPORTED")]
        [string]$Status
    )

    Export-ControlDetails -ControlID $ControlID -Data $Data
    Add-SummaryEntry -ControlID $ControlID -Result $Result -Status $Status
}
