<#
.SYNOPSIS
    "Super" Master Script to configure the entire Windows + WSL environment.
.DESCRIPTION
    1. Guarantees Administrator privileges (using gsudo if available, or manual check).
    2. Installs WSL 2 (if not installed) and prompts for a required reboot.
    3. Installs Chocolatey (if not installed).
    4. Enables Chocolatey's auto-confirmation for scripts.
    5. Installs/Upgrades ALL Windows tools (Seções 5/6) and Windows Updates (Seção 8) in parallel.
    6. Installs essential VS Code Extensions (in batch).
    7. Automatically executes the 'wsl_ubuntu.sh' script (sequentially, for sudo).
    8. Cleans up all temp files and optimizes the system.
.NOTES
    Version: 5.3 (Exact package cache, 1618 retry, WSL detection fix, PS 5.1 encoding fix)
    Author: Kaua
    LOGIC: Uses hybrid Install-Package function with winget priority and choco fallback
           (fallback only when the JSON entry defines a "choco" name).
    IMPROVEMENTS: 
    - Externalized packages to packages_windows.json for easy maintenance
    - Hybrid Install-Package function with smart existence checks
    - Added hxd and cloc packages as requested
    - Maintains special handling for MariaDB and Visual Studio
    - Detailed logging with JSON summary saved to %LOCALAPPDATA%\ESSENTIALSPPACK\
#>

param(
    [string]$WslDistro = "Ubuntu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- 0. Helper Functions & Global Variables ---
$Global:RebootIsNeeded = $false
$Global:InstallSummary = @{
    Succeeded = @()
    Failed = @()
    Skipped = @()
}

function Test-RebootRequired {
    try {
        if (Get-Command Test-PendingReboot -ErrorAction SilentlyContinue) {
            if (Test-PendingReboot -ErrorAction SilentlyContinue) { return $true }
        }
    } catch {}
    
    $RegKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    )
    
    foreach ($key in $RegKeys) {
        if (Test-Path $key) { return $true }
    }
    
    if (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue) {
        return $true
    }
    
    return $false
}

function Install-PSModuleSafely {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing PowerShell module: $Name..." -ForegroundColor Yellow
        try {
            Install-Module -Name $Name -Force -Scope AllUsers -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        } catch {
            Write-Host "  WARNING: Failed to install $Name - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "PowerShell module '$Name' already installed." -ForegroundColor Green
    }
}

function Write-InstallSummary {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  INSTALLATION SUMMARY" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "✓ Succeeded ($($Global:InstallSummary.Succeeded.Count)):" -ForegroundColor Green
    if ($Global:InstallSummary.Succeeded.Count -gt 0) {
        foreach ($pkg in $Global:InstallSummary.Succeeded) {
            Write-Host "  - $pkg" -ForegroundColor Green
        }
    } else {
        Write-Host "  (none)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "✗ Failed ($($Global:InstallSummary.Failed.Count)):" -ForegroundColor Red
    if ($Global:InstallSummary.Failed.Count -gt 0) {
        foreach ($pkg in $Global:InstallSummary.Failed) {
            if ($pkg -is [hashtable]) {
                Write-Host "  - $($pkg.Package) (Exit: $($pkg.ExitCode), Error: $($pkg.Error))" -ForegroundColor Red
            } else {
                Write-Host "  - $pkg" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  (none)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "⊘ Already installed / skipped ($($Global:InstallSummary.Skipped.Count)):" -ForegroundColor Yellow
    if ($Global:InstallSummary.Skipped.Count -gt 0) {
        foreach ($pkg in $Global:InstallSummary.Skipped) {
            Write-Host "  - $pkg" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  (none)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    
    # Create log directory
    $logDir = Join-Path $env:LOCALAPPDATA "ESSENTIALSPPACK"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    # Generate log file name with timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $logFile = Join-Path $logDir "install-log-$timestamp.json"
    
    # Prepare summary object for JSON
    $summaryObject = @{
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        ScriptVersion = "5.3"
        Succeeded = $Global:InstallSummary.Succeeded
        Failed = $Global:InstallSummary.Failed
        Skipped = $Global:InstallSummary.Skipped
        Statistics = @{
            TotalSucceeded = $Global:InstallSummary.Succeeded.Count
            TotalFailed = $Global:InstallSummary.Failed.Count
            TotalSkipped = $Global:InstallSummary.Skipped.Count
        }
    }
    
    # Write to JSON file
    try {
        $summaryObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $logFile -Encoding UTF8
        Write-Host "Installation log saved to: $logFile" -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Failed to write log file: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Install-PackageWithChoco {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageName,
        [string]$ExtraArgs = "",
        [scriptblock]$SpecialHandler = $null
    )
    
    # Native stderr must not become a terminating error ($ErrorActionPreference = "Stop" at script level)
    $ErrorActionPreference = 'Continue'

    Write-Host "  -> Installing/Upgrading: $PackageName" -ForegroundColor Cyan
    
    # Capture output and errors
    $output = ""
    $exitCode = 0
    
    try {
        if ($ExtraArgs) {
            $output = choco upgrade $PackageName -y --noprogress $ExtraArgs 2>&1 | Out-String
        } else {
            $output = choco upgrade $PackageName -y --noprogress 2>&1 | Out-String
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $exitCode = -1
    }
    
    # Run special handler if provided
    if ($null -ne $SpecialHandler) {
        & $SpecialHandler -ExitCode $exitCode -Output $output -PackageName $PackageName
    }
    
    # Standard exit code handling
    if ($exitCode -eq 0) {
        Write-Host "  ✓ $PackageName" -ForegroundColor Green
        $Global:InstallSummary.Succeeded += $PackageName
        return $true
    } elseif ($exitCode -eq 1605 -or $exitCode -eq 1614 -or $exitCode -eq 1641) {
        # 1605 = Product not found (already installed)
        # 1614 = Product already installed
        # 1641 = Restart initiated
        Write-Host "  ✓ $PackageName (already installed or requires restart)" -ForegroundColor Green
        $Global:InstallSummary.Succeeded += $PackageName
        return $true
    } elseif ($exitCode -eq 1603) {
        # MSI fatal error - common with database packages
        Write-Host "  ✗ $PackageName (MSI fatal error 1603)" -ForegroundColor Red
        Write-Host "    Hint: Check for conflicting installations or locked files" -ForegroundColor Yellow
        $Global:InstallSummary.Failed += @{
            Package = $PackageName
            ExitCode = $exitCode
            Error = "MSI fatal error 1603"
        }
        return $false
    } else {
        Write-Host "  ✗ $PackageName (exit code: $exitCode)" -ForegroundColor Yellow
        $Global:InstallSummary.Failed += @{
            Package = $PackageName
            ExitCode = $exitCode
            Error = if ($output -match "error|failed") { ($output -split "`n" | Select-Object -First 3) -join "; " } else { "Unknown error" }
        }
        return $false
    }
}

function Install-PortableApps {
    param(
        [array]$Apps
    )
    
    Write-Host ""
    Write-Host ">>> Starting Portable App downloads..." -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($app in $Apps) {
        Write-Host "  -> Downloading: $($app.name)" -ForegroundColor Cyan
        
        # Verifica se o arquivo já existe no destino
        if (Test-Path $app.destination) {
            Write-Host "  ✓ $($app.name) (already exists at $($app.destination))" -ForegroundColor Green
            $Global:InstallSummary.Succeeded += $app.name
            continue
        }
        
        try {
            # Cria o diretório de destino se não existir
            $Dir = Split-Path $app.destination -Parent
            if (-not (Test-Path $Dir)) {
                New-Item -ItemType Directory -Force -Path $Dir | Out-Null
            }
            
            # Baixa o arquivo
            Write-Host "    Downloading from $($app.url)..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $app.url -OutFile $app.destination -ErrorAction Stop
            
            Write-Host "  ✓ $($app.name) (downloaded to $($app.destination))" -ForegroundColor Green
            $Global:InstallSummary.Succeeded += $app.name
        } catch {
            Write-Host "  ✗ $($app.name) (Download failed: $($_.Exception.Message))" -ForegroundColor Red
            # Adiciona ao seu sumário de falhas
            $Global:InstallSummary.Failed += @{
                Package = $app.name
                ExitCode = -1
                Error = "Download failed: $($_.Exception.Message)"
            }
        }
    }
}

function Install-Msys2Packages {
    param(
        [string[]]$Packages
    )
    
    Write-Host ""
    Write-Host ">>> Configuring MSYS2 Environment..." -ForegroundColor Yellow
    
    # Localizar o executável bash do MSYS2 (O Chocolatey instala geralmente em C:\tools\msys64)
    $msysBash = "C:\tools\msys64\usr\bin\bash.exe"
    if (-not (Test-Path $msysBash)) {
        # Tenta o caminho padrão alternativo
        $msysBash = "C:\msys64\usr\bin\bash.exe"
    }

    if (Test-Path $msysBash) {
        Write-Host "  -> MSYS2 detected at $msysBash" -ForegroundColor Cyan
        
        # Junta a lista de pacotes numa string separada por espaços
        $packageString = $Packages -join " "
        
        Write-Host "  -> Installing internal packages via pacman..." -ForegroundColor Cyan
        Write-Host "     List: $packageString" -ForegroundColor Gray
        
        # Comando para atualizar as chaves e instalar os pacotes
        # --noconfirm: Não pergunta Sim/Não
        # --needed: Só instala se não estiver atualizado
        $cmdArgs = "-l -c 'pacman -Sy --noconfirm --needed $packageString'"
        
        try {
            $process = Start-Process -FilePath $msysBash -ArgumentList $cmdArgs -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-Host "  ✓ MSYS2 packages installed successfully." -ForegroundColor Green
                $Global:InstallSummary.Succeeded += "MSYS2-Internal-Packages"
            } else {
                throw "Pacman exited with code $($process.ExitCode)"
            }
        } catch {
            Write-Host "  ✗ Failed to install MSYS2 packages: $($_.Exception.Message)" -ForegroundColor Red
            $Global:InstallSummary.Failed += "MSYS2-Internal-Packages"
        }
    } else {
        Write-Host "  ⊘ MSYS2 installation not found. Skipping internal packages." -ForegroundColor Yellow
        $Global:InstallSummary.Skipped += "MSYS2-Internal-Packages (Binary not found)"
    }
}

# Legacy wrapper for compatibility
function Install-ChocoPackage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageName,
        [string]$ExtraArgs = ""
    )
    Install-PackageWithChoco -PackageName $PackageName -ExtraArgs $ExtraArgs
}

# --- LOAD PACKAGE DEFINITIONS FROM JSON ---
$PackageJsonPath = Join-Path $PSScriptRoot "packages_windows.json"
if (-not (Test-Path $PackageJsonPath)) {
    Write-Host "ERROR: packages_windows.json not found at: $PackageJsonPath" -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit
}

try {
    $PackageDefinitions = Get-Content $PackageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "Package definitions loaded from JSON successfully." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to parse packages_windows.json" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit
}

# --- HYBRID INSTALLATION (winget -> choco) ---

# Handled exit codes
$Script:WingetAlreadyInstalledCodes = @(
    -1978335189,  # 0x8A15002B: no applicable update
    -1978335135   # 0x8A150061: package already installed
)
$Script:InstallInProgressCodes = @(
    1618,         # MSI: another installation in progress (e.g. parallel Windows Update)
    -1978334974   # 0x8A150102: winget - install in progress
)
$Script:ChocoSuccessCodes = @(0, 1605, 1614, 1641, 3010)

function Get-JsonProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object -or $Object -is [string]) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function ConvertTo-PackageSpec {
    # Accepts "Winget.Id" (string) or { "name": "...", "winget": "...", "choco": "..." }
    param($Entry, [switch]$ChocoOnly)
    if ($Entry -is [string]) {
        if ($ChocoOnly) { return [pscustomobject]@{ Name = $Entry; Winget = ""; Choco = $Entry } }
        return [pscustomobject]@{ Name = $Entry; Winget = $Entry; Choco = "" }
    }
    $winget = [string](Get-JsonProperty $Entry "winget")
    $choco  = [string](Get-JsonProperty $Entry "choco")
    $name   = [string](Get-JsonProperty $Entry "name")
    if (-not $name) { $name = if ($winget) { $winget } else { $choco } }
    return [pscustomobject]@{ Name = $name; Winget = $winget; Choco = $choco }
}

function Get-WingetInstalledIds {
    # 'winget list' truncates long IDs with "…"; 'winget export' returns full IDs.
    $ErrorActionPreference = 'Continue'
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $tmp = Join-Path $env:TEMP "winget-export-$PID.json"
    try {
        winget export -o $tmp --accept-source-agreements 2>&1 | Out-Null
        if (Test-Path $tmp) {
            $data = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($src in $data.Sources) {
                foreach ($pkg in $src.Packages) { [void]$ids.Add($pkg.PackageIdentifier) }
            }
        }
    } catch {
        Write-Host "  WARNING: Failed to list winget packages: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    return ,$ids
}

function Get-ChocoInstalledNames {
    # Choco v2: 'list' is local-only. Choco v1 needs '-lo' (otherwise it lists the whole remote feed).
    $ErrorActionPreference = 'Continue'
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try {
        $major = 0
        [void][int]::TryParse(((choco --version 2>$null | Select-Object -First 1) -split '\.')[0], [ref]$major)
        $lines = if ($major -ge 2) { choco list -r 2>$null } else { choco list -lo -r 2>$null }
        foreach ($line in $lines) {
            $pkgName = ($line -split '\|')[0].Trim()
            if ($pkgName) { [void]$names.Add($pkgName) }
        }
    } catch {
        Write-Host "  WARNING: Failed to list Chocolatey packages: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    return ,$names
}

function Invoke-WithInstallRetry {
    # Retries when another installer (e.g. Windows Update) is holding the MSI lock.
    param([scriptblock]$Action, [string]$PackageName, [int]$MaxAttempts = 4, [int]$DelaySeconds = 45)
    $code = 0
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $code = & $Action
        if ($Script:InstallInProgressCodes -notcontains $code) { return $code }
        if ($attempt -lt $MaxAttempts) {
            Write-Host "    Another installation in progress (code $code). Retrying in $DelaySeconds s... ($attempt/$MaxAttempts)" -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    return $code
}

function Install-Package {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageName,
        [string]$WingetId = "",
        [string]$ChocoName = "",
        [scriptblock]$SpecialHandler = $null,
        $InstalledWinget = $null,
        $InstalledChoco = $null
    )

    # Native commands write to stderr; with $ErrorActionPreference='Stop' that would throw.
    $ErrorActionPreference = 'Continue'

    Write-Host "  -> Installing: $PackageName" -ForegroundColor Cyan

    if ($WingetId -and $InstalledWinget -and $InstalledWinget.Contains($WingetId)) {
        Write-Host "  ✓ $PackageName (already installed via winget)" -ForegroundColor Green
        $Global:InstallSummary.Skipped += $PackageName
        return $true
    }
    if ($ChocoName -and $InstalledChoco -and $InstalledChoco.Contains($ChocoName)) {
        Write-Host "  ✓ $PackageName (already installed via choco)" -ForegroundColor Green
        $Global:InstallSummary.Skipped += $PackageName
        return $true
    }

    if ($WingetId) {
        Write-Host "    Trying winget..." -ForegroundColor Gray
        $wingetCode = Invoke-WithInstallRetry -PackageName $PackageName -Action {
            winget install --id $WingetId -e --accept-package-agreements --accept-source-agreements -h | Out-Host
            $LASTEXITCODE
        }

        if ($wingetCode -eq 0) {
            Write-Host "  ✓ $PackageName (installed via winget)" -ForegroundColor Green
            $Global:InstallSummary.Succeeded += $PackageName
            return $true
        } elseif ($Script:WingetAlreadyInstalledCodes -contains $wingetCode) {
            Write-Host "  ✓ $PackageName (already installed/up to date via winget)" -ForegroundColor Green
            $Global:InstallSummary.Skipped += $PackageName
            return $true
        }

        if (-not $ChocoName) {
            Write-Host "  ✗ $PackageName (winget failed, code $wingetCode; no choco fallback)" -ForegroundColor Yellow
            $Global:InstallSummary.Failed += @{
                Package  = $PackageName
                ExitCode = $wingetCode
                Error    = "winget install failed and no 'choco' name is defined in the JSON"
            }
            return $false
        }
        Write-Host "    Winget failed (code $wingetCode), trying Chocolatey ($ChocoName)..." -ForegroundColor Yellow
    }

    $output = ""
    $Script:LastChocoOutput = ""
    $exitCode = Invoke-WithInstallRetry -PackageName $PackageName -Action {
        $Script:LastChocoOutput = choco upgrade $ChocoName -y --no-progress 2>&1 | Out-String
        $LASTEXITCODE
    }
    $output = $Script:LastChocoOutput

    if ($null -ne $SpecialHandler) {
        & $SpecialHandler -ExitCode $exitCode -Output $output -PackageName $PackageName
    }

    if ($Script:ChocoSuccessCodes -contains $exitCode) {
        if ($exitCode -in 1641, 3010) { $Global:RebootIsNeeded = $true }
        Write-Host "  ✓ $PackageName (installed via choco)" -ForegroundColor Green
        $Global:InstallSummary.Succeeded += $PackageName
        return $true
    }

    Write-Host "  ✗ $PackageName (exit code: $exitCode)" -ForegroundColor Yellow
    $Global:InstallSummary.Failed += @{
        Package  = $PackageName
        ExitCode = $exitCode
        Error    = if ($output -match "error|failed") { ($output -split "`n" | Where-Object { $_ -match "error|failed" } | Select-Object -First 3) -join "; " } else { "Unknown error" }
    }
    return $false
}

function Show-ManualPackages {
    param($Entries)
    if (-not $Entries) { return }
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  MANUAL INSTALLATION (no winget/choco package)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    foreach ($entry in $Entries) {
        $name = Get-JsonProperty $entry "name"
        $url  = Get-JsonProperty $entry "url"
        $note = Get-JsonProperty $entry "note"
        Write-Host "  - $name" -ForegroundColor Yellow -NoNewline
        if ($url)  { Write-Host "  ->  $url" -NoNewline }
        Write-Host ""
        if ($note) { Write-Host "      $note" -ForegroundColor Gray }
    }
}

# --- 0.1. Check for Pending Reboot (Initial Check) ---
if (Test-RebootRequired) {
    Write-Host "WARNING: A pending system reboot was detected." -ForegroundColor Red
    Write-Host "It is highly recommended to reboot the PC before continuing." -ForegroundColor Yellow
    Read-Host "Press ENTER to continue anyway, or close the window to reboot..."
}

# --- 1. Administrator Check (gsudo fallback) ---
Write-Host "Checking for Administrator privileges..." -ForegroundColor Yellow
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (Get-Command gsudo -ErrorAction SilentlyContinue) {
        Write-Host "Requesting Administrator privileges via gsudo..." -ForegroundColor Yellow
        gsudo "$PSCommandPath" -WslDistro $WslDistro
        exit
    } else {
        Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
        Write-Host "Please right-click the script and 'Run as Administrator'." -ForegroundColor Red
        Read-Host "Press ENTER to exit..."
        exit
    }
}
Write-Host "Administrator privileges confirmed." -ForegroundColor Green

# --- 2. WSL 2 Check & Installation ---
Write-Host ""
Write-Host "Checking WSL 2 installation..." -ForegroundColor Yellow
# NOTE: native commands never throw, so try/catch around 'wsl' can't detect a missing distro.
# 'wsl -l -q' prints UTF-16, so the console encoding is switched while reading it.
$wslDistros = @()
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $wslDistros = & {
            $ErrorActionPreference = 'Continue'
            wsl.exe -l -q 2>$null
        } | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ }
    } catch {
        $wslDistros = @()
    } finally {
        [Console]::OutputEncoding = $prevEncoding
    }
}

if (@($wslDistros) -contains $WslDistro) {
    Write-Host "WSL 2 is already installed. Distribution: $WslDistro" -ForegroundColor Green
} else {
    Write-Host "WSL 2 or distribution '$WslDistro' not found. Starting installation..." -ForegroundColor Yellow
    Write-Host "This may take a few minutes..."
    
    wsl --install -d $WslDistro
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "  REBOOT REQUIRED" -ForegroundColor Red
    Write-Host "============================================================"
    Write-Host "WSL 2 has been installed."
    Write-Host "PLEASE RESTART YOUR COMPUTER NOW."
    Write-Host "After rebooting, run this 'setup_windows.ps1' script again."
    Write-Host "============================================================"
    Read-Host "Press ENTER to close and restart your PC..."
    exit
}

# --- 3. Chocolatey Check & Installation ---
Write-Host ""
Write-Host "Checking if Chocolatey is installed..."
$chocoPath = Get-Command choco -ErrorAction SilentlyContinue
if ($null -eq $chocoPath) {
    Write-Host "Chocolatey not found. Installing now..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Host "Chocolatey installed successfully!" -ForegroundColor Green
        $env:Path = "$($env:Path);$($env:ALLUSERSPROFILE)\chocolatey\bin"
    } catch {
        Write-Host "ERROR: Failed to install Chocolatey." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Read-Host "Press ENTER to exit..."
        exit
    }
} else {
    Write-Host "Chocolatey is already installed." -ForegroundColor Green
}

# --- 4. Enabling Chocolatey Auto-Confirmation ---
Write-Host ""
Write-Host "Enabling Chocolatey's automatic script confirmation..." -ForegroundColor Yellow
try {
    choco feature enable -n=allowGlobalConfirmation | Out-Null
    Write-Host "Feature 'allowGlobalConfirmation' enabled." -ForegroundColor Green
    
    # Verify the setting was applied
    $confirmSetting = choco config list | Select-String "allowGlobalConfirmation"
    if ($confirmSetting -match "Enabled") {
        Write-Host "Verification: allowGlobalConfirmation is confirmed enabled." -ForegroundColor Green
    }
} catch {
    Write-Host "WARNING: Failed to enable 'allowGlobalConfirmation'." -ForegroundColor Yellow
}


# --- OTIMIZAÇÃO NÍVEL 3 (HÍBRIDO): INICIAR WINDOWS UPDATE EM BACKGROUND ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  STARTING PARALLEL JOB (Windows Update)..." -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""

Write-Host "[+] Installing 'PSWindowsUpdate' module (required for job)..." -ForegroundColor Cyan
Install-PSModuleSafely -Name "PSWindowsUpdate"

Write-Host "[+] Starting Job: Windows Update (running in background)..." -ForegroundColor Cyan
$JobWinUpdate = Start-Job -Name "WinUpdate" -ScriptBlock {
    # É preciso importar o módulo DENTRO do job
    Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
    
    if (-not (Get-Command Install-WindowsUpdate -ErrorAction SilentlyContinue)) {
        Write-Host "JOB (WU) ERROR: Módulo PSWindowsUpdate não pôde ser importado no job." -ForegroundColor Red
        return $false
    }
    
    Write-Host "JOB (WU): Procurando e instalando updates..."
    try {
        Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue | Out-Null
        Write-Host "JOB (WU): Verificação de updates completa."
        # Verifica se um reboot é necessário e armazena o resultado
        if (Get-Command Test-PendingReboot -ErrorAction SilentlyContinue) {
            if (Test-PendingReboot -ErrorAction SilentlyContinue) { return $true }
        }
    } catch {
        Write-Host "JOB (WU) ERROR: Falha ao rodar Windows Update." -ForegroundColor Red
    }
    return $false # Retorna $false se nenhum reboot for necessário
}
# --- FIM DA OTIMIZAÇÃO NÍVEL 3 ---


# --- 5. BEGINNING WINDOWS TOOL UPGRADES (THREAD PRINCIPAL) ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  STARTING INSTALLATION/UPGRADE OF WINDOWS TOOLS (Main Thread)"
Write-Host "  (Windows Update está a correr em paralelo...)"
Write-Host "============================================================"
Write-Host ""

# --- PACKAGE CACHE (exact IDs, built once) ---
Write-Host "Building package cache (this may take a moment)..." -ForegroundColor Yellow
$installedWinget = Get-WingetInstalledIds
$installedChoco = Get-ChocoInstalledNames
Write-Host "Package cache built ($($installedWinget.Count) winget / $($installedChoco.Count) choco)." -ForegroundColor Green


# 5.1: INSTALL WINGET PACKAGES (Priority: try winget first, fallback to choco)
Write-Host ">>> Starting Winget package installations (with Chocolatey fallback)..." -ForegroundColor Yellow
Write-Host ""
Write-Host "[+] Installing Winget packages (priority method)" -ForegroundColor Cyan

foreach ($entry in @(Get-JsonProperty $PackageDefinitions "winget")) {
    if ($null -eq $entry) { continue }
    $spec = ConvertTo-PackageSpec $entry
    Install-Package -PackageName $spec.Name -WingetId $spec.Winget -ChocoName $spec.Choco -InstalledWinget $installedWinget -InstalledChoco $installedChoco | Out-Null
}

# 5.2: INSTALL CHOCOLATEY-ONLY PACKAGES
Write-Host ""
Write-Host ">>> Starting Chocolatey-only package installations..." -ForegroundColor Yellow
Write-Host ""
Write-Host "[+] Installing Chocolatey packages" -ForegroundColor Cyan

# MariaDB special handler for exit code 1603
$mariadbHandler = {
    param($ExitCode, $Output, $PackageName)
    
    if ($ExitCode -eq 1603) {
        Write-Host ""
        Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "  MariaDB Installation Failed (MSI Error 1603)" -ForegroundColor Red
        Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "  Troubleshooting Steps:" -ForegroundColor Yellow
        Write-Host "  1. Uninstall any existing MySQL/MariaDB installations via Control Panel" -ForegroundColor Yellow
        Write-Host "  2. Delete C:\Program Files\MariaDB* and C:\ProgramData\MySQL folders" -ForegroundColor Yellow
        Write-Host "  3. Restart your computer" -ForegroundColor Yellow
        Write-Host "  4. Re-run this script to install MariaDB" -ForegroundColor Yellow
        Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host ""
        
        $Global:InstallSummary.Skipped += "mariadb (conflict detected - manual intervention required)"
    }
}

foreach ($chocoEntry in @(Get-JsonProperty $PackageDefinitions "choco")) {
    if ($null -eq $chocoEntry) { continue }
    $packageName = (ConvertTo-PackageSpec $chocoEntry -ChocoOnly).Choco
    # Special handling for mariadb
    if ($packageName -eq "mariadb") {
        # Check for existing MySQL/MariaDB installations
        # Win32_Product is slow and triggers an MSI consistency check/repair on every product,
        # so read the Uninstall registry keys instead.
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $existingMySQL = @(Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties['DisplayName'] -and ($_.DisplayName -like "*MySQL*" -or $_.DisplayName -like "*MariaDB*") })
        
        if ($existingMySQL.Count -gt 0) {
            Write-Host "  ⚠ Existing MySQL/MariaDB installation detected:" -ForegroundColor Yellow
            foreach ($product in $existingMySQL) {
                Write-Host "    - $($product.DisplayName)" -ForegroundColor Yellow
            }

            Write-Host "  ⊘ SKIPPING MariaDB installation to avoid conflicts and delays." -ForegroundColor Yellow
            $Global:InstallSummary.Skipped += "mariadb (conflict with existing MySQL detected)"

        }
        else {
        
            Install-Package -PackageName $packageName -ChocoName $packageName -SpecialHandler $mariadbHandler -InstalledWinget $installedWinget -InstalledChoco $installedChoco | Out-Null
        }
    }
    # Special handling for Visual Studio 2022 with extra parameters
    elseif ($packageName -eq "visualstudio2022community") {
        Write-Host ""
        Write-Host "================== LONG TASK WARNING (VS 2022) ==================" -ForegroundColor Yellow
        Write-Host "Starting 'Visual Studio 2022 Community' upgrade/install."
        Write-Host "This is the largest download and can take 30-60 minutes."
        Write-Host "================================================================="
        Write-Host ""
        
        Install-PackageWithChoco -PackageName $packageName -ExtraArgs "--package-parameters `"--add Microsoft.VisualStudio.Workload.NativeDesktop --quiet`""
    }
    else {
        Install-Package -PackageName $packageName -ChocoName $packageName -InstalledWinget $installedWinget -InstalledChoco $installedChoco | Out-Null
    }
}

# --- 5.3: DOWNLOAD PORTABLE APPS (NOVA SEÇÃO) ---
Write-Host ""
Write-Host ">>> Starting Portable App downloads..." -ForegroundColor Yellow
$portableApps = Get-JsonProperty $PackageDefinitions "portable_apps"
if ($portableApps) {
    Install-PortableApps -Apps $portableApps
}

# --- 5.4: MSYS2 INTERNAL PACKAGES (pacman) ---
# Install-Msys2Packages existed but was never called, so the "msys2" list in the JSON was ignored.
$msys2Packages = @(Get-JsonProperty $PackageDefinitions "msys2")
if ($msys2Packages.Count -gt 0 -and $null -ne $msys2Packages[0]) {
    Install-Msys2Packages -Packages $msys2Packages
}


Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  WINDOWS TOOLS UPGRADE COMPLETE!" -ForegroundColor Green
Write-Host "================================================="
Write-Host ""

# --- 6. INSTALLING VS CODE EXTENSIONS ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  INSTALLING VS CODE EXTENSIONS..." -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""

if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Host "[+] Installing/Updating extensions in one batch..." -ForegroundColor Cyan
    
    $extensions = @(
        "pkief.material-icon-theme",
        "eamodio.gitlens",
        "formulahendry.code-runner",
        "visualstudioexptteam.vscodeintellicode",
        "github.copilot",
        "esbenp.prettier-vscode",
        "dbaeumer.vscode-eslint",
        "ritwickdey.liveserver",
        "ms-vscode.cpptools",
        "ms-vscode.cmake-tools",
        "ms-python.python",
        "ms-python.vscode-pylance",
        "vscjava.vscode-java-pack",
        "ms-vscode-remote.remote-wsl",
        "ms-azuretools.vscode-docker",
        "firefox-devtools.vscode-firefox-debug",
        "dart-code.dart-code",
        "dart-code.flutter",
        "SonarSource.SonarLint-VSCode"
    )

    # --- OTIMIZAÇÃO NÍVEL 1: INSTALAÇÃO EM LOTE ---
    # Junta todas as extensões em um único comando
    # Each flag and value must be a separate argument ("--install-extension", "<id>"),
    # otherwise 'code' receives "--install-extension <id> --force" as one unknown option.
    $argumentList = @()
    foreach ($ext in $extensions) { $argumentList += @("--install-extension", $ext) }
    $argumentList += "--force"
    & {
        $ErrorActionPreference = 'Continue'
        code @argumentList 2>&1 | Out-Null
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ All extensions installed/updated successfully." -ForegroundColor Green
    } else {
        Write-Host "  ✗ One or more extensions failed to install." -ForegroundColor Yellow
    }
    # --- FIM DA OTIMIZAÇÃO NÍVEL 1 ---

} else {
    Write-Host "WARNING: 'code.exe' not found in PATH." -ForegroundColor Yellow
}

# --- 6.1: CONFIGURING POWERSHELL 7 PROFILE ---
Write-Host ""
Write-Host "[+] Configuring PowerShell 7 Profile..." -ForegroundColor Yellow

# Setup NuGet with better error handling
try {
    Write-Host "  -> Setting up NuGet provider..." -ForegroundColor Cyan
    
    # Try to get PackageProvider first
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    
    if (-not $nuget) {
        # Force TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Install with minimal version
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Host "  ✓ NuGet provider installed" -ForegroundColor Green
    } else {
        Write-Host "  ✓ NuGet provider already available" -ForegroundColor Green
    }
    
    # Set PSGallery as trusted
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "  ✗ NuGet setup failed (not critical): $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- OTIMIZAÇÃO NÍVEL 1: INSTALAÇÃO EM LOTE ---
# Install PowerShell modules
Write-Host "  -> Installing PowerShell modules in one batch..." -ForegroundColor Cyan
try {
    # Instala todos de uma vez, pulando verificações individuais
    Install-Module -Name "PSReadLine", "Terminal-Icons", "Pester" -Force -Scope AllUsers -AllowClobber -SkipPublisherCheck -ErrorAction Stop
    Write-Host "  ✓ PSReadLine, Terminal-Icons, Pester installed/updated." -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Failed to install PowerShell modules - $($_.Exception.Message)" -ForegroundColor Yellow
}
# --- FIM DA OTIMIZAÇÃO NÍVEL 1 ---


# Configure PowerShell Profile
try {
    $ProfileDir = Join-Path $env:USERPROFILE "Documents\PowerShell"
    $ProfilePath = Join-Path $ProfileDir "profile.ps1"
    
    if (-not (Test-Path $ProfileDir)) {
        New-Item -Path $ProfileDir -ItemType Directory -Force | Out-Null
    }

    $ProfileContent = @"

# --- Productivity Pack ---
# Oh My Posh theme
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config `$env:POSH_THEMES_PATH\powerlevel10k_rainbow.omp.json | Invoke-Expression
}

# Terminal Icons
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
}

# PSReadLine improvements
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
}

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
"@
    
    $Marker = "# --- Productivity Pack ---"
    
    if (Test-Path $ProfilePath) {
        $FileContent = Get-Content $ProfilePath -Raw
        if ($FileContent -notlike "*$Marker*") {
            $ProfileContent | Out-File -FilePath $ProfilePath -Encoding UTF8 -Append
            Write-Host "  ✓ PowerShell profile configured" -ForegroundColor Green
        } else {
            Write-Host "  ✓ PowerShell profile already configured" -ForegroundColor Green
        }
    } else {
        $ProfileContent | Out-File -FilePath $ProfilePath -Encoding UTF8
        Write-Host "  ✓ PowerShell profile created" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✗ PowerShell profile configuration failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- 7. EXECUTING WSL SCRIPT (SEQUENCIALMENTE) ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  STARTING AUTOMATED WSL ($WslDistro) SETUP... (Sequential)" -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""

$wslScriptPath = Join-Path $PSScriptRoot "wsl_ubuntu.sh"

if (-not (Test-Path $wslScriptPath)) {
    Write-Host "ERROR: 'wsl_ubuntu.sh' script not found in the same directory." -ForegroundColor Red
    Write-Host "WSL setup will have to be run manually." -ForegroundColor Red
} else {
    Write-Host "Found 'wsl_ubuntu.sh' script."
    Write-Host "Converting Windows path to WSL format..." -ForegroundColor Yellow
    
    $fullWinPath = (Resolve-Path $wslScriptPath).Path
    $driveLetter = $fullWinPath.Substring(0, 1).ToLower()
    $linuxPath = $fullWinPath.Substring(2) -replace '\\', '/'
    $fullLinuxPath = "/mnt/$driveLetter$linuxPath"
    
    Write-Host "WSL script path: $fullLinuxPath"
    
    Write-Host ""
    Write-Host "================== ATTENTION: SUDO PASSWORD ==================" -ForegroundColor Red
    Write-Host "The script will now run the $WslDistro (WSL) setup."
    Write-Host "PLEASE TYPE YOUR UBUNTU PASSWORD AND PRESS ENTER."
    Write-Host "============================================================="
    Write-Host ""
    
    try {
        # Esta etapa é interativa, por isso NÃO pode estar num job
        wsl.exe -d $WslDistro sudo bash "$fullLinuxPath"
        Write-Host ""
        Write-Host "=================================================" -ForegroundColor Green
        Write-Host "  WSL ($WslDistro) SETUP COMPLETE!" -ForegroundColor Green
        Write-Host "================================================="
    } catch {
        Write-Host "ERROR: Failed to execute WSL script." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

# --- 8. SINCRONIZAÇÃO DO WINDOWS UPDATE (OTIMIZAÇÃO NÍVEL 3) ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SYNCHRONIZING BACKGROUND JOBS (Windows Update)..." -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""

Write-Host "Aguardando a conclusão do Windows Update (se ainda estiver a correr)..." -ForegroundColor Yellow
# O 'Wait-Job' pausa o script ATÉ o job terminar
$WinUpdateJobResult = Wait-Job -Name "WinUpdate"
$RebootNeededByUpdate = $WinUpdateJobResult | Receive-Job

# Exibe o log do job
Write-Host "[+] Log do Windows Update Job:" -ForegroundColor Cyan
Write-Host $RebootNeededByUpdate
Write-Host "Sincronização do Windows Update concluída." -ForegroundColor Green

if ($RebootNeededByUpdate -eq $true) {
    $Global:RebootIsNeeded = $true
    Write-Host "  -> O Windows Update marcou que um reboot é necessário." -ForegroundColor Yellow
}

# Limpa o job
Remove-Job -Name "WinUpdate" -ErrorAction SilentlyContinue
# --- FIM DA SINCRONIZAÇÃO (NÍVEL 3) ---


# --- 9. SYSTEM CLEANUP & OPTIMIZATION ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  STARTING SYSTEM CLEANUP & OPTIMIZATION..." -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""

Write-Host "[+] Cleaning up Windows temporary files..." -ForegroundColor Cyan
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[+] Cleaning up Chocolatey cache..." -ForegroundColor Cyan
& { $ErrorActionPreference = 'Continue'; choco cache remove --all 2>&1 | Out-Null }

Write-Host "[+] Optimizing drive C:..." -ForegroundColor Cyan
Optimize-Volume -DriveLetter C -ErrorAction SilentlyContinue | Out-Null

Write-Host "System cleanup complete." -ForegroundColor Green

# --- 9.1: WRITE INSTALLATION SUMMARY ---
Write-InstallSummary

# --- 10. Finalization ---
Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  ENTIRE SETUP COMPLETE (WINDOWS + WSL)!" -ForegroundColor Green
Write-Host "================================================="
Write-Host ""

if (Test-RebootRequired) {
    # Esta verificação garante que, mesmo que o WU não tenha reportado,
    # o sistema sabe se precisa de um reboot.
    $Global:RebootIsNeeded = $true
}

if ($Global:RebootIsNeeded) {
    Write-Host "****************** REBOOT REQUIRED ******************" -ForegroundColor Red
    Write-Host "A reboot is required to finalize Windows Updates"
    Write-Host "and register all system runtimes."
    Write-Host "Please restart your computer now."
    Write-Host "*****************************************************" -ForegroundColor Red
} else {
    Write-Host "All tasks complete." -ForegroundColor Green
    Write-Host "Please CLOSE AND RE-OPEN your terminal for all"
    Write-Host "PATH changes to take effect." -ForegroundColor Yellow
}

Read-Host "Press ENTER to close..."
