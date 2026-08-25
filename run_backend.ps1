# SimulGroove Music - 一键启动后端与 Sidecar 服务 (同终端运行)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$rootPath = $PSScriptRoot

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " SimulGroove Music - 后端与 Sidecar 统一运行环境" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  - go-music-dl sidecar:  http://127.0.0.1:8081" -ForegroundColor Yellow
Write-Host "  - Music.Api 后端:       http://localhost:5080" -ForegroundColor Yellow
Write-Host "  - 提示: 按 Ctrl + C 可一并停止两项服务" -ForegroundColor Gray
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$env:ASPNETCORE_ENVIRONMENT = "Development"

function Stop-ProcessTree($procId) {
    if ($procId) {
        cmd.exe /c "taskkill /PID $procId /T /F >nul 2>nul"
    }
}

$goProc = $null
$dotnetProc = $null
$exitCode = 0

try {
    Write-Host "[1/2] 正在启动 go-music-dl sidecar (8081)..." -ForegroundColor Green
    $goProc = Start-Process -FilePath "go" `
        -ArgumentList "run", "./cmd/music-dl", "integration", "--host", "127.0.0.1", "--port", "8081" `
        -WorkingDirectory "$rootPath\go-music-dl" `
        -NoNewWindow `
        -PassThru

    Start-Sleep -Seconds 2

    Write-Host "[2/2] 正在启动 ASP.NET Core Music.Api (5080)..." -ForegroundColor Green
    $dotnetProc = Start-Process -FilePath "dotnet" `
        -ArgumentList "run", "--project", "backend/Music.Api/Music.Api.csproj", "--urls", "http://0.0.0.0:5080" `
        -WorkingDirectory $rootPath `
        -NoNewWindow `
        -PassThru

    # 持续等待任意一个进程退出或捕获 Ctrl+C
    while ($true) {
        if ($goProc.HasExited) {
            Write-Host "go-music-dl sidecar 服务已退出 (退出码: $($goProc.ExitCode))" -ForegroundColor Red
            $exitCode = $goProc.ExitCode
            break
        }
        if ($dotnetProc.HasExited) {
            Write-Host "Music.Api 后端服务已退出 (退出码: $($dotnetProc.ExitCode))" -ForegroundColor Red
            $exitCode = $dotnetProc.ExitCode
            break
        }
        Start-Sleep -Milliseconds 500
    }
}
finally {
    Write-Host "`n正在停止并清理服务进程..." -ForegroundColor Yellow
    if ($goProc -and !$goProc.HasExited) {
        Stop-ProcessTree $goProc.Id
    }
    if ($dotnetProc -and !$dotnetProc.HasExited) {
        Stop-ProcessTree $dotnetProc.Id
    }
    Write-Host "后端服务已全部停止。" -ForegroundColor Green
}

exit $exitCode
