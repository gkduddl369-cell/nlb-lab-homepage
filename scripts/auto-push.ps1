param(
    [string]$RepoPath = (Get-Location).Path,
    [int]$DebounceSeconds = 4,
    [bool]$RequireApproval = $true,
    [string[]]$IncludeExtensions = @('.html', '.css', '.js', '.mjs', '.json', '.svg', '.png', '.jpg', '.jpeg', '.gif', '.webp')
)

$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

function Get-GitCommand {
    $gitCommand = (Get-Command git -ErrorAction SilentlyContinue)
    if ($gitCommand) {
        return $gitCommand.Source
    }

    $candidates = @(
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files\Git\bin\git.exe',
        'C:\Program Files (x86)\Git\cmd\git.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Confirm-AutoPush {
    param([string]$ChangedPath)

    if (-not $RequireApproval) {
        return $true
    }

    try {
        $answer = Read-Host "변경 파일 감지됨: $ChangedPath`n지금 GitHub로 업로드할까요? (Y/N)"
    } catch {
        Write-Status '승인 입력을 받을 수 없어 자동 업로드를 건너뜁니다.'
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($answer)) {
        Write-Status '승인이 없어 자동 업로드를 건너뜁니다.'
        return $false
    }

    return @('y', 'yes') -contains $answer.Trim().ToLowerInvariant()
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
        if (-not $script:GitCommand) {
            Write-Status 'Git 실행 파일을 찾을 수 없습니다. Git 설치 또는 PATH 설정을 확인하세요.'
            return
        }

        $insideRepo = & $script:GitCommand rev-parse --is-inside-work-tree 2>$null
        if ($insideRepo -ne 'true') {
            Write-Status 'Git 저장소가 아닙니다. 자동 업로드를 건너뜁니다.'
            return
        }

        $originUrl = & $script:GitCommand remote get-url origin 2>$null
        if (-not $originUrl) {
            Write-Status 'origin 원격 저장소가 없습니다. 먼저 GitHub 원격을 연결해야 자동 업로드됩니다.'
            return
        }

        & $script:GitCommand add -A

        $hasChanges = & $script:GitCommand diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Status '업로드할 변경 사항이 없습니다.'
            return
        }

        $branch = & $script:GitCommand branch --show-current
        if (-not $branch) {
            Write-Status '현재 브랜치를 찾을 수 없습니다.'
            return
        }

        $message = 'chore: auto sync website changes'
        & $script:GitCommand commit -m $message | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Status '자동 커밋에 실패했습니다.'
            return
        }

        & $script:GitCommand push origin $branch | Out-Host
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

$script:GitCommand = Get-GitCommand

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

    if (-not (Confirm-AutoPush -ChangedPath $path)) {
        Write-Status '사용자 승인 거부로 업로드를 건너뜁니다.'
        return
    }

    Start-Sleep -Seconds $DebounceSeconds
    Invoke-GitAutoPush -WorkingPath $fullRepoPath
}

$subscriptions = @(
    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action
    Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
    Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $action
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action
)

if ($RequireApproval) {
    Write-Status '자동 업로드 감시를 시작했습니다. 변경 시 승인(Y/N) 후 업로드됩니다. 종료하려면 Ctrl+C를 누르세요.'
} else {
    Write-Status '자동 업로드 감시를 시작했습니다. 종료하려면 Ctrl+C를 누르세요.'
}

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