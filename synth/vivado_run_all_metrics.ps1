# =============================================================================
# vivado_run_all_metrics.ps1
# Orchestration script to run synthesis for all R and N configurations
#
# This script:
#   1. Runs Vivado synthesis for each (R, N) configuration
#   2. Collects metrics from reports
#   3. Generates Table IV output
#
# Usage (from PowerShell):
#   cd path\to\NTT Multiplication Algorithm
#   .\synth\vivado_run_all_metrics.ps1
#
# Or with custom Vivado path:
#   .\synth\vivado_run_all_metrics.ps1 -VivadoPath "C:\Xilinx\Vivado\2022.2\bin\vivado.bat"
#
# =============================================================================

param(
    [string]$VivadoPath = "vivado",
    [switch]$SkipSynthesis = $false,
    [switch]$ExtractOnly = $false
)

$ErrorActionPreference = "Stop"

# ---- Configuration ----------------------------------------------------------
$repo_root = Split-Path -Parent $PSScriptRoot
$synth_dir = $PSScriptRoot
$tcl_script = Join-Path $synth_dir "vivado_synth_metrics.tcl"
$py_script = Join-Path $synth_dir "vivado_metrics_extract.py"

function Resolve-VivadoPath {
    param([string]$Path)

    if (Test-Path $Path) {
        return (Resolve-Path $Path).Path
    }

    $cmd = Get-Command $Path -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

$vivado_exe = Resolve-VivadoPath $VivadoPath
if (-not $vivado_exe) {
    Write-Host "[ERROR] Vivado not found. Set -VivadoPath to vivado.bat or add Vivado to PATH." -ForegroundColor Red
    Write-Host "Example: .\\synth\\vivado_run_all_metrics.ps1 -VivadoPath \"C:\\Xilinx\\Vivado\\2022.2\\bin\\vivado.bat\"" -ForegroundColor Yellow
    exit 1
}

# Configurations to run: (Radix, Degree)
# NOTE: Default is N=256 (twiddle_factors.hex is generated for N=256).
# Enable N=512/1024 only after regenerating twiddle ROM for those sizes.
$configs = @(
    @{R=4; N=256},
    @{R=8; N=256},
    @{R=16; N=256}
)

Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "  NTT Synthesis - All Configurations" -ForegroundColor Cyan
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "Repository: $repo_root"
Write-Host "Synth dir:  $synth_dir"
Write-Host "Vivado:     $vivado_exe"
Write-Host ""

# Verify tcl script exists
if (-not (Test-Path $tcl_script)) {
    Write-Host "[ERROR] TCL script not found: $tcl_script" -ForegroundColor Red
    exit 1
}

# ---- Run Synthesis ----------------------------------------------------------
if (-not $ExtractOnly -and -not $SkipSynthesis) {
    Write-Host "[INFO] Running synthesis for all configurations..." -ForegroundColor Yellow
    Write-Host ""
    
    $failed_configs = @()
    
    foreach ($cfg in $configs) {
        $r = $cfg.R
        $n = $cfg.N
        $config_name = "R=$r, N=$n"
        
        Write-Host "[SYNTH] Starting $config_name ..." -ForegroundColor Green
        
        # Vivado command
        $argsList = @(
            "-mode", "batch",
            "-source", $tcl_script,
            "-log", (Join-Path $synth_dir "vivado_r${r}_n${n}.log"),
            "-journal", (Join-Path $synth_dir "vivado_r${r}_n${n}.jou"),
            "-tclargs", $r, $n, 3.0
        )
        
        try {
            & $vivado_exe @argsList
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] $config_name complete" -ForegroundColor Green
            } else {
                Write-Host "[FAIL] $config_name exited with code $LASTEXITCODE" -ForegroundColor Red
                $failed_configs += $config_name
            }
        } catch {
            Write-Host "[ERROR] Failed to run $config_name : $_" -ForegroundColor Red
            $failed_configs += $config_name
        }
        
        Write-Host ""
    }
    
    if ($failed_configs.Count -gt 0) {
        Write-Host "[WARN] Failed configurations:" -ForegroundColor Yellow
        foreach ($cfg in $failed_configs) {
            Write-Host "  - $cfg" -ForegroundColor Yellow
        }
    }
}

# ---- Extract & Generate Table IV -------------------------------------------
Write-Host "[INFO] Extracting metrics and generating Table IV..." -ForegroundColor Yellow

if (Test-Path $py_script) {
    # Use Python script if available
    python $py_script $synth_dir
} else {
    Write-Host "[WARN] Python script not found: $py_script" -ForegroundColor Yellow
    Write-Host "       Run manually: python $py_script $synth_dir" -ForegroundColor Yellow
}

# ---- Summary ----------------------------------------------------------------
Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "  SYNTHESIS COMPLETE" -ForegroundColor Cyan
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "Metrics location: $synth_dir"
Write-Host "Table IV output: $(Join-Path $synth_dir "TABLE_IV.txt")"
Write-Host ""
Write-Host "Results by configuration:"
Write-Host ""

foreach ($cfg in $configs) {
    $r = $cfg.R
    $n = $cfg.N
    $result_dir = Join-Path $synth_dir "results_r${r}_n${n}"
    $metrics_file = Join-Path $result_dir "metrics_raw.txt"
    
    if (Test-Path $metrics_file) {
        Write-Host "  R=$r, N=$n  OK" -ForegroundColor Green
    }
    else {
        Write-Host "  R=$r, N=$n  FAIL" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Next steps:"
Write-Host ("  1. Review Table IV: " + (Join-Path $synth_dir 'TABLE_IV.txt'))
Write-Host ("  2. Check individual reports in: " + (Join-Path $synth_dir 'results_r<R>_n<N>'))
Write-Host ""
