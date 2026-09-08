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
