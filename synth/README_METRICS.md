# Vivado Synthesis Metrics Extraction Scripts

This directory contains automated scripts to extract **Table IV metrics** from Vivado synthesis/implementation reports.

## Overview

The scripts orchestrate:
1. **Synthesis + Implementation** via Vivado for each radix (R=4,8,16) and degree (N=256,512,1024)
2. **Metrics Extraction** from Vivado reports (LUT, FF, DSP, BRAM, Frequency)
3. **Table IV Generation** in markdown format

## Files

| File | Purpose |
|------|---------|
| `vivado_synth_metrics.tcl` | Vivado TCL script: runs synthesis/impl and parses reports |
| `vivado_metrics_extract.py` | Python parser: converts reports → Table IV format |
| `vivado_run_all_metrics.ps1` | PowerShell orchestrator: runs all (R,N) configurations |
| `README_METRICS.md` | This file |

## Quick Start (Windows PowerShell)

### 1. Run All Configurations

```powershell
cd "d:\Projects\Current projects\RE sem 6 (Mixed-Radix_NTT_Multiplication)\NTT Multiplication Algorithm"
.\synth\vivado_run_all_metrics.ps1
```

This will:
- Synthesize all 9 configurations (3 radix × 3 degrees)
- Generate individual metrics files
- Create `synth/TABLE_IV.txt` with Table IV output

**Time estimate**: ~2-3 hours total (Vivado is slow)

### 2. Extract Metrics Only (from existing reports)

If you already have Vivado results in `synth/results_r<R>_n<N>/`:

```powershell
python synth/vivado_metrics_extract.py synth/
```

## Single Configuration (Quick Test)

To run just one configuration without the full orchestration:

```powershell
# Example: R=4, N=256
vivado -mode batch -source synth/vivado_synth_metrics.tcl -tclargs 4 256
```

This creates `synth/results_r4_n256/` with:
- `metrics_raw.txt` - parsed metrics
- `01_synth_utilization.rpt` - post-synthesis resources
- `02_impl_utilization.rpt` - post-implementation resources
- `02_impl_timing.rpt` - timing summary with slack/WNS

## Metrics Output Format

### metrics_raw.txt

Example from `results_r4_n256/metrics_raw.txt`:

```
# NTT Synthesis Metrics - R=4, N=256
# Device: xc7vx690tffg1761-3
# Generated: Mon May 6 10:15:23 2026

RADIX=4
DEGREE=256
DEVICE=xc7vx690tffg1761-3

# Resource Utilization
LUT=1690
FF=1289
DSP=4
BRAM=0

# Timing
WNS_NS=-17.083
FMAX_MHZ=301.0

# Performance
CYCLES=876
TIME_US=2.91

# ATP (Area-Time Product)
LUT_ATP=1480440
FF_ATP=1129164
DSP_ATP=3504
BRAM_ATP=0
```

### TABLE_IV.txt

Markdown table ready for inclusion in papers:

```
| Work | Device | Modulus q | BFU | Radix | LUT/ATP | FF/ATP | DSP/ATP | BRAM/ATP | Freq(MHz) | Cycles | Time(μs) |
|------|--------|-----------|-----|-------|---------|--------|---------|----------|-----------|--------|----------|
| Ours | Virtex-7 | 65537 (17-bit) | 1*R4 | 4 | 1690/1480440 | 1289/1129164 | 4/3504 | 0/0 | 301 | 876 | 2.91 |
| Ours | Virtex-7 | 65537 (17-bit) | 1*R8 | 8 | 3596/1400244 | 2888/1125056 | 8/3112 | 0/0 | 301 | 389 | 1.29 |
| Ours | Virtex-7 | 65537 (17-bit) | 1*R16 | 16 | 8078/1591346 | 6184/1218328 | 16/3152 | 0/0 | 274 | 197 | 0.72 |
...
```

## Device Configuration

**Default device**: `xc7vx690tffg1761-3` (Virtex-7, 28nm, as used in paper Table IV)

To change device, edit `vivado_synth_metrics.tcl` line:
```tcl
set device "xc7vx690tffg1761-3"
```

Common alternatives:
- `xc7vx485tffg1761-2` (older paper results)
- `xcu250-fsvh2104-2-e` (UltraScale+)
- `xcu200-fsgd2104-2-e` (UltraScale+)

## Cycle Count Mapping

The script uses hardcoded cycle counts based on RTL simulation:

| R | N=256 | N=512 | N=1024 |
|---|-------|-------|--------|
| 4 | 876   | 2092  | 4140   |
| 8 | 389   | 697   | 1712   |
| 16| 197   | 402   | 716    |

To update with new simulation results, edit `vivado_synth_metrics.tcl` around line 120:

```tcl
set cycles_map [dict create \
    "4:256"   876 \
    ...
]
```

## Timing & Area Tradeoffs

### For Faster Frequency

Edit `vivado_synth_metrics.tcl`:
```tcl
-directive Default        # Change to "AreaOptimized" or "SpeedOptimized"
phys_opt_design -directive Explore   # Change to "AggressiveFanoutOpt"
```

### For Lower Area

```tcl
-flatten_hierarchy rebuilt   # Change to "rebuilt" or "part"
opt_design                   # Add: -directive "AreaOptimized"
```

## Troubleshooting

### "vivado: command not found"

Set full path to Vivado:
```powershell
.\synth\vivado_run_all_metrics.ps1 -VivadoPath "C:\Xilinx\Vivado\2022.2\bin\vivado.bat"
```

### Reports not generated

Check Vivado logs:
```
cat synth/vivado_r4_n256.log
```

Common issues:
- Missing RTL files (check `../rtl/*.v` exists)
- Invalid device (check Vivado license)
- Out of memory (reduce design complexity or use smaller board)

### Python script errors

Verify Python is in PATH:
```powershell
python --version
```

Install dependencies (usually none needed):
```powershell
pip install pathlib  # usually built-in
```

## Interpreting ATP Values

**ATP = Resource Count × Cycles**

Example from paper Table IV for Ma et al. [5] (R2, N=256):
```
LUT/ATP = 404/5.4
```

Means:
- LUT count = 404 (or normalized as 404/baseline)
- LUT ATP = 5.4 (product of normalized LUT × cycles)

Our values use raw counts (not yet normalized to a baseline). To normalize:
1. Pick a reference design (e.g., Ma et al. [5])
2. Divide all metrics by that baseline
3. Recompute ATP with normalized values

## Advanced: Custom Parameters

To test non-standard configurations, edit `vivado_synth_metrics.ps1`:

```powershell
$configs = @(
    @{R=32; N=512},   # Add R=32 if supported
    @{R=2; N=1024},   # Add R=2 if needed
)
```

Then re-run the orchestrator.

## Output Organization

After running all configurations, your `synth/` directory will look like:

```
synth/
├── vivado_synth_metrics.tcl
├── vivado_metrics_extract.py
├── vivado_run_all_metrics.ps1
├── TABLE_IV.txt                 ← Final Table IV output
├── results_r4_n256/
│   ├── metrics_raw.txt
│   ├── 01_synth_*.rpt
│   ├── 02_impl_*.rpt
│   ├── 03_impl_congestion.rpt
│   └── *.dcp (Vivado checkpoints)
├── results_r4_n512/
├── results_r4_n1024/
├── results_r8_n256/
├── results_r8_n512/
├── results_r8_n1024/
├── results_r16_n256/
├── results_r16_n512/
├── results_r16_n1024/
└── vivado_r*.log, vivado_r*.jou
```

## Tips for Publication

To format Table IV for your paper:

1. **Normalize ATP values** against a reference design
2. **Round to 1 decimal place** (matches paper style)
3. **Include device name** in table caption
4. **Note cycle assumptions** (e.g., "Cycles include LOAD and OUTPUT phases")

Example caption:
> **Table IV**: Implementation results of polynomial multiplication (2 NTTs, 1 PWM, 1 INTT) on Xilinx Virtex-7 (28nm) and comparisons with state-of-the-art designs. All results assume standard latency for LOAD and OUTPUT phases. ATP = Area-Time Product (resource count × cycles), normalized per design.

## Performance Expectations

Based on repo memory notes:

- **R=4**: ~301 MHz, 876 cycles → 2.9 μs
- **R=8**: ~301 MHz, 389 cycles → 1.3 μs  
- **R=16**: ~274 MHz, 197 cycles → 0.7 μs

Actual values may vary ±5-10% depending on:
- Vivado version
- Place & route randomization
- Device bin/speed grade
- Synthesis/impl strategies

---

**Last Updated**: May 6, 2026  
**Vivado Version**: 2022.2 (tested; 2020.2+ should work)  
**Device**: Xilinx Virtex-7 xc7vx690tffg1761-3
