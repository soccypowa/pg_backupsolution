param(
  # Path to the mandatory Config file
  [Parameter(Mandatory = $true)]
  [string]
  $ConfigFile
)

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
  # Defaults
  $HOSTNAME = if ($HOSTNAME) { $HOSTNAME } else { 'localhost' }
  $USERNAME = if ($USERNAME) { $USERNAME } else { 'postgres' }
}
function Remove-PgBackup {
  param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('daily', 'weekly', 'monthly')]
    [string]
    $Type,
    [Parameter(Mandatory = $true)]
    [string]
    $Path,
    [Parameter(Mandatory = $false)]
    [int]
    $NumberToKeep
  )
  Get-ChildItem -Name $Path -Directory | Where-Object { $_.Name -like "*-$($Type)" } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force } 
}

function New-PgBackup {
  param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('daily', 'weekly', 'monthly')]
    [string]
    $Type,
    [Parameter(Mandatory = $true)]
    [string]
    $Path
  )
  # TODO: Check that we can find the pqsl executables, and make them full paths?
  
  $BackupDate = Get-Date -Format 'yyyy-MM-dd'
  $FullPathBackupdir = Join-Path $Path "$($BackupDate)-$($Type)"

  if (-not (Test-Path $FullPathBackupdir)) {
    New-Item -ItemType Directory -Path $FullPathBackupdir -Force | Out-Null
  }
}


$DayOfMonth = (Get-Date).Day
$DayOfWeek = (Get-Date).DayOfWeek.value__

New-PgBackupConfig -ConfigFile $ConfigFile
Get-Variable -Scope script
if ($DayOfMonth -eq 1) {
  Remove-PgBackup -Type monthly -Path $BACKUP_DIR -NumberToKeep $MONTHS_TO_KEEP
  New-PgBackup -Type monthly -Path $BACKUP_DIR
} elseif ($DayOfWeek -eq $DAY_OF_WEEK_TO_KEEP) {
  Remove-PgBackup -Type weekly -Path $BACKUP_DIR -NumberToKeep $WEEKS_TO_KEEP
  New-PgBackup -Type weekly -Path $BACKUP_DIR
} else {
  Remove-PgBackup -Type daily -Path $BACKUP_DIR -NumberToKeep $DAYS_TO_KEEP 
  New-PgBackup -Type daily -Path $BACKUP_DIR
}

