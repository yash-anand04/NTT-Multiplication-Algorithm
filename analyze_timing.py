#!/usr/bin/env python3
"""Compare baseline and optimized timing reports."""

import openpyxl
from pathlib import Path

# Load both workbooks
baseline_path = Path("Reports/Table.xlsx")
optimized_path = Path("Reports/Table_new.xlsx")

wb_baseline = openpyxl.load_workbook(baseline_path, data_only=True)
wb_optimized = openpyxl.load_workbook(optimized_path, data_only=True)

ws_baseline = wb_baseline.active
ws_optimized = wb_optimized.active

# Extract summary metrics
baseline_wns = ws_baseline['B2'].value
optimized_wns = ws_optimized['B2'].value

baseline_rows = ws_baseline.max_row - 1
optimized_rows = ws_optimized.max_row - 1

print("=" * 70)
print("TIMING REPORT COMPARISON: BASELINE vs OPTIMIZED")
print("=" * 70)
print(f"\nBaseline (Table.xlsx):")
print(f"  WNS: {baseline_wns:.4f} ns")
print(f"  Total paths analyzed: {baseline_rows}")

print(f"\nOptimized (Table_new.xlsx):")
print(f"  WNS: {optimized_wns:.4f} ns") 
print(f"  Total paths analyzed: {optimized_rows}")

improvement = optimized_wns - baseline_wns
improvement_pct = (improvement / baseline_wns) * 100 if baseline_wns != 0 else 0

print(f"\nChange: {improvement:.4f} ns ({improvement_pct:.2f}%)")
if improvement > 0:
    print("  ⚠ DEGRADATION - Timing got worse")
else:
    print("  ✓ IMPROVEMENT - Timing got better")

# Extract top 10 failing paths from both
print("\n" + "=" * 70)
print("TOP 10 FAILING PATHS - BASELINE")
print("=" * 70)
print(f"{'#':<3} {'Slack (ns)':<12} {'Start Point':<40} {'End Point':<40}")
print("-" * 95)

for i in range(2, min(12, ws_baseline.max_row + 1)):
    slack = ws_baseline[f'B{i}'].value
    start = ws_baseline[f'F{i}'].value
    end = ws_baseline[f'G{i}'].value
    delay = ws_baseline[f'H{i}'].value
    print(f"{i-1:<3} {slack:<12.4f} {str(start)[:39]:<40} {str(end)[:39]:<40}")

print("\n" + "=" * 70)
print("TOP 10 FAILING PATHS - OPTIMIZED")
print("=" * 70)
print(f"{'#':<3} {'Slack (ns)':<12} {'Start Point':<40} {'End Point':<40}")
print("-" * 95)

for i in range(2, min(12, ws_optimized.max_row + 1)):
    slack = ws_optimized[f'B{i}'].value
    start = ws_optimized[f'F{i}'].value
    end = ws_optimized[f'G{i}'].value
    delay = ws_optimized[f'H{i}'].value
    print(f"{i-1:<3} {slack:<12.4f} {str(start)[:39]:<40} {str(end)[:39]:<40}")

# Analyze path signature changes
print("\n" + "=" * 70)
print("PATH SIGNATURE ANALYSIS")
print("=" * 70)

# Count path signatures in baseline
baseline_starts = {}
for i in range(2, ws_baseline.max_row + 1):
    start = ws_baseline[f'F{i}'].value
    if start:
        baseline_starts[start] = baseline_starts.get(start, 0) + 1

# Count path signatures in optimized
optimized_starts = {}
for i in range(2, ws_optimized.max_row + 1):
    start = ws_optimized[f'F{i}'].value
    if start:
        optimized_starts[start] = optimized_starts.get(start, 0) + 1

print("\nBaseline - Top start points:")
for start, count in sorted(baseline_starts.items(), key=lambda x: -x[1])[:5]:
    print(f"  {str(start)[:60]:<60} : {count} paths")

print("\nOptimized - Top start points:")
for start, count in sorted(optimized_starts.items(), key=lambda x: -x[1])[:5]:
    print(f"  {str(start)[:60]:<60} : {count} paths")

wb_baseline.close()
wb_optimized.close()
