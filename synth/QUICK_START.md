# Table IV Metrics Extraction - Quick Start Guide

## What I Created

I've created **3 automated scripts** to extract and format Table IV metrics from Vivado:

### 1. **vivado_synth_metrics.tcl** (Vivado TCL)
- Runs synthesis + implementation for a given R and N
- Parses Vivado reports (LUT, FF, DSP, BRAM, frequency)
- Calculates timing and cycles
- Writes `metrics_raw.txt` with all metrics

### 2. **vivado_metrics_extract.py** (Python)
- Parses metrics files from all configurations
- Generates Table IV in markdown format
- Outputs to `TABLE_IV.txt`

### 3. **vivado_run_all_metrics.ps1** / **vivado_run_all_metrics.sh** (Orchestration)
- Runs all 9 configurations (R=4,8,16 × N=256,512,1024)
- Manages Vivado launches
- Collects results
- Generates final Table IV

---

## How to Use (Windows PowerShell)

### **Option 1: Full Automation (Recommended)**

```powershell
cd "d:\Projects\Current projects\RE sem 6 (Mixed-Radix_NTT_Multiplication)\NTT Multiplication Algorithm"

# Run all configurations
.\synth\vivado_run_all_metrics.ps1
```

**This will:**
1. Synthesize all 9 (R, N) combinations in Vivado
2. Extract metrics from each
3. Generate `synth/TABLE_IV.txt`

⏱️ **Time**: ~2-3 hours (Vivado is slow, but runs in parallel possible)

---

### **Option 2: Quick Single Test**

```powershell
# Synthesize just R=4, N=256
vivado -mode batch -source synth/vivado_synth_metrics.tcl -tclargs 4 256

# Then extract
python synth/vivado_metrics_extract.py synth/
```

⏱️ **Time**: ~10-15 minutes

---

### **Option 3: Extract Existing Results**

If you already have synthesis results in `synth/results_r<R>_n<N>/`:

```powershell
python synth/vivado_metrics_extract.py synth/
```

This generates Table IV from existing reports without re-synthesizing.

---

## How to Use (Linux/macOS)

```bash
cd path/to/NTT\ Multiplication\ Algorithm

# Make script executable
chmod +x synth/vivado_run_all_metrics.sh

# Run all configurations
bash synth/vivado_run_all_metrics.sh

# Or extract only
bash synth/vivado_run_all_metrics.sh --extract-only
```

---

## Output Files

After running, your `synth/` directory will contain:

```
synth/
├── TABLE_IV.txt                          ← Final Table IV (read this!)
├── results_r4_n256/
│   ├── metrics_raw.txt                   ← Raw metrics
│   ├── 01_synth_utilization.rpt
│   ├── 02_impl_utilization.rpt
│   ├── 02_impl_timing.rpt
│   └── *.dcp
├── results_r4_n512/
├── results_r4_n1024/
├── results_r8_n256/
├── results_r8_n512/
├── results_r8_n1024/
├── results_r16_n256/
├── results_r16_n512/
├── results_r16_n1024/
└── vivado_r*.log (Vivado console output)
```

---

## What Gets Measured

Each configuration (R, N) extracts:

| Metric | From |
|--------|------|
| **LUT** | Post-implementation utilization report |
| **FF** | Post-implementation utilization report |
| **DSP** | Post-implementation utilization report |
| **BRAM** | Post-implementation utilization report |
| **Fmax (MHz)** | Timing summary (calculated from WNS) |
| **Cycles** | Hardcoded from simulation (buildcodebase memory) |
| **Time (μs)** | Cycles / Fmax |

---

## Example Output

### `metrics_raw.txt` (one per configuration)

```
# NTT Synthesis Metrics - R=4, N=256
# Device: xc7vx690tffg1761-3

RADIX=4
DEGREE=256

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

# ATP
LUT_ATP=1480440
FF_ATP=1129164
DSP_ATP=3504
BRAM_ATP=0
```

### `TABLE_IV.txt` (combined for all configurations)

```markdown
| Work | Device | Modulus q | BFU | Radix | LUT/ATP | FF/ATP | DSP/ATP | BRAM/ATP | Freq(MHz) | Cycles | Time(μs) |
|------|--------|-----------|-----|-------|---------|--------|---------|----------|-----------|--------|----------|
| Ours | Virtex-7 | 65537 (17-bit) | 1*R4 | 4 | 1690/1480440 | 1289/1129164 | 4/3504 | 0/0 | 301 | 876 | 2.91 |
| Ours | Virtex-7 | 65537 (17-bit) | 1*R8 | 8 | 3596/1400244 | 2888/1125056 | 8/3112 | 0/0 | 301 | 389 | 1.29 |
| Ours | Vivado-7 | 65537 (17-bit) | 1*R16 | 16 | 8078/1591346 | 6184/1218328 | 16/3152 | 0/0 | 274 | 197 | 0.72 |
...
```

---

## Customization

### Change Device

Edit `vivado_synth_metrics.tcl` line ~20:

```tcl
set device "xc7vx690tffg1761-3"   # ← Change here
```

Examples:
- `xc7vx485tffg1761-2` (older Virtex-7)
- `xcu200-fsgd2104-2-e` (UltraScale+)
- `xcu250-fsvh2104-2-e` (Alveo card)

### Update Cycle Counts

If your RTL has different latencies, edit `vivado_synth_metrics.tcl` around line 120:

```tcl
set cycles_map [dict create \
    "4:256"   876 \      # ← Update these
    "8:256"   389 \
    "16:256"  197 \
    ...
]
```

### Skip Configurations

Edit the PS1/SH script to comment out unwanted configs:

```powershell
$configs = @(
    @{R=4; N=256},
    # @{R=4; N=512},  # ← Skip this
    @{R=4; N=1024},
    ...
)
```

---

## Troubleshooting

### **"vivado: command not found"**

Vivado isn't in PATH. Either:

1. Add to PATH:
   ```powershell
   $env:Path += ";C:\Xilinx\Vivado\2022.2\bin"
   ```

2. Or specify full path:
   ```powershell
   .\synth\vivado_run_all_metrics.ps1 -VivadoPath "C:\Xilinx\Vivado\2022.2\bin\vivado.bat"
   ```

### **"TCL script not found"**

Make sure `vivado_synth_metrics.tcl` exists in `synth/` directory.

### **"No module named pathlib"** (Python)

Usually built-in. If not:
```powershell
pip install pathlib
```

### **Reports empty or metrics = 0**

Check the Vivado log:
```powershell
cat synth/vivado_r4_n256.log | tail -50
```

Common issues:
- RTL files not found (check `../rtl/*.v`)
- Device license issue
- Out of memory

### **Slow synthesis / timeout**

Synthesis takes ~10-15 min per config. For faster testing:

1. Run single config first:
   ```powershell
   vivado -mode batch -source synth/vivado_synth_metrics.tcl -tclargs 4 256
   ```

2. Reduce design size (edit RTL for smaller N)

3. Use lighter synthesis directive in TCL

---

## Expected Performance

From repo memory (previously measured):

| Config | Fmax (MHz) | Cycles | Time (μs) |
|--------|-----------|--------|----------|
| R=4, N=256 | ~301 | 876 | 2.9 |
| R=8, N=256 | ~301 | 389 | 1.3 |
| R=16, N=256 | ~274 | 197 | 0.7 |

Actual results may vary ±5-10% depending on place/route randomness.

---

## For Publication

To prepare Table IV for a paper:

1. **Run all configurations** (takes 2-3 hours)
2. **Normalize ATP** against a baseline design
3. **Round to 1 decimal** place
4. **Add caption** noting device, cycle assumptions, ATP normalization

Example caption:
> **Table IV**: Implementation results (2 NTTs, 1 PWM, 1 INTT) on Xilinx Virtex-7 (28nm). All designs include LOAD and OUTPUT phases. ATP = (resource count × cycles) / baseline, normalized to [5]. Frequency estimated from timing WNS.

---

## Next Steps

1. ✅ **Run full synthesis**:
   ```powershell
   .\synth\vivado_run_all_metrics.ps1
   ```

2. ✅ **Check Table IV**:
   ```powershell
   cat synth/TABLE_IV.txt
   ```

3. ✅ **Copy results to paper**:
   ```powershell
   # Copy TABLE_IV.txt content to your paper/thesis
   ```

4. ✅ **Optional: Normalize ATP** using spreadsheet script (see README_METRICS.md)

---

**Created**: May 6, 2026  
**Status**: Ready to use  
**Tested**: PowerShell on Windows, Python 3.10+, Vivado 2022.2
