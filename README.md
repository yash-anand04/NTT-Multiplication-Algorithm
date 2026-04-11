# NTT Multiplication Algorithm

Verilog RTL implementation of polynomial multiplication over the Fermat modulus q = 65537 for degree N = 256 using a radix-4 pipeline structure.

This repository contains:
- RTL source modules for control, memory, interconnect, arithmetic, and top-level integration.
- Documentation extracted from and aligned with the target architecture paper.
- A minimal and maintained simulation/testbench set.

## Current status

- Functional output correctness is verified in simulation with random, impulse, and identity vector tests.
- The implementation is currently configured for R = 4.

## Repository layout

.
|-- docs/
|   |-- High-Radix_Mixed-Radix_NTT_Multiplication_Algorithm_Architecture_Co-Design_Over_Fermat_Modulus.pdf
|   |-- Architecture.png
|   `-- paper_text.txt
|-- rtl/
|   |-- addr_gen.v
|   |-- ctrl_unit.v
|   |-- d1_arith.v
|   |-- interconnect.v
|   |-- mem_banks.v
|   |-- mod_mul_fermat.v
|   |-- ntt_top.v
|   |-- r2_butterfly.v
|   |-- r2intt_r4.v
|   |-- r2ntt_r4.v
|   `-- twiddle_rom.v
|-- scripts/
|   `-- golden_model.py
|-- sim/
|   |-- input_a.hex
|   |-- input_b.hex
|   |-- expected_out.hex
|   |-- twiddle_factors.hex
|   |-- gen_impulse_vectors.py
|   |-- bin/                     (generated simulation artifacts)
|   `-- testbenches/
|       |-- tb_ntt_capture.v
|       |-- tb_mod_mul.v
|       |-- tb_d1_arith.v
|       `-- tb_twiddle_rom_test.v
|-- .gitignore
`-- README.md

## Prerequisites

- Python 3.10+
- Icarus Verilog (`iverilog` and `vvp`) available in PATH
- PowerShell (commands below are PowerShell examples)

## Testbenches retained

1. `tb_ntt_capture.v`
	- End-to-end top-level regression test for `ntt_top`.
	- Streams `input_a.hex` and `input_b.hex`, captures `OUTPUT[i]` from the OUTPUT state.
2. `tb_mod_mul.v`
	- Unit smoke test for `mod_mul_fermat.v`.
3. `tb_d1_arith.v`
	- Unit checks for D1 conversion, add/sub, and multiply-by-power-of-2 behavior.
4. `tb_twiddle_rom_test.v`
	- Twiddle ROM lookup sanity checks for representative `tw_step` values.

## Quick start (end-to-end)

From repository root:

```powershell
Set-Location sim
$py = "../venv/Scripts/python.exe"

# 1) Regenerate deterministic vectors
& $py ../scripts/golden_model.py

# 2) Compile and run end-to-end testbench
iverilog -g2009 -I../rtl testbenches/tb_ntt_capture.v ../rtl/*.v -o a.out
vvp ./a.out 2>&1 |
  Select-String "OUTPUT\[" |
  ForEach-Object {
	 $_ -match 'OUTPUT\[\s*(\d+)\]\s*=\s*([0-9a-f]+)' | Out-Null
	 "$($matches[1]): $($matches[2])"
  } | Out-File -FilePath outputs_current.txt -Encoding utf8

# 3) Compare against expected output
& $py -c "N=256;exp=[int(x.strip(),16) for x in open('expected_out.hex').read().splitlines()[:N]];rtl=[int(x.split(': ')[1],16) for x in open('outputs_current.txt').read().splitlines()[:N]];m=sum(1 for i in range(N) if rtl[i]==exp[i]);print('matches',m,'/256')"
```

## Unit test execution

From `sim/`:

```powershell
# Modular multiplier smoke test
iverilog -g2009 -I../rtl testbenches/tb_mod_mul.v ../rtl/*.v -o a.out
vvp ./a.out

# D1 arithmetic test
iverilog -g2009 -I../rtl testbenches/tb_d1_arith.v ../rtl/*.v -o a.out
vvp ./a.out

# Twiddle ROM test
iverilog -g2009 -I../rtl testbenches/tb_twiddle_rom_test.v ../rtl/*.v -o a.out
vvp ./a.out
```

## Notes

- `sim/bin/`, `sim/a.out`, waveform files, and temporary output dumps are ignored by `.gitignore`.
- If `outputs_current.txt` is generated locally, treat it as a temporary artifact.

