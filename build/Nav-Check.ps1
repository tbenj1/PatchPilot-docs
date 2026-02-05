#Requires -Version 7.0

[CmdletBinding()]
param(
  [string]$DocsRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

Write-Output "PatchPilot docs link check"
Write-Output "Docs root: $DocsRoot`n"

$ErrorCount = 0
$MdFiles = Get-ChildItem -Path $DocsRoot -Filter *.md -Recurse -File

function Get-SlugsFromFile([string]$Path) {
    $Content = Get-Content -LiteralPath $Path -Raw
    $Slugs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Regex = [regex]'(?m)^\s{0,3}(#+)\s+(.+?)\s*$'
    foreach ($M in $Regex.Matches($Content)) {
        $H = $M.Groups[2].Value.Trim()
        $Slug = $H.ToLowerInvariant()
        $Slug = ($Slug -replace '[^\p{L}\p{Nd}\s-]','') -replace '\s+','-'
        $Slug = $Slug.Trim('-')
        $null = $Slugs.Add($Slug)
    }
    return $Slugs
}

function Get-ContentSansFences([string]$Path) {
    $Raw = Get-Content -LiteralPath $Path -Raw
    # Remove fenced code blocks (including mermaid) by toggling fence state line-by-line.
    $InFence = $false
    $OutLines = New-Object System.Collections.Generic.List[string]
    foreach ($Line in ($Raw -split "\r?\n", 0)) {
        if ($Line -match '^\s*```') { $InFence = -not $InFence; continue }
        if (-not $InFence) { $OutLines.Add($Line) }
    }
    return ($OutLines -join [Environment]::NewLine)
}

function Test-FileLinks($File, [ref]$ErrorCount) {
$null = $ErrorCount.Value
    $Text = Get-ContentSansFences $File.FullName

    # Only real links: [text](href)
    $LinkRe = [regex]'(?<!\!)\[(?<text>[^\]]+)\]\((?<href>[^)]+)\)'
    foreach ($M in $LinkRe.Matches($Text)) {
        $Label = $M.Groups['text'].Value
        $Href  = $M.Groups['href'].Value.Trim()

        # Skip external
        if ($Href -match '^(https?|mailto|tel):') { continue }

        # In-page anchor
        if ($Href -like '#*') {
            $Slug = $Href.TrimStart('#')
            $Slugs = Get-SlugsFromFile $File.FullName
            if (-not $Slugs.Contains($Slug)) {
                Write-Output "✗ [$($File.FullName.Substring($DocsRoot.Length))] -> $Label : missing anchor '#$Slug'"
                $ErrorCount.Value++
            }
            continue
        }

        # Split path#anchor
        $TargetPath, $TargetAnchor = $Href -split '#', 2
        $TargetFull = Resolve-Path (Join-Path $File.DirectoryName $TargetPath) -ErrorAction SilentlyContinue
        if (-not $TargetFull) {
            Write-Output "✗ [$($File.FullName.Substring($DocsRoot.Length))] -> $Label : missing file '$Href'"
            $ErrorCount.Value++
            continue
        }
        if ($TargetAnchor) {
            $Slugs = Get-SlugsFromFile $TargetFull.Path
            if (-not $Slugs.Contains($TargetAnchor)) {
                Write-Output "✗ [$($File.FullName.Substring($DocsRoot.Length))] -> $Label : missing anchor '#$TargetAnchor' in '$TargetPath'"
                $ErrorCount.Value++
            }
        }
    }
}

foreach ($F in $MdFiles) { Test-FileLinks $F ([ref]$ErrorCount) }

if ($ErrorCount -eq 0) {
    Write-Output "`nAll good. 0 issue(s) found."
    exit 0
} else {
    Write-Output "`n$ErrorCount issue(s) found."
    exit 1
}

