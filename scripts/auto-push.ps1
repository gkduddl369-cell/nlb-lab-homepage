param(
    [string]$RepoPath = (Get-Location).Path,
    [int]$DebounceSeconds = 4,
    [string[]]$IncludeExtensions = @('.html', '.css', '.js', '.mjs', '.json', '.svg', '.png', '.jpg', '.jpeg', '.gif', '.webp')
)

$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

function Test-TrackedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if ($Path -like '*\.git\*' -or $Path -like '*\\.git\\*') {
        return $false
    }

    if (Test-Path $Path -PathType Container) {
        return $false
    }

    $extension = [System.IO.Path]::GetExtension($Path)
    return $IncludeExtensions -contains $extension.ToLowerInvariant()
}

function Invoke-GitAutoPush {
    param([string]$WorkingPath)

    Push-Location $WorkingPath
    try {
        $insideRepo = git rev-parse --is-inside-work-tree 2>$null
        if ($insideRepo -ne 'true') {
            Write-Status 'Git 저장소가 아닙니다. 자동 업로드를 건너뜁니다.'
            return
        }

        $originUrl = git remote get-url origin 2>$null
        if (-not $originUrl) {
            Write-Status 'origin 원격 저장소가 없습니다. 먼저 GitHub 원격을 연결해야 자동 업로드됩니다.'
            return
        }

        git add -A

        $hasChanges = git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Status '업로드할 변경 사항이 없습니다.'
            return
        }

        $branch = git branch --show-current
        if (-not $branch) {
            Write-Status '현재 브랜치를 찾을 수 없습니다.'
            return
        }

        $message = 'chore: auto sync website changes'
        git commit -m $message | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Status '자동 커밋에 실패했습니다.'
            return
        }

        git push origin $branch | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Status "자동 업로드 완료: $branch"
        } else {
            Write-Status '자동 푸시에 실패했습니다.'
        }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $RepoPath)) {
    throw "경로를 찾을 수 없습니다: $RepoPath"
}

$fullRepoPath = (Resolve-Path $RepoPath).Path
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $fullRepoPath
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

$script:lastEvent = Get-Date '2000-01-01'

$action = {
    $path = $Event.SourceEventArgs.FullPath
    if (-not (Test-TrackedPath $path)) {
        return
    }

    $now = Get-Date
    if (($now - $script:lastEvent).TotalSeconds -lt $DebounceSeconds) {
        return
    }

    $script:lastEvent = $now
    Write-Status "변경 감지: $path"
    Start-Sleep -Seconds $DebounceSeconds
    Invoke-GitAutoPush -WorkingPath $fullRepoPath
}

$subscriptions = @(
    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action,
    Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action,
    Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $action,
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action
)

Write-Status '자동 업로드 감시를 시작했습니다. 종료하려면 Ctrl+C를 누르세요.'

try {
    while ($true) {
        Wait-Event -Timeout 1 | Out-Null
    }
} finally {
    foreach ($subscription in $subscriptions) {
        Unregister-Event -SubscriptionId $subscription.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $subscription.Id -Force -ErrorAction SilentlyContinue
    }

    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
}