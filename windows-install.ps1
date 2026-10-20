[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AgentUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Pi,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ListenerHostPublicKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnrollmentToken,

    [ValidatePattern('^[a-zA-Z0-9._-]{1,64}$')]
    [string]$AgentName = $env:COMPUTERNAME,

    [ValidateSet('powershell', 'pwsh', 'cmd')]
    [string]$Shell = 'powershell'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$AppDir       = Join-Path $env:LOCALAPPDATA 'PocketAgent'
$AgentExe     = Join-Path $AppDir 'pocket-agent-windows-amd64.exe'
$AgentKey     = Join-Path $AppDir 'agent_ed25519'
$HostKeyFile  = Join-Path $AppDir 'listener_host_key.pub'
$LauncherFile = Join-Path $AppDir 'run-agent.ps1'
$LogFile      = Join-Path $AppDir 'agent.log'
$TaskName     = 'PocketAgent'

$PowerShellExe = Join-Path $env:SystemRoot `
    'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---------------------------------------------------------------------------
# Validate configuration
# ---------------------------------------------------------------------------

if (-not $AgentUrl.StartsWith(
    'https://',
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw 'AgentUrl must use HTTPS.'
}

if ($ListenerHostPublicKey -notmatch '^ssh-ed25519\s+\S+') {
    throw 'ListenerHostPublicKey must be an ssh-ed25519 public host key.'
}

if ([string]::IsNullOrWhiteSpace($AgentName)) {
    throw 'AgentName cannot be empty.'
}

Write-Host ''
Write-Host 'Installing Pocket Agent...' -ForegroundColor Cyan
Write-Host "Install directory: $AppDir"
Write-Host "Agent name:        $AgentName"
Write-Host "Shell:             $Shell"
Write-Host ''

# ---------------------------------------------------------------------------
# Create installation directory and restrict permissions
# ---------------------------------------------------------------------------

New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

& icacls.exe $AppDir /inheritance:r `
    /grant:r "${CurrentUser}:(OI)(CI)F" `
    '*S-1-5-18:(OI)(CI)F' | Out-Host

if ($LASTEXITCODE -ne 0) {
    throw 'Failed to configure permissions on the Pocket Agent directory.'
}

# ---------------------------------------------------------------------------
# Download agent executable
# ---------------------------------------------------------------------------

$TempExe = Join-Path $env:TEMP (
    'pocket-agent-' + [guid]::NewGuid().ToString('N') + '.exe'
)

try {
    Write-Host 'Downloading Pocket Agent...' -ForegroundColor Cyan

    Invoke-WebRequest `
        -Uri $AgentUrl `
        -OutFile $TempExe `
        -UseBasicParsing

    if (-not (Test-Path -LiteralPath $TempExe)) {
        throw 'Agent download failed: file was not found.'
    }

    if ((Get-Item -LiteralPath $TempExe).Length -eq 0) {
        throw 'Agent download failed: downloaded file is empty.'
    }

    Move-Item -LiteralPath $TempExe -Destination $AgentExe -Force
}
finally {
    Remove-Item -LiteralPath $TempExe -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Save pinned listener host key
# ---------------------------------------------------------------------------

Set-Content `
    -LiteralPath $HostKeyFile `
    -Value $ListenerHostPublicKey.Trim() `
    -Encoding ascii

# ---------------------------------------------------------------------------
# Configure environment for enrollment
# ---------------------------------------------------------------------------

$env:POCKET_PI = $Pi
$env:POCKET_SHELL = $Shell
$env:POCKET_AGENT_NAME = $AgentName
$env:POCKET_AGENT_KEY = $AgentKey
$env:POCKET_LISTENER_HOST_PUBLIC_KEY = $HostKeyFile
$env:POCKET_ENROLLMENT_TOKEN = $EnrollmentToken

# ---------------------------------------------------------------------------
# Enroll agent
# ---------------------------------------------------------------------------

try {
    Write-Host ''
    Write-Host 'Enrolling Pocket Agent...' -ForegroundColor Cyan

    & $AgentExe `
        -pi $Pi `
        -shell $Shell `
        -host $AgentName `
        -enroll-only

    if ($LASTEXITCODE -ne 0) {
        throw "Agent enrollment failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Agent enrolled successfully.' -ForegroundColor Green
}
finally {
    # Do not assign to the validated EnrollmentToken parameter.
    Remove-Item Env:POCKET_ENROLLMENT_TOKEN -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Create hidden background launcher with logging and reconnect retries
# ---------------------------------------------------------------------------

$LauncherTemplate = @'
$ErrorActionPreference = 'Continue'

$AppDir = Join-Path $env:LOCALAPPDATA 'PocketAgent'
$AgentExe = Join-Path $AppDir 'pocket-agent-windows-amd64.exe'
$AgentKey = Join-Path $AppDir 'agent_ed25519'
$HostKeyFile = Join-Path $AppDir 'listener_host_key.pub'
$LogFile = Join-Path $AppDir 'agent.log'

$env:POCKET_PI = '__POCKET_PI__'
$env:POCKET_SHELL = '__POCKET_SHELL__'
$env:POCKET_AGENT_NAME = '__POCKET_AGENT_NAME__'
$env:POCKET_AGENT_KEY = $AgentKey
$env:POCKET_LISTENER_HOST_PUBLIC_KEY = $HostKeyFile

function Write-AgentLog {
    param([string]$Message)

    $Line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
}

Write-AgentLog 'Background launcher started.'

if (-not (Test-Path -LiteralPath $AgentExe)) {
    Write-AgentLog "ERROR: Agent executable not found: $AgentExe"
    exit 1
}

while ($true) {
    try {
        Write-AgentLog 'Starting Pocket Agent.'

        & $AgentExe `
            -pi $env:POCKET_PI `
            -shell $env:POCKET_SHELL `
            -host $env:POCKET_AGENT_NAME *>> $LogFile

        $ExitCode = $LASTEXITCODE
        Write-AgentLog "Agent exited with code $ExitCode. Restarting in 5 seconds."
    }
    catch {
        Write-AgentLog ("ERROR: " + $_.Exception.Message)
        Write-AgentLog 'Retrying in 5 seconds.'
    }

    Start-Sleep -Seconds 5
}
'@

# Escape single quotes for PowerShell single-quoted string literals.
$SafePi = $Pi.Replace("'", "''")
$SafeShell = $Shell.Replace("'", "''")
$SafeAgentName = $AgentName.Replace("'", "''")

$LauncherContent = $LauncherTemplate.Replace('__POCKET_PI__', $SafePi)
$LauncherContent = $LauncherContent.Replace('__POCKET_SHELL__', $SafeShell)
$LauncherContent = $LauncherContent.Replace(
    '__POCKET_AGENT_NAME__',
    $SafeAgentName
)

Set-Content `
    -LiteralPath $LauncherFile `
    -Value $LauncherContent `
    -Encoding UTF8

# ---------------------------------------------------------------------------
# Register background task at user logon
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Registering background scheduled task...' -ForegroundColor Cyan

$Action = New-ScheduledTaskAction `
    -Execute $PowerShellExe `
    -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LauncherFile`""

$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser

$Principal = New-ScheduledTaskPrincipal `
    -UserId $CurrentUser `
    -LogonType Interactive `
    -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Days 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$Task = New-ScheduledTask `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description 'Runs Pocket Agent in the background at user logon.'

Register-ScheduledTask `
    -TaskName $TaskName `
    -InputObject $Task `
    -Force | Out-Null

Write-Host 'Background task registered.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# Start the agent now
# ---------------------------------------------------------------------------

Start-ScheduledTask -TaskName $TaskName

Write-Host ''
Write-Host 'Pocket Agent installation completed.' -ForegroundColor Green
Write-Host "Install directory: $AppDir"
Write-Host "Scheduled task:    $TaskName"
Write-Host "Agent log:         $LogFile"
Write-Host ''
Write-Host 'The agent runs hidden and starts again at user logon.'
Write-Host ''
