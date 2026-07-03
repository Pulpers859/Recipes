param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$BaseRef = 'origin/main',

    [string]$WorktreeRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoName = Split-Path -Leaf $repoRoot

if (-not $WorktreeRoot) {
    $sandboxRoot = Join-Path (Split-Path -Parent $repoRoot) '.agent-sandboxes'
    $WorktreeRoot = Join-Path $sandboxRoot $repoName
}

function ConvertTo-Slug {
    param([string]$Value)
    $slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { throw 'The sandbox name must contain at least one letter or number.' }
    return $slug
}

function Invoke-GitChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & git -C $repoRoot @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE." }
}

Invoke-GitChecked -Arguments @('rev-parse', '--show-toplevel')
Invoke-GitChecked -Arguments @('fetch', '--all', '--prune')
Invoke-GitChecked -Arguments @('rev-parse', '--verify', $BaseRef)

$sandboxPath = Join-Path $WorktreeRoot (ConvertTo-Slug -Value $Name)
if (Test-Path -LiteralPath $sandboxPath) { throw "A sandbox path already exists at $sandboxPath." }

New-Item -ItemType Directory -Force -Path $WorktreeRoot | Out-Null
Invoke-GitChecked -Arguments @('worktree', 'add', '--detach', $sandboxPath, $BaseRef)

Write-Host "Created detached agent sandbox:" -ForegroundColor Green
Write-Host "  Path: $sandboxPath"
Write-Host "  Base: $BaseRef"
Write-Host ''
Write-Host 'Do not commit or push from this sandbox. Diff it, then integrate selected changes from the main checkout.' -ForegroundColor Yellow
