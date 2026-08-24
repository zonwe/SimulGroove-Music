$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'publish_artifacts.ps1')

Push-Location $repoRoot
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Windows 构建失败，退出码: $LASTEXITCODE"
    }

    $destination = Publish-WindowsArtifacts -RepositoryRoot $repoRoot
    Write-Host "Windows 构建产物已复制到: $destination" -ForegroundColor Green
} finally {
    Pop-Location
}
