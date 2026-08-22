<#
.SYNOPSIS
    SimulGroove Music 一键全量构建脚本 (Build All)
#>

[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$ContinueOnError
)

$params = @{
    All = $true
}
if ($Clean) { $params['Clean'] = $true }
if ($ContinueOnError) { $params['ContinueOnError'] = $true }

& "$PSScriptRoot\build.ps1" @params
exit $LASTEXITCODE
