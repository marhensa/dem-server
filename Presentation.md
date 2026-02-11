# Penyajian DEM Resolusi Tinggi (1m) untuk Platform WebGIS Modern

### Proof of Concept — Pipeline DEM Server Terintegrasi
**Badan Informasi Geospasial (BIG)**

Februari 2026

---

## Daftar Isi

1. Masalah yang Dihadapi
2. Apa yang Kami Bangun
3. Arsitektur Sistem
4. Pipeline: Dari NLP TIF ke Web
5. Kode: Server-Side (PNG Hub & Mesh Hub)
6. Kode: Client-Side (MapLibre & CesiumJS)
7. Kode: Pipeline Scripts & Infrastructure
8. Demo Langsung
9. Angka Performa & Skala
10. Skalabilitas ke Tingkat Nasional
11. Integrasi dengan Infrastruktur Existing
12. Stack Teknologi & Open Source
13. Langkah Selanjutnya
14. Tanya Jawab

---

<!-- ====================================================================== -->
<!-- SLIDE 1 — MASALAH -->
<!-- ====================================================================== -->

## Slide 1 — Masalah: DEM Kita Sulit Diakses di Web

### Situasi Saat Ini

- BIG memiliki **DEM baru resolusi ~1 meter** (belum dirilis) — aset data paling detail yang pernah diproduksi
- **ArcGIS Image Server** sudah menyajikan DEM dengan baik — lengkap dengan LOD, pyramid, caching, dan analisis raster
- Namun ArcGIS Image Server dirancang untuk **ekosistem Esri** (ArcGIS Pro, QGIS via REST) — bukan untuk konsumsi langsung oleh library WebGIS open-source seperti MapLibre atau CesiumJS
- **Celah yang belum terisi:** menyajikan DEM sebagai **terrain 3D interaktif** di browser web standar, tanpa ketergantungan pada lisensi Esri di sisi klien

### Mengapa Tidak Bisa Langsung ke Browser?

Browser web memiliki keterbatasan fundamental untuk mengonsumsi data elevasi:

| Kendala Browser | Dampak |
|-----------------|--------|
| Tidak bisa membaca GeoTIFF/LERC secara native | Butuh format khusus web (PNG Terrain-RGB, Quantized Mesh) |
| GPU browser merender segitiga (mesh), bukan piksel raster | Data elevasi harus dikonversi ke geometry 3D |
| Tidak ada GDAL di browser | Butuh server-side processing atau pre-bake |
| Bandwidth terbatas | Butuh tiling + LOD agar tidak memuat seluruh dataset sekaligus |

### Apa yang ArcGIS Image Server Sudah Bisa vs Belum Bisa

| Kemampuan | ArcGIS Image Server | Yang Dibutuhkan Browser |
|-----------|---------------------|------------------------|
| LOD / Pyramid | ✅ Ya | ✅ (sudah ada di server) |
| Analisis raster | ✅ Ya (slope, hillshade, dll) | ❌ Bukan prioritas browser |
| Format output | LERC, TIFF, PNG (raster) | **Terrain-RGB PNG** (MapLibre) atau **Quantized Mesh** (CesiumJS) |
| 3D terrain di browser | ❌ Tidak (butuh Scene Server / ArcGIS JS SDK) | ✅ Ini yang kita bangun |
| Tanpa lisensi klien | ❌ Butuh ArcGIS JS SDK | ✅ MapLibre & CesiumJS open-source |

### Pertanyaan Inti

> **Bagaimana kita menjembatani data DEM yang sudah ada di ArcGIS Image Server ke format yang bisa langsung dikonsumsi oleh library WebGIS open-source (MapLibre, CesiumJS) di browser — tanpa kehilangan kualitas?**

---

<!-- ====================================================================== -->
<!-- SLIDE 2 — SOLUSI -->
<!-- ====================================================================== -->

## Slide 2 — Solusi: Unified Terrain Hub

### Konsep Utama: "Bake Once, Serve All"

Kami membangun sebuah **pipeline otomatis** yang:

1. **Mengonversi** file NLP TIF mentah menjadi format yang dioptimasi untuk cloud (COG)
2. **Mengindeks** semua COG menjadi satu kesatuan virtual (MosaicJSON)
3. **Melakukan Bake** data elevasi menjadi geometry 3D siap browser (Quantized Mesh)
4. **Menyajikan** seluruh data melalui endpoint tunggal — tanpa duplikasi data

### Hasilnya

- **MapLibre GL JS** — Terrain 3D, hillshade, kontur, analisis kemiringan langsung di browser
- **CesiumJS** — Visualisasi globe 3D penuh dengan data DEM asli BIG
- **Satu set endpoint** untuk semua pulau — regional data, tapi akses terpadu

---

<!-- ====================================================================== -->
<!-- SLIDE 3 — ARSITEKTUR -->
<!-- ====================================================================== -->

## Slide 3 — Arsitektur Sistem

### Diagram Alur

```
┌──────────────────────┐
│  File NLP TIF Asli   │
│  (dari BIG, ~1m)     │
└──────────┬───────────┘
           │
    ┌──────▼──────┐
    │ Preprocess  │  gdal_translate → Cloud Optimized GeoTIFF (COG)
    │ (GDAL)      │  NoData fill, kompresi DEFLATE, lossless
    └──────┬──────┘
           │
    ┌──────▼──────────────────────────────────────────┐
    │              data/cogs/                         │
    │  ├── sulawesi/  ├── jawa/  ├── sumatra/ ...     │
    └──────┬──────────────────┬───────────────────────┘
           │                  │
    ┌──────▼──────┐    ┌──────▼──────┐
    │  MosaicJSON │    │  CTB Tile   │
    │  (Indexing) │    │  (Baking)   │
    └──────┬──────┘    └──────┬──────┘
           │                  │
    ┌──────▼──────┐    ┌──────▼──────┐
    │ TiTiler Hub │    │  Mesh Hub   │
    │ (Port 8000) │    │ (Port 8001) │
    │ PNG Terrain │    │ .terrain    │
    └──────┬──────┘    └──────┬──────┘
           │                  │
    ┌──────▼──────────────────▼──────┐
    │        Nginx Gateway           │
    │        (Port 3333)             │
    │  /titiler/ → PNG Hub           │
    │  /tiles/   → Mesh Hub          │
    │  /         → Test Viewers      │
    └────────────────────────────────┘
           │                  │
    ┌──────▼──────┐    ┌──────▼──────┐
    │ MapLibre GL │    │  CesiumJS   │
    │ (2D/2.5D)   │    │  (3D Globe) │
    └─────────────┘    └─────────────┘
```

### Tiga Container, Tiga Peran

| Service | Container | Fungsi |
|---------|-----------|--------|
| **PNG Hub** | `png-terrain-server-hub` | Menyajikan tile Terrain-RGB untuk MapLibre (terrain 3D, hillshade, slope) |
| **Mesh Hub** | `quantized-mesh-server-hub` | Menyajikan tile Quantized Mesh untuk CesiumJS (globe 3D) |
| **Gateway** | `viewer-gateway` | Nginx: routing `/titiler/` dan `/tiles/`, menyajikan halaman test |

---

<!-- ====================================================================== -->
<!-- SLIDE 4 — PIPELINE STEP 1: PREPROCESSING -->
<!-- ====================================================================== -->

## Slide 4 — Pipeline Step 1: Preprocessing (NLP TIF → COG)

### Apa yang Dilakukan

```bash
docker compose -f docker-compose.preprocess.yml run --rm preprocess
```

Setiap file NLP TIF mentah dikonversi menjadi **Cloud Optimized GeoTIFF (COG)**:

| Langkah | Detail |
|---------|--------|
| **Fill NoData** | Nilai -32767 (kosong) diganti 0 (sea level) |
| **Kompresi** | DEFLATE + PREDICTOR=2, lossless, ~40-60% lebih kecil |
| **Format** | Tetap Float32 — **tidak ada kehilangan presisi** |
| **Overview** | Built-in pyramid untuk zoom out cepat |
| **Struktur** | Mirror 1:1 dari `data/source/` ke `data/cogs/` |

### Mengapa COG?

| Fitur COG | Keuntungan |
|-----------|------------|
| HTTP Range Requests | Hanya stream bytes yang dibutuhkan, tidak perlu download seluruh file |
| Built-in Overviews | Zoom out cepat tanpa file pyramid terpisah |
| Kompresi Lossless | Ukuran storage lebih kecil, kualitas penuh |
| Single File | Tidak perlu manajemen folder tile pyramid |
| Cloud-Native | Kompatibel dengan S3, object storage, CDN |

### Contoh Hasil

```
data/source/sulawesi/DTM_MND_2417-1445C.tif  →  90 MB (Raw)
data/cogs/sulawesi/DTM_MND_2417-1445C.tif    →  38 MB (COG, lossless)
                                                  ↓ 58% lebih kecil
```

---

<!-- ====================================================================== -->
<!-- SLIDE 5 — PIPELINE STEP 2: INDEXING -->
<!-- ====================================================================== -->

## Slide 5 — Pipeline Step 2: Indexing (COG → MosaicJSON)

### Apa yang Dilakukan

```bash
REGION=sulawesi docker compose -f docker-compose.preprocess.yml run --rm mosaic
```

Membuat sebuah **MosaicJSON** — indeks spasial yang "menjahit" ribuan lembaran NLP secara virtual menjadi satu kesatuan.

### Bagaimana MosaicJSON Bekerja

```
┌───────────────────────────────────────────────┐
│              MosaicJSON                       │
│                                               │
│  "Untuk tile di koordinat X,Y → baca          │
│   file COG #1247 di byte range 45000-46000" │
│                                               │
│  Satu file JSON, mengindeks ribuan COG        │
│  TiTiler membaca indeks ini on-the-fly        │
└───────────────────────────────────────────────┘
```

- **Tidak ada duplikasi data** — indeks hanya berisi pointer ke file COG asli
- **Minzoom 0, Maxzoom 18** — didukung dari zoom nasional sampai zoom 1 meter
- Output: `data/mosaic_sulawesi.json`

---

<!-- ====================================================================== -->
<!-- SLIDE 6 — PIPELINE STEP 3: MESH BAKING -->
<!-- ====================================================================== -->

## Slide 6 — Pipeline Step 3: Mesh Baking (COG → Quantized Mesh)

### Apa yang Dilakukan

```bash
REGION=sulawesi docker compose -f docker-compose.tile.yml run --rm tile
```

Mengonversi data elevasi raster menjadi **geometry 3D** yang bisa langsung dikonsumsi GPU browser.

### Proses Internal CTB (Cesium Terrain Builder)

```
File COG (piksel elevasi)
    │
    ▼
[1] Hitung batas tile → setiap tile z/x/y punya bounds geografis
    │
    ▼
[2] Sampling elevasi → baca nilai ketinggian dari DEM dalam bounds
    │
    ▼
[3] Triangulasi adaptif → area datar = sedikit segitiga
    │                       area curam = banyak segitiga
    ▼
[4] Kuantisasi → koordinat float64 → uint16 (0-32767)
    │
    ▼
[5] Edge stitching → identifikasi vertex di tepi tile
    │                  untuk menyambung tile bertetangga tanpa celah
    ▼
[6] Kompresi gzip → simpan sebagai {z}/{x}/{y}.terrain (1-50 KB per tile)
```

### Perbedaan Fundamental

| Aspek | File DEM (GeoTIFF) | Terrain Tiles (Quantized Mesh) |
|-------|--------------------|---------------------------------|
| Struktur | Satu file raster kontinu | Jutaan file mesh dalam pyramid |
| Data | Grid piksel reguler | Mesh segitiga irregular |
| Ukuran | MB–GB per file | 1–50 KB per tile |
| Akses | Butuh GDAL (desktop) | HTTP streaming (browser) |
| GPU | Tidak bisa langsung | Langsung dikonsumsi GPU |

### Setting Resolusi

| DEM Source | Resolusi Asli | MAX_ZOOM yang Direkomendasikan |
|------------|---------------|-------------------------------|
| SRTM | 30m | 14 |
| ALOS PALSAR | 12.5m | 14 |
| DEMNAS BIG (5m) | 5m | 15 |
| **DEM Baru BIG (~1m)** | **~0.97m** | **18** |

---

<!-- ====================================================================== -->
<!-- SLIDE 6B — PENJELASAN FORMAT TILE -->
<!-- ====================================================================== -->

## Slide 6B — Dua Format Tile Terrain untuk Browser

DEM asli (GeoTIFF) tidak bisa langsung dibuka browser. Solusinya: konversi ke **format tile** — data dipotong-potong kecil dalam pyramid `{z}/{x}/{y}`, persis seperti tile peta biasa (Google Maps, OpenStreetMap). Bedanya: isinya bukan gambar peta, tapi **data elevasi**.

Ada dua format tile terrain yang kita gunakan:

### 1. PNG Terrain-RGB Tiles (untuk MapLibre)

**Apa ini?** File PNG biasa (gambar 256×256 piksel), tapi warna setiap pikselnya bukan warna visual — melainkan **elevasi yang di-encode ke nilai RGB**.

```
Piksel biasa:  R=120, G=180, B=60  → warna hijau
Terrain-RGB:   R=120, G=180, B=60  → elevasi = -10000 + (120×65536 + 180×256 + 60) × 0.1
                                    → elevasi = 776,891.8 m? Tidak — ini contoh saja.

Contoh nyata:
  R=1, G=136, B=64  → elevasi = -10000 + (1×65536 + 136×256 + 64) × 0.1
                     → elevasi = -10000 + (65536 + 34816 + 64) × 0.1
                     → elevasi = -10000 + 10041.6
                     → elevasi = 41.6 meter ← ketinggian di atas sea level
```

```
┌────────────────────────────────────┐
│  Tile PNG biasa (foto satelit)     │   Tile PNG Terrain-RGB (elevasi)
│  ┌───┬───┬───┬───┐                 │   ┌───┬───┬───┬───┐
│  │🟢│🟢│🟤│🟤│  ← warna visual   │   │   │   │   │   │  ← warna = elevasi
│  ├───┼───┼───┼───┤                 │   ├───┼───┼───┼───┤
│  │🟢│🟢│🟤│⬜│                   │   │   │   │   │   │    R,G,B → meter
│  ├───┼───┼───┼───┤                 │   ├───┼───┼───┼───┤
│  │🔵│🟢│🟤│🟤│                   │   │   │   │   │   │    256×256 piksel
│  └───┴───┴───┴───┘                 │   └───┴───┴───┴───┘
│  Mata manusia: gambar              │   Mata manusia: warna aneh
│  Browser: gambar                   │   MapLibre: 65.536 titik elevasi!
└────────────────────────────────────┘
```

| Aspek | Detail |
|-------|--------|
| **Format file** | PNG standar — bisa dibuka di image viewer manapun (terlihat aneh warnanya) |
| **Isi** | 256×256 piksel, tiap piksel = 1 nilai elevasi encoded di R, G, B |
| **Encoding** | Mapbox Terrain-RGB: `elevasi = -10000 + (R×65536 + G×256 + B) × 0.1` |
| **Presisi** | 0.1 meter (cukup untuk visualisasi 3D) |
| **Digunakan oleh** | **MapLibre GL JS** — decode RGB → elevasi, render terrain 3D |
| **Tile scheme** | `{z}/{x}/{y}.png` — sama persis seperti tile peta biasa |
| **Ukuran per tile** | ~5–30 KB |

### 2. Quantized Mesh Tiles (untuk CesiumJS)

**Apa ini?** File binary (bukan gambar) yang berisi **mesh segitiga 3D** — vertex, triangle indices, dan edge data. Langsung dikonsumsi GPU untuk rendering 3D globe.

```
┌─────────────────────────────────────────────────────────────┐
│  PNG Terrain-RGB:              Quantized Mesh (.terrain):   │
│                                                             │
│  ┌───┬───┬───┬───┐            ┌───────────────────┐         │
│  │ · │ · │ · │ · │            │  ╲   ╲   ╱   ╱    │         │
│  ├───┼───┼───┼───┤            │   ╲   ╲ ╱   ╱     │         │
│  │ · │ · │ · │ · │  ← Grid    │    ╲   ╳   ╱      │   ← Mesh│
│  ├───┼───┼───┼───┤    reguler │    ╱  ╱ ╲  ╲      │   adap- │
│  │ · │ · │ · │ · │    piksel  │   ╱  ╱   ╲  ╲     │   tif   │
│  └───┴───┴───┴───┘            └───────────────────┘         │
│                                                             │
│  Setiap titik = 1 elevasi     Lebih banyak segitiga di area │
│  Resolusi tetap (grid)        curam, lebih sedikit di area  │
│                                datar → lebih efisien        │
└─────────────────────────────────────────────────────────────┘
```

| Aspek | Detail |
|-------|--------|
| **Format file** | Binary (bukan gambar) — tidak bisa dibuka di image viewer |
| **Isi** | Daftar vertex (x, y, height) + daftar segitiga + data tepi tile |
| **Encoding** | Quantized uint16 (0–32767), delta + zigzag encoded, gzip compressed |
| **Adaptif** | Area curam → banyak segitiga, area datar → sedikit segitiga |
| **Digunakan oleh** | **CesiumJS** — langsung dikonsumsi GPU untuk globe 3D |
| **Tile scheme** | `{z}/{x}/{y}.terrain` — TMS scheme (sama seperti tile peta) |
| **Ukuran per tile** | ~1–50 KB |

### Perbandingan Kedua Format

| | PNG Terrain-RGB | Quantized Mesh (.terrain) |
|---|---|---|
| **Tipe data** | Raster (grid piksel) | Vector (mesh segitiga) |
| **Isi** | Elevasi per piksel, encoded di RGB | Geometry 3D (vertex + triangles) |
| **Bisa dilihat mata?** | Ya (terlihat sebagai warna aneh) | Tidak (binary) |
| **Generated** | On-the-fly oleh TiTiler dari COG | Pre-baked oleh CTB (sekali proses) |
| **Client** | MapLibre GL JS | CesiumJS |
| **Kelebihan** | Tidak perlu pre-bake, on-demand | Lebih efisien karena mesh adaptif |
| **Kesamaan** | **Keduanya tile pyramid `{z}/{x}/{y}`** — sama seperti tile peta biasa |

> **Intinya:** Keduanya adalah **tile** — data dipotong dalam pyramid zoom level persis seperti Google Maps. Yang berbeda adalah **isi** tile-nya: satu berisi gambar PNG (elevasi encoded di warna), satu berisi mesh 3D binary.

---

<!-- ====================================================================== -->
<!-- SLIDE 7 — SERVING: PNG HUB -->
<!-- ====================================================================== -->

## Slide 7 — Serving: PNG Terrain Hub (MapLibre)

### Peran

Menyajikan data elevasi sebagai tile gambar **Terrain-RGB PNG** secara on-the-fly dari COG melalui MosaicJSON.

### Cara Kerja

```
Browser (MapLibre)
    │
    │  GET /titiler/mosaic/tiles/{z}/{x}/{y}.png
    │      ?url=file:///data/mosaic_sulawesi.json
    │      &algorithm=terrainrgb
    ▼
┌─────────────────────────────┐
│  TiTiler (Python/FastAPI)   │
│                              │
│  1. Baca MosaicJSON         │
│  2. Cari COG yang overlap   │
│  3. Baca byte range          │
│  4. Encode elevasi → RGB    │
│  5. Return PNG 256×256      │
└─────────────────────────────┘
```

### Algoritma yang Tersedia

| Algoritma | Fungsi | Digunakan Untuk |
|-----------|--------|-----------------|
| `terrainrgb` | Encode elevasi ke warna RGB | Terrain 3D di MapLibre |
| `hillshade` | Bayangan bukit dari pencahayaan | Overlay hillshade |
| `slope` | Hitung kemiringan per piksel | Analisis kemiringan lereng |

### Keunggulan

- **Tidak perlu pre-bake** — tile PNG dihasilkan on-the-fly dari COG
- **Satu endpoint** untuk seluruh wilayah via MosaicJSON
- **Failsafe** — EmptyMosaicError ditangkap, return 404 tanpa crash server

---

<!-- ====================================================================== -->
<!-- SLIDE 8 — SERVING: MESH HUB -->
<!-- ====================================================================== -->

## Slide 8 — Serving: Quantized Mesh Hub (CesiumJS)

### Peran

Menyajikan tile `.terrain` pre-baked dari disk untuk visualisasi globe 3D di CesiumJS.

### Endpoint Terpadu

```
Browser (CesiumJS)
    │
    │  GET /tiles/layer.json          ← Metadata gabungan semua region
    │  GET /tiles/{z}/{x}/{y}.terrain ← Tile mesh dari region manapun
    ▼
┌──────────────────────────────────────┐
│  Virtual Mesh Compositor (FastAPI)   │
│                                      │
│  /layer.json:                        │
│    Scan semua folder region          │
│    Gabungkan bounds & availability   │
│    Return metadata terintegrasi      │
│                                      │
│  /{z}/{x}/{y}.terrain:               │
│    Cari tile di semua folder region  │
│    Return file pertama yang cocok    │
└──────────────────────────────────────┘
```

### Konsep "Virtual Compositor"

- CesiumJS hanya melihat **satu endpoint** (`/tiles/`)
- Di balik layar, server mencari tile yang cocok dari folder regional mana saja
- Ketika region baru ditambahkan, **server otomatis mendeteksi** — tanpa konfigurasi tambahan

---

<!-- ====================================================================== -->
<!-- SLIDE 8A — KODE: PNG TERRAIN HUB (SERVER) -->
<!-- ====================================================================== -->

## Slide 8A — Kode Server: PNG Terrain Hub (`png_terrain_hub.py`)

### Seluruh File — Hanya ~35 Baris

PNG Hub adalah wrapper tipis di atas TiTiler. Kuncinya: mendaftarkan **MosaicTilerFactory** agar TiTiler bisa membaca MosaicJSON.

```python
# png_terrain_hub.py — Server-side (Python/FastAPI)
import logging
import warnings
from titiler.application.main import app as base_app
from titiler.mosaic.factory import MosaicTilerFactory
from cogeo_mosaic.backends import MosaicBackend
from rio_tiler.errors import EmptyMosaicError
from fastapi import Request
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)

# Tangkap error ketika tile diminta di luar bounds mosaic
# Tanpa ini, Uvicorn crash dan log penuh error
@base_app.exception_handler(EmptyMosaicError)
async def empty_mosaic_handler(request: Request, exc: EmptyMosaicError):
    return JSONResponse(
        status_code=404,
        content={"detail": "Tile outside of mosaic bounds or contains no data."},
    )

# Inisialisasi Mosaic Factory — ini yang membuat endpoint /mosaic/tiles/{z}/{x}/{y}.png
mosaic = MosaicTilerFactory(backend=MosaicBackend)
base_app.include_router(mosaic.router, prefix="/mosaic", tags=["Mosaic"])

app = base_app
```

### Poin Penting

| Baris | Fungsi |
|-------|--------|
| `MosaicTilerFactory(backend=MosaicBackend)` | Membuat endpoint tile yang bisa membaca MosaicJSON |
| `prefix="/mosaic"` | Semua endpoint mosaic tersedia di `/mosaic/tiles/...` |
| `EmptyMosaicError` handler | Mencegah server crash saat tile di luar area DEM |
| Tanpa route custom | TiTiler sudah menyediakan `terrainrgb`, `hillshade`, `slope` sebagai algorithm |

> **Inti:** Kita tidak menulis logika rendering tile sendiri. TiTiler sudah melakukan semuanya — kita hanya mendaftarkan Mosaic backend dan menangkap error.

---

<!-- ====================================================================== -->
<!-- SLIDE 8B — KODE: MESH TERRAIN HUB (SERVER) -->
<!-- ====================================================================== -->

## Slide 8B — Kode Server: Quantized Mesh Hub (`mesh_terrain_hub.py`)

### Endpoint 1: Integrasi `layer.json` (Metadata Terpadu)

CesiumJS pertama kali meminta `layer.json` untuk tahu zoom level apa saja yang tersedia dan di mana bounds-nya.

```python
# mesh_terrain_hub.py — Compositing layer.json dari semua region

TILES_ROOT = "/data/tiles"

def get_regional_layers():
    """Scan semua subfolder untuk layer.json"""
    layers = {}
    for region in os.listdir(TILES_ROOT):
        region_path = os.path.join(TILES_ROOT, region)
        if not os.path.isdir(region_path):
            continue
        layer_file = os.path.join(region_path, "layer.json")
        if os.path.exists(layer_file):
            with open(layer_file, "r") as f:
                layers[region] = json.load(f)
    return layers

@app.get("/layer.json")
async def get_integrated_layer():
    regional_layers = get_regional_layers()

    # Hitung union bounds dari semua region
    tight_bounds = [180.0, 90.0, -180.0, -90.0]  # [minLon, minLat, maxLon, maxLat]
    for region, meta in regional_layers.items():
        b = meta["bounds"]
        tight_bounds[0] = min(tight_bounds[0], b[0])  # minLon
        tight_bounds[1] = min(tight_bounds[1], b[1])  # minLat
        tight_bounds[2] = max(tight_bounds[2], b[2])  # maxLon
        tight_bounds[3] = max(tight_bounds[3], b[3])  # maxLat

    # Gabungkan availability dari semua region
    # → CesiumJS tahu tile mana yang ada di zoom berapa
    return {
        "format": "quantized-mesh-1.0",
        "scheme": "tms",
        "tiles": ["{z}/{x}/{y}.terrain?v={version}"],
        "bounds": tight_bounds,
        "available": merged_availability,  # Gabungan semua region
    }
```

### Endpoint 2: Routing Tile ke Region yang Benar

```python
@app.get("/{z}/{x}/{y}.terrain")
async def get_tile(z: int, x: int, y: int, v: str = ""):
    """Cari tile di semua folder region, return yang pertama cocok"""
    for region in os.listdir(TILES_ROOT):
        region_path = os.path.join(TILES_ROOT, region)
        tile_file = os.path.join(region_path, str(z), str(x), f"{y}.terrain")

        if os.path.exists(tile_file):
            return FileResponse(
                tile_file,
                media_type="application/octet-stream",
                headers={"Content-Encoding": "gzip"},  # File sudah di-gzip oleh CTB
            )

    raise HTTPException(status_code=404)
```

### Poin Penting

| Konsep | Detail |
|--------|--------|
| **Virtual Compositor** | Satu endpoint `/layer.json` menggabungkan metadata dari `sulawesi/`, `jawa/`, dll |
| **Auto-discovery** | `os.listdir(TILES_ROOT)` — tambah folder baru = otomatis terdeteksi |
| **Static file serving** | Tile `.terrain` disajikan langsung dari disk, tidak ada processing |
| **Content-Encoding: gzip** | File sudah di-gzip oleh CTB saat baking, tidak perlu compress ulang |

---

<!-- ====================================================================== -->
<!-- SLIDE 8C — KODE: MAPLIBRE CLIENT -->
<!-- ====================================================================== -->

## Slide 8C — Kode Client: MapLibre Mengonsumsi Terrain-RGB PNG

### 1. Konstruksi URL Tile

```javascript
// maplibre-terrain.html — Konfigurasi URL tile

// Path ke MosaicJSON (di dalam container)
const MOSAIC_PATH = `file:///data/mosaic_${REGION}.json`;

// Parameter: 256px tile, nodata=0, nodata_height=0
// algorithm=terrainrgb → TiTiler encode elevasi ke RGB
const ALGO_PARAMS = encodeURIComponent(JSON.stringify({ nodata_height: 0 }));
const HUB_PARAMS  = `&tilesize=256&nodata=0`;

// URL final yang MapLibre gunakan untuk request setiap tile
const TERRAIN_RGB_URL = `${TITILER_BASE}/mosaic/tiles/WebMercatorQuad/{z}/{x}/{y}.png` +
    `?url=${MOSAIC_PATH}` +
    `&algorithm=terrainrgb` +
    `&algorithm_params=${ALGO_PARAMS}` +
    `${HUB_PARAMS}` +
    `&resampling_method=nearest`;

// URL terpisah untuk hillshade dan slope (algoritma beda, data sama)
const HILLSHADE_URL = `...&algorithm=hillshade&resampling_method=bilinear`;
const SLOPE_URL     = `...&algorithm=slope&colormap_name=rdylgn_r&resampling_method=bilinear`;
```

### 2. Mendaftarkan Source Terrain DEM

```javascript
// Setelah map.on('load'):

// Source raster-dem — ini yang MapLibre gunakan untuk 3D terrain
map.addSource('local-dem', {
    type: 'raster-dem',         // Tipe khusus: MapLibre decode RGB → elevasi
    tiles: [TERRAIN_RGB_URL],   // URL ke TiTiler PNG Hub
    tileSize: 256,              // Harus cocok dengan server (256px)
    encoding: 'mapbox',         // Terrain-RGB encoding: elevation = -10000 + ((R×256×256 + G×256 + B) × 0.1)
    minzoom: 13,                // Tidak load terrain di bawah zoom 13
    maxzoom: 17                 // Cap di zoom 17 (VPS performance)
});

// Aktifkan 3D terrain
map.setTerrain({ source: 'local-dem', exaggeration: 1.0 });
```

### 3. Hillshade & Slope Overlay (Sumber Data Sama, Algoritma Beda)

```javascript
// Hillshade — overlay bayangan bukit
map.addSource('local-hillshade', {
    type: 'raster',             // Bukan raster-dem, tapi raster biasa (gambar)
    tiles: [HILLSHADE_URL],     // TiTiler hillshade dari COG yang sama
    tileSize: 256,
    minzoom: 13, maxzoom: 17
});
map.addLayer({
    id: 'hillshade-layer', type: 'raster', source: 'local-hillshade',
    paint: { 'raster-opacity': 0.5 },
    layout: { visibility: 'none' }  // Default: hidden, toggle via UI
});

// Slope analysis — peta kemiringan berwarna
map.addSource('local-slope', {
    type: 'raster',
    tiles: [SLOPE_URL],         // TiTiler slope + colormap rdylgn_r
    tileSize: 256,
    minzoom: 13, maxzoom: 17
});
```

### 4. Kontur Real-Time (Client-Side)

```javascript
// maplibre-contour: decode Terrain-RGB di browser, hasilkan garis kontur
const demSource = new mlcontour.DemSource({
    url: TERRAIN_RGB_URL,   // Pakai URL terrain yang sama
    encoding: 'mapbox',     // Sama dengan raster-dem di atas
    minzoom: 13,
    maxzoom: 17,
    tileSize: 256,
    worker: true,           // Proses di Web Worker (tidak blok UI)
    cacheSize: 20           // Simpan 20 tile di memori
});
demSource.setupMaplibre(maplibregl);

// Daftarkan sebagai vector source
map.addSource('contour-source', {
    type: 'vector',
    tiles: [
        demSource.contourProtocolUrl({
            multiplier: 1,
            thresholds: {  // Interval kontur adaptif per zoom
                14: [5, 25],    // Minor 5m, Mayor 25m
                15: [5, 25],
                16: [2, 10],    // Minor 2m, Mayor 10m
                17: [1, 5],     // Minor 1m, Mayor 5m — resolusi penuh!
            },
            contourLayer: 'contours',
            elevationKey: 'ele',
            levelKey: 'level'
        })
    ],
    minzoom: 13, maxzoom: 17
});

// Render garis kontur
map.addLayer({
    id: 'contour-lines', type: 'line', source: 'contour-source',
    'source-layer': 'contours',
    paint: {
        'line-color': 'rgba(220, 38, 38, 0.8)',
        'line-width': ['match', ['get', 'level'], 1, 1.5, 0.6]  // Mayor: tebal, minor: tipis
    }
});

// Label kontur
map.addLayer({
    id: 'contour-labels', type: 'symbol', source: 'contour-source',
    'source-layer': 'contours',
    filter: ['>', ['get', 'level'], 0],  // Hanya label mayor
    layout: {
        'symbol-placement': 'line',
        'text-field': ['concat', ['number-format', ['get', 'ele'], {}], 'm']
    }
});
```

### Poin Penting

| Konsep | Detail |
|--------|--------|
| `type: 'raster-dem'` | MapLibre decode RGB → float elevation secara otomatis |
| `encoding: 'mapbox'` | Formula: `elev = -10000 + (R×65536 + G×256 + B) × 0.1` |
| 3 algoritma, 1 sumber data | terrainrgb, hillshade, slope — semua dari COG yang sama |
| Kontur client-side | `mlcontour` baca tile terrain, generate kontur di Web Worker |
| `minzoom: 13` | Terrain disabled di zoom rendah — cegah artefak "tiang" dan "bidang melayang" |

---

<!-- ====================================================================== -->
<!-- SLIDE 8D — KODE: CESIUM CLIENT -->
<!-- ====================================================================== -->

## Slide 8D — Kode Client: CesiumJS Mengonsumsi Quantized Mesh

### 1. Inisialisasi Terrain Provider

```javascript
// cesium-terrain.html — Konsumsi Mesh Hub

// URL ke Mesh Hub (melalui Nginx gateway)
const terrainUrl = `${window.location.origin}/tiles/`;
// CesiumJS akan otomatis request: /tiles/layer.json dulu

// Buat terrain provider dari endpoint terpadu
terrainProvider = await Cesium.CesiumTerrainProvider.fromUrl(terrainUrl, {
    requestVertexNormals: true  // Minta normal vertex untuk pencahayaan
});

// Pasang ke viewer — terrain 3D langsung aktif
viewer.terrainProvider = terrainProvider;
```

### Apa yang Terjadi di Balik Layar

```
CesiumJS Browser                          Mesh Hub Server
    │                                           │
    │  GET /tiles/layer.json                    │
    │ ────────────────────────────────────────► │
    │                                           │ Scan semua region
    │  ◄──────── { bounds, available, ... }     │ Gabungkan metadata
    │                                           │
    │  (User zoom in ke Manado)                 │
    │                                           │
    │  GET /tiles/14/27756/11262.terrain        │
    │ ────────────────────────────────────────► │
    │                                           │ Cek: sulawesi/14/27756/11262.terrain
    │  ◄──────── [binary gzip mesh data]        │ Ada! Return file
    │                                           │
    │  (GPU decode mesh, render 3D)             │
    │                                           │
```

### 2. Fitur Viewer

```javascript
// Toggle terrain on/off
document.getElementById('toggle-terrain').onchange = (e) => {
    viewer.terrainProvider = e.target.checked
        ? terrainProvider                          // Terrain mesh BIG
        : new Cesium.EllipsoidTerrainProvider();   // Bola polos (flat)
};

// Kontrol exaggeration (perpanjangan elevasi)
document.getElementById('exaggeration').oninput = (e) => {
    viewer.scene.verticalExaggeration = parseFloat(e.target.value);
};

// Wireframe mode — lihat mesh triangulasi secara langsung
document.getElementById('toggle-wireframe').onchange = (e) => {
    viewer.scene.globe._surface.tileProvider._debug.wireframe = e.target.checked;
};

// Real-time elevasi di posisi kursor
handler.setInputAction((movement) => {
    const cartesian = viewer.scene.pickPosition(movement.endPosition);
    if (Cesium.defined(cartesian)) {
        const carto = Cesium.Cartographic.fromCartesian(cartesian);
        // carto.height = elevasi dari terrain mesh (meter)
        document.getElementById('cursor-elev').textContent =
            `${carto.height.toFixed(1)}m`;
    }
}, Cesium.ScreenSpaceEventType.MOUSE_MOVE);
```

### 3. Navigasi Regional

```javascript
// Ketika user pilih region dari dropdown:
const response = await fetch(`${window.location.origin}/tiles/${region}/layer.json`);
const layerData = await response.json();

if (layerData.bounds) {
    // Terbang ke bounding box region
    viewer.camera.flyTo({
        destination: Cesium.Rectangle.fromDegrees(
            layerData.bounds[0],  // west
            layerData.bounds[1],  // south
            layerData.bounds[2],  // east
            layerData.bounds[3]   // north
        ),
        duration: 2  // Animasi 2 detik
    });
}
```

### Poin Penting

| Konsep | Detail |
|--------|--------|
| `CesiumTerrainProvider.fromUrl()` | CesiumJS otomatis baca `layer.json`, lalu request tile sesuai kebutuhan |
| `requestVertexNormals: true` | Minta data normal untuk pencahayaan realistis |
| Format `quantized-mesh-1.0` | Binary mesh terkompresi gzip, ~1-50 KB per tile |
| LOD otomatis | CesiumJS request zoom rendah saat jauh, zoom tinggi saat dekat |
| Satu endpoint | `/tiles/` — satu URL untuk seluruh Indonesia |

---

<!-- ====================================================================== -->
<!-- SLIDE 8E — KODE: PIPELINE SCRIPTS -->
<!-- ====================================================================== -->

## Slide 8E — Kode Pipeline: Script Preprocessing & Baking

### 1. Preprocessing: NLP TIF → COG (`preprocess.sh`)

```bash
# preprocess.sh — Inti konversi (per file)

# Langkah 1: Isi NoData dengan 0 (sea level)
# -32767 adalah nilai "kosong" dari NLP grid BIG
gdalwarp \
    -srcnodata "-32767" \
    -dstnodata "0" \
    -overwrite -q \
    "$INPUT_FILE" \
    "$TEMP_FILE"

# Langkah 2: Konversi ke Cloud Optimized GeoTIFF
gdal_translate -q \
    -of COG \                          # Output format: COG
    -co COMPRESS=DEFLATE \             # Kompresi lossless
    -co PREDICTOR=2 \                  # Optimasi untuk data kontinu (elevasi)
    -co OVERVIEW_RESAMPLING=BILINEAR \ # Pyramid resampling
    -co NUM_THREADS=ALL_CPUS \         # Paralelisasi
    -a_nodata 0 \                      # Tandai 0 sebagai nodata
    "$TEMP_FILE" \
    "$OUTPUT_FILE"
```

### 2. Indexing: COG → MosaicJSON (`mosaic.sh`)

```bash
# mosaic.sh — Buat indeks spasial

# Kumpulkan semua COG dalam satu region
find "$INPUT_DIR" -name "*.tif" > /tmp/file_list.txt

# cogeo-mosaic baca metadata tiap COG (bounds, resolusi)
# dan buat satu JSON yang mengindeks semuanya
cogeo-mosaic create /tmp/file_list.txt \
    -o "$OUTPUT_FILE" \    # Output: data/mosaic_sulawesi.json
    --minzoom 0 \          # Dukung zoom nasional (overview)
    --maxzoom 18 \         # Sampai zoom 18 (~0.6m/pixel)
    --quiet
```

### 3. Mesh Baking: COG → Quantized Mesh (`tile.sh`)

```bash
# tile.sh — Bake terrain mesh untuk CesiumJS

MAX_ZOOM=18

# Langkah 1: Buat VRT (Virtual Raster) dari semua COG
# VRT = "daftar isi" virtual, tidak copy data
find "$INPUT_DIR" -name "*.tif" > /tmp/baking_list.txt
gdalbuildvrt -input_file_list /tmp/baking_list.txt "$VRT_FILE"

# Langkah 2: Generate mesh tiles
# -f Mesh     = output format Quantized Mesh
# -s 18       = maximum zoom level (hard cap)
# -e 0        = minimum zoom level
ctb-tile \
    -f Mesh \
    -s "$MAX_ZOOM" \
    -e 0 \
    -o "$OUTPUT_DIR" \
    "$VRT_FILE"
# Output: data/tiles/sulawesi/0/...  sampai  .../18/{x}/{y}.terrain

# Langkah 3: Generate layer.json (metadata untuk CesiumJS)
ctb-tile \
    -f Mesh \
    -l \               # Flag: hanya generate metadata, bukan tile
    -s "$MAX_ZOOM" \
    -e 0 \
    -o "$OUTPUT_DIR" \
    "$VRT_FILE"
# Output: data/tiles/sulawesi/layer.json
```

### Poin Penting

| Script | Input | Output | Kapan Dijalankan |
|--------|-------|--------|------------------|
| `preprocess.sh` | `data/source/*.tif` | `data/cogs/*.tif` | Sekali per batch data baru |
| `mosaic.sh` | `data/cogs/*.tif` | `data/mosaic_*.json` | Sekali per region (cepat) |
| `tile.sh` | `data/cogs/*.tif` | `data/tiles/*/` | Sekali per region (lama, tapi hanya sekali) |

---

<!-- ====================================================================== -->
<!-- SLIDE 8F — KODE: INFRASTRUKTUR -->
<!-- ====================================================================== -->

## Slide 8F — Kode Infrastruktur: Docker Compose & Nginx

### 1. Docker Compose — 3 Service, 1 Perintah

```yaml
# docker-compose.yml
services:
  # PNG Hub: TiTiler + Mosaic plugin
  png-terrain-server-hub:
    image: ghcr.io/developmentseed/titiler:1.1.1
    volumes:
      - ./data:/data:ro          # COG files (read-only)
      - ./scripts:/scripts:ro    # png_terrain_hub.py
    command:
      - uvicorn
      - scripts.png_terrain_hub:app   # Load script kita sebagai FastAPI app
      - --host
      - "0.0.0.0"
      - --port
      - "8000"
      - --workers
      - "2"                      # 2 worker untuk paralel
    environment:
      - GDAL_CACHEMAX=75%        # GDAL pakai 75% RAM untuk cache
      - VSI_CACHE=TRUE           # Cache HTTP range request

  # Mesh Hub: FastAPI custom (static file server + compositor)
  quantized-mesh-server-hub:
    image: ghcr.io/developmentseed/titiler:1.1.1    # Pakai image sama (sudah ada Python/FastAPI)
    volumes:
      - ./data:/data:ro
      - ./scripts:/scripts:ro
    command:
      - uvicorn
      - scripts.mesh_terrain_hub:app  # Load mesh compositor kita
      - --host
      - "0.0.0.0"
      - --port
      - "8001"

  # Gateway: Nginx sebagai entry point tunggal
  viewer-gateway:
    image: nginx:alpine
    ports:
      - "3333:80"                # Satu-satunya port yang exposed
    volumes:
      - ./test:/usr/share/nginx/html:ro   # Halaman test viewer
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
```

### 2. Nginx — Routing Terpusat

```nginx
# nginx.conf — Semua traffic masuk di port 3333
server {
    listen 80;

    # Halaman test viewer (MapLibre & Cesium)
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ =404;
    }

    # /titiler/* → PNG Terrain Hub (TiTiler, port 8000)
    # MapLibre request terrain-RGB, hillshade, slope di sini
    location /titiler/ {
        proxy_pass http://png-terrain-server-hub:8000/;
    }

    # /tiles/* → Quantized Mesh Hub (FastAPI, port 8001)
    # CesiumJS request layer.json dan .terrain files di sini
    location /tiles/ {
        proxy_pass http://quantized-mesh-server-hub:8001/;
        add_header Access-Control-Allow-Origin *;
    }
}
```

### 3. VPS Config — Optimasi untuk RAM 1 GB

```yaml
# docker-compose-vps.yml — Perubahan dari config lokal
services:
  png-terrain-server-hub:
    command: [... --workers, "1"]           # Turun dari 2 ke 1 worker
    environment:
      - GDAL_CACHEMAX=128                  # Fixed 128MB (bukan 75% RAM)
      - VSI_CACHE_SIZE=33554432            # 32MB (bukan 512MB)
      - GDAL_NUM_THREADS=1                 # Single thread
    deploy:
      resources:
        limits:
          memory: 400M                     # Hard cap 400MB per container

  viewer-gateway:
    networks:
      - default
      - cfnet       # Cloudflare Tunnel network (HTTPS otomatis)

networks:
  cfnet:
    external: true  # Network dari Cloudflare Tunnel container
```

### Poin Penting

| Konsep | Detail |
|--------|--------|
| 1 port exposed | Hanya `3333` — Nginx route ke service internal |
| Image sharing | Mesh Hub pakai image TiTiler yang sama (sudah ada Python) |
| Read-only volumes | `:ro` — container tidak bisa modifikasi data |
| VPS safety | Memory limit 400MB cegah OOM kill |
| Cloudflare Tunnel | Zero port exposure ke internet, HTTPS otomatis |

---

<!-- ====================================================================== -->
<!-- SLIDE 9 — DEMO: MAPLIBRE -->
<!-- ====================================================================== -->

## Slide 9 — Demo: MapLibre GL JS (2D/2.5D)

### URL: `http://localhost:3333/maplibre-terrain.html`

### Fitur yang Ditampilkan

| Fitur | Deskripsi |
|-------|-----------|
| **Terrain 3D** | Elevasi asli ~1m, terrain exaggeration adjustable (0.5×–5×) |
| **Hillshade** | Overlay bayangan bukit, opacity adjustable |
| **Kontur** | Garis kontur real-time (client-side via mlcontour), interval adaptif per zoom |
| **Slope Analysis** | Peta kemiringan berwarna (hijau=datar → merah=curam) |
| **Cursor Elevation** | Ketinggian real-time saat hover mouse |
| **Region Selector** | Dropdown untuk navigasi antar pulau |

### Interval Kontur Adaptif

| Zoom Level | Kontur Minor | Kontur Mayor |
|------------|-------------|-------------|
| 14 | 5m | 25m |
| 15 | 5m | 25m |
| 16 | 2m | 10m |
| 17 | 1m | 5m |

### Catatan Teknis

- Semua sumber data di-cap di **zoom 17** (client-side) untuk performa VPS
- Pipeline mendukung hingga **zoom 18** — bisa dinaikkan dengan VPS yang lebih besar
- Tile PNG 256×256px, encoding Mapbox Terrain-RGB

---

<!-- ====================================================================== -->
<!-- SLIDE 10 — DEMO: CESIUM -->
<!-- ====================================================================== -->

## Slide 10 — Demo: CesiumJS (Globe 3D)

### URL: `http://localhost:3333/cesium-terrain.html`

### Fitur yang Ditampilkan

| Fitur | Deskripsi |
|-------|-----------|
| **Globe 3D** | Visualisasi bumi penuh dengan terrain mesh BIG |
| **Terrain Exaggeration** | Adjustable 0.5×–5× |
| **Wireframe Mode** | Lihat mesh triangulasi secara langsung |
| **Globe Lighting** | Pencahayaan matahari realistis |
| **Cursor Elevation** | Ketinggian real-time di posisi kursor |
| **Camera Readout** | Lon, Lat, Height, Heading, Pitch, Roll |

### Mengapa CesiumJS Penting?

- Format **standar OGC** untuk terrain 3D di web
- Digunakan oleh NASA, USGS, Airbus, dan puluhan agensi geospasial dunia
- Mendukung **level-of-detail otomatis** — mesh disederhanakan saat zoom out
- Data BIG bisa disajikan dalam format yang **interoperable secara global**

---

<!-- ====================================================================== -->
<!-- SLIDE 11 — PERFORMA -->
<!-- ====================================================================== -->

## Slide 11 — Angka Performa & Skala

### Referensi Zoom Level (di Khatulistiwa Indonesia)

| Zoom | Meter/Piksel | Cakupan Tile |
|------|-------------|-------------|
| 14 | ~9.55 m | ~2.4 km |
| 15 | ~4.77 m | ~1.2 km |
| 16 | ~2.39 m | ~612 m |
| 17 | ~1.19 m | ~306 m |
| **18** | **~0.60 m** | **~153 m** |

### Hasil POC — Manado (~20 km²)

| Metrik | Nilai |
|--------|-------|
| Jumlah piksel | ~23 juta |
| Ukuran raw | ~90 MB |
| Ukuran COG | ~38 MB (58% kompresi lossless) |
| Jumlah terrain tile (Z0–Z18) | ~15.000 file |
| Ukuran per tile | 1–50 KB (gzip) |
| Kecepatan baking | ~1000–5000 tile/detik |

### Proyeksi Skala Nasional

| Wilayah | Luas Daratan | Piksel | Estimasi COG | File (Z18) |
|---------|-------------|--------|-------------|------------|
| Sulawesi Utara | ~13.800 km² | ~14 miliar | ~25 GB | ~8 juta |
| Jawa | ~129.000 km² | ~129 miliar | ~200 GB | ~80 juta |
| **Nasional** | **~1.900.000 km²** | **~1,9 triliun** | **~3 TB** | **~1,2 miliar** |

---

<!-- ====================================================================== -->
<!-- SLIDE 12 — DEPLOYMENT -->
<!-- ====================================================================== -->

## Slide 12 — Deployment: Dari Laptop ke VPS ke Cloud

### Opsi Deployment

| Lingkungan | Spesifikasi | Konfigurasi |
|------------|------------|-------------|
| **Lokal (Dev)** | Laptop/PC biasa | `docker compose up -d` — 3 container |
| **VPS (Produksi Awal)** | 1 GB RAM, 1 vCPU | `docker compose -f docker-compose-vps.yml up -d` |
| **Cloud (Nasional)** | Scalable | Object storage + CDN + auto-scaling |

### Konfigurasi VPS (1 GB RAM)

Optimasi yang sudah diterapkan pada `docker-compose-vps.yml`:

| Parameter | Nilai Lokal | Nilai VPS | Alasan |
|-----------|------------|-----------|--------|
| Uvicorn workers | 2 | 1 | Hemat RAM |
| GDAL cache | 75% RAM | 128 MB fixed | Cegah crash OOM |
| VSI cache | 512 MB | 32 MB | Sesuaikan RAM |
| Memory limit | — | 400 MB | Hard cap per container |
| Viewer maxzoom | 18 | 17 | Kurangi beban request |

### Akses via Cloudflare Tunnel

```
Internet → Cloudflare Tunnel → viewer-gateway (Nginx) → Hub services
                                      │
                                 Docker network: cfnet (external)
```

- Zero port exposure ke internet
- HTTPS otomatis via Cloudflare
- Tanpa domain khusus — cukup subdomain Cloudflare

---

<!-- ====================================================================== -->
<!-- SLIDE 13 — INTEGRASI -->
<!-- ====================================================================== -->

## Slide 13 — Integrasi dengan Infrastruktur Existing

### Posisi dalam Ekosistem BIG

```
┌─────────────────────────────────────────────────────┐
│                INFRASTRUKTUR BIG                    │
│                                                     │
│  ┌──────────────────────┐  ┌──────────────────────┐ │
│  │  ArcGIS Image Server │  │  DEM Server Pipeline │ │
│  │  (Server Existing)   │  │  (POC Ini)           │ │
│  │                      │  │                      │ │
│  │  • Governance        │  │  • Web delivery      │ │
│  │  • Analisis tingkat  │  │  • 3D visualisasi    │ │
│  │    lanjut            │  │  • Terrain streaming │ │
│  │  • Desktop GIS       │  │  • Browser-based     │ │
│  │  • Kontrol akses     │  │  • Open source       │ │
│  └──────────┬───────────┘  └──────────┬───────────┘ │
│             │                          │            │
│             └──────────┬───────────────┘            │
│                        │                            │
│              ┌─────────▼─────────┐                  │
│              │  Data DEM BIG     │                  │
│              │  (Sumber Tunggal) │                  │
│              └───────────────────┘                  │
└─────────────────────────────────────────────────────┘
```

### Pembagian Peran

| Aspek | ArcGIS Image Server | DEM Server Pipeline |
|-------|---------------------|---------------------|
| **Pengguna** | Analis GIS internal | Publik, developer, WebGIS |
| **Akses** | Desktop (ArcGIS/QGIS) | Browser, mobile |
| **Format** | LERC, native raster | Terrain-RGB PNG, Quantized Mesh |
| **Kekuatan** | Analisis raster, geoprocessing | Visualisasi 3D, streaming cepat |
| **Lisensi** | Esri License | Fully Open Source |

### Tidak Menggantikan — Melengkapi

- ArcGIS Image Server tetap menjadi **server otoritatif** untuk governance
- DEM Server Pipeline adalah **layer delivery performa tinggi** untuk web & mobile
- Sumber data sama — konversi satu arah, tidak ada duplikasi logika

---

<!-- ====================================================================== -->
<!-- SLIDE 14 — TECH STACK -->
<!-- ====================================================================== -->

## Slide 14 — Stack Teknologi

### Seluruh Pipeline Menggunakan Open Source

| Komponen | Teknologi | Lisensi |
|----------|-----------|---------|
| Container Runtime | Docker / Podman | Apache 2.0 |
| GDAL (Preprocessing) | `ghcr.io/osgeo/gdal:alpine-small-3.12.1` | MIT |
| TiTiler (PNG Hub) | `ghcr.io/developmentseed/titiler:1.1.1` | MIT |
| CTB (Mesh Baking) | `tumgis/ctb-quantized-mesh` | Apache 2.0 |
| Gateway | Nginx Alpine | BSD-2 |
| Viewer 2D/2.5D | MapLibre GL JS 5.17 | BSD-3 |
| Viewer 3D | CesiumJS 1.122 | Apache 2.0 |
| Kontur Client-side | maplibre-contour 0.1.0 | BSD-3 |
| MosaicJSON | cogeo-mosaic | MIT |
| Orchestration | Docker Compose | Apache 2.0 |

### Tidak Ada Vendor Lock-in

- Semua komponen bisa diganti secara independen
- Data tersimpan dalam format standar (COG, Quantized Mesh)
- Tidak ada lisensi komersial yang diperlukan untuk serving

---

<!-- ====================================================================== -->
<!-- SLIDE 15 — COMMAND RINGKAS -->
<!-- ====================================================================== -->

## Slide 15 — Perintah Ringkas: Dari Nol ke Serving

### Full Pipeline dalam 4 Perintah

```bash
# Masuk ke direktori
cd .dem-server

# 1. Letakkan file DEM
cp /path/to/NLP_TIF/*.tif data/source/sulawesi/

# 2. Konversi ke COG (satu kali per batch data baru)
docker compose -f docker-compose.preprocess.yml run --rm preprocess

# 3. Buat indeks + bake mesh (satu kali per region)
REGION=sulawesi docker compose -f docker-compose.preprocess.yml run --rm mosaic
REGION=sulawesi docker compose -f docker-compose.tile.yml run --rm tile

# 4. Jalankan server
docker compose up -d
```

### Akses

| Viewer | URL |
|--------|-----|
| MapLibre (2D/2.5D) | http://localhost:3333/maplibre-terrain.html |
| CesiumJS (3D Globe) | http://localhost:3333/cesium-terrain.html |

### Menambah Region Baru

```bash
# Cukup buat folder baru dan jalankan pipeline
mkdir -p data/source/jawa
cp /path/to/jawa/*.tif data/source/jawa/

docker compose -f docker-compose.preprocess.yml run --rm preprocess
REGION=jawa docker compose -f docker-compose.preprocess.yml run --rm mosaic
REGION=jawa docker compose -f docker-compose.tile.yml run --rm tile

# Restart server — Mesh Hub auto-detect region baru
docker compose restart
```

---

<!-- ====================================================================== -->
<!-- SLIDE 16 — TANTANGAN SKALA NASIONAL -->
<!-- ====================================================================== -->

## Slide 16 — Tantangan Skala Nasional & Solusi

### Masalah "Miliaran File"

DEM 1 meter nasional Indonesia pada zoom 18 menghasilkan **~1,2 miliar tile**. Filesystem tradisional tidak dirancang untuk ini.

### Strategi yang Sudah Diterapkan

| Strategi | Detail |
|----------|--------|
| **Partisi Regional** | Bake per pulau/provinsi, bukan seluruh nasional sekaligus |
| **Virtual Compositor** | Mesh Hub menyatukan folder regional secara otomatis |
| **COG + MosaicJSON** | Tidak perlu pre-tile untuk MapLibre — on-the-fly dari COG |
| **Bake Once** | Terrain mesh hanya di-bake sekali lalu disajikan statis |

### Strategi Masa Depan (untuk Skala Penuh)

| Strategi | Detail |
|----------|--------|
| **Object Storage** | Pindahkan tile ke S3/MinIO — filesystem tak terbatas |
| **CDN** | Cache tile di edge — kurangi beban server |
| **PMTiles** | Simpan pyramid tile dalam 1 file (menghindari masalah miliaran file) |
| **Kubernetes** | Auto-scale TiTiler berdasarkan beban |

---

<!-- ====================================================================== -->
<!-- SLIDE 17 — LANGKAH SELANJUTNYA -->
<!-- ====================================================================== -->

## Slide 17 — Langkah Selanjutnya

### Jangka Pendek (1–3 Bulan)

- [ ] Bake region tambahan (Jawa, Sumatra) sebagai validasi skala
- [ ] Deploy ke Server BIG
- [ ] Integrasi endpoint DEM server ke WebGIS BIG yang sudah ada
- [ ] Dokumentasi API endpoint untuk tim developer lain

### Jangka Menengah (3–6 Bulan)

- [ ] Migrasi tile ke object storage (S3-compatible)
- [ ] Implementasi PMTiles untuk mengurangi jumlah file
- [ ] Tambah autentikasi layer (API key / session) untuk kontrol akses
- [ ] Performance audit & caching layer (CDN)

### Jangka Panjang (6–12 Bulan)

- [ ] Coverage nasional penuh — semua pulau utama
- [ ] Integrasi dengan ArcGIS Image Server via Sharp Proxy (Terrain-RGB dari LERC)
- [ ] Serve DEM melalui protokol OGC Tiles resmi
- [ ] Evaluasi untuk rilis publik sebagai layanan nasional

---

<!-- ====================================================================== -->
<!-- SLIDE 18 — RINGKASAN -->
<!-- ====================================================================== -->

## Slide 18 — Ringkasan

### Apa yang Sudah Dibuktikan

| Aspek | Status |
|-------|--------|
| DEM 1m BIG bisa disajikan di browser | ✅ Berhasil |
| Terrain 3D dengan MapLibre GL JS | ✅ Berhasil |
| Globe 3D dengan CesiumJS | ✅ Berhasil |
| Hillshade, kontur, slope on-the-fly | ✅ Berhasil |
| Deploy di VPS 1GB RAM | ✅ Berhasil |
| Pipeline dari NLP TIF ke web | ✅ Terotomasi 4 perintah |
| Arsitektur scalable multi-region | ✅ Terverifikasi (Sulawesi POC) |
| Seluruh stack open source | ✅ Tanpa lisensi komersial |

### Pesan Utama

> BIG memiliki DEM resolusi tertinggi di Indonesia. Dengan pipeline ini, kita bisa menyajikannya langsung ke browser web — tanpa kehilangan kualitas, tanpa vendor lock-in, dan siap untuk skala nasional.

---

<!-- ====================================================================== -->
<!-- SLIDE 19 — Q&A -->
<!-- ====================================================================== -->

## Slide 19 — Tanya Jawab

### Terima Kasih

Badan Informasi Geospasial (BIG)

Demo langsung tersedia di:
- MapLibre: `http://localhost:3333/maplibre-terrain.html`
- CesiumJS: `http://localhost:3333/cesium-terrain.html`

Repository: `.dem-server/`

---

*Presentasi ini dibuat berdasarkan implementasi POC aktual — semua angka, perintah, dan arsitektur merujuk pada kode yang berjalan.*
