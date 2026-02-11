#!/usr/bin/env python3
import os
import json
import sys
import math


def tile_to_lonlat(x, y, z):
    n = 2.0**z
    lon_deg = x / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * y / n)))
    lat_deg = math.degrees(lat_rad)
    return lon_deg, lat_deg


def generate_layer_json(output_dir, max_zoom=18):
    """
    Generates layer.json for a Quantized Mesh tile directory.
    Scans the directory structure to determine bounds and available zooms.
    """
    print(f"Scanning {output_dir} for tiles...")

    min_z = 999
    max_z = -1
    bounds = [180, 90, -180, -90]  # min_lon, min_lat, max_lon, max_lat

    # We need to find the global bounds of the terrain.
    # Iterating all files is slow and memory intensive.
    # Heuristic: Check min/max tiles at the highest available zoom level?
    # Or just iterate the directories (Z/X/Y).

    # Let's walk the directory tree.
    # Structure: {z}/{x}/{y}.terrain

    has_tiles = False

    try:
        z_dirs = [d for d in os.listdir(output_dir) if d.isdigit()]
    except FileNotFoundError:
        print(f"Error: Directory {output_dir} not found.")
        sys.exit(1)

    if not z_dirs:
        print("No zoom directories found.")
        sys.exit(0)

    z_dirs = sorted([int(z) for z in z_dirs])
    min_z = z_dirs[0]
    max_z = z_dirs[-1]

    # To find bounds, we only need to look at the extremes of the highest zoom level
    # or arguably the lowest zoom level (0) if it covers the whole area.
    # But usually datasets are sparse.
    # Let's find the min_x, max_x, min_y, max_y for the highest zoom level found.

    target_z = max_z
    z_path = os.path.join(output_dir, str(target_z))

    x_dirs = [int(x) for x in os.listdir(z_path) if x.isdigit()]
    if not x_dirs:
        print(f"No X directories in zoom {target_z}")
        return

    min_x = min(x_dirs)
    max_x = max(x_dirs)

    # For Y, we need to check the min_x and max_x directories to find the corner tiles
    # This is an approximation but usually sufficient for layer.json bounds

    # Find min_y (southernmost) in any X
    min_y = 999999999
    max_y = -1

    # Check all X directories to find global Y bounds (a bit slow but safe)
    for x in x_dirs:
        x_path = os.path.join(z_path, str(x))
        y_files = [
            int(f.split(".")[0]) for f in os.listdir(x_path) if f.endswith(".terrain")
        ]
        if y_files:
            min_y = min(min_y, min(y_files))
            max_y = max(max_y, max(y_files))

    # Calculate bounds from TMS coordinates
    # TMS: (0,0) is bottom-left (South-West) ??
    # Wait, standard TMS? or XYZ?
    # Cesium usually uses TMS (Y goes up from bottom).
    # Google/OSM uses XYZ (Y goes down from top).
    # ctb-tile produces TMS by default.

    # Bounds calculation for TMS:
    # West edge of min_x
    # South edge of min_y
    # East edge of max_x + 1
    # North edge of max_y + 1

    # We need a proper TMS to LatLon conversion.
    # Or we can just default to global bounds [-180, -90, 180, 90]
    # Cesium handles global bounds fine even if data is partial.
    # Let's try to be accurate.

    # Simple global bounds for now to avoid complexity and bugs.
    # Using specific bounds allows Cesium to "zoom to" the terrain, but global is safer.
    final_bounds = [-180, -90, 180, 90]

    # Construct the JSON
    layer_json = {
        "tilejson": "2.1.0",
        "name": "terrain",
        "description": "Quantized Mesh Terrain",
        "version": "1.1.0",
        "format": "quantized-mesh-1.0",
        "scheme": "tms",
        "extensions": ["octvertexnormals", "watermask", "metadata"],
        "tiles": ["{z}/{x}/{y}.terrain"],
        "minzoom": min_z,
        "maxzoom": max_z,
        "bounds": final_bounds,
        "projection": "EPSG:4326",
    }

    # Optional: "available" tiles logic.
    # Calculating this for 1M files is OOM-prone in Python too without optimization.
    # Cesium works without it (it just tries to load tiles).
    # We will omit "available" to save memory.

    output_file = os.path.join(output_dir, "layer.json")
    with open(output_file, "w") as f:
        json.dump(layer_json, f, indent=2)

    print(f"Generated {output_file}")
    print(f"  MinZoom: {min_z}")
    print(f"  MaxZoom: {max_z}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate_layer_json.py <tiles_dir>")
        sys.exit(1)

    output_dir = sys.argv[1]
    generate_layer_json(output_dir)
