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
  if (Test-Path $Path) {
    Get-ChildItem -Name $Path -Directory | Where-Object { $_.Name -like "*-$($Type)" } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force } 
  }
}

function New-PgBackup {
  param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('daily', 'weekly', 'monthly')]
    [string]
    $Type,
    [Parameter(Mandatory = $true)]
    [string]
    $Path,
    [Parameter(Mandatory = $true)]
    [ValidateSet('yes', 'no')]
    [string]
    $BackupGlobals,
    [Parameter(Mandatory = $false)]
    [string]
    $ComputerName = $env:COMPUTERNAME,
    [Parameter(Mandatory = $false)]
    [string]
    $UserName = 'postgres',
    [Parameter(Mandatory = $false)]
    [string]
    $SchemaOnlyDatabases = ''
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
      pg_dump.exe -Fp -s -h $ComputerName -U $UserName -d $database | Out-File -FilePath $schemaBackupFile -Encoding utf8; Compress-Archive -Path $schemaBackupFile -DestinationPath "$schemaBackupFile.zip"; Remove-Item $schemaBackupFile 
    }
  }
  
}


$DayOfMonth = (Get-Date).Day
$DayOfWeek = (Get-Date).DayOfWeek.value__

New-PgBackupConfig -ConfigFile $ConfigFile
Get-Variable -Scope script
if ($DayOfMonth -eq 1) {
  Remove-PgBackup -Type monthly -Path $BACKUP_DIR -NumberToKeep $MONTHS_TO_KEEP
  New-PgBackup -Type monthly -Path $BACKUP_DIR -BackupGlobals $ENABLE_GLOBALS_BACKUPS -ComputerName $HOSTNAME -UserName $USERNAME -SchemaOnlyDatabases $SCHEMA_ONLY_LIST
} elseif ($DayOfWeek -eq $DAY_OF_WEEK_TO_KEEP) {
  Remove-PgBackup -Type weekly -Path $BACKUP_DIR -NumberToKeep $WEEKS_TO_KEEP
  New-PgBackup -Type weekly -Path $BACKUP_DIR -BackupGlobals $ENABLE_GLOBALS_BACKUPS -ComputerName $HOSTNAME -UserName $USERNAME -SchemaOnlyDatabases $SCHEMA_ONLY_LIST
} else {
  Remove-PgBackup -Type daily -Path $BACKUP_DIR -NumberToKeep $DAYS_TO_KEEP 
  New-PgBackup -Type daily -Path $BACKUP_DIR -BackupGlobals $ENABLE_GLOBALS_BACKUPS -ComputerName $HOSTNAME -UserName $USERNAME -SchemaOnlyDatabases $SCHEMA_ONLY_LIST
}

