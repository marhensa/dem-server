import logging
import warnings
from titiler.application.main import app as base_app
from titiler.mosaic.factory import MosaicTilerFactory
from cogeo_mosaic.backends import MosaicBackend
from rio_tiler.errors import EmptyMosaicError
from fastapi import Request
from fastapi.responses import JSONResponse

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Silence rio_tiler colormap conversion warnings (float32 -> Int)
warnings.filterwarnings("ignore", category=UserWarning, module="rio_tiler.colormap")


# Catch EmptyMosaicError to prevent Uvicorn/H11 crashes and log spam
@base_app.exception_handler(EmptyMosaicError)
async def empty_mosaic_handler(request: Request, exc: EmptyMosaicError):
    return JSONResponse(
        status_code=404,
        content={"detail": "Tile outside of mosaic bounds or contains no data."},
    )


logger.info("Starting PNG Terrain Server Hub (MapLibre/TiTiler)...")

try:
    # Initialize the Mosaic Factory for seamless PNG delivery
    mosaic = MosaicTilerFactory(backend=MosaicBackend)
    base_app.include_router(mosaic.router, prefix="/mosaic", tags=["Mosaic"])
    logger.info("PNG Mosaic endpoints (/mosaic) enabled.")
except Exception as e:
    logger.error(f"Failed to initialize PNG Mosaic Factory: {e}")

app = base_app
