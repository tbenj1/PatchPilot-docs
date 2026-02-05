<#
.SYNOPSIS
  One-command launcher for PatchPilot-docs (MkDocs) that:
    - Ensures a local venv (.venv-mkdocs) exists
    - Installs/updates MkDocs dependencies
    - Starts `mkdocs serve`
    - Optionally opens the default browser to the served site

.DESCRIPTION
  Intended for "new user":
    1) git clone https://github.com/tbenj1/PatchPilot-docs.git
    2) pwsh -NoProfile -ExecutionPolicy Bypass -File .\Run-Docs.ps1

  Notes:
  - Requires Python 3 available as `py` (Windows launcher) or `python`.
  - Creates venv at .\.venv-mkdocs in the repo root.
  - Uses mkdocs.yml in the repo root.

.PARAMETER Port
  Port to bind (default 8000)

.PARAMETER BindHost
  Host to bind (default 127.0.0.1)

.PARAMETER OpenBrowser
  Open default browser to the local URL (default: true)

.PARAMETER NoVenv
  If set, do not create/use venv; assumes mkdocs is globally available.

.PARAMETER Strict
  If set, treat warnings as errors (fails on common mkdocs warnings).

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\Run-Docs.ps1

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\Run-Docs.ps1 -Port 9000 -OpenBrowser:$false
#>

[CmdletBinding()]
param(
  [Parameter()]
  [ValidateRange(1,65535)]
  [int]$Port = 8000,

  [Parameter()]
  [string]$BindHost = '127.0.0.1',

  [Parameter()]
  [bool]$OpenBrowser = $true,

  [Parameter()]
  [switch]$NoVenv,

  [Parameter()]
  [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$Message) { Write-Output "[Run-Docs] $Message" }
function Throw-Fail([string]$Message) { throw "[Run-Docs] $Message" }

$RepoRoot = Split-Path -Parent $PSCommandPath
$MkdocsYml = Join-Path $RepoRoot 'mkdocs.yml'
$VenvPath  = Join-Path $RepoRoot '.venv-mkdocs'
$ReqFile   = Join-Path $RepoRoot 'build\requirements-mkdocs.txt'

if (-not (Test-Path $MkdocsYml)) {
  Throw-Fail "mkdocs.yml not found at repo root: $MkdocsYml"
}

# Resolve Python launcher / executable
function Resolve-Python {
  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) { return @{ Kind='py'; Path=$py.Path } }

  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) { return @{ Kind='python'; Path=$python.Path } }

  Throw-Fail "Python not found. Install Python 3 and ensure 'py' or 'python' is on PATH."
}

$Python = Resolve-Python

# Resolve venv python
function Get-VenvPython([string]$VenvRoot) {
  $p = Join-Path $VenvRoot 'Scripts\python.exe'
  if (-not (Test-Path $p)) {
    Throw-Fail "Venv python not found at: $p"
  }
  return $p
}

# Create venv if missing
if (-not $NoVenv) {
  if (-not (Test-Path $VenvPath)) {
    Write-Info "Creating venv at: $VenvPath"
    if ($Python.Kind -eq 'py') {
      & $Python.Path -3 -m venv $VenvPath
    } else {
      & $Python.Path -m venv $VenvPath
    }
  } else {
    Write-Info "Using existing venv: $VenvPath"
  }
}

# Determine python to use for installs/running
$PyExec = if ($NoVenv) {
  $Python.Path
} else {
  Get-VenvPython -VenvRoot $VenvPath
}

# Ensure pip is present/up-to-date (best-effort)
Write-Info "Ensuring pip..."
try {
  & $PyExec -m pip --version | Out-Null
} catch {
  Throw-Fail "pip is not available for Python at '$PyExec'."
}

# Upgrade pip (safe)
try {
  & $PyExec -m pip install --upgrade pip | Out-Host
} catch {
  Write-Info "pip upgrade failed (continuing): $($_.Exception.Message)"
}

# Install requirements
if (Test-Path $ReqFile) {
  Write-Info "Installing docs dependencies from: $ReqFile"
  & $PyExec -m pip install -r $ReqFile | Out-Host
} else {
  # Fallback minimal set
  Write-Info "requirements-mkdocs.txt not found; installing minimal deps (mkdocs, mkdocs-material, pymdown-extensions)"
  & $PyExec -m pip install mkdocs mkdocs-material pymdown-extensions | Out-Host
}

# Build URL
$Url = "http://$BindHost`:$Port/"
Write-Info "Serving docs at: $Url"

# Open browser (optional)
if ($OpenBrowser) {
  # Start browser after a short delay so server is listening
  Start-Job -ScriptBlock {
    param($U)
    Start-Sleep -Milliseconds 900
    Start-Process $U
  } -ArgumentList $Url | Out-Null
}

# Run mkdocs serve (foreground, so CTRL+C stops it)
# Use --strict if requested (treat warnings as errors)
$serveArgs = @(
  '-m','mkdocs','serve',
  '-a', "$BindHost`:$Port",
  '--config-file', $MkdocsYml
)

if ($Strict) { $serveArgs += '--strict' }

Push-Location $RepoRoot
try {
  & $PyExec @serveArgs
} finally {
  Pop-Location
}