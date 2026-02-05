#Requires -Version 7.0
<##
.SYNOPSIS
  Convenience wrapper for building/serving PatchPilot-docs.

.DESCRIPTION
  Calls .\build\Docs.ps1 with the requested action.
  This exists so contributors can run:
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Docs.ps1 serve

  For the full interface (port/bind/strict/etc.), call Docs.ps1 directly.
##>

[CmdletBinding()]
param(
  [Parameter(Position=0)]
  [ValidateSet('serve','build','clean','doctor')]
  [string]$Action = 'serve',

  [switch]$OpenBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$docsPs1  = Join-Path $repoRoot 'build\Docs.ps1'

if (-not (Test-Path $docsPs1)) {
  throw "Docs helper not found: $docsPs1"
}

$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$docsPs1,'-Action',$Action)
if ($OpenBrowser) { $args += '-OpenBrowser' }

& pwsh @args