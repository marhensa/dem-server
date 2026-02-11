import os
import json
import logging
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, FileResponse
from starlette.middleware.cors import CORSMiddleware

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Quantized Mesh Server Hub")

# Enable CORS for CesiumJS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

TILES_ROOT = "/data/tiles"


def get_regional_layers():
    """Scans subdirectories for layer.json files."""
    layers = {}
    if not os.path.exists(TILES_ROOT):
        return layers

    for region in os.listdir(TILES_ROOT):
        region_path = os.path.join(TILES_ROOT, region)
        if not os.path.isdir(region_path):
            continue
        layer_file = os.path.join(region_path, "layer.json")
        if os.path.exists(layer_file):
            try:
                with open(layer_file, "r") as f:
                    layers[region] = json.load(f)
            except Exception as e:
                logger.error(f"Error reading layer.json for {region}: {e}")
    return layers


@app.get("/layer.json")
async def get_integrated_layer():
    """Composites regional layer.json files into a single metadata file with tight bounds."""
    regional_layers = get_regional_layers()

    if not regional_layers:
        raise HTTPException(status_code=404, detail="No regional terrain data found.")

    # Calculate tight union of actual data bounds
    tight_bounds = [180.0, 90.0, -180.0, -90.0]
    max_level = 0
    availability_by_level = {}

    for region, meta in regional_layers.items():
        if "bounds" in meta:
            b = meta["bounds"]
            # Detect and fix global hemisphere defaults from CTB (0, -90, 180, 90)
            if (b[0] == 0.0 and b[1] == -90.0) or (b[0] == -180.0 and b[1] == -90.0):
                if region == "sulawesi":
                    b = [124.91, 1.41, 124.96, 1.46]
                else:
                    continue  # Skip global bounds to prevent "Hollow Earth" masking

            tight_bounds[0] = min(tight_bounds[0], b[0])
            tight_bounds[1] = min(tight_bounds[1], b[1])
            tight_bounds[2] = max(tight_bounds[2], b[2])
            tight_bounds[3] = max(tight_bounds[3], b[3])

        # Merge availability
        if "available" in meta:
            for level, ranges in enumerate(meta["available"]):
                if level not in availability_by_level:
                    availability_by_level[level] = []
                availability_by_level[level].extend(ranges)
                max_level = max(max_level, level)

    # Reconstruct unified availability
    available_list = [availability_by_level.get(l, []) for l in range(max_level + 1)]

    # Final metadata
    integrated_layer = {
        "tilejson": "2.1.0",
        "name": "Integrated DEM Terrain",
        "description": "Unified Mesh Terrain Hub",
        "version": "1.1.0",
        "format": "quantized-mesh-1.0",
        "attribution": "Integrated DEM Server",
        "scheme": "tms",
        "tiles": ["{z}/{x}/{y}.terrain?v={version}"],
        "projection": "EPSG:4326",
        # CRITICAL: Tight bounds tell Cesium to only use our hub for high-res areas
        "bounds": tight_bounds,
        "available": available_list,
    }

    sample = list(regional_layers.values())[0]
    if "extensions" in sample:
        integrated_layer["extensions"] = sample["extensions"]
    if "metadata" in sample:
        integrated_layer["metadata"] = sample["metadata"]

    return integrated_layer


@app.get("/{z}/{x}/{y}.terrain")
async def get_tile(z: int, x: int, y: int, v: str = ""):
    """Routes tile requests to the correct regional folder.
    Note: Since scheme is 'tms' in layer.json, Y is already TMS-ordered.
    """
    if not os.path.exists(TILES_ROOT):
        raise HTTPException(status_code=404)

    for region in os.listdir(TILES_ROOT):
        region_path = os.path.join(TILES_ROOT, region)
        tile_file = os.path.join(region_path, str(z), str(x), f"{y}.terrain")

        if os.path.exists(tile_file):
            return FileResponse(
                tile_file,
                media_type="application/octet-stream",
                headers={"Content-Encoding": "gzip"},
            )

    raise HTTPException(status_code=404)


@app.get("/{region}/layer.json")
async def get_region_metadata(region: str):
    path = os.path.join(TILES_ROOT, region, "layer.json")
    if os.path.exists(path):
        return FileResponse(path)
    raise HTTPException(status_code=404)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8001)
