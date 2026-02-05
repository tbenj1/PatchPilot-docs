#Requires -Version 7.0
<#
.SYNOPSIS
  MkDocs helper for PatchPilot-docs.

.DESCRIPTION
  Actions:
    - serve  : live preview (optionally opens browser)
    - build  : build static site
    - clean  : remove site output directory
    - doctor : environment diagnostics

  Creates/uses a local Python venv at .\.venv-mkdocs and installs dependencies
  from build\requirements-mkdocs.txt (if present), otherwise installs a minimal set.

.PARAMETER Action
  serve | build | clean | doctor

.PARAMETER Port
  Port for serve (default 8000)

.PARAMETER BindHost
  Host for serve (default 127.0.0.1)

.PARAMETER OpenBrowser
  For serve: open default browser to the local URL

.PARAMETER Strict
  Treat MkDocs warnings as errors (--strict)

.PARAMETER NoVenv
  Do not use venv; assumes mkdocs deps are installed globally

.EXAMPLE
  .\docs.cmd serve

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\build\Docs.ps1 serve -OpenBrowser
#>

[CmdletBinding()]
param(
  [Parameter(Position=0)]
  [ValidateSet('serve','build','clean','doctor')]
  [string]$Action = 'serve',

  [ValidateRange(1,65535)]
  [int]$Port = 8000,

  [string]$BindHost = '127.0.0.1',

  [switch]$OpenBrowser,

  [switch]$Strict,

  [switch]$NoVenv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

function Write-Info([string]$Message) { Write-Information "[Docs] $Message" -InformationAction Continue }
function Throw-Fail([string]$Message) { throw "[Docs] $Message" }

$RepoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..')
$MkdocsYml = Join-Path $RepoRoot 'mkdocs.yml'
$VenvPath  = Join-Path $RepoRoot '.venv-mkdocs'
$ReqFile   = Join-Path $RepoRoot 'build\requirements-mkdocs.txt'

if (-not (Test-Path $MkdocsYml)) {
  Throw-Fail "mkdocs.yml not found at: $MkdocsYml"
}

function Resolve-Python {
  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) { return @{ Kind='py'; Path=$py.Path } }

  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) { return @{ Kind='python'; Path=$python.Path } }

  Throw-Fail "Python not found. Install Python 3 and ensure 'py' or 'python' is on PATH."
}

function Get-VenvPython([string]$VenvRoot) {
  $p = Join-Path $VenvRoot 'Scripts\python.exe'
  if (-not (Test-Path $p)) { Throw-Fail "Venv python not found at: $p" }
  return $p
}

function Ensure-VenvAndDeps {
  param([switch]$NoVenv)

  $python = Resolve-Python

  if ($NoVenv) {
    Write-Info "NoVenv set: using system python at '$($python.Path)'."
    return $python.Path
  }

  if (-not (Test-Path $VenvPath)) {
    Write-Info "Creating venv: $VenvPath"
    if ($python.Kind -eq 'py') {
      & $python.Path -3 -m venv $VenvPath
    } else {
      & $python.Path -m venv $VenvPath
    }
  } else {
    Write-Info "Using existing venv: $VenvPath"
  }

  $pyExec = Get-VenvPython -VenvRoot $VenvPath

  Write-Info "Ensuring pip..."
  & $pyExec -m pip --version | Out-Null

  try {
    & $pyExec -m pip install --upgrade pip | Out-Host
  } catch {
    Write-Info "pip upgrade failed (continuing): $($_.Exception.Message)"
  }

  if (Test-Path $ReqFile) {
    Write-Info "Installing deps from: $ReqFile"
    & $pyExec -m pip install -r $ReqFile | Out-Host
  } else {
    Write-Info "requirements-mkdocs.txt not found; installing minimal deps"
    & $pyExec -m pip install mkdocs mkdocs-material pymdown-extensions | Out-Host
  }

  return $pyExec
}

function Invoke-MkDocs {
  param(
    [Parameter(Mandatory)][object]$PythonExe,
    [Parameter(Mandatory)][string[]]$Args
  )

  # Robust to PathInfo/arrays returned from helper functions
  $PythonExe = [string]$PythonExe

  Push-Location $RepoRoot
  try {
    & $PythonExe @Args
  } finally {
    Pop-Location
  }
}

switch ($Action) {
  'doctor' {
    Write-Info "RepoRoot : $RepoRoot"
    Write-Info "mkdocs.yml: $MkdocsYml"
    Write-Info "venv     : $VenvPath"
    $python = Resolve-Python
    Write-Info "python   : $($python.Path)"
    if (-not $NoVenv) {
      if (Test-Path $VenvPath) {
        $venvPy = Get-VenvPython -VenvRoot $VenvPath
        Write-Info "venv py  : $venvPy"
        & $venvPy -m pip --version | Out-Host
        try { & $venvPy -m mkdocs --version | Out-Host } catch { }
      } else {
        Write-Info "venv not created yet"
      }
    }
    exit 0
  }

  'clean' {
    # mkdocs.yml currently uses site_dir: site
    $site = Join-Path $RepoRoot 'site'
    if (Test-Path $site) {
      Write-Info "Removing site dir: $site"
      Remove-Item -Recurse -Force $site
    } else {
      Write-Info "Nothing to clean at: $site"
    }
    exit 0
  }

  'build' {
    $pyExec = [string](Ensure-VenvAndDeps -NoVenv:$NoVenv)
    $args = @('-m','mkdocs','build','--config-file',$MkdocsYml,'--clean')
    if ($Strict) { $args += '--strict' }
    Write-Info "Building site..."
    Invoke-MkDocs -PythonExe $pyExec -Args $args
    exit 0
  }

  'serve' {
    $pyExec = [string](Ensure-VenvAndDeps -NoVenv:$NoVenv)

    $url = "http://$BindHost`:$Port/"
    Write-Info "Serving at: $url"

    if ($OpenBrowser) {
      Start-Job -ScriptBlock {
        param($U)
        Start-Sleep -Milliseconds 900
        Start-Process $U
      } -ArgumentList $url | Out-Null
    }

    $args = @('-m','mkdocs','serve','--config-file',$MkdocsYml,'-a',"$BindHost`:$Port")
    if ($Strict) { $args += '--strict' }
    Invoke-MkDocs -PythonExe $pyExec -Args $args
    exit 0
  }
}
