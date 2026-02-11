#!/bin/bash
# =============================================================================
# DEM Preprocessing Script (Batch Mode - Recursive)
# Converts each NLP GeoTIFF/BIL in data/source/ into a Cloud Optimized GeoTIFF (COG)
# logic: 1:1 conversion (NLP TIF/BIL -> NLP COG) mirroring directory structure.
#
# This script runs inside a GDAL Docker container.
# Usage: docker compose -f docker-compose.preprocess.yml run --rm preprocess
# =============================================================================

set -euo pipefail

SOURCE_DIR="/data/source"
OUTPUT_DIR="/data/cogs"

echo "============================================="
echo "  DEM Batch Preprocessing: NLP TIF/BIL -> COG"
echo "============================================="

# ---- Check for source files ----
TIFF_COUNT=$(find "$SOURCE_DIR" \( -name "*.tif" -o -name "*.tiff" -o -name "*.bil" \) 2>/dev/null | wc -l)
if [ "$TIFF_COUNT" -eq 0 ]; then
    echo ""
    echo "ERROR: No .tif/.tiff/.bil files found in $SOURCE_DIR"
    echo "       Place your NLP Grid TIFF/BIL files in data/source/ and try again."
    exit 1
fi

echo ""
echo "Found $TIFF_COUNT source file(s). Starting batch conversion..."

# ---- Process each file ----
# Use find to handle subdirectories and spaces
find "$SOURCE_DIR" \( -name "*.tif" -o -name "*.tiff" -o -name "*.bil" \) -print0 | while IFS= read -r -d '' INPUT_FILE; do
    # Calculate relative path to source root to mirror folder structure
    FILE_PATH="${INPUT_FILE#$SOURCE_DIR/}"
    DIR_PATH=$(dirname "$FILE_PATH")
    FILENAME=$(basename "$FILE_PATH")
    BASENAME="${FILENAME%.*}"
    
    # Check for BIL companion files
    if [[ "${FILENAME##*.}" == "bil" ]]; then
        if [ ! -f "${INPUT_FILE%.*}.hdr" ]; then
            echo "  - ERROR: Missing .hdr file! BIL format requires a companion .hdr file. Skipping $FILENAME"
            continue
        fi
        if [ ! -f "${INPUT_FILE%.*}.prj" ]; then
            echo "  - ERROR: Missing .prj file! BIL format requires a companion .prj file. Skipping $FILENAME"
            continue
        fi
    fi
    
    # Ensure output subdirectory exists
    mkdir -p "${OUTPUT_DIR}/${DIR_PATH}"
    
    OUTPUT_FILE="${OUTPUT_DIR}/${DIR_PATH}/${BASENAME}.tif"
    TEMP_FILE="${OUTPUT_DIR}/${DIR_PATH}/${BASENAME}_filled.tif"
    
    echo "---------------------------------------------"
    echo "Processing: $FILE_PATH"
    
    # Check if COG already exists
    if [ -f "$OUTPUT_FILE" ]; then
        echo "  - SKIP: $OUTPUT_FILE already exists."
        continue
    fi

    # Step 1: Replace NoData with 0 (sea level)
    echo "  - Filling NoData (-32767 -> 0)..."
    gdalwarp \
        -srcnodata "-32767" \
        -dstnodata "0" \
        -overwrite \
        -q \
        "$INPUT_FILE" \
        "$TEMP_FILE"

    # Step 2: Convert to Cloud Optimized GeoTIFF
    echo "  - Converting to COG..."
    gdal_translate \
        -q \
        -of COG \
        -co COMPRESS=DEFLATE \
        -co PREDICTOR=2 \
        -co OVERVIEW_RESAMPLING=BILINEAR \
        -co NUM_THREADS=ALL_CPUS \
        -a_nodata 0 \
        "$TEMP_FILE" \
        "$OUTPUT_FILE"

    # Cleanup temp file
    rm -f "$TEMP_FILE"
    
    echo "  - DONE: $(du -h "$OUTPUT_FILE" | cut -f1)"
done

echo ""
echo "============================================="
echo "  Batch Processing Complete."
echo "  COGs available in: $OUTPUT_DIR"
echo "============================================="
