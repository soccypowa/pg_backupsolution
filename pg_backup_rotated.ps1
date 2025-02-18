# Configuration loading
param(
  [string]$ConfigFilePath
)

if (-not $ConfigFilePath) {
  $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
  $ConfigFilePath = Join-Path $ScriptPath 'pg_backup.config'
}

if (-not (Test-Path $ConfigFilePath)) {
  Write-Host "Could not load config file from $ConfigFilePath" -ForegroundColor Red
  exit 1
}

# Load config file as key-value pairs
Get-Content $ConfigFilePath | ForEach-Object {
  if ($_ -match '^(.*?)=(.*)$') {
    Set-Variable -Name $matches[1].Trim() -Value $matches[2].Trim() -Scope Script
  }
}

# Pre-backup checks
if ($Env:USERNAME -ne $BACKUP_USER -and $BACKUP_USER) {
  Write-Host "This script must be run as $BACKUP_USER. Exiting." -ForegroundColor Red
  exit 1
}

# Defaults
$HOSTNAME = if ($HOSTNAME) { $HOSTNAME } else { 'localhost' }
$USERNAME = if ($USERNAME) { $USERNAME } else { 'postgres' }

function Perform-Backup {
  param($Suffix)

  $BackupDate = Get-Date -Format 'yyyy-MM-dd'
  $FinalBackupDir = Join-Path $BACKUP_DIR "$BackupDate$Suffix"

  if (-not (Test-Path $FinalBackupDir)) {
    New-Item -ItemType Directory -Path $FinalBackupDir | Out-Null
  }

  # Globals backup
  if ($ENABLE_GLOBALS_BACKUPS -eq 'yes') {
    Write-Host "Performing globals backup"
    $GlobalsBackupFile = Join-Path $FinalBackupDir 'globals.sql.gz'
    pg_dumpall -g -h $HOSTNAME -U $USERNAME | Out-File -FilePath $GlobalsBackupFile -Encoding utf8; Compress-Archive -Path $GlobalsBackupFile -DestinationPath "$GlobalsBackupFile.zip"; Remove-Item $GlobalsBackupFile
  }

  # Schema-only backups
  $SchemaOnlyDatabases = psql -h $HOSTNAME -U $USERNAME -At -c "SELECT datname FROM pg_database WHERE datname = ANY(ARRAY[$(($SCHEMA_ONLY_LIST -split ',') -join ',' -replace '(\w+)', '''$1''')])" postgres

  foreach ($Database in $SchemaOnlyDatabases) {
    Write-Host "Schema-only backup of $Database"
    $SchemaBackupFile = Join-Path $FinalBackupDir "${Database}_SCHEMA.sql.gz"
    pg_dump -Fp -s -h $HOSTNAME -U $USERNAME -d $Database | Out-File -FilePath $SchemaBackupFile -Encoding utf8; Compress-Archive -Path $SchemaBackupFile -DestinationPath "$SchemaBackupFile.zip"; Remove-Item $SchemaBackupFile
  }

  # Full backups
  $FullDatabases = psql -h $HOSTNAME -U $USERNAME -At -c "SELECT datname FROM pg_database WHERE datname NOT IN ($(($SCHEMA_ONLY_LIST -split ',') -join ',' -replace '(\w+)', '''$1''')) AND datistemplate = false AND datallowconn = true" postgres

  foreach ($Database in $FullDatabases) {
    if ($ENABLE_PLAIN_BACKUPS -eq 'yes') {
      Write-Host "Plain backup of $Database"
      $PlainBackupFile = Join-Path $FinalBackupDir "${Database}.sql.gz"
      pg_dump -Fp -h $HOSTNAME -U $USERNAME -d $Database | Out-File -FilePath $PlainBackupFile -Encoding utf8; Compress-Archive -Path $PlainBackupFile -DestinationPath "$PlainBackupFile.zip"; Remove-Item $PlainBackupFile
    }

    if ($ENABLE_CUSTOM_BACKUPS -eq 'yes') {
      Write-Host "Custom backup of $Database"
      $CustomBackupFile = Join-Path $FinalBackupDir "${Database}.custom"
      pg_dump -Fc -h $HOSTNAME -U $USERNAME -d $Database -f $CustomBackupFile
    }
  }

  Write-Host "All database backups complete!"
}

# Rotations
$DayOfMonth = (Get-Date).Day
$DayOfWeek = (Get-Date).DayOfWeek.value__

if ($DayOfMonth -eq 1) {
  Get-ChildItem $BACKUP_DIR -Directory | Where-Object { $_.Name -like '*-monthly' } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
  Perform-Backup '-monthly'
} elseif ($DayOfWeek -eq $DAY_OF_WEEK_TO_KEEP) {
  Get-ChildItem $BACKUP_DIR -Directory | Where-Object { $_.Name -like '*-weekly' -and $_.LastWriteTime -lt (Get-Date).AddDays( - $($WEEKS_TO_KEEP * 7)) } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
  Perform-Backup '-weekly'
} else {
  Get-ChildItem $BACKUP_DIR -Directory | Where-Object { $_.Name -like '*-daily' -and $_.LastWriteTime -lt (Get-Date).AddDays(-$DAYS_TO_KEEP) } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
  Perform-Backup '-daily'
}
