param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$scriptsRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $scriptsRoot 'invoke-git-bash.ps1') (Join-Path $PSScriptRoot 'token-report.sh') @Arguments
exit $LASTEXITCODE