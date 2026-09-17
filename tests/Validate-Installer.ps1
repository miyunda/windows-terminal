[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repositoryRoot 'Install-RosePine.ps1'
$workingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("rose-pine-installer-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $workingDirectory | Out-Null

function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function New-SettingsFile([string]$Name, [string]$Content) {
    $path = Join-Path $workingDirectory $Name
    [System.IO.File]::WriteAllText($path, $Content, [System.Text.UTF8Encoding]::new($false))
    return $path
}

function Invoke-Installer([string]$SettingsPath, [string]$Variant) {
    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer -Variant $Variant -SettingsPath $SettingsPath 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

try {
    $commentedSettings = @'
// Keep this header comment.
{
  "profiles": {
    "defaults": {
      "fontSize": 14,
    },
    "list": [
      { "name": "PowerShell", "commandline": "pwsh", "startingDirectory": "C:\\Users\\Taylor\\\"quoted\\\"" },
    ],
  },
  "schemes": [
    { "name": "custom-scheme", "background": "#000000" }, // Keep this custom scheme.
  ],
  "themes": [
    { "name": "custom-theme" },
  ],
  "theme": { "dark": "custom-theme", "light": "custom-theme" },
}
'@
    $commentedPath = New-SettingsFile 'commented.json' $commentedSettings
    $firstRun = Invoke-Installer $commentedPath 'Moon'
    Assert-That ($firstRun.ExitCode -eq 0) "Commented settings install failed: $($firstRun.Output)"
    $updated = Get-Content -LiteralPath $commentedPath -Raw
    $escapedSetting = '"startingDirectory": "C:\\Users\\Taylor\\\"quoted\\\""'
    Assert-That ($updated.Contains('// Keep this header comment.')) 'The header JSONC comment was not preserved.'
    Assert-That ($updated.Contains('// Keep this custom scheme.')) 'The array JSONC comment was not preserved.'
    Assert-That ($updated.Contains($escapedSetting)) 'An unrelated setting containing JSON escapes was changed.'
    Assert-That ($updated.Contains('"fontSize": 14')) 'profiles.defaults customization was changed.'
    Assert-That (($updated | Select-String -AllMatches -Pattern '"name": "rose-pine-moon"').Matches.Count -eq 2) 'Moon scheme and theme were not each added exactly once.'
    Assert-That ($updated.Contains('"colorScheme": "rose-pine-moon"')) 'profiles.defaults.colorScheme was not selected.'
    Assert-That ($updated.Contains('"dark": "rose-pine-moon"')) 'The dark theme selection was not updated.'
    Assert-That ($updated.Contains('"light": "rose-pine-moon"')) 'The light theme selection was not updated.'
    $firstBackupCount = @(Get-ChildItem -Path "$commentedPath.rose-pine-backup-*.json").Count
    Assert-That ($firstBackupCount -eq 1) 'The first update did not create exactly one backup.'

    $secondRun = Invoke-Installer $commentedPath 'Moon'
    Assert-That ($secondRun.ExitCode -eq 0) "Repeated install failed: $($secondRun.Output)"
    $secondBackupCount = @(Get-ChildItem -Path "$commentedPath.rose-pine-backup-*.json").Count
    Assert-That ($secondBackupCount -eq 1) 'Repeated install created an unnecessary backup.'
    $afterRepeat = Get-Content -LiteralPath $commentedPath -Raw
    Assert-That (($afterRepeat | Select-String -AllMatches -Pattern '"name": "rose-pine-moon"').Matches.Count -eq 2) 'Repeated install duplicated a theme or scheme.'

    $existingEntrySettings = @'
{
  "schemes": [
    { "name": "rose-pine-dawn", "background": "#ABCDEF" }
  ],
  "themes": [
    { "name": "rose-pine-dawn", "window": { "useMica": true } }
  ],
  "profiles": { "defaults": { "opacity": 87 } }
}
'@
    $existingEntryPath = New-SettingsFile 'existing-entry.json' $existingEntrySettings
    $existingRun = Invoke-Installer $existingEntryPath 'Dawn'
    Assert-That ($existingRun.ExitCode -eq 0) "Existing entry install failed: $($existingRun.Output)"
    $existingUpdated = Get-Content -LiteralPath $existingEntryPath -Raw
    Assert-That ($existingUpdated.Contains('"background": "#ABCDEF"')) 'An existing custom scheme was overwritten.'
    Assert-That ($existingUpdated.Contains('"useMica": true')) 'An existing custom theme was overwritten.'
    Assert-That ($existingUpdated.Contains('"opacity": 87')) 'An unrelated profile customization was changed.'

    $malformedPath = New-SettingsFile 'malformed.json' '{ "profiles": '
    $malformedOriginal = Get-Content -LiteralPath $malformedPath -Raw
    $malformedRun = Invoke-Installer $malformedPath 'RosePine'
    Assert-That ($malformedRun.ExitCode -ne 0) 'Malformed settings were accepted.'
    Assert-That ((Get-Content -LiteralPath $malformedPath -Raw) -eq $malformedOriginal) 'Malformed settings were modified.'
    Assert-That (@(Get-ChildItem -Path "$malformedPath.rose-pine-backup-*.json").Count -eq 0) 'Malformed settings created a backup.'

    Write-Host 'Installer validation passed.'
}
finally {
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
