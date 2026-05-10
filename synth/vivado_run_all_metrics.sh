#!/bin/bash
# =============================================================================
# vivado_run_all_metrics.sh
# Orchestration script for Linux/macOS users
#
# Runs synthesis for all R and N configurations and generates Table IV
#
# Usage:
#   cd path/to/NTT Multiplication Algorithm
#   bash synth/vivado_run_all_metrics.sh [--skip-synth] [--extract-only]
#
# Options:
#   --skip-synth     Don't run Vivado (just extract existing results)
#   --extract-only   Only extract metrics (no synthesis)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SYNTH_DIR="$SCRIPT_DIR"
TCL_SCRIPT="$SYNTH_DIR/vivado_synth_metrics.tcl"
PY_SCRIPT="$SYNTH_DIR/vivado_metrics_extract.py"

VIVADO_CMD="${VIVADO_CMD:-vivado}"
SKIP_SYNTH=false
EXTRACT_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-synth)
            SKIP_SYNTH=true
            shift
            ;;
        --extract-only)
            EXTRACT_ONLY=true
            SKIP_SYNTH=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "========================================================================="
echo "  NTT Synthesis - All Configurations"
echo "========================================================================="
echo "Repository:  $REPO_ROOT"
echo "Synth dir:   $SYNTH_DIR"
echo "Vivado cmd:  $VIVADO_CMD"
echo ""

# Verify files exist
if [ ! -f "$TCL_SCRIPT" ]; then
    echo "[ERROR] TCL script not found: $TCL_SCRIPT"
    exit 1
fi

# Configurations: (R, N)
declare -a CONFIGS=(
    "4:256"
    "4:512"
    "4:1024"
    "8:256"
    "8:512"
    "8:1024"
    "16:256"
    "16:512"
    "16:1024"
)

# ---- Run Synthesis ----------------------------------------------------------
if [ "$EXTRACT_ONLY" = false ] && [ "$SKIP_SYNTH" = false ]; then
    echo "[INFO] Running synthesis for all configurations..."
    echo ""
    
    FAILED_CONFIGS=()
    
    for config in "${CONFIGS[@]}"; do
        IFS=':' read -r R N <<< "$config"
        CONFIG_NAME="R=$R, N=$N"
        
        echo "[SYNTH] Starting $CONFIG_NAME ..."
        
        LOG_FILE="$SYNTH_DIR/vivado_r${R}_n${N}.log"
        JOU_FILE="$SYNTH_DIR/vivado_r${R}_n${N}.jou"
        
        if $VIVADO_CMD -mode batch \
            -source "$TCL_SCRIPT" \
            -tclargs $R $N \
            -log "$LOG_FILE" \
            -journal "$JOU_FILE" 2>&1 | tail -20; then
            echo "[OK] $CONFIG_NAME complete"
        else
            echo "[FAIL] $CONFIG_NAME failed"
            FAILED_CONFIGS+=("$CONFIG_NAME")
        fi
        
        echo ""
    done
    
    if [ ${#FAILED_CONFIGS[@]} -gt 0 ]; then
        echo "[WARN] Failed configurations:"
        for cfg in "${FAILED_CONFIGS[@]}"; do
            echo "  - $cfg"
        done
    fi
fi

# ---- Extract & Generate Table IV -------------------------------------------
echo "[INFO] Extracting metrics and generating Table IV..."
echo ""

if [ -f "$PY_SCRIPT" ]; then
    python3 "$PY_SCRIPT" "$SYNTH_DIR"
else
    echo "[WARN] Python script not found: $PY_SCRIPT"
    echo "       Run manually: python3 $PY_SCRIPT $SYNTH_DIR"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo "========================================================================="
echo "  SYNTHESIS COMPLETE"
echo "========================================================================="
echo "Metrics location: $SYNTH_DIR"
echo "Table IV output: $SYNTH_DIR/TABLE_IV.txt"
echo ""
echo "Results by configuration:"
echo ""

for config in "${CONFIGS[@]}"; do
    IFS=':' read -r R N <<< "$config"
    RESULT_DIR="$SYNTH_DIR/results_r${R}_n${N}"
    METRICS_FILE="$RESULT_DIR/metrics_raw.txt"
    
    if [ -f "$METRICS_FILE" ]; then
        echo "  R=$R, N=$N  ✓"
    else
        echo "  R=$R, N=$N  ✗"
    fi
done

echo ""
echo "Next steps:"
echo "  1. Review Table IV: $SYNTH_DIR/TABLE_IV.txt"
echo "  2. Check individual reports in: $SYNTH_DIR/results_r<R>_n<N>/"
echo ""

exit 0
