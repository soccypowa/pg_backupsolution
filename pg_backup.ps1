param(
  # Path to the mandatory Config file
  [Parameter(Mandatory = $true)]
  [string]
  $ConfigFile
)

# TODO: Function that reads the config and set environment variables in the context of the script
# TODO: We need to check that the plain_text and custom is not set at the same time
function New-PgBackupConfig {
  param (
    [Parameter(Mandatory = $true)]
    [string]
    $ConfigFile
  )
  if (!(Test-Path $ConfigFile)) {
    Write-Host "File not found: $ConfigFile" -ForegroundColor Red
    Exit 1
  }
  # Load config file as key-value pairs
  Get-Content $ConfigFile | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$' -and $_ -notmatch '#') {
      Set-Variable -Name $matches[1].Trim() -Value $matches[2].Trim() -Scope Script
    }
  }
}

function New-PgBackup {
  param (
    #OptionalParameters
  )
  # TODO: Check that we can find the pqsl executables, and make them full paths?
}

New-PgBackupConfig -ConfigFile $ConfigFile
Get-Variable -Scope script
New-PgBackup