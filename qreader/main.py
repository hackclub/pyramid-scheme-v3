import os
import io
import logging
import warnings
from fastapi import FastAPI, File, UploadFile, Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from PIL import Image
import numpy as np
from qreader import QReader

# Register HEIC support with Pillow
from pillow_heif import register_heif_opener
register_heif_opener()

# Initialize QReader once at startup
qreader = QReader()
logger = logging.getLogger("qreader")
MAX_UPLOAD_BYTES = 20 * 1024 * 1024
MAX_IMAGE_PIXELS = 25_000_000
Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
warnings.simplefilter("error", Image.DecompressionBombWarning)


def is_admin_request(request: Request) -> bool:
    """Check if the request has a valid admin key"""
    key = request.headers.get("x-admin-key")
    admin_key = os.getenv("ADMIN_KEY", "")
    return key == admin_key and admin_key != ""


def key_or_ip(request: Request):
    """Rate limit key function - admins get separate higher limits"""
    if is_admin_request(request):
        return f"admin_{request.headers.get('x-admin-key')}"
    return get_remote_address(request)


app = FastAPI(title="qr", docs_url=None, redoc_url=None)
limiter = Limiter(key_func=key_or_ip)
app.state.limiter = limiter


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"error": "rate limit exceeded"})


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Catch all exceptions and return JSON error"""
    logger.exception("Unhandled exception while reading QR code")
    return JSONResponse(
        status_code=500,
        content={"error": "internal server error", "results": [], "count": 0}
    )


def decode_qr_codes(img: Image.Image) -> list[str]:
    """Decode QR codes from an image using QReader"""
    # Ensure RGB mode for QReader
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    # Convert to numpy array for QReader
    arr = np.array(img)
    
    # Use QReader to detect and decode QR codes
    results = qreader.detect_and_decode(arr)
    
    # Filter out None values and return
    return [r for r in results if r]


@app.post("/read")
@limiter.limit("1000/hour")
async def read(request: Request, file: UploadFile = File(...)):
    if file.size and file.size > MAX_UPLOAD_BYTES:
        return JSONResponse(status_code=413, content={"error": "file too large (max 20MB)"})

    data = await file.read()
    if len(data) > MAX_UPLOAD_BYTES:
        return JSONResponse(status_code=413, content={"error": "file too large (max 20MB)"})

    if len(data) == 0:
        return JSONResponse(status_code=400, content={"error": "empty file"})

    try:
        img = Image.open(io.BytesIO(data))
        if img.width * img.height > MAX_IMAGE_PIXELS:
            return JSONResponse(status_code=413, content={"error": "image dimensions too large"})
        img.verify()
        img = Image.open(io.BytesIO(data))
    except Image.DecompressionBombError:
        logger.info("Rejected image upload exceeding pixel limit")
        return JSONResponse(status_code=413, content={"error": "image dimensions too large"})
    except Exception as e:
        logger.info("Invalid image upload: %s", e)
        return JSONResponse(
            status_code=400,
            content={"error": "invalid image format - supported: PNG, JPG, HEIC, WebP"}
        )

    results = decode_qr_codes(img)

    return {"results": results, "count": len(results)}


@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "4444")))
