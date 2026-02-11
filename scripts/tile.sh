#!/bin/bash
# =============================================================================
# Cesium Terrain Tiling Script
# Converts Cloud Optimized GeoTIFFs (COGs) into static Quantized Mesh tiles.
# 
# Features:
# - Supports REGION environment variable for island-based partitioning.
# - Automatically creates VRT for seamless edge-stitching.
# - Robust file list handling for national-scale datasets.
#
# Usage: 
#   REGION=sulawesi podman compose -f docker-compose.tile.yml run --rm tile
#   (Default: bakes everything from /data/cogs into /data/tiles)
# =============================================================================

set -euo pipefail

# ---- Environment Configuration ----
REGION="${REGION:-}"
INPUT_BASE_DIR="/data/cogs"
OUTPUT_BASE_DIR="/data/tiles"
VRT_NAME="baking.vrt"
MAX_ZOOM=18

# ---- Memory Safety Limits (Prevent OOM) ----
# Aggressive memory constraints for stability
export GDAL_CACHEMAX=256       # Lower cache to 256MB
export GDAL_NUM_THREADS=1      # Force single-threaded GDAL
export OMP_NUM_THREADS=1       # Force single-threaded ctb-tile (critical for OOM)
export CPL_VSIL_CURL_ALLOWED_EXTENSIONS=.tif

# Ensure disk buffers are flushed before heavy lifting
sync # Optimization

# ---- Determine Paths based on REGION ----
if [ -n "$REGION" ]; then
    INPUT_DIR="${INPUT_BASE_DIR}/${REGION}"
    OUTPUT_DIR="${OUTPUT_BASE_DIR}/${REGION}"
    VRT_FILE="${OUTPUT_DIR}/${VRT_NAME}"
    echo "============================================="
    echo "  Regional Baking Mode: $REGION"
    echo "============================================="
else
    INPUT_DIR="$INPUT_BASE_DIR"
    OUTPUT_DIR="$OUTPUT_BASE_DIR"
    VRT_FILE="${OUTPUT_DIR}/${VRT_NAME}"
    echo "============================================="
    echo "  Global Baking Mode (Fallback)"
    echo "============================================="
fi

# ---- Input Validation ----
if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR: Input directory not found: $INPUT_DIR"
    exit 1
fi

TIFF_COUNT=$(find "$INPUT_DIR" -maxdepth 1 -name "*.tif" | wc -l)
if [ "$TIFF_COUNT" -eq 0 ]; then
    echo "ERROR: No COG files (*.tif) found in $INPUT_DIR"
    exit 1
fi

echo "Found $TIFF_COUNT file(s) in $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Maximum Zoom: $MAX_ZOOM"
echo "Running as: $(whoami) (UID: $(id -u))"

# ---- Ensure output directory exists (Robust Mode) ----
echo "Verifying output structure..."
if [ -e "/data/tiles" ] && [ ! -d "/data/tiles" ]; then
    echo "ERROR: /data/tiles exists but is not a directory. Removing it..."
    rm -rf "/data/tiles"
fi

mkdir -p "/data/tiles"
if [ ! -d "/data/tiles" ]; then
    echo "ERROR: Failed to create /data/tiles. Check permissions on host."
    ls -la /data
    exit 1
fi

echo "Creating regional directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: Failed to create $OUTPUT_DIR"
    ls -la /data/tiles
    exit 1
fi

# ---- Step 1: Create Virtual Mosaic (VRT) ----
# We use VRT even for single files to ensure consistent handling and metadata.
# This step is critical for edge-stitching within the region.
# No -tr flag: preserve native resolution from source DEMs.
# MAX_ZOOM (ctb-tile -s flag) is the hard cap that prevents zoom 19+ generation.
echo ""
echo "[1/3] Creating virtual mosaic index..."
find "$INPUT_DIR" -name "*.tif" > "/tmp/baking_list.txt"
gdalbuildvrt -input_file_list "/tmp/baking_list.txt" "$VRT_FILE"

# ---- Step 2: Generate Terrain Mesh Tiles ----
echo ""
echo "[2/3] Generating Quantized Mesh tiles..."
echo "      Progress:"
ctb-tile \
    -f Mesh \
    -s "$MAX_ZOOM" \
    -e 0 \
    -o "$OUTPUT_DIR" \
    "$VRT_FILE"

# ---- Step 3: Generate layer.json Metadata ----
echo ""
echo "[3/3] Generating layer.json metadata (Safe Mode)..."

# Note: We avoid 'ctb-tile -l' because it causes OOM on large datasets.
# Instead, we write a standard layer.json with global bounds.
# Cesium will try to load tiles and get 404s for empty areas, which is fine.

cat <<EOF > "$OUTPUT_DIR/layer.json"
{
  "tilejson": "2.1.0",
  "name": "terrain",
  "description": "Quantized Mesh Terrain",
  "version": "1.1.0",
  "format": "quantized-mesh-1.0",
  "scheme": "tms",
  "extensions": ["octvertexnormals", "watermask", "metadata"],
  "tiles": ["{z}/{x}/{y}.terrain"],
  "minzoom": 0,
  "maxzoom": $MAX_ZOOM,
  "bounds": [-180, -90, 180, 90],
  "projection": "EPSG:4326"
}
EOF

echo "  Generated static layer.json at $OUTPUT_DIR/layer.json"

# Cleanup temp files
rm -f "/tmp/baking_list.txt"
rm -f "$VRT_FILE"

echo ""
echo "============================================="
echo "  Baking Complete!"
echo "  Tiles: $OUTPUT_DIR"
if [ -n "$REGION" ]; then
    echo "  Access via: http://localhost:3333/tiles/$REGION/layer.json"
else
    echo "  Access via: http://localhost:3333/tiles/layer.json"
fi
echo "============================================="
