$ErrorActionPreference = 'Stop'

function Reset-BuildArtifactDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativeDestination
    )

    $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build'))
    $destination = [System.IO.Path]::GetFullPath(
        (Join-Path $RepositoryRoot $RelativeDestination)
    )
    $buildPrefix = $buildRoot.TrimEnd([char[]]@('\', '/')) +
        [System.IO.Path]::DirectorySeparatorChar

    if (-not $destination.StartsWith(
            $buildPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "构建产物目录必须位于 $buildRoot 下: $destination"
    }

    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null

    return $destination
}

function Write-Sha256Manifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArtifactDirectory
    )

    $manifestPath = Join-Path $ArtifactDirectory 'SHA256SUMS.txt'
    $artifactDirectoryPrefix = $ArtifactDirectory.TrimEnd([char[]]@('\', '/')) +
        [System.IO.Path]::DirectorySeparatorChar
    $artifactFiles = @(
        Get-ChildItem -LiteralPath $ArtifactDirectory -File -Recurse |
            Where-Object FullName -ne $manifestPath |
            Sort-Object FullName
    )
    if ($artifactFiles.Count -eq 0) {
        throw "没有可生成校验和的文件: $ArtifactDirectory"
    }

    $checksumLines = foreach ($file in $artifactFiles) {
        $relativePath = $file.FullName.Substring(
            $artifactDirectoryPrefix.Length
        ).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        "$hash  $relativePath"
    }
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines(
        $manifestPath,
        [string[]]$checksumLines,
        $utf8WithoutBom
    )

    Write-Host 'SHA-256 校验和:' -ForegroundColor Cyan
    foreach ($line in $checksumLines) {
        Write-Host "  $line"
    }

    return $manifestPath
}

function Publish-AndroidArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $sourceDirectory = Join-Path $RepositoryRoot 'build\app\outputs\flutter-apk'
    $apkNames = @(
        'app-arm64-v8a-release.apk'
        'app-armeabi-v7a-release.apk'
        'app-x86_64-release.apk'
    )
    $sourceApks = foreach ($apkName in $apkNames) {
        $apkPath = Join-Path $sourceDirectory $apkName
        if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
            throw "未找到 Android release APK: $apkPath"
        }
        Get-Item -LiteralPath $apkPath
    }

    $destination = Reset-BuildArtifactDirectory `
        -RepositoryRoot $RepositoryRoot `
        -RelativeDestination 'build\artifacts\android'
    foreach ($apk in $sourceApks) {
        Copy-Item -LiteralPath $apk.FullName -Destination $destination -Force
    }
    Write-Sha256Manifest -ArtifactDirectory $destination | Out-Null

    return $destination
}

function Publish-WindowsArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $sourceDirectory = Join-Path $RepositoryRoot 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "未找到 Windows release 目录: $sourceDirectory"
    }

    $sourceEntries = @(Get-ChildItem -LiteralPath $sourceDirectory -Force)
    if ($sourceEntries.Count -eq 0) {
        throw "Windows release 目录为空: $sourceDirectory"
    }

    $destination = Reset-BuildArtifactDirectory `
        -RepositoryRoot $RepositoryRoot `
        -RelativeDestination 'build\artifacts\windows'
    foreach ($entry in $sourceEntries) {
        Copy-Item `
            -LiteralPath $entry.FullName `
            -Destination $destination `
            -Recurse `
            -Force
    }
    Write-Sha256Manifest -ArtifactDirectory $destination | Out-Null

    return $destination
}
