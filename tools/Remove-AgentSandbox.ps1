param(
    [Parameter(Mandatory = $true)]
    [string]$NameOrPath,

    [string]$WorktreeRoot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoName = Split-Path -Leaf $repoRoot

if (-not $WorktreeRoot) {
    $WorktreeRoot = Join-Path (Split-Path -Parent $repoRoot) "$repoName-agent-sandboxes"
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

if (Test-Path -LiteralPath $NameOrPath) {
    $sandboxPath = (Resolve-Path -LiteralPath $NameOrPath).Path
} else {
    $sandboxPath = Join-Path $WorktreeRoot (ConvertTo-Slug -Value $NameOrPath)
}

if (-not (Test-Path -LiteralPath $sandboxPath)) { throw "No sandbox was found at $sandboxPath." }

$reportedRoot = (& git -C $sandboxPath rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw "$sandboxPath is not a git worktree." }

$normalizedSandboxPath = ($sandboxPath -replace '\\', '/').TrimEnd('/')
if ($reportedRoot.TrimEnd('/') -ne $normalizedSandboxPath) {
    throw "Refusing to remove $sandboxPath because git reported a different root: $reportedRoot."
}

$status = (& git -C $sandboxPath status --porcelain)
if ($status -and -not $Force) { throw "Sandbox '$sandboxPath' has local changes. Review them first or rerun with -Force." }

$args = @('worktree', 'remove', $sandboxPath)
if ($Force) { $args += '--force' }
Invoke-GitChecked -Arguments $args
Write-Host "Removed agent sandbox: $sandboxPath" -ForegroundColor Green
