#!/usr/bin/env python3
"""
vivado_normalize_atp.py
Normalize ATP values against a baseline design for paper publication

Usage:
    python vivado_normalize_atp.py [--baseline <design>] [--output <file>]
    
Examples:
    # Normalize against [5] Ma et al. (R2, N=256)
    python vivado_normalize_atp.py --baseline "[5]" --output TABLE_IV_normalized.txt
    
    # Normalize against first result
    python vivado_normalize_atp.py --baseline "Ours_R4_N256"

This script:
    1. Reads metrics_raw.txt files from all configs
    2. Normalizes ATP against baseline design
    3. Outputs Table IV with normalized values
    4. Rounds to 1 decimal place (publication style)
"""

import argparse
import sys
from pathlib import Path
from typing import Dict, Optional, Tuple
import re

# Baseline values from paper Table IV references
BASELINES = {
    "[5]_R2_N256": {
        "LUT": 404, "FF": 599, "DSP": 0, "BRAM": 1,
        "cycles": 3824,  # From Table IV
        "name": "[5] Ma et al. (R2, N=256, q=65537)"
    },
    "[21]_R4_N256": {
        "LUT": 9211, "FF": 9810, "DSP": 60, "BRAM": 1,
        "cycles": 246,
        "name": "[21] Duong-Ngoc & Lee (R4, N=256)"
    },
    "[24]_R2_N512": {
        "LUT": 741, "FF": 330, "DSP": 2, "BRAM": 5,
        "cycles": 4010,
        "name": "[24] Zhang et al. (R2, N=512)"
    },
    "[16]_R4_N1024": {
        "LUT": 1196, "FF": 969, "DSP": 12, "BRAM": 3,
        "cycles": 4186,
        "name": "[16] Chen et al. (R4, N=1024)"
    },
}


class TableIVNormalizer:
    def __init__(self, results_dir: Path):
        self.results_dir = Path(results_dir)
        self.metrics = self._load_all_metrics()
    
    def _load_all_metrics(self) -> Dict[Tuple[int, int], Dict]:
        """Load metrics from all results_r<R>_n<N>/ directories"""
        metrics = {}
        
        for config_dir in self.results_dir.glob("results_r*_n*"):
            match = re.match(r"results_r(\d+)_n(\d+)", config_dir.name)
            if not match:
                continue
            
            r, n = int(match.group(1)), int(match.group(2))
            key = (r, n)
            
            metrics_file = config_dir / "metrics_raw.txt"
            if metrics_file.exists():
                metrics[key] = self._parse_metrics_file(metrics_file)
        
        return metrics
    
    def _parse_metrics_file(self, path: Path) -> Dict:
        """Parse metrics_raw.txt"""
        data = {}
        with open(path) as f:
            for line in f:
                line = line.strip()
                if '=' not in line or line.startswith('#'):
                    continue
                key, val = line.split('=', 1)
                key = key.strip()
                try:
                    data[key] = float(val) if '.' in val else int(val)
                except ValueError:
                    data[key] = val
        return data
    
    def normalize_against_baseline(self, baseline_key: str) -> Dict[Tuple[int, int], Dict]:
        """Normalize all metrics against a baseline design"""
        
        if baseline_key not in BASELINES:
            print(f"[ERROR] Unknown baseline: {baseline_key}")
            print(f"Available: {list(BASELINES.keys())}")
            sys.exit(1)
        
        baseline = BASELINES[baseline_key]
        baseline_name = baseline["name"]
        
        print(f"[INFO] Normalizing against: {baseline_name}")
        print(f"       Baseline ATP denominators: LUT={baseline['LUT']}, FF={baseline['FF']}, "
              f"DSP={baseline['DSP']}, BRAM={baseline['BRAM']}, Cycles={baseline['cycles']}")
        print()
        
        normalized = {}
        
        for (r, n), metrics in self.metrics.items():
            norm_metrics = {}
            
            # Normalize resource counts
            for resource in ['LUT', 'FF', 'DSP', 'BRAM']:
                actual = metrics.get(resource, 0)
                baseline_val = baseline.get(resource, 1)
                # Normalize: (actual / baseline) provides relative scale
                norm_metrics[f'{resource}_norm'] = actual / baseline_val if baseline_val else 0
            
            # Compute normalized ATP: (norm_LUT) * (cycles / baseline_cycles)
            cycles = metrics.get('CYCLES', 1000)
            cycle_norm = cycles / baseline['cycles']
            
            norm_metrics['LUT_ATP_norm'] = norm_metrics['LUT_norm'] * cycle_norm
            norm_metrics['FF_ATP_norm'] = norm_metrics['FF_norm'] * cycle_norm
            norm_metrics['DSP_ATP_norm'] = norm_metrics['DSP_norm'] * cycle_norm
            norm_metrics['BRAM_ATP_norm'] = norm_metrics['BRAM_norm'] * cycle_norm
            
            # Keep raw values too
            norm_metrics.update(metrics)
            
            normalized[(r, n)] = norm_metrics
        
        return normalized
    
    def generate_table(self, normalized_metrics: Dict[Tuple[int, int], Dict], 
                      include_raw: bool = False) -> str:
        """Generate Table IV markdown"""
        
        lines = []
        
        if include_raw:
            # Header with both raw and normalized
            lines.append(
                "| Config | R | LUT (raw/norm×ATP) | FF (raw/norm×ATP) | "
                "DSP (raw/norm×ATP) | BRAM (raw/norm×ATP) | Freq(MHz) | Cycles | Time(μs) |"
            )
            lines.append("|--------|---|-------------------|------------------|-------------------|------------------|-----------|---------|----------|")
        else:
            # Simplified header (normalized only)
            lines.append(
                "| N | R | LUT/ATP | FF/ATP | DSP/ATP | BRAM/ATP | Freq(MHz) | Cycles | Time(μs) |"
            )
            lines.append("|---|---|---------|--------|---------|----------|-----------|---------|----------|")
        
        # Group by N, then iterate R
        configs_by_n = {}
        for (r, n), metrics in normalized_metrics.items():
            if n not in configs_by_n:
                configs_by_n[n] = []
            configs_by_n[n].append((r, metrics))
        
        for n in sorted(configs_by_n.keys()):
            for r, metrics in sorted(configs_by_n[n]):
                lut = int(metrics.get('LUT', 0))
                ff = int(metrics.get('FF', 0))
                dsp = int(metrics.get('DSP', 0))
                bram = int(metrics.get('BRAM', 0))
                
                fmax = metrics.get('FMAX_MHZ', 300)
                cycles = int(metrics.get('CYCLES', 1000))
                time_us = metrics.get('TIME_US', 1.0)
                
                lut_atp_norm = metrics.get('LUT_ATP_norm', 0)
                ff_atp_norm = metrics.get('FF_ATP_norm', 0)
                dsp_atp_norm = metrics.get('DSP_ATP_norm', 0)
                bram_atp_norm = metrics.get('BRAM_ATP_norm', 0)
                
                if include_raw:
                    lines.append(
                        f"| R={r},N={n} | {r} | "
                        f"{lut}/{lut_atp_norm:.1f} | {ff}/{ff_atp_norm:.1f} | "
                        f"{dsp}/{dsp_atp_norm:.1f} | {bram}/{bram_atp_norm:.1f} | "
                        f"{fmax:.0f} | {cycles} | {time_us:.2f} |"
                    )
                else:
                    lines.append(
                        f"| {n} | {r} | "
                        f"{lut_atp_norm:.1f} | {ff_atp_norm:.1f} | "
                        f"{dsp_atp_norm:.1f} | {bram_atp_norm:.1f} | "
                        f"{fmax:.0f} | {cycles} | {time_us:.2f} |"
                    )
        
        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Normalize Table IV ATP values for publication"
    )
    parser.add_argument(
        'results_dir',
        nargs='?',
        default='synth',
        help='Results directory containing results_r*_n*/ subdirs'
    )
    parser.add_argument(
        '--baseline',
        default='[5]_R2_N256',
        help=f'Baseline design ({list(BASELINES.keys())})'
    )
    parser.add_argument(
        '--output',
        default=None,
        help='Output file (default: TABLE_IV_normalized.txt)'
    )
    parser.add_argument(
        '--list-baselines',
        action='store_true',
        help='List available baselines and exit'
    )
    
    args = parser.parse_args()
    
    # List baselines if requested
    if args.list_baselines:
        print("Available baseline designs:\n")
        for key, data in BASELINES.items():
            print(f"  {key:25} : {data['name']}")
        sys.exit(0)
    
    results_dir = Path(args.results_dir)
    if not results_dir.exists():
        print(f"[ERROR] Directory not found: {results_dir}")
        sys.exit(1)
    
    print("=" * 90)
    print("  TABLE IV ATP NORMALIZATION FOR PUBLICATION")
    print("=" * 90)
    print(f"Results directory: {results_dir}")
    print()
    
    # Create normalizer and normalize
    normalizer = TableIVNormalizer(results_dir)
    normalized = normalizer.normalize_against_baseline(args.baseline)
    
    # Generate table
    table = normalizer.generate_table(normalized, include_raw=True)
    
    print("\n" + table)
    
    # Write output
    output_file = Path(args.output or "TABLE_IV_normalized.txt")
    with open(output_file, 'w') as f:
        f.write(table)
    
    print(f"\n[INFO] Normalized Table IV written to: {output_file}")
    print("\nUsage for paper:")
    print("  1. Copy the table above into your paper")
    print("  2. Update caption to note baseline design used")
    print("  3. Cite this project in references")
    print()


if __name__ == '__main__':
    main()
