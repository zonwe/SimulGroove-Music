$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$isWindowsHost = $env:OS -eq 'Windows_NT'
$isLinuxHost = -not $isWindowsHost -and (Test-Path '/proc/version')
. (Join-Path $PSScriptRoot 'publish_artifacts.ps1')

$buildSteps = @(
    [PSCustomObject]@{
        Name = 'Android APK'
        Command = 'flutter'
        Arguments = @('build', 'apk', '--release', '--split-per-abi')
        Supported = $true
        SkipReason = ''
        Publisher = 'Android'
        Artifacts = @(
            'build\artifacts\android\*-release.apk'
            'build\artifacts\android\SHA256SUMS.txt'
        )
    }
    [PSCustomObject]@{
        Name = 'Music.Api'
        Command = 'dotnet'
        Arguments = @('build', 'backend/Music.Api/Music.Api.csproj', '-c', 'Release')
        Supported = $true
        SkipReason = ''
        Publisher = ''
        Artifacts = @('backend\Music.Api\bin\Release\net10.0\Music.Api.dll')
    }
    [PSCustomObject]@{
        Name = 'Linux'
        Command = 'flutter'
        Arguments = @('build', 'linux', '--release')
        Supported = $isLinuxHost
        SkipReason = 'Linux 桌面包需要在 Linux 主机上构建'
        Publisher = ''
        Artifacts = @('build\linux\x64\release\bundle\simul_groove_player')
    }
    [PSCustomObject]@{
        Name = 'Web'
        Command = 'flutter'
        Arguments = @('build', 'web', '--release')
        Supported = $true
        SkipReason = ''
        Publisher = ''
        Artifacts = @('build\web')
    }
    [PSCustomObject]@{
        Name = 'Windows'
        Command = 'flutter'
        Arguments = @('build', 'windows', '--release')
        Supported = $isWindowsHost
        SkipReason = 'Windows 桌面包需要在 Windows 主机上构建'
        Publisher = 'Windows'
        Artifacts = @(
            'build\artifacts\windows\simul_groove_player.exe'
            'build\artifacts\windows\SHA256SUMS.txt'
        )
    }
)

function Get-ArtifactPaths {
    param([string[]]$Patterns)

    $paths = foreach ($pattern in $Patterns) {
        Resolve-Path -Path $pattern -Relative -ErrorAction SilentlyContinue
    }
    return @($paths | Sort-Object -Unique)
}

$results = @()
$totalTimer = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' SimulGroove Music Release Build' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "项目目录: $repoRoot"
Write-Host "开始时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Push-Location $repoRoot
try {
    for ($index = 0; $index -lt $buildSteps.Count; $index++) {
        $step = $buildSteps[$index]
        $position = $index + 1

        Write-Host ''
        Write-Host "[$position/$($buildSteps.Count)] $($step.Name)" -ForegroundColor Cyan

        if (-not $step.Supported) {
            Write-Host "跳过: $($step.SkipReason)" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Name = $step.Name
                Status = '跳过'
                Duration = '-'
                Artifacts = @()
                Message = $step.SkipReason
            }
            continue
        }

        $commandLine = "$($step.Command) $($step.Arguments -join ' ')"
        $commandArguments = @($step.Arguments)
        Write-Host "执行: $commandLine"
        $timer = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            if (-not (Get-Command $step.Command -ErrorAction SilentlyContinue)) {
                throw "未找到命令: $($step.Command)"
            }

            $LASTEXITCODE = 0
            & $step.Command @commandArguments
            $exitCode = $LASTEXITCODE
            $timer.Stop()

            if ($exitCode -ne 0) {
                throw "命令退出码: $exitCode"
            }

            $publishDirectory = switch ($step.Publisher) {
                'Android' {
                    Publish-AndroidArtifacts -RepositoryRoot $repoRoot
                }
                'Windows' {
                    Publish-WindowsArtifacts -RepositoryRoot $repoRoot
                }
                default { $null }
            }
            if ($null -ne $publishDirectory) {
                $relativePublishDirectory = Resolve-Path `
                    -LiteralPath $publishDirectory `
                    -Relative
                Write-Host "已复制到: $relativePublishDirectory" -ForegroundColor DarkGreen
            }

            $artifactPaths = Get-ArtifactPaths -Patterns $step.Artifacts
            Write-Host "成功: $($step.Name)（$($timer.Elapsed.ToString('hh\:mm\:ss'))）" -ForegroundColor Green
            if ($artifactPaths.Count -gt 0) {
                foreach ($artifact in $artifactPaths) {
                    Write-Host "产物: $artifact" -ForegroundColor DarkGreen
                }
            } else {
                Write-Host "提示: 构建成功，但未在预期位置找到产物" -ForegroundColor Yellow
            }

            $results += [PSCustomObject]@{
                Name = $step.Name
                Status = '成功'
                Duration = $timer.Elapsed.ToString('hh\:mm\:ss')
                Artifacts = $artifactPaths
                Message = ''
            }
        } catch {
            $timer.Stop()
            Write-Host "失败: $($step.Name)（$($timer.Elapsed.ToString('hh\:mm\:ss'))）" -ForegroundColor Red
            Write-Host "原因: $($_.Exception.Message)" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Name = $step.Name
                Status = '失败'
                Duration = $timer.Elapsed.ToString('hh\:mm\:ss')
                Artifacts = @()
                Message = $_.Exception.Message
            }
        }
    }
} finally {
    Pop-Location
    $totalTimer.Stop()
}

$successCount = @($results | Where-Object Status -eq '成功').Count
$failureCount = @($results | Where-Object Status -eq '失败').Count
$skippedCount = @($results | Where-Object Status -eq '跳过').Count

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' 构建结果汇总' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
$results | Select-Object Name, Status, Duration | Format-Table -AutoSize
Write-Host "成功: $successCount  失败: $failureCount  跳过: $skippedCount"
Write-Host "总耗时: $($totalTimer.Elapsed.ToString('hh\:mm\:ss'))"

$artifactResults = @($results | Where-Object { $_.Artifacts.Count -gt 0 })
if ($artifactResults.Count -gt 0) {
    Write-Host ''
    Write-Host '构建产物:' -ForegroundColor Cyan
    foreach ($result in $artifactResults) {
        foreach ($artifact in $result.Artifacts) {
            Write-Host "- $($result.Name): $artifact"
        }
    }
}

if ($failureCount -gt 0) {
    Write-Host ''
    Write-Host '部分构建失败，请查看上方日志。' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '全部可用目标构建成功。' -ForegroundColor Green
exit 0
