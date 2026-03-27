param(
    [string]$RepoPath = (Get-Location).Path,
    [string]$CommitMessage = 'chore: update website'
)

$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

Push-Location $RepoPath
try {
    $insideRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($insideRepo -ne 'true') {
        throw '현재 폴더가 Git 저장소가 아닙니다.'
    }

    $originUrl = git remote get-url origin 2>$null
    if (-not $originUrl) {
        throw 'origin 원격 저장소가 없습니다. 먼저 GitHub 저장소 주소를 origin으로 연결해야 합니다.'
    }

    $branch = git branch --show-current
    if (-not $branch) {
        throw '현재 브랜치를 찾을 수 없습니다.'
    }

    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Status '배포할 변경 사항이 없습니다.'
        exit 0
    }

    git commit -m $CommitMessage | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw '커밋에 실패했습니다.'
    }

    git push origin $branch | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw '푸시에 실패했습니다.'
    }

    Write-Status "배포용 업로드 완료: $branch"
    Write-Status 'Vercel이 GitHub 변경을 감지하면 자동으로 재배포됩니다.'
} finally {
    Pop-Location
}