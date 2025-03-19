param(
  # Path to the mandatory Config file
  [Parameter(Mandatory)]
  [System.IO.FileInfo]
  $ConfigFile
)

function New-PgBackupConfig {
  param (
    [Parameter(Mandatory)]
    [System.IO.FileInfo]
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
    [Parameter(Mandatory)]
    [ValidateSet('daily', 'weekly', 'monthly')]
    [string]
    $Type,
    [Parameter(Mandatory)]
    [System.IO.FileInfo]
    $Path,
    [Parameter]
    [int]
    $NumberToKeep
  )

  if (Test-Path $Path) {
    Get-ChildItem -Path $Path\*-$($Type) -Directory | Select-Object -SkipLast $NumberToKeep | ForEach-Object { Remove-Item $_.FullName -Recurse -Force } 
  }
}

function New-PgBackup {
  param (
    [Parameter(Mandatory)]
    [ValidateSet('daily', 'weekly', 'monthly')]
    [string]
    $Type,
    [Parameter(Mandatory)]
    [System.IO.FileInfo]
    $Path,
    [Parameter(Mandatory)]
    [ValidateSet('yes', 'no')]
    [string]
    $BackupGlobals,
    [Parameter]
    [string]
    $ComputerName = $env:COMPUTERNAME,
    [Parameter]
    [string]
    $UserName = 'postgres',
    [Parameter]
    [string]
    $SchemaOnlyDatabases = '',
    [Parameter(Mandatory)]
    [ValidateSet('yes', 'no')]
    [string]
    $PlainBackups,
    [Parameter(Mandatory)]
    [ValidateSet('yes', 'no')]
    [string]
    $CustomBackups
  )
  
  $BackupDate = Get-Date -Format 'yyyy-MM-dd'
  $FullPathBackupdir = Join-Path $Path "$($BackupDate)-$($Type)"

  # Create folder if not exists
  if (-not (Test-Path $FullPathBackupdir)) {
    New-Item -ItemType Directory -Path $FullPathBackupdir -Force | Out-Null
  }

  # Check so that pg-commands are reachable
  Get-Command pg_dumpall.exe | Out-Null
  Get-Command pg_dump.exe | Out-Null
  Get-Command psql.exe | Out-Null
  
  # TODO: We should always overwite files, for simplicity

  # Global backups
  if ($BackupGlobals -eq 'yes') {
    Write-Host 'Performing globals backup'
    $GlobalsBackupFile = Join-Path $FullPathBackupdir 'globals.sql'
    pg_dumpall.exe -g -h $ComputerName -U $UserName | Out-File -FilePath $GlobalsBackupFile -Encoding utf8; Compress-Archive -Path $GlobalsBackupFile -DestinationPath "$GlobalsBackupFile.zip" -Force; Remove-Item $GlobalsBackupFile
  }
  # Schema-Only backups
  if ($SchemaOnlyDatabases -ne '') {
    $SchemaOnlyDatabases = (($SCHEMA_ONLY_LIST).Split(',') | ForEach-Object { "'$_'" }) -join ','
    $databases = psql.exe -h $ComputerName -U $UserName -d postgres -At -c "SELECT datname FROM pg_database WHERE datname = ANY(ARRAY[$SchemaOnlyDatabases]) AND datistemplate = false AND datallowconn = true"
    foreach ($database  in $databases) {
      Write-Host "Performing schema-only backup of database $database"
      $schemaBackupFile = Join-Path $FullPathBackupdir "${database}_SCHEMA.sql"
      pg_dump.exe -Fp -s -h $ComputerName -U $UserName -d $database | Out-File -FilePath $schemaBackupFile -Encoding utf8; Compress-Archive -Path $schemaBackupFile -DestinationPath "$schemaBackupFile.zip" -Force; Remove-Item $schemaBackupFile 
    }
  }
  # Full backups
  $SchemaOnlyDatabases = (($SCHEMA_ONLY_LIST).Split(',') | ForEach-Object { "'$_'" }) -join ','
  $databases = psql.exe -h $ComputerName -U $UserName -d postgres -At -c "SELECT datname FROM pg_database WHERE datname NOT IN ($SchemaOnlyDatabases) AND datistemplate = false AND datallowconn = true"
  foreach ($database in $databases) {
    if ($PlainBackups -eq 'yes') {
      Write-Host "Plain backup of database $database"
      $plainBackupFile = Join-Path $FullPathBackupdir "${database}.sql"
      pg_dump.exe -Fp -h $ComputerName -U $UserName -d $database | Out-File -FilePath $plainBackupFile -Encoding utf8; Compress-Archive -Path $PlainBackupFile -DestinationPath "$PlainBackupFile.zip" -Force; Remove-Item $PlainBackupFile
    }
    if ($CustomBackups -eq 'yes') {
      Write-Host "Custom backup of database $database"
      $customBackupFile = Join-Path $FullPathBackupdir "${database}.bak"
      pg_dump.exe -Fc -h $HOSTNAME -U $USERNAME -d $database -f $customBackupFile
    }
  }
  Write-Host "All database backups complete!"
}


$DayOfMonth = (Get-Date).Day
$DayOfWeek = (Get-Date).DayOfWeek.value__

New-PgBackupConfig -ConfigFile $ConfigFile
if ($DayOfMonth -eq 1) {
  Remove-PgBackup -Type monthly -Path $BACKUP_DIR -NumberToKeep $MONTHS_TO_KEEP
  New-PgBackup -Type monthly -Path $BACKUP_DIR -BackupGlobals $ENABLE_GLOBALS_BACKUPS -ComputerName $HOSTNAME -UserName $USERNAME -SchemaOnlyDatabases $SCHEMA_ONLY_LIST -PlainBackups $ENABLE_PLAIN_BACKUPS -CustomBackups $ENABLE_CUSTOM_BACKUPS
} elseif ($DayOfWeek -eq $DAY_OF_WEEK_TO_KEEP) {
  Remove-PgBackup -Type weekly -Path $BACKUP_DIR -NumberToKeep $WEEKS_TO_KEEP
  New-PgBackup -Type weekly -Path $BACKUP_DIR -BackupGlobals $ENABLE_GLOBALS_BACKUPS -ComputerName $HOSTNAME -UserName $USERNAME -SchemaOnlyDatabases $SCHEMA_ONLY_LIST -PlainBackups $ENABLE_PLAIN_BACKUPS -CustomBackups $ENABLE_CUSTOM_BACKUPS
} else {
  Remove-PgBackup -Type daily -Path $BACKUP_DIR -NumberToKeep $DAYS_TO_KEEP 
  New-PgBackup -Type daily -Path $BACKUP_DIR -BackupGlobals $ENABLE_GLOBALS_BACKUPS -ComputerName $HOSTNAME -UserName $USERNAME -SchemaOnlyDatabases $SCHEMA_ONLY_LIST -PlainBackups $ENABLE_PLAIN_BACKUPS -CustomBackups $ENABLE_CUSTOM_BACKUPS
}

