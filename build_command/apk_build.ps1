$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'publish_artifacts.ps1')

Push-Location $repoRoot
try {
    flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) {
        throw "Android 构建失败，退出码: $LASTEXITCODE"
    }

    $destination = Publish-AndroidArtifacts -RepositoryRoot $repoRoot
    Write-Host "Android 构建产物已复制到: $destination" -ForegroundColor Green
} finally {
    Pop-Location
}
