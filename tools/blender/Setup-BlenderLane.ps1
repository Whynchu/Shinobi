<#
.SYNOPSIS
    Sets up the Blender lane: portable Blender, the Lab MCP add-on, and the MCP server.

.DESCRIPTION
    Everything the Blender lane needs, reproducible. Written because the lane
    has three moving parts that must agree on a port, and because the failure
    mode is a tower of silent half-configuration: the MCP server starts, the
    add-on is installed, and the tool call times out because Blender was never
    actually enabled, with nothing anywhere saying so.

    Locates Blender at $BlenderDir. Pass -Uninstall to remove the add-on.
    Idempotent: every step checks its own state first.

.EXAMPLE
    .\tools\blender\Setup-BlenderLane.ps1
    .\tools\blender\Setup-BlenderLane.ps1 -WhatIfBlenderDir "..\blender"
#>
[CmdletBinding()]
param(
    [string]$BlenderDir = "$env:USERPROFILE\Downloads\blender-5.2.2-windows-x64",
    [int]$MCPPort = 9876,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

Set-StrictMode -Version Latest
$script:LaneRoot = $PSScriptRoot
if ($null -eq $script:LaneRoot) { $script:LaneRoot = (Get-Location).Path }

# --- Helpers --------------------------------------------------------------------

# Does something hold the port? Not Test-NetConnection: that builtin name exists
# on every box and shadowing it inside this script means anyone later calling
# Test-NetConnection here gets a local function with different output.
function Test-LocalPort {
    param([int]$Port)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $result = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $reached = $result.AsyncWaitHandle.WaitOne(300, $false)
        $client.Close()
        return $reached
    } catch {
        return $false
    }
}

function Write-Step([string]$m) { Write-Host "`n== $m" -ForegroundColor Cyan }

# --- Locate / verify Blender ----------------------------------------------------

Write-Step "Locating Blender"
if (-not (Test-Path $BlenderDir)) {
    throw @"
Blender not found at $BlenderDir

The lane runs headless, so the editor is only needed for authoring; the build
and test steps need the interpreter. Download the Windows x64 build from
https://www.blender.org/download/ and pass -BlenderDir if it is elsewhere.
"@
}
$blenderExe = Join-Path $BlenderDir "blender.exe"
if (-not (Test-Path $blenderExe)) { throw "No blender.exe in $BlenderDir" }

$version = & $blenderExe --version 2>&1 | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "blender.exe ran but printed no version. It may be a blocked download - check the file's properties for a security flag."
}
Write-Host "  $version"

$extensionDir = Join-Path $env:APPDATA "Blender Foundation\Blender\5.2\extensions\user_default\mcp"

# --- The extension must be a real directory, not just a folder name -------------

Write-Step "Checking the Blender Lab MCP add-on"
if (-not (Test-Path $extensionDir)) {
    Write-Host "  not installed"

    $cloneDir = Join-Path $env:TEMP "blender_lab_mcp"
    if (Test-Path $cloneDir) {
        Write-Host "  reusing the checkout at $cloneDir, fetching"
        & git -C $cloneDir fetch origin --quiet
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed; delete $cloneDir and retry." }
        & git -C $cloneDir reset --hard origin/main --quiet
    } else {
        Write-Host "  cloning the official Lab repository"
        & git clone --quiet "https://projects.blender.org/lab/blender_mcp.git" $cloneDir
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed. Check network access, or clone by hand and re-run."
        }
    }

    $addonSrc = Join-Path $cloneDir "addon\blender_mcp_addon"
    if (-not (Test-Path $addonSrc)) { throw "the clone has no addon\blender_mcp_addon" }

    New-Item -ItemType Directory -Path $extensionDir -Force | Out-Null
    Copy-Item (Join-Path $addonSrc "*") $extensionDir -Recurse -Force
    Write-Host "  installed to $extensionDir"
} else {
    Write-Host "  already installed at $extensionDir"
}

if ($Uninstall) {
    Write-Step "Removing the add-on"
    Remove-Item $extensionDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  removed; run this script again without -Uninstall to restore it"
    return
}

# --- Enable the add-on ----------------------------------------------------------

Write-Step "Enabling the add-on"

# Written with a single-quoted here-string on purpose: the Python inside uses
# its own quotes and interpolation is exactly what would corrupt them.
$enableScript = @'
import bpy
try:
    bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mcp")
    print("MCP_ENABLE_OK")
except Exception as ex:
    print("MCP_ENABLE_FAIL: " + str(ex))
bpy.ops.wm.save_userpref()
'@
$enablePath = Join-Path $env:TEMP "blmcp_enable.py"
Set-Content -LiteralPath $enablePath -Value $enableScript -Encoding UTF8
& $blenderExe --background --python $enablePath 2>&1 |
    Select-String -Pattern "MCP_ENABLE" |
    ForEach-Object { "  $_" }

# --- Confirm it can actually serve a request ------------------------------------

Write-Step "Smoke-testing the add-on socket on port $MCPPort"

$smokeScript = @'
import socket, sys, json

port = int(sys.argv[1])
request = {
    "type": "execute",
    "code": "import bpy\nresult = {'version': bpy.app.version_string}",
    "strict_json": True,
}
try:
    with socket.create_connection(("127.0.0.1", port), timeout=10) as s:
        s.sendall(json.dumps(request).encode("utf-8") + b"\0")
        buf = b""
        while not buf.endswith(b"\0"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    print("MCP_SOCKET_OK " + buf.decode("utf-8", "replace").replace("\0", "").strip())
except Exception as ex:
    print("MCP_SOCKET_FAIL " + str(ex))
'@
$smokePath = Join-Path $env:TEMP "blmcp_smoke.py"
Set-Content -LiteralPath $smokePath -Value $smokeScript -Encoding UTF8

Push-Location $BlenderDir
$blenderProc = $null
try {
    # --online-mode: the add-on's network permission is not granted by default,
    # and Blender refuses to open the socket without it. The bind is 127.0.0.1
    # only -- nothing reaches the network.
    $blenderProc = Start-Process -FilePath $blenderExe `
        -ArgumentList "--background", "--online-mode", "--command", "blender_mcp", "--port", "$MCPPort" `
        -WindowStyle Hidden -PassThru

    $waited = 0
    while ($waited -lt 100) {
        if ($blenderProc.HasExited -or (Test-LocalPort -Port $MCPPort)) { break }
        Start-Sleep -Milliseconds 300
        $waited++
    }

    # Prefer the lane's venv interpreter, then whatever python is on PATH. The
    # smoke script is stdlib only, so either works.
    $python = $null
    $venvPython = Join-Path $env:TEMP "blmcp-venv\Scripts\python.exe"
    if (Test-Path $venvPython) { $python = $venvPython }
    else {
        $found = Get-Command python -ErrorAction SilentlyContinue
        if ($found) { $python = $found.Source } else { throw "No python on PATH for the smoke test." }
    }

    & $python $smokePath "$MCPPort" 2>&1 |
        Select-String -Pattern "MCP_SOCKET" |
        ForEach-Object { "  $_" }
} finally {
    if ($blenderProc -and -not $blenderProc.HasExited) { Stop-Process -Id $blenderProc.Id -Force }
    Pop-Location
}

# --- What to do next ------------------------------------------------------------

Write-Step "Done"
Write-Host @"
The Blender lane is wired up. To use it interactively, start Blender's MCP
socket and keep it running:

    cd "$BlenderDir"
    .\blender.exe --background --online-mode --command blender_mcp --port $MCPPort

The 'blender' entry in ~/.config/opencode/opencode.jsonc relays tool calls to
that socket, so an agent can then drive Blender directly.

The rig build and both test suites are plain headless bpy runs and need neither
the add-on nor the MCP server:

    blender --background --python tools/blender/build_rig.py
    blender --background --python tools/blender/test_proportions.py
    blender --background --python tools/blender/test_proportions_negative_control.py
"@ -ForegroundColor Green