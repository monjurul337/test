# Sync GitHub repository About description and topics (requires GH CLI + auth).
# Usage: .\scripts\sync-github-repo-settings.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Host 'Install GitHub CLI: winget install GitHub.cli'
  Write-Host 'Then run: gh auth login'
  exit 1
}

$about = Get-Content '.github\ABOUT.txt' -Raw
$desc = ($about -split "Description:\s*\r?\n")[1] -split "Website:" | Select-Object -First 1
$desc = $desc.Trim() -replace "`r`n", ' '

$website = ($about -split "Website:\s*\r?\n")[1].Trim() -split "`r`n" | Select-Object -First 1

$topics = Get-Content '.github\TOPICS.txt' | Where-Object { $_.Trim() -ne '' }

Write-Host "Setting description..."
gh repo edit --description $desc --homepage $website

Write-Host "Setting topics..."
gh repo edit --add-topic ($topics -join ',')

Write-Host 'Done. Verify at https://github.com/Anti-detect/Multilogin-Mastery--Top-1-Anti-detect-browser'
