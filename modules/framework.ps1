function New-AppContext {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        [Parameter(Mandatory)]
        [string]$TenantId,
        [Parameter(Mandatory)]
        [string]$ClientId
    )

    $entraCategoriesPath = Join-Path $BasePath 'categories\EntraID'
    $exchangeCategoriesPath = Join-Path $BasePath 'categories\Exchange'
    $oneDriveCategoriesPath = Join-Path $BasePath 'categories\OneDrive'

    $entraCategoryMap = [ordered]@{
        '1' = [PSCustomObject]@{ Label = 'Alerting and Reporting'; Path = Join-Path $entraCategoriesPath 'alerting-reporting.ps1' }
        '2' = [PSCustomObject]@{ Label = 'Conditional Access'; Path = Join-Path $entraCategoriesPath 'conditional-access.ps1' }
        '3' = [PSCustomObject]@{ Label = 'External Collaboration'; Path = Join-Path $entraCategoriesPath 'external-collaboration.ps1' }
        '4' = [PSCustomObject]@{ Label = 'Governance'; Path = Join-Path $entraCategoriesPath 'governance.ps1' }
        '5' = [PSCustomObject]@{ Label = 'Identity Management'; Path = Join-Path $entraCategoriesPath 'identity-management.ps1' }
        '6' = [PSCustomObject]@{ Label = 'Identity Protection'; Path = Join-Path $entraCategoriesPath 'identity-protection.ps1' }
        '7' = [PSCustomObject]@{ Label = 'Privileged Access'; Path = Join-Path $entraCategoriesPath 'privileged-access.ps1' }
        '8' = [PSCustomObject]@{ Label = 'Security Configuration'; Path = Join-Path $entraCategoriesPath 'security-configuration.ps1' }
        '9' = [PSCustomObject]@{
            Label = 'Run ALL controls'
            Paths = @(
                Join-Path $entraCategoriesPath 'alerting-reporting.ps1'
                Join-Path $entraCategoriesPath 'conditional-access.ps1'
                Join-Path $entraCategoriesPath 'external-collaboration.ps1'
                Join-Path $entraCategoriesPath 'governance.ps1'
                Join-Path $entraCategoriesPath 'identity-management.ps1'
                Join-Path $entraCategoriesPath 'identity-protection.ps1'
                Join-Path $entraCategoriesPath 'privileged-access.ps1'
                Join-Path $entraCategoriesPath 'security-configuration.ps1'
            )
        }
    }

    $exchangeCategoryMap = [ordered]@{
        '1' = [PSCustomObject]@{ Label = 'Mail Flow Baseline'; Path = Join-Path $exchangeCategoriesPath 'mail-flow.ps1' }
    }

    $oneDriveCategoryMap = [ordered]@{
        '1' = [PSCustomObject]@{ Label = 'Sharing Baseline'; Path = Join-Path $oneDriveCategoriesPath 'sharing.ps1' }
    }

    return [PSCustomObject]@{
        BasePath             = $BasePath
        ReportsPath          = Join-Path $BasePath 'Reports'
        SummaryPath          = Join-Path $BasePath 'Reports\Summary'
        DetailedPath         = Join-Path $BasePath 'Reports\Detailed'
        EntraCategoriesPath  = $entraCategoriesPath
        ExchangePath         = $exchangeCategoriesPath
        OneDrivePath         = $oneDriveCategoriesPath
        TenantId             = $TenantId
        ClientId             = $ClientId
        EntraCategoryMap     = $entraCategoryMap
        ExchangeCategoryMap  = $exchangeCategoryMap
        OneDriveCategoryMap  = $oneDriveCategoryMap
    }
}

function Ensure-FrameworkFolders {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    Write-Host 'Checking folder structure...'

    $folders = @(
        $Context.ReportsPath,
        $Context.SummaryPath,
        $Context.DetailedPath,
        $Context.EntraCategoriesPath,
        $Context.ExchangePath,
        $Context.OneDrivePath
    )

    foreach ($folder in $folders) {
        if (-not (Test-Path $folder)) {
            Write-Host "Creating folder $folder"
            New-Item -ItemType Directory -Path $folder | Out-Null
        }
    }
}

function Invoke-ScriptList {
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths
    )

    foreach ($path in $Paths) {
        . $path
    }
}
