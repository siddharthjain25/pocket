
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AgentUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$AgentSha256,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Pi,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ListenerHostPublicKey,

    [string]$AgentName = $env:COMPUTERNAME,

    [ValidateSet('powershell', 'pwsh', 'cmd')]
    [string]$Shell = 'powershell'
)

$ErrorActionPreference = 'Stop'

$AppDir = Join-Path $env:LOCALAPPDATA 'PocketAgent'
$AgentExe = Join-Path $AppDir 'pocket-agent-windows-amd64.exe'
$KeyPath = Join-Path $AppDir 'agent_ed25519'
$HostKeyPath = Join-Path $AppDir 'listener_host_key.pub'
$RunnerPath = Join-Path $AppDir 'run-agent.ps1'
$TaskName = 'PocketAgent'

function Assert-HttpsUrl([string]$Url, [string]$Label) {
    $parsed = $null
    if (-not [Uri]::TryCreate(
        $Url, [UriKind]::Absolute, [ref]$parsed
    ) -or $parsed.Scheme -ne 'https') {
        throw "$Label must be a valid HTTPS URL."
    }
}

try {
    Assert-HttpsUrl $AgentUrl 'AgentUrl'

    if ($Pi -match '[\s/\\]') {
        throw 'Pi must be a hostname or IP address, without a port or path.'
    }

    if ($AgentName -notmatch '^[a-zA-Z0-9_.-]{1,64}$') {
        throw 'AgentName must contain only letters, digits, dots, underscores, or hyphens (maximum 64 characters).'
    }

    if ($ListenerHostPublicKey -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^\s]+)\s+\S+') {
        throw 'ListenerHostPublicKey does not look like an SSH public host-key line.'
    }

    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

    # Restrict the configuration directory to this user and SYSTEM.
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $AppDir /inheritance:r `
        /grant:r "${identity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw 'Could not restrict permissions on the agent directory.'
    }

    # Download to a temporary file and verify before installing.
    $download = Join-Path $AppDir 'agent.download.tmp'

    Write-Host 'Downloading Windows agent...'
    Invoke-WebRequest -Uri $AgentUrl -OutFile $download -UseBasicParsing

    $actualHash = (Get-FileHash -Path $download -Algorithm SHA256).Hash
    if ($actualHash -ne $AgentSha256.ToUpperInvariant()) {
        Remove-Item $download -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch. Expected $AgentSha256; got $actualHash. Agent was not installed."
    }

    Move-Item -Path $download -Destination $AgentExe -Force

    # Pin the listener key. Never disable SSH host-key verification.
    [System.IO.File]::WriteAllText(
        $HostKeyPath,
        $ListenerHostPublicKey.Trim() + "`n",
        [System.Text.Encoding]::ASCII
    )

    # Do not overwrite an existing private key.
    if (-not (Test-Path $KeyPath)) {
        Write-Host 'The agent will generate its SSH key during enrollment.'
    }

    # Ask for the token without echoing it to the console.
    $secureToken = Read-Host 'Enter the Pi enrollment token' -AsSecureString
    $tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)

    try {
        $env:POCKET_PI = $Pi
        $env:POCKET_SHELL = $Shell
        $env:POCKET_AGENT_NAME = $AgentName
        $env:POCKET_AGENT_KEY = $KeyPath
        $env:POCKET_LISTENER_HOST_PUBLIC_KEY = $HostKeyPath
        $env:POCKET_ENROLLMENT_TOKEN =
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr)

        Write-Host 'Enrolling agent with the Raspberry Pi...'
        & $AgentExe -pi $Pi -shell $Shell -host $AgentName -enroll-only

        if ($LASTEXITCODE -ne 0) {
            throw "Agent enrollment failed (exit code $LASTEXITCODE). Check the Pi address, token, pinned host key, and listener logs."
        }
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr)
        $secureToken.Dispose()
        Remove-Item Env:POCKET_ENROLLMENT_TOKEN -ErrorAction SilentlyContinue
    }

    # Create a launcher that supplies persistent, non-secret configuration.
    $runner = @'
$ErrorActionPreference = 'Stop'
$AppDir = Join-Path $env:LOCALAPPDATA 'PocketAgent'
$env:POCKET_AGENT_KEY = Join-Path $AppDir 'agent_ed25519'
$env:POCKET_LISTENER_HOST_PUBLIC_KEY = Join-Path $AppDir 'listener_host_key.pub'
$env:POCKET_PI = '__PI__'
$env:POCKET_SHELL = '__SHELL__'
$env:POCKET_AGENT_NAME = '__NAME__'
$exe = Join-Path $AppDir 'pocket-agent-windows-amd64.exe'
& $exe
exit $LASTEXITCODE
'@

    $runner = $runner.Replace('__PI__', $Pi).
        Replace('__SHELL__', $Shell).
        Replace('__NAME__', $AgentName)

    Set-Content -Path $RunnerPath -Value $runner -Encoding UTF8

    # Register a current-user logon task; no admin elevation is requested.
    $powerShellExe = Join-Path $PSHOME 'powershell.exe'
    $action = New-ScheduledTaskAction `
        -Execute $powerShellExe `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RunnerPath`""

    $trigger = New-ScheduledTaskTrigger -AtLogOn `
        -User "$env:USERDOMAIN\$env:USERNAME"

    $principal = New-ScheduledTaskPrincipal `
        -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive `
        -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description 'Pocket Key Windows agent' `
        -Force | Out-Null

    # Start it now; it will also start at future logons.
    Start-ScheduledTask -TaskName $TaskName

    Write-Host ''
    Write-Host 'Pocket Agent installation and enrollment completed.' -ForegroundColor Green
    Write-Host "Agent directory: $AppDir"
    Write-Host "Scheduled task:  $TaskName"
    Write-Host 'The enrollment token was not written to the launcher or scheduled task.'
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Remove-Item Env:POCKET_ENROLLMENT_TOKEN -ErrorAction SilentlyContinue
}
