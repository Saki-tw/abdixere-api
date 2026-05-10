<#
.SYNOPSIS
    SakiMCPDeus 一鍵部署腳本 — Windows x64
.DESCRIPTION
    1. 編譯 SakiMCPDeus (release)
    2. 複製 binary 至 Deploy 目錄
    3. 設定 Antigravity (Windsurf) MCP 配置
    4. 設定 Gemini CLI MCP 配置
    5. 設定 Claude Code MCP 配置
    6. 驗證 fd + rg 可用
.NOTES
    Saki Studio · S700 MoreFine · 202605080630
    作者：Antigravity (Google DeepMind)
#>

param(
    [switch]$SkipBuild,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ===== 路徑定義 =====
$StudioRoot   = "E:\Saki_Studio"
$ProjectRoot  = "$StudioRoot\SakiMCPforDeusExAgentX64"
$DeployDir    = "$StudioRoot\Deploy\SakiMCPDeus"
$BinaryName   = "sakimcp-deus.exe"
$BinaryPath   = "$ProjectRoot\target\release\$BinaryName"
$DeployBinary = "$DeployDir\$BinaryName"

# ===== Agent 配置路徑 =====
$AntigravityConfig = "$env:APPDATA\Windsurf\User\globalStorage\codeium.windsurf\settings\mcp_settings.json"
$GeminiCliConfig   = "$env:USERPROFILE\.gemini\settings.json"
$ClaudeCodeConfig  = "$env:USERPROFILE\.claude\claude_desktop_config.json"

Write-Host "=== SakiMCPDeus -- One-Click Deploy for Win64 ===" -ForegroundColor Cyan
Write-Host "=== Saki Studio - S700 MoreFine                ===" -ForegroundColor Cyan
Write-Host ""

# ===== Step 1: 檢查依賴 =====
Write-Host "[1/6] Checking dependencies..." -ForegroundColor Yellow

$missing = @()
if (-not (Get-Command fd -ErrorAction SilentlyContinue))  { $missing += "fd" }
if (-not (Get-Command rg -ErrorAction SilentlyContinue))  { $missing += "rg" }

if ($missing.Count -gt 0) {
    Write-Host "  [!] Missing tools: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "  [!] Installing via scoop..." -ForegroundColor Yellow
    foreach ($tool in $missing) {
        if (-not $DryRun) {
            scoop install $tool
        } else {
            Write-Host "  [DRY] Would install: scoop install $tool"
        }
    }
}
Write-Host "  [OK] fd + rg available" -ForegroundColor Green

# ===== Step 2: Build =====
if (-not $SkipBuild) {
    Write-Host "[2/6] Building SakiMCPDeus (release)..." -ForegroundColor Yellow
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    if (-not $DryRun) {
        Push-Location $ProjectRoot
        cargo build --release 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "Build failed with exit code $LASTEXITCODE"
        }
        Pop-Location
    } else {
        Write-Host "  [DRY] Would run: cargo build --release"
    }
    Write-Host "  [OK] Build complete" -ForegroundColor Green
} else {
    Write-Host "[2/6] Build skipped (--SkipBuild)" -ForegroundColor DarkGray
}

# ===== Step 3: Deploy binary =====
Write-Host "[3/6] Deploying binary..." -ForegroundColor Yellow

if (-not $DryRun) {
    New-Item -ItemType Directory -Path $DeployDir -Force | Out-Null
    Copy-Item $BinaryPath $DeployBinary -Force
    $size = (Get-Item $DeployBinary).Length / 1MB
    $sizeStr = "{0:N1}" -f $size
    Write-Host "  [OK] $DeployBinary ($sizeStr MB)" -ForegroundColor Green
} else {
    Write-Host "  [DRY] Would copy $BinaryPath -> $DeployBinary"
}

# ===== Step 4-6: Configure Agent Tools =====

$mcpEntry = @{
    command = $DeployBinary.Replace('\', '\\')
    args    = @()
}

# Helper: 插入或更新 MCP 配置
function Set-McpConfig {
    param(
        [string]$ConfigPath,
        [string]$ToolName,
        [hashtable]$Entry
    )
    
    Write-Host "  Configuring $ToolName at $ConfigPath" -ForegroundColor DarkGray
    
    if ($DryRun) {
        Write-Host "  [DRY] Would write MCP config to $ConfigPath"
        return
    }
    
    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    # 讀取或建立配置
    $json = @{}
    if (Test-Path $ConfigPath) {
        try {
            $raw = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $json = $raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if (-not $json) { $json = @{} }
            }
        } catch {
            $json = @{}
        }
    }
    
    if (-not $json.ContainsKey("mcpServers")) {
        $json["mcpServers"] = @{}
    }
    
    $json["mcpServers"]["sakimcp-deus"] = $Entry
    
    $json | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding utf8
    Write-Host "  [OK] $ToolName configured" -ForegroundColor Green
}

# Step 4: Antigravity (Windsurf)
Write-Host "[4/6] Configuring Antigravity (Windsurf)..." -ForegroundColor Yellow
$antigravityEntry = @{
    command = $DeployBinary
    args    = @()
}
Set-McpConfig -ConfigPath $AntigravityConfig -ToolName "Antigravity" -Entry $antigravityEntry

# Step 5: Gemini CLI
Write-Host "[5/6] Configuring Gemini CLI..." -ForegroundColor Yellow
$geminiEntry = @{
    command = $DeployBinary
    args    = @()
}
Set-McpConfig -ConfigPath $GeminiCliConfig -ToolName "Gemini CLI" -Entry $geminiEntry

# Step 6: Claude Code (Desktop)
Write-Host "[6/6] Configuring Claude Code..." -ForegroundColor Yellow
$claudeEntry = @{
    command = $DeployBinary
    args    = @()
}
Set-McpConfig -ConfigPath $ClaudeCodeConfig -ToolName "Claude Code" -Entry $claudeEntry

# ===== Summary =====
Write-Host ""
Write-Host "=== SakiMCPDeus Deploy Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Binary:  $DeployBinary" -ForegroundColor Cyan
Write-Host "Tools:   run_command, read_file, write_file, list_files, search_files, search_filename" -ForegroundColor Cyan
Write-Host "Inject:  Saki Studio instructions -> Agent System Prompt" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configured for:" -ForegroundColor White
Write-Host "  - Antigravity (Windsurf): $AntigravityConfig" -ForegroundColor DarkGray
Write-Host "  - Gemini CLI:             $GeminiCliConfig" -ForegroundColor DarkGray
Write-Host "  - Claude Code:            $ClaudeCodeConfig" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Restart your Agent tools to activate SakiMCPDeus." -ForegroundColor Yellow

