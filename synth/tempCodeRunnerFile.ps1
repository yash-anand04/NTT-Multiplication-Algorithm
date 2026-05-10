function Resolve-VivadoPath {
#     param([string]$Path)

#     if (Test-Path $Path) {
#         return (Resolve-Path $Path).Path
#     }

#     $cmd = Get-Command $Path -ErrorAction SilentlyContinue
#     if ($cmd) {
#         return $cmd.Source
#     }

#     return $null
# }

# $vivado_exe = Resolve-VivadoPath $VivadoPath
# if (-not $vivado_exe) {
#     Write-Host "[ERROR] Vivado not found. Set -VivadoPath to vivado.bat or add Vivado to PATH." -ForegroundColor Red
#     Write-Host "Example: .\\synth\\vivado_run_all_metrics.ps1 -VivadoPath \"C:\\Xilinx\\Vivado\\2022.2\\bin\\vivado.bat\"" -ForegroundColor Yellow
#     exit 1
# }

# # Configurations to run: (Radix, Degree)
# # NOTE: Default is N=256 (twiddle_factors.hex is generated for N=256).
# # Enable N=512/1024 only after regenerating twiddle ROM for those sizes.
# $configs = @(
#     @{R=4; N=256},
#     @{R=8; N=256},
#     @{R=16; N=256}
# )

# Write-Host "=========================================================================" -ForegroundColor Cyan
# Write-Host "  NTT Synthesis - All Configurations" -ForegroundColor Cyan
# Write-Host "=========================================================================" -ForegroundColor Cyan
# Write-Host "Repository: $repo_root"
# Write-Host "Synth dir:  $synth_dir"
# Write-Host "Vivado:     $vivado_exe"
# Write-Host ""

# # Verify tcl script exists
# if (-not (Test-Path $tcl_script)) {
#     Write-Host "[ERROR] TCL script not found: $tcl_script" -ForegroundColor Red
#     exit 1
# }

# # ---- Run Synthesis ----------------------------------------------------------
# if (-not $ExtractOnly -and -not $SkipSynthesis) {
#     Write-Host "[INFO] Running synthesis for all configurations..." -ForegroundColor Yellow
#     Write-Host ""
    
#     $failed_configs = @()
    
#     foreach ($cfg in $configs) {
#         $r = $cfg.R
#         $n = $cfg.N
#         $config_name = "R=$r, N=$n"
        
#         Write-Host "[SYNTH] Starting $config_name ..." -ForegroundColor Green
        
#         # Vivado command
#         $argsList = @(
#             "-mode", "batch",
#             "-source", $tcl_script,
#             "-log", (Join-Path $synth_dir "vivado_r${r}_n${n}.log"),
#             "-journal", (Join-Path $synth_dir "vivado_r${r}_n${n}.jou"),
#             "-tclargs", $r, $n, 3.0
#         )
        
#         try {
#             & $vivado_exe @argsList
#             if ($LASTEXITCODE -eq 0) {
#                 Write-Host "[OK] $config_name complete" -ForegroundColor Green
#             } else {
#                 Write-Host "[FAIL] $config_name exited with code $LASTEXITCODE" -ForegroundColor Red
#                 $failed_configs += $config_name
#             }
#         } catch {
#             Write-Host "[ERROR] Failed to run $config_name : $_" -ForegroundColor Red
#             $failed_configs += $config_name
#         }
        
#         Write-Host ""
#     }
    
#     if ($failed_configs.Count -gt 0) {
#         Write-Host "[WARN] Failed configurations:" -ForegroundColor Yellow
#         foreach ($cfg in $failed_configs) {
#             Write-Host "  - $cfg" -ForegroundColor Yellow
#         }
#     }
# }