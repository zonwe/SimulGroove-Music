#requires -Version 7.2

function Assert-AcceptanceGitState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$RequiredBuildRevision,

        [Parameter(Mandatory)]
        [string]$GitCommand,

        [Parameter(Mandatory)]
        [string]$AcceptanceName
    )

    Set-StrictMode -Version Latest

    $revisionOutput = @(& $GitCommand -C $RepositoryRoot rev-parse HEAD 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "读取当前仓库提交失败。$([Environment]::NewLine)$($revisionOutput -join [Environment]::NewLine)"
    }
    $repositoryRevision = ($revisionOutput -join "").Trim().ToLowerInvariant()
    if ($repositoryRevision -ne $RequiredBuildRevision.ToLowerInvariant()) {
        throw "BuildRevision 与当前检出提交不一致。"
    }

    $statusOutput = @(
        & $GitCommand -C $RepositoryRoot status --porcelain=v1 --untracked-files=all --ignore-submodules=none 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "检查当前工作区状态失败。$([Environment]::NewLine)$($statusOutput -join [Environment]::NewLine)"
    }
    if ($statusOutput.Count -gt 0) {
        throw "${AcceptanceName}要求干净检出；当前工作区存在未提交或未跟踪文件。"
    }
}

function Resolve-AcceptanceExternalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [ValidateSet("Any", "Container", "Leaf")]
        [string]$PathType = "Any",

        [switch]$MustExist
    )

    Set-StrictMode -Version Latest

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) {
        throw "$Name 必须是绝对路径。"
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($null -eq [IO.Directory]::GetParent($fullPath)) {
        throw "$Name 不能是文件系统根目录。"
    }

    $fullRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $relative = [IO.Path]::GetRelativePath($fullRepositoryRoot, $fullPath)
    $insideRepository = -not [IO.Path]::IsPathRooted($relative) -and
        $relative -ne ".." -and
        -not $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")
    if ($insideRepository) {
        throw "$Name 必须位于仓库工作区之外。"
    }

    if ($MustExist -and -not (Test-Path -LiteralPath $fullPath -PathType $PathType)) {
        throw "$Name 不存在或类型不正确。"
    }

    $probePath = $fullPath
    while (-not (Test-Path -LiteralPath $probePath)) {
        $parent = [IO.Directory]::GetParent($probePath)
        if ($null -eq $parent) {
            throw "$Name 无法解析到现有父目录。"
        }
        $probePath = $parent.FullName
    }
    $item = Get-Item -LiteralPath $probePath -Force
    while ($null -ne $item) {
        if ($item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
            throw "$Name 路径不能包含符号链接或目录联接。"
        }
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }

    return $fullPath
}
