# Implementation Plan: Zoom Level Hard-Cap (Level 18) - CORRECTED

## Problem
The tool was auto-detecting Level 19 because the 1m source data is slightly higher resolution than what Zoom 18 represents in WGS84. My previous "pruning" step was a temporary hack.

## Objective
Implement an engineering fix that prevents the tool from ever seeing Level 19 detail by capping the input resolution.

## Status: COMPLETED (Engineering Fix)

### 1. Update Baking Hub (`scripts/tile.sh`) - FIXED
- **Target Resolution Cap:** Updated `gdalbuildvrt` to use `-tr 0.0000105637` (Zoom 18 resolution).
- **Correct Flags:** Using `-s 18` (Start Zoom) and `-e 0` (End Zoom).
- **Removed Pruning:** Deleted the `rm -rf` pruning block. The tool now naturally stops at 18 because it thinks the source data ends there.

### 2. Verify Result
- Run a fresh bake. The tool will no longer even attempt to create a Level 19 folder.

---

# Implementation Plan: MapLibre Rendering & Artifact Fix

## Problem
1. **Floating Planes/Pillars:** Terrain drops to -10000m or shows flat planes at 0m in areas with no data, causing visual artifacts.
2. **Dimension Mismatch:** Discrepancy between server tile size and client expectation.
3. **Low-Zoom Noise:** Loading high-res terrain at national scales is unnecessary and causes artifacts.

## Objective
Implement strict zoom constraints and data normalization to ensure a clean, performant 3D experience.

## Status: UPDATED

### 1. Update Viewer Hub (`test/maplibre-terrain.html`) - FIXED
- **Strict 256px Sync:** Standardized all sources (`raster-dem`, `hillshade`, `slope`, `mlcontour`) to 256px.
- **MinZoom Hard-Cap:** Set `minzoom: 13` for all terrain layers.
  - **Why:** Terrain is now completely disabled at low zoom levels (Z0-12), eliminating "national-scale" pillars and the "floating plane" effect.
- **Elevation Normalization:** Added `nodata_height=0` to algorithm params to map null values to Sea Level (0m) instead of -10000m.

### 2. Backend Fixes - DONE
- **Clean Backend:** Reverted to the original high-performance TiTiler hub (removed problematic Python middleware).
- **Nginx Revert:** Reverted `nginx.conf` to its standard proxy state to avoid protocol errors with new Python versions.

### 3. Verification
- Imagery remains flat at low zooms (Z < 13).
- High-fidelity 1m terrain loads seamlessly when zooming into specific regions (Z >= 13).
- No console errors regarding dimensions or decoding at any zoom level.
