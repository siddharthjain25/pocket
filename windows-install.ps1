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

    [ValidatePattern('^[a-zA-Z0-9._-]{1,64}$')]
    [string]$AgentName = $env:COMPUTERNAME,

    [ValidateSet('powershell', 'pwsh', 'cmd')]
    [string]$Shell = 'powershell'
)

$ErrorActionPreference = 'Stop'

# Validate inputs
if (-not $AgentUrl.StartsWith(
    'https://',
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw 'AgentUrl must use HTTPS.'
}

if ($ListenerHostPublicKey -notmatch '^ssh-ed25519\s+[A-Za-z0-9+/]+={0,3}(\s+.*)?$') {
    throw 'ListenerHostPublicKey is not a valid ssh-ed25519 public key line.'
}

# Installation paths
$AppDir = Join-Path $env:LOCALAPPDATA 'PocketAgent'
$AgentExe = Join-Path $AppDir 'pocket-agent-windows-amd64.exe'
$KeyPath = Join-Path $AppDir 'agent_ed25519'
$HostKeyPath = Join-Path $AppDir 'listener_host_key.pub'
$RunnerPath = Join-Path $AppDir 'run-agent.ps1'
$TaskName = 'PocketAgent'

# Create a private installation directory
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

# Restrict directory access to the current user and SYSTEM
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $AppDir /inheritance:r /grant:r `
    "${CurrentUser}:(OI)(CI)F" `
    '*S-1-5-18:(OI)(CI)F' | Out-Null

if ($LASTEXITCODE -ne 0) {
    throw 'Failed to set installation directory permissions.'
}

# Download the agent executable
$DownloadPath = Join-Path $env:TEMP (
    'pocket-agent-' + [guid]::NewGuid().ToString('N') + '.exe'
)

try {
    Invoke-WebRequest `
        -UseBasicParsing `
        -Uri $AgentUrl `
        -OutFile $DownloadPath

    if (-not (Test-Path $DownloadPath) -or
        (Get-Item $DownloadPath).Length -eq 0) {
        throw 'The downloaded agent executable is missing or empty.'
    }

    Move-Item -Path $DownloadPath -Destination $AgentExe -Force
}
finally {
    Remove-Item $DownloadPath -Force -ErrorAction SilentlyContinue
}

# Save the listener host key used for SSH host verification
Set-Content -Path $HostKeyPath `
    -Value $ListenerHostPublicKey `
    -Encoding ascii

# Ask for the enrollment token without echoing it
$SecureToken = Read-Host 'Enter the Pocket enrollment token' -AsSecureString
$TokenPointer = [IntPtr]::Zero
$EnrollmentToken = $null

try {
    $TokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $SecureToken
    )
    $EnrollmentToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        $TokenPointer
    )

    # Configure the enrollment process
    $env:POCKET_PI = $Pi
    $env:POCKET_SHELL = $Shell
    $env:POCKET_AGENT_NAME = $AgentName
    $env:POCKET_AGENT_KEY = $KeyPath
    $env:POCKET_LISTENER_HOST_PUBLIC_KEY = $HostKeyPath
    $env:POCKET_ENROLLMENT_TOKEN = $EnrollmentToken

    # Enroll and generate/store the agent key as implemented by the agent
    & $AgentExe `
        -pi $Pi `
        -shell $Shell `
        -host $AgentName `
        -enroll-only

    if ($LASTEXITCODE -ne 0) {
        throw "Agent enrollment failed with exit code $LASTEXITCODE."
    }
}
finally {
    $env:POCKET_ENROLLMENT_TOKEN = $null
    $EnrollmentToken = $null

    if ($TokenPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($TokenPointer)
    }

    if ($SecureToken) {
        $SecureToken.Dispose()
    }
}

# Write a launcher that restores the non-secret configuration
$Runner = @'
$ErrorActionPreference = 'Stop'

$env:POCKET_PI = __PI__
$env:POCKET_SHELL = __SHELL__
$env:POCKET_AGENT_NAME = __AGENT_NAME__
$env:POCKET_AGENT_KEY = __KEY_PATH__
$env:POCKET_LISTENER_HOST_PUBLIC_KEY = __HOST_KEY_PATH__

$AgentExe = __AGENT_EXE__
& $AgentExe -pi $env:POCKET_PI -shell $env:POCKET_SHELL -host $env:POCKET_AGENT_NAME
exit $LASTEXITCODE
'@

# Use PowerShell literal quoting to safely embed configured values
function ConvertTo-PowerShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

$Runner = $Runner.Replace('__PI__', (ConvertTo-PowerShellLiteral $Pi))
$Runner = $Runner.Replace('__SHELL__', (ConvertTo-PowerShellLiteral $Shell))
$Runner = $Runner.Replace('__AGENT_NAME__', (ConvertTo-PowerShellLiteral $AgentName))
$Runner = $Runner.Replace('__KEY_PATH__', (ConvertTo-PowerShellLiteral $KeyPath))
$Runner = $Runner.Replace('__HOST_KEY_PATH__', (ConvertTo-PowerShellLiteral $HostKeyPath))
$Runner = $Runner.Replace('__AGENT_EXE__', (ConvertTo-PowerShellLiteral $AgentExe))

Set-Content -Path $RunnerPath -Value $Runner -Encoding utf8

# Register a current-user task to start the agent at logon
$PowerShellExe = Join-Path $PSHOME 'powershell.exe'
$Action = New-ScheduledTaskAction `
    -Execute $PowerShellExe `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RunnerPath`"" `
    -WorkingDirectory $AppDir

$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser
$Principal = New-ScheduledTaskPrincipal `
    -UserId $CurrentUser `
    -LogonType Interactive `
    -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description 'Starts the Pocket Agent at user logon.' `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host ''
Write-Host 'Pocket Agent installation and enrollment completed.' -ForegroundColor Green
Write-Host "Install directory: $AppDir"
Write-Host "Scheduled task:    $TaskName"
Write-Host 'The agent will start at the next user logon.'
