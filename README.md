# Integrated DEM Server

> **Pipeline Integration by [Marhensa Aditya Hadi](https://github.com/marhensa)**
> 
> This project combines multiple open-source tools into a unified DEM serving infrastructure.
> Licensed under MIT. Individual container images retain their original licenses.

A high-performance, large-scale pipeline for serving high-resolution (1m) Digital Elevation Models (DEM) to modern web mapping platforms. This infrastructure implements a **Unified Terrain Hub** architecture that serves regional datasets from a single set of endpoints with zero data duplication.

## Architecture (Unified Terrain Hub)

The system is designed to handle the "Billions of Files" problem inherent in 1m national coverage by using specialized **Middleware Hubs** that aggregate modular, island-based storage into unified web streams.

```
             [Official NLP Grid TIFFs]
                        │
    ┌───────────────────┴──────────────────┐
    ▼                                      ▼
[ArcGIS Image Server]               [Batch Preprocessing]
  Existing Server                      (GDAL Tool)
           │                               │
    ┌──────┴───────┐                       ▼
    ▼              ▼               [National NLP-COGs]
[ArcGIS / QGIS]  [JS Sharp]          (Object Storage)
(Desktop GIS)     (Proxy)                  │
                   │       ┌───────────────┴───────────────┐
                   │       ▼                               ▼
                   │ [PNG Terrain Hub]           [Baking Tool (CTB)]
                   │ (TiTiler + Mosaic)           (One-time Process)
                   │       │                               │
                   │       │                               ▼
                   │       │                     [Mesh Terrain Hub]
                   │       │                    (Virtual Compositor)
                   │       │                               │
                   │       └───────────────┬───────────────┘
                   │                       ▼
                   │            [Viewer Gateway (Nginx)]
                   │                       │
                   └───────┐       ┌───────┴───────┐
                           ▼       ▼               ▼
                   [MapLibre/Leaflet]          [CesiumJS]
                    (Dynamic PNG)        (Unified Mesh Terrain)
```

### Key Components

| Service | Container | Responsibility |
| :--- | :--- | :--- |
| **PNG Hub** | `png-terrain-server-hub` | Serves seamless Terrain-RGB PNGs using **MosaicJSON**. It virtually "stitches" thousands of NLP grid sheets on-the-fly. |
| **Mesh Hub** | `quantized-mesh-server-hub` | A **Virtual Mesh Compositor** (Python) that aggregates modular regional bakes into a single unified Mesh endpoint for CesiumJS. |
| **Gateway** | `viewer-gateway` | The Nginx entry point (port 3333) that routes all traffic to the hubs and serves the unified viewers. |
| **Sharp Proxy** | (External) | A developer-managed Node.js proxy that translates ArcGIS ImageServer LERC/PNG tiles into Terrain-RGB for MapLibre/Leaflet. |

---

## ArcGIS & Desktop Integration

The **ArcGIS Image Server** remains the official **Existing Server** for governance and high-end analysis in **ArcGIS / QGIS**. This DEM-Server infrastructure acts as the **High-Performance Delivery Layer** specifically optimized for modern web and mobile applications.

---

## Quick Start

See **[QUICK-COMMANDS.md](QUICK-COMMANDS.md)** for full step-by-step commands.

For resolution settings and zoom level configuration, see **[DEM-Resolution-Quality.md](DEM-Resolution-Quality.md)**.

### 1. Ingest Data
Organize your raw NLP TIFFs by island/region in `data/source/`:
```bash
data/source/sulawesi/*.tif
data/source/jawa/*.tif
data/source/sumatra/*.tif
```

### 2. Preprocess (NLP -> COG)
Convert raw files to Cloud Optimized GeoTIFFs (COG). This step replaces NoData (-32767) with 0 and creates a parallel mirrored archive in `data/cogs/` (recursive support):
```bash
podman compose -f docker-compose.preprocess.yml run --rm preprocess
```

### 3. Generate Unified Hub Index
Create a single `mosaic.json` that indexes every regional COG across all subfolders:
```bash
podman compose -f docker-compose.preprocess.yml run --rm mosaic
```

### 4. Bake Regional Mesh
Bake the 3D geometry **once per region**. The Mesh Hub will automatically detect and composite these regional folders:
```bash
REGION=sulawesi podman compose -f docker-compose.tile.yml run --rm tile
```

### 5. Start Infrastructure
```bash
podman compose up -d
```

---

## Large-Scale Infrastructure Analysis

Indonesia's 1.9M km² landmass at 1m resolution presents unique engineering challenges. This infrastructure uses a **Bake Once, Serve All** logic to avoid data duplication and filesystem degradation.

### The Numbers (Indonesia 1m DTM)

| Scenario | Land Area | Pixels | Raw Size (Float32) | Estimated COG | File Count (Z18) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Manado POC** | ~20 km² | ~23 million | ~90 MB | 38 MB | ~15,000 |
| **Sulawesi Utara** | ~13,800 km² | ~14 billion | ~55 GB | ~25 GB | ~8,000,000 |
| **Jawa Island** | ~129,000 km² | ~129 billion | ~516 GB | ~200 GB | ~80,000,000 |
| **National Total** | **~1,900,000 km²** | **~1.9 trillion** | **~7.6 TB** | **~3 TB** | **~1.2 Billion** |

### Why COG (Cloud Optimized GeoTIFF)?

The "Estimated COG" column shows **~40-60% size reduction** compared to raw Float32. This is achieved through:

| Feature | Benefit |
| :--- | :--- |
| **DEFLATE Compression** | Lossless compression, no data loss |
| **PREDICTOR=2** | Horizontal differencing optimized for continuous elevation data |
| **Still Float32** | Full precision preserved - this is NOT lossy conversion |
| **HTTP Range Requests** | Stream only the bytes needed, no full file download |
| **Built-in Overviews** | Fast zoom-out without separate pyramid files |
| **Single File** | No tile pyramid folder management, works with S3/object storage |

**Downsides?** Minimal:
- Slightly higher CPU for decompression (negligible on modern hardware)
- One-time conversion cost (handled by `preprocess.sh`)

**Bottom line:** COG gives you smaller storage, faster streaming, and cloud-native compatibility with zero quality loss. Use it.

### How Quantized Mesh Works (CTB Pipeline)

This infrastructure uses **Cesium Terrain Builder (CTB)** by [TUM-GIS](https://github.com/tum-gis/cesium-terrain-builder) to convert raster DEMs into **Quantized Mesh** tiles for CesiumJS. The Docker image `tumgis/ctb-quantized-mesh` provides the `ctb-tile` command.

#### What is CTB (Cesium Terrain Builder)?

**Cesium Terrain Builder (CTB)** is an open-source C++ command-line tool that converts raster elevation data (GeoTIFF, VRT, etc.) into tiled terrain formats consumable by CesiumJS. It was originally developed by Homme Zwaagstra at the British Geological Survey, later maintained and containerized by the Technical University of Munich (TUM-GIS).

**Key facts:**

| Property | Value |
| :--- | :--- |
| **Language** | C++ with GDAL bindings |
| **License** | Apache 2.0 |
| **Input** | Any GDAL-readable raster (GeoTIFF, VRT, HFA, etc.) |
| **Output** | Quantized Mesh tiles (`.terrain`) or Heightmap tiles (PNG) |
| **Docker Image** | `tumgis/ctb-quantized-mesh:latest` |
| **Commands** | `ctb-tile` (generate tiles), `ctb-export` (export heightmaps) |

**Why do we need CTB?**

CesiumJS cannot directly consume GeoTIFF or COG files for 3D terrain rendering. The browser needs:
1. **Pre-tiled data** - Millions of small files organized in `{z}/{x}/{y}` pyramid
2. **Binary mesh format** - Triangulated geometry, not raster pixels
3. **Metadata** - `layer.json` describing available zoom levels and bounds

CTB performs this one-time "baking" process, converting continuous raster elevation into discrete mesh tiles.

#### DEM Files vs Terrain Tiles: Fundamental Difference

A **DEM file** (Digital Elevation Model) and **Terrain Tiles** serve completely different purposes in the geospatial stack:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DEM FILE (GeoTIFF/COG)                              │
│                                                                             │
│   • Single continuous raster file                                          │
│   • Each pixel = one elevation value (Float32 or Int16)                    │
│   • Georeferenced with coordinate system metadata                          │
│   • Used for: GIS analysis, watershed modeling, slope calculation          │
│   • Accessed by: GDAL, QGIS, ArcGIS, Python/rasterio                       │
│   • Size: 1 file, megabytes to gigabytes                                   │
│                                                                             │
│   Example: DTM_Sulawesi_1m.tif (500 MB, 25000×20000 pixels)                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │  ctb-tile (one-time conversion)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      TERRAIN TILES (Quantized Mesh)                         │
│                                                                             │
│   • Millions of small binary files in {z}/{x}/{y}.terrain pyramid          │
│   • Each tile = triangulated 3D mesh (vertices + indices)                  │
│   • Tiled in TMS/WMTS scheme for efficient streaming                       │
│   • Used for: 3D globe visualization in web browsers                       │
│   • Accessed by: CesiumJS, Cesium for Unreal, deck.gl                      │
│   • Size: Millions of files, 1-50 KB each                                  │
│                                                                             │
│   Example: tiles/sulawesi/14/8234/5621.terrain (12 KB, ~500 triangles)     │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key differences:**

| Aspect | DEM File (GeoTIFF/COG) | Terrain Tiles (Quantized Mesh) |
| :--- | :--- | :--- |
| **Structure** | Single continuous raster | Millions of tiled mesh files |
| **Data model** | Regular grid of elevation pixels | Irregular triangulated mesh per tile |
| **Coordinates** | Geographic (lat/lon) or projected | Quantized 0-32767 relative to tile |
| **Precision** | Full Float32 (7 decimal digits) | Quantized uint16 (sufficient for rendering) |
| **File size** | Large (MB-GB per file) | Small (1-50 KB per tile) |
| **Access pattern** | Random access via GDAL | Sequential streaming via HTTP |
| **Use case** | Analysis, processing, derivation | Visualization, rendering |
| **Can browser use it?** | No (needs server-side processing) | Yes (direct GPU consumption) |
| **Updatable** | Edit single file | Regenerate affected tiles |

**Why can't CesiumJS just use GeoTIFF directly?**

1. **File size** - A 1m national DEM could be 3+ TB. Browsers can't load this.
2. **No LOD** - GeoTIFF has no built-in level-of-detail. You'd load full resolution even when zoomed out.
3. **Raster vs Mesh** - GPUs render triangles, not pixels. Converting raster→mesh at runtime is too slow.
4. **No streaming** - GeoTIFF requires GDAL library. Browsers have no native GDAL support.

**The solution:** Pre-bake the DEM into a tile pyramid where each zoom level has appropriately simplified meshes. This is what CTB does.

#### How CTB-tile Works Internally

When you run `ctb-tile -f Mesh`, here's what happens for each output tile:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 1: Tile Bounds Calculation                                            │
│                                                                             │
│  For tile (z=14, x=8234, y=5621):                                          │
│  • Calculate geographic bounds from TMS grid                                │
│  • West: 124.5°, South: 1.2°, East: 124.522°, North: 1.222°                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 2: Raster Sampling                                                    │
│                                                                             │
│  • Read elevation values from source DEM within tile bounds                 │
│  • Resample to appropriate resolution for this zoom level                   │
│  • Handle NoData values (replace with 0 or interpolate)                     │
│  • Result: Regular grid of elevation samples (e.g., 65×65 points)          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 3: TIN Generation (Triangulated Irregular Network)                    │
│                                                                             │
│  • Apply mesh simplification algorithm (Ramer-Douglas-Peucker variant)      │
│  • Remove vertices where terrain is "flat enough" (within error threshold)  │
│  • Keep more vertices on steep slopes, ridges, valleys                      │
│  • Generate triangle indices via Delaunay triangulation                     │
│  • Result: Optimized mesh with 100-2000 triangles (varies by terrain)       │
│                                                                             │
│  Flat area:          Steep slope:                                           │
│  ┌─────────┐         ┌─────────┐                                           │
│  │ ╲     ╱ │         │╲│╲│╲│╲│ │                                           │
│  │   ╲ ╱   │         │─┼─┼─┼─┤ │  ← More triangles where                   │
│  │   ╱ ╲   │         │╱│╱│╱│╱│ │    terrain changes rapidly                │
│  │ ╱     ╲ │         │─┼─┼─┼─┤ │                                           │
│  └─────────┘         └─────────┘                                           │
│  (4 triangles)       (32 triangles)                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 4: Quantization                                                       │
│                                                                             │
│  • Convert vertex positions from float64 world coords to uint16 tile coords │
│  • X: longitude → 0-32767 (west edge = 0, east edge = 32767)               │
│  • Y: latitude  → 0-32767 (south edge = 0, north edge = 32767)             │
│  • Z: elevation → 0-32767 (min height = 0, max height = 32767)             │
│  • Apply zigzag encoding: value → (value << 1) ^ (value >> 15)             │
│  • Apply delta encoding: store difference from previous value               │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 5: Edge Extraction                                                    │
│                                                                             │
│  • Identify vertices that lie exactly on tile boundaries                    │
│  • Store indices of west/south/east/north edge vertices separately          │
│  • CesiumJS uses these to stitch adjacent tiles without cracks              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 6: Binary Serialization + Compression                                 │
│                                                                             │
│  • Write header: tile center (ECEF), bounding sphere, height range          │
│  • Write vertex buffers: u[], v[], height[] (all delta+zigzag encoded)     │
│  • Write triangle indices (high-water mark encoded)                         │
│  • Write edge indices                                                       │
│  • Gzip compress entire payload                                             │
│  • Save as {z}/{x}/{y}.terrain                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Performance characteristics:**

| Metric | Typical Value |
| :--- | :--- |
| Processing speed | ~1000-5000 tiles/second (depends on zoom level) |
| Output tile size | 1-50 KB (gzip compressed) |
| Triangles per tile | 100-2000 (adaptive to terrain) |
| Memory usage | ~2-4 GB for national-scale processing |

#### Conversion Pipeline

```
┌─────────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│    Source COGs      │      │     VRT Mosaic      │      │      ctb-tile       │
│  (Float32 raster)   │ ───▶ │  (Virtual index)    │ ───▶ │    -f Mesh -s 18    │
│  data/cogs/*.tif    │      │  gdalbuildvrt       │      │                     │
└─────────────────────┘      └─────────────────────┘      └──────────┬──────────┘
                                                                     │
         ┌───────────────────────────────────────────────────────────┘
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Quantized Mesh Output                                │
│  data/tiles/{region}/                                                       │
│  ├── layer.json          (Metadata: bounds, available zooms, format)       │
│  ├── 0/0/0.terrain       (Zoom 0: 1 tile, entire region)                   │
│  ├── 1/...               (Zoom 1: up to 4 tiles)                           │
│  ├── ...                                                                    │
│  └── 18/{x}/{y}.terrain  (Zoom 18: ~1.19m/pixel, millions of tiles)        │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Pipeline steps in `tile.sh`:**

| Step | Command | Purpose |
| :--- | :--- | :--- |
| 1 | `gdalbuildvrt` | Creates virtual mosaic from all COGs - enables seamless edge-stitching without copying data |
| 2 | `ctb-tile -f Mesh -s 18` | Generates TIN mesh tiles for zoom levels 0-18 |
| 3 | `ctb-tile -f Mesh -l` | Generates `layer.json` metadata for CesiumJS |

#### What is Quantized Mesh?

Quantized Mesh is a **binary terrain format** designed by Cesium for efficient 3D globe rendering. Unlike Terrain-RGB (which stores elevation as rasterized pixels), Quantized Mesh stores **actual 3D geometry**.

**Key characteristics:**

| Feature | Technical Detail | Benefit |
| :--- | :--- | :--- |
| **Quantization** | Vertex XYZ stored as `uint16` (0-32767) relative to tile bounding box, not `float64` world coordinates | ~75% smaller than raw coordinates |
| **TIN Meshing** | Triangulated Irregular Network - triangle density adapts to terrain complexity | More triangles on slopes, fewer on flat areas |
| **Delta Encoding** | Triangle indices use high-water mark encoding: each index stored as delta from running max | Smaller integers = better compression |
| **Edge Vertices** | Boundary vertices stored separately (west/south/east/north edge arrays) | Enables crack-free stitching between tiles |
| **Vertex Normals** | Optional `Oct16` encoded normals (2 bytes per vertex) | GPU lighting without runtime calculation |
| **Extensions** | Supports metadata, water mask, and custom extensions | Future-proof format |

#### Binary Structure (`.terrain` file)

Each `.terrain` file is a gzip-compressed binary with this structure:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         HEADER (88 bytes)                           │
├─────────────────────────────────────────────────────────────────────┤
│ CenterX, CenterY, CenterZ    (3 × float64)  Tile center in ECEF     │
│ MinimumHeight, MaximumHeight (2 × float32)  Elevation range         │
│ BoundingSphereCenterX/Y/Z    (3 × float64)  For frustum culling     │
│ BoundingSphereRadius         (1 × float64)                          │
│ HorizonOcclusionPointX/Y/Z   (3 × float64)  For horizon culling     │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│                      VERTEX DATA (variable)                         │
├─────────────────────────────────────────────────────────────────────┤
│ vertexCount                  (uint32)       Number of vertices      │
│ uBuffer[vertexCount]         (uint16[])     X positions (quantized) │
│ vBuffer[vertexCount]         (uint16[])     Y positions (quantized) │
│ heightBuffer[vertexCount]    (uint16[])     Z heights (quantized)   │
│                              ↑ All zigzag + delta encoded           │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│                     INDEX DATA (variable)                           │
├─────────────────────────────────────────────────────────────────────┤
│ triangleCount                (uint32)       Number of triangles     │
│ indices[triangleCount × 3]   (uint16/32[])  High-water encoded      │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│                    EDGE INDICES (variable)                          │
├─────────────────────────────────────────────────────────────────────┤
│ westVertexCount + indices    West edge vertices for stitching       │
│ southVertexCount + indices   South edge vertices                    │
│ eastVertexCount + indices    East edge vertices                     │
│ northVertexCount + indices   North edge vertices                    │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│                     EXTENSIONS (optional)                           │
├─────────────────────────────────────────────────────────────────────┤
│ Oct-Encoded Vertex Normals   (if requestVertexNormals: true)        │
│ Water Mask                   (if requestWaterMask: true)            │
│ Metadata                     (custom JSON payload)                  │
└─────────────────────────────────────────────────────────────────────┘
```

#### Quantized Mesh vs Terrain-RGB

| Aspect | Quantized Mesh (Cesium) | Terrain-RGB (MapLibre) |
| :--- | :--- | :--- |
| **Data type** | 3D geometry (vertices + triangles) | 2D heightmap (256×256 pixels) |
| **Precision** | Variable - adapts to terrain | Fixed - 1 sample per pixel |
| **File format** | Binary `.terrain` (gzip) | PNG image |
| **Rendering** | Direct GPU mesh rendering | Shader-based displacement |
| **Steep terrain** | More triangles where needed | Same resolution everywhere |
| **Flat terrain** | Fewer triangles (efficient) | Same resolution (wasteful) |
| **Tile size** | Variable (1KB - 50KB typical) | Fixed (~30KB for 256px PNG) |
| **Edge handling** | Built-in edge vertices | Requires 1px overlap |
| **Best for** | True 3D, flight simulation | 2.5D maps, overlays |

#### CTB Command Reference

The `ctb-tile` command used in `tile.sh`:

```bash
ctb-tile \
    -f Mesh \        # Output format: "Mesh" for Quantized Mesh
    -s 18 \          # Stop zoom level (max zoom to generate)
    -e 0 \           # Start zoom level (min zoom)
    -o /data/tiles \ # Output directory
    input.vrt        # Input raster (VRT or GeoTIFF)
```

**Key flags:**

| Flag | Description | Default |
| :--- | :--- | :--- |
| `-f Mesh` | Output format (Mesh = Quantized Mesh, Terrain = heightmap PNG) | Terrain |
| `-s <zoom>` | Maximum zoom level to generate | Auto-calculated |
| `-e <zoom>` | Minimum zoom level | 0 |
| `-l` | Generate `layer.json` only (no tiles) | - |
| `-n` | Generate vertex normals for lighting | Off |
| `-C` | Compression (gzip level 0-9) | 6 |

**Resolution capping:** The `-s` flag is the **hard cap** that prevents generating zoom levels beyond your DEM's native resolution. For 1m DEMs, zoom 18 (~1.19m/pixel) is the engineering sweet spot. See `DEM-Resolution-Quality.md` for the zoom level reference table.

### Why the Virtual Hub Architecture?
- **Filesystem Integrity:** Storing 1.2 billion files in a single folder would break standard OS file descriptors. We keep them in modular regional folders.
- **Zero Redundancy:** The "Virtual Compositor" logic in the Mesh Hub means you never need a "Global Bake." Regional bakes are stitched in memory at request-time.
- **Atomic Updates:** Updating a single NLP grid sheet only requires re-processing that 25MB file, not the 3TB total archive.
- **Optimized Zoom:** The system is strictly capped at **Zoom Level 18**. For 1m resolution data, this is the engineering "sweet spot"—providing maximum visual fidelity without the exponential storage waste of Level 19.

---

## Choosing Between MapLibre and Cesium

This infrastructure supports both **MapLibre GL JS** and **CesiumJS** for 3D terrain visualization. Both display the same DEM data through different rendering pipelines.

### Quick Comparison

| Feature | MapLibre GL JS | CesiumJS |
| :--- | :--- | :--- |
| **Rendering** | 2.5D map + globe mode (v3+) | True 3D globe |
| **Projection** | Web Mercator, Globe (v3+) | WGS84 ellipsoid |
| **Terrain Format** | Terrain-RGB PNG (raster-dem) | Quantized Mesh (binary) |
| **Bundle Size** | ~200 KB | ~2+ MB |
| **Performance** | Lighter, faster load | Heavier, more GPU intensive |
| **Camera** | Top-down with tilt, globe orbit | Free-flight, orbit, first-person |
| **Best For** | Web maps, mobile apps | Flight simulators, complex 3D scenes |

### When to Use MapLibre

- **2D/2.5D mapping** with terrain as enhancement
- **Globe view** with simpler setup (v3+ globe projection)
- **Mobile-first** applications where bundle size matters
- **Existing Mapbox/MapLibre** ecosystem integration
- **Dynamic overlays** - contours, hillshade, slope analysis as styled layers
- **Simpler deployment** - just PNG tiles, no special binary format

### When to Use Cesium

- **Advanced 3D navigation** - first-person, flight simulation
- **Higher fidelity terrain** - Quantized Mesh preserves geometry better than rasterized heightmaps
- **3D Tiles / CZML** integration for buildings, point clouds, sensors
- **Time-dynamic visualization** - CZML timeline animations
- **Global fallback** - seamlessly blend your regional DEM with Cesium World Terrain

### How They Connect

```
                    ┌─────────────────────────────────────┐
                    │         Integrated DEM Server       │
                    └─────────────────────────────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              ▼                                               ▼
    [PNG Terrain Hub]                               [Mesh Terrain Hub]
    TiTiler + MosaicJSON                            FastAPI + Static Tiles
              │                                               │
              ▼                                               ▼
    Terrain-RGB PNG tiles                           Quantized Mesh tiles
    /titiler/mosaic/tiles/...                       /tiles/{z}/{x}/{y}.terrain
              │                                               │
              ▼                                               ▼
       [MapLibre GL JS]                                  [CesiumJS]
       raster-dem source                         CesiumTerrainProvider
```

Both test viewers (`test/maplibre-terrain.html` and `test/cesium-terrain.html`) display the same underlying DEM data.

---

## API Reference

The **Viewer Gateway (:3333)** hub proxies all requests to the specialized backend hubs.

### PNG Terrain Hub (TiTiler)
Full docs at `http://localhost:3333/titiler/docs`

| Endpoint | Description |
| :--- | :--- |
| `GET /titiler/mosaic/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=file:///data/mosaic.json&algorithm=terrainrgb` | **Terrain-RGB** (MapLibre) |
| `GET /titiler/mosaic/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=file:///data/mosaic.json&algorithm=hillshade` | Hillshade |
| `GET /titiler/mosaic/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=file:///data/mosaic.json&algorithm=contours` | Contours |
| `GET /titiler/mosaic/info?url=file:///data/mosaic.json` | Unified Hub Metadata |

### Mesh Terrain Hub (FastAPI)
Aggregates all regional bakes found in `data/tiles/`

| Endpoint | Description |
| :--- | :--- |
| `GET /tiles/layer.json` | **Unified Mesh Metadata** (CesiumJS) |
| `GET /tiles/{z}/{x}/{y}.terrain` | Unified Mesh Tile |
| `GET /tiles/{region}/layer.json` | Regional Metadata Passthrough |

---

## Integration Details

### MapLibre GL JS (Seamless Hub)

```javascript
// Terrain-RGB Source
map.addSource('integrated-dtm', {
  type: 'raster-dem',
  tiles: [
    'http://localhost:3333/titiler/mosaic/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=file:///data/mosaic.json&algorithm=terrainrgb&algorithm_params={"nodata_height":0}'
  ],
  tileSize: 256,
  encoding: 'mapbox',
  maxzoom: 17  // Capped for VPS performance, use 18 for high-end servers
});

// Enable 3D
map.setTerrain({ source: 'integrated-dtm', exaggeration: 1.0 });
```

### CesiumJS (Unified Mesh Terrain)

```javascript
// Point to the Unified Hub Endpoint
const viewer = new Cesium.Viewer('cesiumContainer');

viewer.terrainProvider = await Cesium.CesiumTerrainProvider.fromUrl(
  'http://localhost:3333/tiles/',
  { requestVertexNormals: true } // Enables 3D lighting
);
```

### OpenLayers (Unified Hillshade)

```javascript
import TileLayer from 'ol/layer/WebGLTile';
import XYZ from 'ol/source/XYZ';

const hillshadeLayer = new TileLayer({
  source: new XYZ({
    url: 'http://localhost:3333/titiler/mosaic/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=file:///data/mosaic.json&algorithm=hillshade',
    crossOrigin: 'anonymous'
  })
});
```

### Regional Navigation & Debugging
Both viewers include a **Regional Navigator** and a **Current Camera View** panel. Since the data for the entire country is loaded into a single hub, selecting a region simply flies the camera to that area. The camera panel provides real-time Longitude, Latitude, Zoom, Heading, and Pitch — useful for identifying precise coordinates for your own applications.

---

## Production Deployment

### Gateway Optimization (`nginx.conf`)
The gateway hub is pre-configured to handle port preservation and Gzip encoding for the 3D meshes.

```nginx
server {
    listen 80;
    server_name terrain.hub.go.id;

    location /titiler/ {
        proxy_pass http://png-terrain-server-hub:8000/;
        proxy_set_header Host $http_host;
    }

    location /tiles/ {
        proxy_pass http://quantized-mesh-server-hub:8001/;
        proxy_set_header Host $http_host;
        # Gzip is mandatory for .terrain files
        add_header Content-Encoding gzip;
    }
}
```

---

## Troubleshooting

### 404: Tile Not Found
- **PNG:** Ensure `data/mosaic.json` was generated with absolute container paths. Run Step 3 again.
- **Mesh:** Ensure the regional `layer.json` exists in `data/tiles/{region}/`. The hub won't detect regions without metadata.

### 502: Bad Gateway
- Check the status of the hubs: `podman compose ps`.
- Inspect logs for container crashes or initialization errors: `podman compose logs png-terrain-server-hub` or `podman compose logs quantized-mesh-server-hub`.

---

## Known Limitations & Bugs

- **Cesium "Hollow Earth"**: When using the Unified Mesh Hub, areas outside the high-resolution DTM coverage (e.g., the Western Hemisphere) may appear "hollow" or transparent. This is due to how Cesium masks the base ellipsoid when a global terrain provider is active. High-resolution data inside the DTM area (Manado) renders correctly.
- **Mosaic Zoom Levels**: The `cogeo-mosaic` tool may auto-calculate a max zoom of 17. For 1m DTM data, zoom 18 is required for native precision. Set `MAX_ZOOM=18` in `tile.sh` - this is the actual cap via `ctb-tile -s` flag. See `DEM-Resolution-Quality.md` for details.

---

## Credits
- **TiTiler** & **Cogeo-Mosaic** by [Development Seed](https://developmentseed.org/)
- **Cesium Terrain Builder (CTB)** by [TUM-GIS](https://github.com/tum-gis/cesium-terrain-builder) - The C++ tool that converts raster DEMs into Quantized Mesh tiles. Docker image: `tumgis/ctb-quantized-mesh`
- **Quantized Mesh Format** - [Cesium Specification](https://github.com/CesiumGS/quantized-mesh)
- **DEM Data** by [BIG](https://www.big.go.id/) Indonesia

---

## License

This project is licensed under [MIT](LICENSE). Third-party components retain their original licenses - see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for details.
