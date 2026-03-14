function Show-MainMenu {
    Write-Host ''
    Write-Host '==== Microsoft 365 Security Audit ===='
    Write-Host ''
    Write-Host '1 - EntraID'
    Write-Host '2 - Exchange'
    Write-Host '3 - OneDrive'
    Write-Host '0 - Exit'
    Write-Host ''
}

function Show-AreaMenu {
    param(
        [Parameter(Mandatory)]
        [string]$AreaName,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$CategoryMap
    )

    Write-Host ''
    Write-Host "==== $AreaName Security Audit ===="
    Write-Host ''

    foreach ($option in $CategoryMap.GetEnumerator()) {
        Write-Host "$($option.Key) - $($option.Value.Label)"
    }

    Write-Host '10 - Return to main menu'
    Write-Host ''
}

function Invoke-CategoryChoice {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$CategoryMap,
        [Parameter(Mandatory)]
        [string]$Choice
    )

    if (-not $CategoryMap.Contains($Choice)) {
        Write-Host 'Invalid option'
        return
    }

    $definition = $CategoryMap[$Choice]

    if ($definition.PSObject.Properties.Name -contains 'Paths') {
        Invoke-ScriptList -Paths $definition.Paths
        return
    }

    . $definition.Path
}

function Start-EntraIDMenu {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $returnToMainMenu = $false

    while (-not $returnToMainMenu) {
        Show-AreaMenu -AreaName 'EntraID' -CategoryMap $Context.EntraCategoryMap
        $choice = Read-Host 'Select EntraID option'

        switch ($choice) {
            '10' { $returnToMainMenu = $true }
            default {
                Initialize-EntraGraphSession -Context $Context
                Invoke-CategoryChoice -CategoryMap $Context.EntraCategoryMap -Choice $choice
            }
        }
    }
}

function Start-ExchangeMenu {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $returnToMainMenu = $false

    while (-not $returnToMainMenu) {
        Show-AreaMenu -AreaName 'Exchange' -CategoryMap $Context.ExchangeCategoryMap
        $choice = Read-Host 'Select Exchange option'

        switch ($choice) {
            '10' { $returnToMainMenu = $true }
            default {
                Initialize-ExchangeSession -Context $Context
                Invoke-CategoryChoice -CategoryMap $Context.ExchangeCategoryMap -Choice $choice
            }
        }
    }
}

function Start-OneDriveMenu {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $returnToMainMenu = $false

    while (-not $returnToMainMenu) {
        Show-AreaMenu -AreaName 'OneDrive' -CategoryMap $Context.OneDriveCategoryMap
        $choice = Read-Host 'Select OneDrive option'

        switch ($choice) {
            '10' { $returnToMainMenu = $true }
            default {
                Initialize-OneDriveSession -Context $Context
                Invoke-CategoryChoice -CategoryMap $Context.OneDriveCategoryMap -Choice $choice
            }
        }
    }
}

function Start-MainMenu {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $exitRequested = $false

    while (-not $exitRequested) {
        Show-MainMenu
        $mainChoice = Read-Host 'Select main option'

        switch ($mainChoice) {
            '1' { Start-EntraIDMenu -Context $Context }
            '2' { Start-ExchangeMenu -Context $Context }
            '3' { Start-OneDriveMenu -Context $Context }
            '0' { $exitRequested = $true }
            default { Write-Host 'Invalid option' }
        }
    }
}
