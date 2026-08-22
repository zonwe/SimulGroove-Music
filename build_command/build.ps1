<#
.SYNOPSIS
    SimulGroove Music 复合构建脚本 (Composite Build Script)

.DESCRIPTION
    聚合执行 SimulGroove Music 各端 (Android APK, Windows, Linux, Web) 以及 ASP.NET Core 后端 (Music.Api) 的构建。
    支持命令行参数批量指定、独立开关、全量构建、清理预处理与交互式选择菜单。

.PARAMETER Target
    构建目标名称列表，可选值: All, Apk, Windows, Linux, Web, Backend, Clean

.PARAMETER All
    构建适用于当前操作系统的全部目标 (Apk, 当前宿主桌面端, Web, Backend)

.PARAMETER Apk
    构建 Android APK (flutter build apk --release --split-per-abi)

.PARAMETER Windows
    构建 Windows 桌面端 (flutter build windows --release)

.PARAMETER Linux
    构建 Linux 桌面端 (flutter build linux --release)

.PARAMETER Web
    构建 Web 端 (flutter build web --release)

.PARAMETER Backend
    构建 ASP.NET Core 后端 (dotnet build backend/Music.Api/Music.Api.csproj -c Release)

.PARAMETER Clean
    构建前执行清理 (flutter clean & dotnet clean)

.PARAMETER ContinueOnError
    单个目标失败时继续构建剩余目标

.PARAMETER Interactive
    强制进入交互式控制台菜单模式

.EXAMPLE
    .\build_command\build.ps1 -All
    全量构建当前平台所有可用产物及后端。

.EXAMPLE
    .\build_command\build.ps1 -Windows -Backend
    同时构建 Windows 桌面端与 ASP.NET Core 后端。

.EXAMPLE
    .\build_command\build.ps1 -Target Apk, Web -Clean
    执行清理后构建 Android APK 与 Web 端。

.EXAMPLE
    .\build_command\build.ps1
    无参数直接运行将进入交互式选择菜单。
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Target = @(),

    [switch]$All,
    [switch]$Apk,
    [switch]$Windows,
    [switch]$Linux,
    [switch]$Web,
    [switch]$Backend,
    [switch]$Clean,
    [switch]$ContinueOnError,
    [switch]$Interactive
)

# 确保 UTF-8 编码输出以避免终端乱码
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

$ErrorActionPreference = 'Stop'

# 定位仓库根目录 (基于本脚本所在路径的上级目录)
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path

# 检测当前宿主系统
$isHostWindows = ($PSVersionTable.PSVersion.Major -le 5) -or ($IsWindows -eq $true) -or ([System.Environment]::OSVersion.Platform -match 'Win32NT')
$isHostLinux = ($IsLinux -eq $true) -or ([System.Environment]::OSVersion.Platform -match 'Unix')

# UI 格式化辅助函数
function Write-Header ([string]$text) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Step ([int]$step, [int]$total, [string]$text) {
    Write-Host "`n[$step/$total] " -ForegroundColor Yellow -NoNewline
    Write-Host $text -ForegroundColor White
}

function Write-Success ([string]$text) {
    Write-Host "  [SUCCESS] $text" -ForegroundColor Green
}

function Write-Failure ([string]$text) {
    Write-Host "  [FAILED]  $text" -ForegroundColor Red
}

function Write-Info ([string]$text) {
    Write-Host "  [INFO]    $text" -ForegroundColor Gray
}

# 检查可执行命令是否存在
function Test-CommandAvailable ([string]$cmd) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    return ($null -ne $found)
}

# 收集所选目标
$selectedTargets = [System.Collections.Generic.List[string]]::new()

# 解析 -Target 参数列表 (容错支持带/不带前缀 - 的形式)
foreach ($t in $Target) {
    if ([string]::IsNullOrWhiteSpace($t)) { continue }
    $tNorm = $t.Trim().TrimStart('-')
    if ($tNorm -ieq 'All') {
        $All = $true
    } elseif ($tNorm -ieq 'Clean') {
        $Clean = $true
    } elseif ($tNorm -ieq 'ContinueOnError') {
        $ContinueOnError = $true
    } elseif ($tNorm -ieq 'Apk') {
        $Apk = $true
    } elseif ($tNorm -ieq 'Windows') {
        $Windows = $true
    } elseif ($tNorm -ieq 'Linux') {
        $Linux = $true
    } elseif ($tNorm -ieq 'Web') {
        $Web = $true
    } elseif ($tNorm -ieq 'Backend') {
        $Backend = $true
    } else {
        Write-Warning "未知的目标名称: '$t'，支持的目标: All, Apk, Windows, Linux, Web, Backend, Clean"
    }
}

# 解析目标到列表
if ($All) {
    if (-not $selectedTargets.Contains('Apk')) { $selectedTargets.Add('Apk') }
    if ($isHostWindows) {
        if (-not $selectedTargets.Contains('Windows')) { $selectedTargets.Add('Windows') }
    } elseif ($isHostLinux) {
        if (-not $selectedTargets.Contains('Linux')) { $selectedTargets.Add('Linux') }
    } else {
        if (-not $selectedTargets.Contains('Windows')) { $selectedTargets.Add('Windows') }
    }
    if (-not $selectedTargets.Contains('Web')) { $selectedTargets.Add('Web') }
    if (-not $selectedTargets.Contains('Backend')) { $selectedTargets.Add('Backend') }
} else {
    if ($Apk -and -not $selectedTargets.Contains('Apk')) { $selectedTargets.Add('Apk') }
    if ($Windows -and -not $selectedTargets.Contains('Windows')) { $selectedTargets.Add('Windows') }
    if ($Linux -and -not $selectedTargets.Contains('Linux')) { $selectedTargets.Add('Linux') }
    if ($Web -and -not $selectedTargets.Contains('Web')) { $selectedTargets.Add('Web') }
    if ($Backend -and -not $selectedTargets.Contains('Backend')) { $selectedTargets.Add('Backend') }
}

# 无目标参数且未请求 Clean 时，或指定 -Interactive 时展示交互式选择菜单
if (($selectedTargets.Count -eq 0 -and -not $Clean) -or $Interactive) {
    Write-Header "SimulGroove Music 构建菜单"
    Write-Host " 1. 全部构建 (All: Apk + 宿主桌面端 + Web + Backend)" -ForegroundColor White
    Write-Host " 2. Windows 桌面端 (flutter build windows --release)" -ForegroundColor White
    Write-Host " 3. Android APK (flutter build apk --release --split-per-abi)" -ForegroundColor White
    Write-Host " 4. Web 端 (flutter build web --release)" -ForegroundColor White
    Write-Host " 5. Linux 桌面端 (flutter build linux --release)" -ForegroundColor White
    Write-Host " 6. 后端服务 (dotnet build backend/Music.Api/Music.Api.csproj -c Release)" -ForegroundColor White
    Write-Host " 7. 清理项目 (flutter clean & dotnet clean)" -ForegroundColor White
    Write-Host " 8. 清理并构建全部 (Clean + All)" -ForegroundColor White
    Write-Host " Q. 退出 (Quit)" -ForegroundColor DarkGray
    Write-Host ""
    
    $choice = Read-Host "请输入序号 (支持逗号隔开组合选择，如 2,6)"
    if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim() -ieq 'q') {
        Write-Host "已取消构建。" -ForegroundColor Yellow
        exit 0
    }

    $selectedTargets.Clear()
    $choices = $choice -split '[,，\s]+'
    foreach ($c in $choices) {
        switch ($c.Trim()) {
            '1' {
                if (-not $selectedTargets.Contains('Apk')) { $selectedTargets.Add('Apk') }
                if ($isHostWindows -and -not $selectedTargets.Contains('Windows')) { $selectedTargets.Add('Windows') }
                if ($isHostLinux -and -not $selectedTargets.Contains('Linux')) { $selectedTargets.Add('Linux') }
                if (-not $selectedTargets.Contains('Web')) { $selectedTargets.Add('Web') }
                if (-not $selectedTargets.Contains('Backend')) { $selectedTargets.Add('Backend') }
            }
            '2' { if (-not $selectedTargets.Contains('Windows')) { $selectedTargets.Add('Windows') } }
            '3' { if (-not $selectedTargets.Contains('Apk')) { $selectedTargets.Add('Apk') } }
            '4' { if (-not $selectedTargets.Contains('Web')) { $selectedTargets.Add('Web') } }
            '5' { if (-not $selectedTargets.Contains('Linux')) { $selectedTargets.Add('Linux') } }
            '6' { if (-not $selectedTargets.Contains('Backend')) { $selectedTargets.Add('Backend') } }
            '7' { $Clean = $true }
            '8' { 
                $Clean = $true
                if (-not $selectedTargets.Contains('Apk')) { $selectedTargets.Add('Apk') }
                if ($isHostWindows -and -not $selectedTargets.Contains('Windows')) { $selectedTargets.Add('Windows') }
                if ($isHostLinux -and -not $selectedTargets.Contains('Linux')) { $selectedTargets.Add('Linux') }
                if (-not $selectedTargets.Contains('Web')) { $selectedTargets.Add('Web') }
                if (-not $selectedTargets.Contains('Backend')) { $selectedTargets.Add('Backend') }
            }
            default { Write-Warning "忽略无效输入: $c" }
        }
    }
}

if ($selectedTargets.Count -eq 0 -and -not $Clean) {
    Write-Host "未选择任何构建目标，构建已结束。" -ForegroundColor Yellow
    exit 0
}

# 切换至仓库根目录执行构建，确保相对路径正确
Push-Location $RepoRoot

try {
    Write-Header "SimulGroove Music 构建流程"
    Write-Info "工作区根目录: $RepoRoot"
    Write-Info "执行目标: $(if ($selectedTargets.Count -gt 0) { $selectedTargets -join ', ' } else { '仅清理' })"
    if ($Clean) { Write-Info "前置操作: 清理项目 (Clean)" }

    # 依赖工具检查
    $needsFlutter = ($selectedTargets | Where-Object { $_ -in @('Apk', 'Windows', 'Linux', 'Web') }).Count -gt 0 -or $Clean
    $needsDotnet = ($selectedTargets | Where-Object { $_ -eq 'Backend' }).Count -gt 0 -or $Clean

    if ($needsFlutter -and -not (Test-CommandAvailable 'flutter')) {
        Write-Failure "未检测到 'flutter' 命令，请确认 Flutter SDK 已安装并加入系统环境变量 PATH。"
        exit 1
    }
    if ($needsDotnet -and -not (Test-CommandAvailable 'dotnet')) {
        Write-Failure "未检测到 'dotnet' 命令，请确认 .NET SDK 已安装并加入系统环境变量 PATH。"
        exit 1
    }

    # 执行清理
    if ($Clean) {
        Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "正在执行清理..." -ForegroundColor DarkCyan
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        
        Write-Info "执行: flutter clean"
        & flutter clean
        
        Write-Info "执行: dotnet clean backend/Music.Api/Music.Api.csproj"
        & dotnet clean backend/Music.Api/Music.Api.csproj
        
        Write-Success "清理完成"
    }

    if ($selectedTargets.Count -eq 0) {
        Write-Header "清理已完成"
        exit 0
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $overallTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $stepIdx = 1
    $totalSteps = $selectedTargets.Count

    foreach ($currentTarget in $selectedTargets) {
        Write-Step $stepIdx $totalSteps "构建目标: $currentTarget"
        $stepIdx++

        $targetTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $success = $false
        $errorMsg = $null

        # 平台兼容性前置检查
        if ($currentTarget -eq 'Linux' -and $isHostWindows) {
            Write-Warning "Flutter Linux 构建仅支持在 Linux 宿主机上运行。在 Windows 上已跳过。"
            $results.Add([PSCustomObject]@{
                TargetName = [string]$currentTarget
                Status     = 'SKIPPED'
                Duration   = '00:00.000'
            })
            continue
        }
        if ($currentTarget -eq 'Windows' -and $isHostLinux) {
            Write-Warning "Flutter Windows 构建仅支持在 Windows 宿主机上运行。在 Linux 上已跳过。"
            $results.Add([PSCustomObject]@{
                TargetName = [string]$currentTarget
                Status     = 'SKIPPED'
                Duration   = '00:00.000'
            })
            continue
        }

        try {
            switch ($currentTarget) {
                'Apk' {
                    Write-Info "命令: flutter build apk --release --split-per-abi"
                    & flutter build apk --release --split-per-abi
                    if ($LASTEXITCODE -eq 0) { $success = $true } else { $errorMsg = "进程退出代码: $LASTEXITCODE" }
                }
                'Windows' {
                    Write-Info "命令: flutter build windows --release"
                    & flutter build windows --release
                    if ($LASTEXITCODE -eq 0) { $success = $true } else { $errorMsg = "进程退出代码: $LASTEXITCODE" }
                }
                'Linux' {
                    Write-Info "命令: flutter build linux --release"
                    & flutter build linux --release
                    if ($LASTEXITCODE -eq 0) { $success = $true } else { $errorMsg = "进程退出代码: $LASTEXITCODE" }
                }
                'Web' {
                    Write-Info "命令: flutter build web --release"
                    & flutter build web --release
                    if ($LASTEXITCODE -eq 0) { $success = $true } else { $errorMsg = "进程退出代码: $LASTEXITCODE" }
                }
                'Backend' {
                    Write-Info "命令: dotnet build backend/Music.Api/Music.Api.csproj -c Release"
                    & dotnet build backend/Music.Api/Music.Api.csproj -c Release
                    if ($LASTEXITCODE -eq 0) { $success = $true } else { $errorMsg = "进程退出代码: $LASTEXITCODE" }
                }
            }
        } catch {
            $errorMsg = $_.Exception.Message
            $success = $false
        } finally {
            $targetTimer.Stop()
        }

        $durationStr = "{0:mm\:ss\.fff}" -f $targetTimer.Elapsed
        if ($success) {
            Write-Success "$currentTarget 构建成功 (耗时: $durationStr)"
            $results.Add([PSCustomObject]@{
                TargetName = [string]$currentTarget
                Status     = 'SUCCESS'
                Duration   = $durationStr
            })
        } else {
            Write-Failure "$currentTarget 构建失败 (耗时: $durationStr) $(if ($errorMsg) { "- $errorMsg" })"
            $results.Add([PSCustomObject]@{
                TargetName = [string]$currentTarget
                Status     = 'FAILED'
                Duration   = $durationStr
            })
            if (-not $ContinueOnError) {
                Write-Host "`n[STOP] 构建已终止。若需忽略错误继续构建后续目标，请添加 -ContinueOnError 参数。" -ForegroundColor Red
                break
            }
        }
    }

    $overallTimer.Stop()
    $totalDurationStr = "{0:mm\:ss\.fff}" -f $overallTimer.Elapsed

    # 输出结果汇总表
    Write-Header "构建结果汇总"
    $hasFailures = $false
    foreach ($res in $results) {
        $color = if ($res.Status -eq 'SUCCESS') { 'Green' } elseif ($res.Status -eq 'SKIPPED') { 'Yellow' } else { 'Red'; $hasFailures = $true }
        $line = "  {0,-12} [{1,-7}] 耗时: {2}" -f $res.TargetName, $res.Status, $res.Duration
        Write-Host $line -ForegroundColor $color
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  总计耗时: $totalDurationStr" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if ($hasFailures) {
        exit 1
    } else {
        exit 0
    }
} finally {
    Pop-Location
}
