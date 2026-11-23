<#
.SYNOPSIS
    Installs Nexer Compass (ncompass) for the current user.

.DESCRIPTION
    Downloads ncompass.exe and its SHA-256 from the public release repository,
    stops unless the checksum matches, places the program in
    %LOCALAPPDATA%\Programs\ncompass with a gentle-ai.exe copy, puts that folder
    first in the user PATH and runs `ncompass install --agent claude-code`.
    Needs no administrator rights, GitHub account or git credentials.
    Running it again replaces the program and keeps one PATH entry.
    Without -Channel it downloads stable and ncompass keeps the saved channel;
    -Channel stable or -Channel early also moves the person to that channel.

.EXAMPLE
    irm https://raw.githubusercontent.com/Nexer-Colombia/ncompass-install/main/install.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Nexer-Colombia/ncompass-install/main/install.ps1))) -Channel early
#>
param(
    # Empty means stable without changing the saved channel (PowerShell does not validate defaults).
    [ValidateSet('stable', 'early')]
    [string]$Channel = '',
    [string]$Repo = 'Nexer-Colombia/ncompass-install',
    # ponytail: test-only overrides (install_windows_test.go); keep the defaults.
    [string]$DownloadBase = 'https://github.com',
    [string]$ApiBase = 'https://api.github.com',
    [string]$EnvKey = 'HKCU:\Environment'
)

# Runs in a child scope so `irm | iex` leaves the caller's session settings alone.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest is very slow with a progress bar in PowerShell 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $dir = Join-Path $env:LOCALAPPDATA 'Programs\ncompass'
    $tmp = Join-Path $env:TEMP ('ncompass-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        # Download. Stable uses the latest-release redirect, which is not rate limited like the API.
        if ($Channel -ne 'early') {
            $exeUrl = "$DownloadBase/$Repo/releases/latest/download/ncompass.exe"
            $shaUrl = "$exeUrl.sha256"
        } else {
            $releases = Invoke-RestMethod -UseBasicParsing -Uri "$ApiBase/repos/$Repo/releases?per_page=20" -Headers @{ 'User-Agent' = 'ncompass-install'; 'Accept' = 'application/vnd.github+json' }
            $early = $null
            foreach ($r in @($releases)) { if ($r.prerelease -and -not $r.draft) { $early = $r; break } }
            if (-not $early) { throw "No early release found in $Repo." }
            $exeUrl = ($early.assets | Where-Object { $_.name -eq 'ncompass.exe' }).browser_download_url
            $shaUrl = ($early.assets | Where-Object { $_.name -eq 'ncompass.exe.sha256' }).browser_download_url
            if (-not $exeUrl -or -not $shaUrl) { throw "Early release $($early.tag_name) is missing ncompass.exe or ncompass.exe.sha256." }
        }
        $exe = Join-Path $tmp 'ncompass.exe'
        $sha = Join-Path $tmp 'ncompass.exe.sha256'
        Write-Host ('Downloading ncompass ({0}) from {1}' -f $(if ($Channel) { $Channel } else { 'stable' }), $Repo)
        Invoke-WebRequest -UseBasicParsing -Uri $exeUrl -OutFile $exe
        Invoke-WebRequest -UseBasicParsing -Uri $shaUrl -OutFile $sha

        # Check. Nothing is installed unless the published checksum matches.
        $line = ([IO.File]::ReadAllText($sha)).Trim()
        if ($line -cnotmatch '^([0-9a-f]{64})  ncompass\.exe$') { throw "ncompass.exe.sha256 is not in the expected format; nothing was installed." }
        $want = $Matches[1]
        $got = (Get-FileHash -Algorithm SHA256 -Path $exe).Hash.ToLowerInvariant()
        if ($got -ne $want) { throw "ncompass.exe checksum mismatch (expected $want, got $got); nothing was installed." }

        # Place. A running copy (a Claude Code hook may be running gentle-ai.exe) cannot be
        # overwritten but can be renamed, so the old file moves aside first.
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Get-ChildItem -Path $dir -Filter '*.old' | Remove-Item -Force -ErrorAction SilentlyContinue
        foreach ($name in 'ncompass.exe', 'gentle-ai.exe') {
            $final = Join-Path $dir $name
            Copy-Item -Path $exe -Destination "$final.new" -Force
            if (Test-Path $final) {
                $old = "$final.$([guid]::NewGuid().ToString('N')).old"
                Move-Item -Path $final -Destination $old
                Remove-Item -Path $old -Force -ErrorAction SilentlyContinue
            }
            Move-Item -Path "$final.new" -Destination $final
        }
    } finally {
        Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
    }

    # PATH. The folder goes first in the user PATH so the gentle-ai.exe copy wins over an
    # upstream Gentle AI install. Other entries keep their %VARS% unexpanded.
    $raw = (Get-Item -Path $EnvKey).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $same = $dir.TrimEnd('\')
    $rest = @($raw -split ';' | Where-Object { $_ -and ([Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ne $same) })
    $userPath = (@($dir) + $rest) -join ';'
    if ($userPath -cne $raw) {
        Set-ItemProperty -Path $EnvKey -Name Path -Value $userPath -Type ExpandString
        if ($EnvKey -eq 'HKCU:\Environment') {
            # Setting a user variable tells running programs (Explorer) that the environment changed.
            [Environment]::SetEnvironmentVariable('NCOMPASS_PATH_REFRESH', '1', 'User')
            [Environment]::SetEnvironmentVariable('NCOMPASS_PATH_REFRESH', $null, 'User')
        }
    }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::ExpandEnvironmentVariables($userPath)

    $alias = Join-Path $dir 'gentle-ai.exe'
    $first = Get-Command -Name gentle-ai -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $first -or $first.Source -ne $alias) {
        Write-Warning "Another gentle-ai comes first in PATH: $($first.Source). Claude Code hooks will run it instead of ncompass. Remove it (see the Compass guide for teams already using Gentle AI)."
    }

    # Run.
    # Continue: in PowerShell ISE a native program's stderr line is an error record and Stop would abort.
    # try/catch: a program that cannot start (AppLocker, antivirus) leaves $LASTEXITCODE
    # unchanged, and under `irm | iex` that is the caller's value, often 0.
    $ErrorActionPreference = 'Continue'
    $installArgs = @('install', '--agent', 'claude-code')
    if ($Channel) { $installArgs += '--channel', $Channel }
    try {
        & (Join-Path $dir 'ncompass.exe') @installArgs
        $code = $LASTEXITCODE
    } catch {
        throw "ncompass could not start, so ncompass install did not run: $_"
    }
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { throw "ncompass install failed with exit code $code." }
    Write-Host ''
    Write-Host "ncompass is installed in $dir. Restart Claude Code, VS Code and open terminals so they see the new PATH."
}
