# DEM Server Quick Commands

Step-by-step commands for processing DEM data from source to serving.

---

## Prerequisites

```bash
cd /path/to/.dem-server
```

---

## 1. Add Source DEM Files

Place your GeoTIFF files in the source folder, organized by region:

```bash
# Create region folder (any name works)
mkdir -p data/source/sulawesi

# Copy your DEM files
cp /path/to/your/*.tif data/source/sulawesi/
```

**Region naming:**
- Region is just a folder name - use any name you want
- Backend scripts dynamically scan folders, no predefined list
- The test viewers have a hardcoded dropdown (Indonesia islands) - update `test/*.html` if you add new regions

**Predefined regions in test viewers:**
`sumatra`, `jawa`, `balinusra`, `kalimantan`, `sulawesi`, `maluku`, `papua`

**Check source resolution (optional):**
```bash
docker run --rm -v "./data:/data:ro" ghcr.io/osgeo/gdal:alpine-small-3.12.1 \
  gdalinfo /data/source/sulawesi/YOUR_FILE.tif | grep "Pixel Size"
```

---

## 2. Preprocess: Convert to COG

Converts raw GeoTIFFs to Cloud Optimized GeoTIFFs (COG):

```bash
docker compose -f docker-compose.preprocess.yml run --rm preprocess
```

**Output:** `data/cogs/[region]/` with optimized TIFFs

---

## 3. Generate Mosaic Index (for MapLibre/TiTiler)

Creates MosaicJSON for seamless tile serving:

```bash
# Single region
REGION=sulawesi docker compose -f docker-compose.preprocess.yml run --rm mosaic

# All regions (integrated)
docker compose -f docker-compose.preprocess.yml run --rm mosaic
```

**Output:** `data/mosaic_[region].json` or `data/mosaic.json`

---

## 4. Generate Terrain Tiles (for Cesium)

Converts COGs to Quantized Mesh tiles:

```bash
# Single region
REGION=sulawesi docker compose -f docker-compose.tile.yml run --rm tile

# All regions
docker compose -f docker-compose.tile.yml run --rm tile
```

**Output:** `data/tiles/[region]/` with zoom level folders (0-18) and `layer.json`

---

## 5. Start the Server

```bash
docker compose up -d
```

**Services:**
| Service | Port | Purpose |
|---------|------|---------|
| viewer-gateway | 3333 | Nginx hub, test pages, static tiles |
| png-terrain-server-hub | 8000 | TiTiler for MapLibre terrain-RGB |
| quantized-mesh-server-hub | 8001 | FastAPI for Cesium mesh tiles |

---

## 6. Test the Viewers

- **Cesium (3D mesh):** http://localhost:3333/cesium-terrain.html
- **MapLibre (terrain-RGB):** http://localhost:3333/maplibre-terrain.html

---

## 7. Pack Tiles for Deployment (Optional)

Create a single archive for easy transfer:

```bash
docker compose -f docker-compose.tile.yml run --rm pack
```

**Output:** `data/terrain_tiles.tar.gz`

---

## Full Pipeline (Single Region)

```bash
# Set region
export REGION=sulawesi

# 1. Preprocess (Convert to COG)
docker compose -f docker-compose.preprocess.yml run --rm preprocess

# 2. Mosaic index (Indexing the COGs)
REGION=$REGION docker compose -f docker-compose.preprocess.yml run --rm mosaic

# 3. Terrain tiles (Cesium Terrain Meshes)
REGION=$REGION docker compose -f docker-compose.tile.yml run --rm tile

# 4. Start server
docker compose up -d
```

---

## Useful Commands

**Check tile output:**
```bash
ls -la data/tiles/sulawesi/
cat data/tiles/sulawesi/layer.json
```

**Check COG info:**
```bash
docker run --rm -v "./data:/data:ro" ghcr.io/osgeo/gdal:alpine-small-3.12.1 \
  gdalinfo /data/cogs/sulawesi/YOUR_FILE.tif
```

**Clear and regenerate tiles:**
```bash
rm -rf data/tiles/sulawesi
REGION=sulawesi docker compose -f docker-compose.tile.yml run --rm tile
```

**View logs:**
```bash
docker compose logs -f
```

**Stop all services:**
```bash
docker compose down
```

---

## Configuration

See `DEM-Resolution-Quality.md` for:
- Zoom level reference table
- MAX_ZOOM settings per DEM source
- Files to update when changing DEM source
