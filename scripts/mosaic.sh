#!/bin/bash
# =============================================================================
# MosaicJSON Generation Script (Regional Aware)
# Creates a spatial index for COGs in data/cogs/
#
# Usage:
#   REGION=sulawesi podman compose -f docker-compose.preprocess.yml run --rm mosaic
#   (Outputs: data/mosaic_sulawesi.json)
#
#   podman compose -f docker-compose.preprocess.yml run --rm mosaic
#   (Outputs: data/mosaic.json - indexes everything)
# =============================================================================

set -euo pipefail

REGION="${REGION:-}"
INPUT_BASE_DIR="/data/cogs"

# ---- Determine Paths based on REGION ----
if [ -n "$REGION" ]; then
    INPUT_DIR="${INPUT_BASE_DIR}/${REGION}"
    OUTPUT_FILE="/data/mosaic_${REGION}.json"
    echo "============================================="
    echo "  Regional Mosaic Mode: $REGION"
    echo "============================================="
else
    INPUT_DIR="$INPUT_BASE_DIR"
    OUTPUT_FILE="/data/mosaic.json"
    echo "============================================="
    echo "  Global Mosaic Mode (Full Index)"
    echo "============================================="
fi

# ---- Check for COGs ----
if [ ! -d "$INPUT_DIR" ] || [ -z "$(find "$INPUT_DIR" -name "*.tif" -print -quit)" ]; then
    echo "ERROR: No COGs found in $INPUT_DIR"
    exit 1
fi

# ---- Install cogeo-mosaic if not present ----
if ! command -v cogeo-mosaic &> /dev/null; then
    echo "Installing cogeo-mosaic..."
    pip install -q cogeo-mosaic
fi

echo "Indexing COGs in $INPUT_DIR (absolute paths)..."
# Use absolute container paths to ensure TiTiler can resolve them correctly
find "$INPUT_DIR" -name "*.tif" > /tmp/file_list.txt

# Generate the mosaic with explicit minzoom 0 and maxzoom 18
# minzoom 0 is critical to ensure TiTiler provides low-zoom overviews and avoids 204 errors
cogeo-mosaic create /tmp/file_list.txt -o "$OUTPUT_FILE" --minzoom 0 --maxzoom 18 --quiet

echo "============================================="
echo "  MosaicJSON ready: $OUTPUT_FILE"
echo "  TiTiler endpoint: /titiler/mosaic/info?url=$OUTPUT_FILE"
echo "============================================="
