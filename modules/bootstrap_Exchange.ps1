function Initialize-ExchangeSession {
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    if (-not $Global:ExchangeSessionInitialized) {
        $Global:ExchangeSessionInitialized = $false
    }

    if ($Global:ExchangeSessionInitialized) {
        return
    }

    Write-Host ''
    Write-Host '==== Exchange Bootstrap ===='
    Write-Host 'Exchange bootstrap skeleton is ready for future module loading and authentication.'
    Write-Host ''

    $Global:ExchangeSessionInitialized = $true
}
