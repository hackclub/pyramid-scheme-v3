import os
import re
import json
import io
import tempfile
import hmac
import logging
import ipaddress
from datetime import datetime
from typing import Optional
from pathlib import Path
from urllib.parse import urlencode
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import RedirectResponse, Response, StreamingResponse
from pydantic import BaseModel, Field
import asyncpg
import qrcode
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
from pypdf import PdfReader, PdfWriter
from PIL import Image

# Pydantic models for poster generation
class PosterRequest(BaseModel):
    content: str = Field(min_length=1, max_length=2048)  # URL to encode in QR code
    campaign_slug: str = Field(min_length=1, max_length=64)
    style: str = Field(default="color", max_length=32)  # color, bw, or printer_efficient
    referral_code: Optional[str] = Field(default=None, max_length=64)

class BatchPosterRequest(BaseModel):
    posters: list[dict] = Field(min_length=1, max_length=100)  # List of {content, referral_code, poster_type} dicts
    campaign_slug: str = Field(min_length=1, max_length=64)

app = FastAPI(title="proxy", docs_url=None, redoc_url=None)
logger = logging.getLogger("proxy")

# Database connection pool
db_pool = None

# Campaign subdomain mapping - maps incoming subdomains to campaign slugs and target domains
CAMPAIGN_DOMAINS = {
    "flavortown.hack.club": {"slug": "flavortown", "target": "https://flavortown.hackclub.com"},
    "aces.hack.club": {"slug": "aces", "target": "https://aces.hackclub.com"},
    "construct.hack.club": {"slug": "construct", "target": "https://construct.hackclub.com"},
    "sleepover.hack.club": {"slug": "sleepover", "target": "https://sleepover.hackclub.com"},
    "hctg.hack.club": {"slug": "hctg", "target": "https://game.hackclub.com"},
}

DEFAULT_CAMPAIGN = {"slug": "flavortown", "target": "https://flavortown.hackclub.com"}
ALLOWED_CAMPAIGN_SLUGS = frozenset(CAMPAIGN_DOMAINS[host]["slug"] for host in CAMPAIGN_DOMAINS) | {DEFAULT_CAMPAIGN["slug"]}
ALLOWED_STYLES = frozenset({"bw", "printer_efficient", "color"})
ASSET_ROOT = Path("/app/assets/images").resolve()

# QR code coordinates for each campaign and style
# PDF dimensions vary by campaign; y is from bottom edge
QR_COORDINATES = {
    "flavortown": {
        "color": {"x": 847, "y": 119, "size": 258},
        "bw": {"x": 530, "y": 122, "size": 218},
        "printer_efficient": {"x": 847, "y": 119, "size": 258}
    },
    "aces": {
        "color": {"x": 857, "y": 148, "size": 226},
        "bw": {"x": 115, "y": 175, "size": 230},
        "printer_efficient": {"x": 857, "y": 148, "size": 226}
    },
    "construct": {
        "color": {"x": 20, "y": 132, "size": 175},
        "bw": {"x": 20, "y": 132, "size": 175},
        "printer_efficient": {"x": 20, "y": 132, "size": 175}
    },
    "sleepover": {
        "color": {"x": 1133, "y": 71, "size": 326},
        "bw": {"x": 1144, "y": 81, "size": 299},
        "printer_efficient": {"x": 1149, "y": 82, "size": 318}
    },
    "hctg": {
        "color": {"x": 1217, "y": 58, "size": 199},
        "bw": {"x": 1217, "y": 58, "size": 199}
    }
}

# Referral code text coordinates for each campaign and style
REFERRAL_CODE_COORDINATES = {
    "flavortown": {
        "color": {"x": 595, "y": 62, "size": 18, "color": "FFFFFF"},
        "bw": {"x": 595, "y": 62, "size": 18, "color": "000000"},
        "printer_efficient": {"x": 595, "y": 62, "size": 18, "color": "FFFFFF"}
    },
    "aces": {
        "color": {"x": 595, "y": 55, "size": 16, "color": "8B1A1A"},
        "bw": {"x": 880, "y": 55, "size": 16, "color": "000000"},
        "printer_efficient": {"x": 595, "y": 55, "size": 16, "color": "8B1A1A"}
    },
    "construct": {
        "color": {"x": 108, "y": 120, "size": 12, "color": "000000"},
        "bw": {"x": 108, "y": 120, "size": 12, "color": "000000"},
        "printer_efficient": {"x": 108, "y": 120, "size": 12, "color": "000000"}
    },
    "sleepover": {
        "color": {"x": 530, "y": 50, "size": 18, "color": "5D4A7A"},
        "bw": {"x": 530, "y": 50, "size": 18, "color": "000000"},
        "printer_efficient": {"x": 530, "y": 50, "size": 18, "color": "000000"}
    },
    "hctg": {
        "color": {"x": 600, "y": 68, "size": 22, "color": "FFFFFF"},
        "bw": {"x": 600, "y": 68, "size": 22, "color": "000000"}
    }
}

async def get_db_pool():
    global db_pool
    if db_pool is None:
        db_pool = await asyncpg.create_pool(
            os.getenv("DATABASE_URL"),
            min_size=1,
            max_size=10
        )
    return db_pool

def get_real_ip(request: Request) -> str:
    """Get real IP from Traefik/Coolify proxy headers"""
    client_host = request.client.host if request.client else "unknown"

    try:
        client_ip = ipaddress.ip_address(client_host)
        trusted_proxy = client_ip.is_private or client_ip.is_loopback
    except ValueError:
        trusted_proxy = False

    if not trusted_proxy:
        return client_host

    # Try various proxy headers in order of preference
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        # x-forwarded-for can be a comma-separated list
        return forwarded_for.split(",")[0].strip()

    real_ip = request.headers.get("x-real-ip")
    if real_ip:
        return real_ip

    # Fallback to direct client
    return request.client.host if request.client else "unknown"

def require_internal_request(request: Request) -> None:
    """Require the shared internal key for expensive service endpoints."""
    admin_key = os.getenv("ADMIN_KEY", "")
    supplied_key = request.headers.get("x-internal-key", "")
    if not admin_key or not hmac.compare_digest(supplied_key, admin_key):
        raise HTTPException(status_code=401, detail="Unauthorized")

def get_campaign_for_host(host: str) -> dict:
    """Determine campaign based on request host"""
    # Remove port if present
    host_clean = host.split(":")[0].lower()
    return CAMPAIGN_DOMAINS.get(host_clean, DEFAULT_CAMPAIGN)

def sanitize_campaign_slug(campaign_slug: str) -> str:
    slug = (campaign_slug or DEFAULT_CAMPAIGN["slug"]).strip().lower()
    if slug not in ALLOWED_CAMPAIGN_SLUGS:
        raise HTTPException(status_code=400, detail="Invalid campaign")
    return slug

def sanitize_style(style: str) -> str:
    poster_style = (style or "color").strip().lower()
    if poster_style not in ALLOWED_STYLES:
        raise HTTPException(status_code=400, detail="Invalid poster style")
    return poster_style

def safe_asset_path(campaign_slug: str, template_filename: str) -> Path:
    template_path = (ASSET_ROOT / campaign_slug / template_filename).resolve()
    if not template_path.is_relative_to(ASSET_ROOT):
        raise HTTPException(status_code=400, detail="Invalid template path")
    return template_path

def campaign_redirect_url(target_url: str, ref: Optional[str] = None) -> str:
    if ref:
        return f"{target_url}/?{urlencode({'ref': ref})}"
    return f"{target_url}/"

def safe_filename_part(value: Optional[str], fallback: str = "generated") -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_-]+", "-", value or "").strip("-")
    return (cleaned or fallback)[:64]

def generate_qr_code_png(content: str, size: int = 300) -> bytes:
    """Generate a QR code as PNG bytes"""
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(content)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")

    # Convert to high-res PNG bytes
    img = img.resize((size * 3, size * 3), Image.Resampling.LANCZOS)

    buffer = io.BytesIO()
    img.save(buffer, format='PNG')
    return buffer.getvalue()

def get_template_path(campaign_slug: str, style: str) -> str:
    """Get the path to the PDF template for a campaign and style"""
    campaign_slug = sanitize_campaign_slug(campaign_slug)
    style = sanitize_style(style)

    # Map style names to filenames
    template_filename = {
        "bw": "poster-bw.pdf",
        "printer_efficient": "poster-printer_efficient.pdf",
        "color": "poster-color.pdf"
    }.get(style, "poster-color.pdf")

    # Path in the mounted volume (assuming Rails assets are mounted)
    template_path = safe_asset_path(campaign_slug, template_filename)

    if not template_path.exists():
        # Fall back to default campaign
        default_slug = os.getenv("DEFAULT_CAMPAIGN_SLUG", "flavortown")
        template_path = safe_asset_path(sanitize_campaign_slug(default_slug), template_filename)

    return str(template_path)

def get_qr_config(campaign_slug: str, style: str) -> dict:
    """Get QR code positioning configuration"""
    campaign_coords = QR_COORDINATES.get(campaign_slug, QR_COORDINATES["flavortown"])
    return campaign_coords.get(style, campaign_coords["color"])

def get_text_config(campaign_slug: str, style: str) -> dict:
    """Get referral code text positioning configuration"""
    campaign_coords = REFERRAL_CODE_COORDINATES.get(campaign_slug, REFERRAL_CODE_COORDINATES["flavortown"])
    return campaign_coords.get(style, campaign_coords["color"])

def hex_to_rgb(hex_color: str) -> tuple:
    """Convert hex color to RGB tuple (0-1 range for reportlab)"""
    hex_color = hex_color.lstrip('#')
    r, g, b = tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))
    return (r / 255.0, g / 255.0, b / 255.0)

def create_qr_overlay_pdf(qr_png_data: bytes, x: float, y: float, qr_size: float,
                          page_width: float, page_height: float,
                          referral_code: Optional[str] = None,
                          text_config: Optional[dict] = None) -> bytes:
    """Create a transparent PDF overlay with QR code and optional referral code text"""
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=(page_width, page_height))

    # Enable compression for reportlab-generated PDF
    c.setPageCompression(1)

    # Draw QR code
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
        tmp.write(qr_png_data)
        tmp.flush()
        tmp_path = tmp.name

    try:
        c.drawImage(tmp_path, x, y, width=qr_size, height=qr_size, mask='auto')

        # Draw referral code text if provided
        if referral_code and text_config:
            text_x = text_config.get('x', 0)
            text_y = text_config.get('y', 0)
            text_size = text_config.get('size', 18)
            text_color = text_config.get('color', '000000')

            # Set text color
            rgb = hex_to_rgb(text_color)
            c.setFillColorRGB(*rgb)

            # Set font and draw text
            c.setFont("Helvetica-Bold", text_size)
            text = f"Ref: {referral_code}"
            text_width = c.stringWidth(text, "Helvetica-Bold", text_size)
            # Center the text at the specified x coordinate
            c.drawString(text_x - text_width / 2, text_y, text)

        c.save()
    finally:
        os.unlink(tmp_path)

    buffer.seek(0)
    return buffer.read()

def generate_poster_pdf(content: str, campaign_slug: str, style: str,
                       referral_code: Optional[str] = None) -> bytes:
    """Generate a complete poster PDF with QR code overlay"""
    # Get template path
    template_path = get_template_path(campaign_slug, style)

    if not Path(template_path).exists():
        raise HTTPException(status_code=404, detail=f"Template not found for campaign '{campaign_slug}' with style '{style}'")

    # Get QR and text configurations
    qr_config = get_qr_config(campaign_slug, style)
    text_config = get_text_config(campaign_slug, style) if referral_code else None

    # Generate QR code
    qr_size = qr_config['size']
    qr_png_data = generate_qr_code_png(content, size=int(qr_size))

    # Load template PDF
    template_reader = PdfReader(template_path)
    first_page = template_reader.pages[0]

    # Get page dimensions
    page_width = float(first_page.mediabox.width)
    page_height = float(first_page.mediabox.height)

    # Create overlay PDF
    overlay_pdf_data = create_qr_overlay_pdf(
        qr_png_data=qr_png_data,
        x=qr_config['x'],
        y=qr_config['y'],
        qr_size=qr_size,
        page_width=page_width,
        page_height=page_height,
        referral_code=referral_code,
        text_config=text_config
    )

    # Merge overlay with template
    overlay_reader = PdfReader(io.BytesIO(overlay_pdf_data))

    # Create output PDF with compression
    writer = PdfWriter()
    first_page.merge_page(overlay_reader.pages[0])
    writer.add_page(first_page)

    # Write to bytes with compression
    output_buffer = io.BytesIO()

    # Add compression to writer before writing
    for page in writer.pages:
        page.compress_content_streams()

    writer.write(output_buffer)
    output_buffer.seek(0)

    return output_buffer.read()

@app.on_event("startup")
async def startup():
    await get_db_pool()

@app.on_event("shutdown")
async def shutdown():
    global db_pool
    if db_pool:
        await db_pool.close()

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/")
async def root(request: Request):
    """Handle root path - redirect to appropriate campaign, preserving ?ref= if present"""
    campaign = get_campaign_for_host(request.headers.get("host", ""))
    target_url = campaign["target"]
    
    # Preserve ?ref= query parameter if present
    ref_param = request.query_params.get("ref")
    if ref_param:
        return RedirectResponse(url=campaign_redirect_url(target_url, ref=ref_param), status_code=302)
    
    return RedirectResponse(url=campaign_redirect_url(target_url), status_code=302)

@app.post("/generate_poster")
async def generate_single_poster(poster_request: PosterRequest, request: Request):
    """Generate a single poster PDF with QR code"""
    require_internal_request(request)

    try:
        pdf_data = generate_poster_pdf(
            content=poster_request.content,
            campaign_slug=poster_request.campaign_slug,
            style=poster_request.style,
            referral_code=poster_request.referral_code
        )

        return Response(
            content=pdf_data,
            media_type="application/pdf",
            headers={
                "Content-Disposition": (
                    "attachment; filename="
                    f"poster-{safe_filename_part(poster_request.referral_code)}-"
                    f"{safe_filename_part(poster_request.style, 'color')}.pdf"
                )
            }
        )
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to generate poster")
        raise HTTPException(status_code=500, detail="Failed to generate poster")

@app.post("/generate_poster_batch")
async def generate_poster_batch(batch_request: BatchPosterRequest, request: Request):
    """Generate multiple posters merged into a single PDF"""
    require_internal_request(request)

    try:
        # Create a PDF writer for merging all posters
        merged_writer = PdfWriter()

        for index, poster_data in enumerate(batch_request.posters):
            content = str(poster_data.get('content') or "")[:2048]
            referral_code = str(poster_data.get('referral_code') or "")[:64]
            poster_type = str(poster_data.get('poster_type') or "color")[:32]

            if not content:
                continue

            # Generate PDF for this poster
            pdf_data = generate_poster_pdf(
                content=content,
                campaign_slug=batch_request.campaign_slug,
                style=sanitize_style(poster_type),
                referral_code=referral_code
            )

            # Read the generated PDF and add its page to the merged document
            pdf_reader = PdfReader(io.BytesIO(pdf_data))
            for page in pdf_reader.pages:
                merged_writer.add_page(page)

        # Write the merged PDF with compression
        output_buffer = io.BytesIO()

        # Add compression to all pages before writing
        for page in merged_writer.pages:
            page.compress_content_streams()

        merged_writer.write(output_buffer)
        output_buffer.seek(0)

        return Response(
            content=output_buffer.read(),
            media_type="application/pdf",
            headers={
                "Content-Disposition": f"attachment; filename=posters_{safe_filename_part(batch_request.campaign_slug)}.pdf"
            }
        )
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to generate poster batch")
        raise HTTPException(status_code=500, detail="Failed to generate poster batch")

@app.post("/generate_poster_batch_zip")
async def generate_poster_batch_zip(batch_request: BatchPosterRequest, request: Request):
    """Generate multiple posters as individual PDFs in a ZIP archive"""
    require_internal_request(request)

    import zipfile
    
    try:
        # Create zip file in memory
        zip_buffer = io.BytesIO()
        
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
            for index, poster_data in enumerate(batch_request.posters):
                content = str(poster_data.get('content') or "")[:2048]
                referral_code = str(poster_data.get('referral_code') or "")[:64]
                poster_type = str(poster_data.get('poster_type') or "color")[:32]

                if not content:
                    continue

                # Generate PDF for this poster
                pdf_data = generate_poster_pdf(
                    content=content,
                    campaign_slug=batch_request.campaign_slug,
                    style=sanitize_style(poster_type),
                    referral_code=referral_code
                )

                # Add to zip with meaningful filename
                filename = f"poster_{index + 1}_{safe_filename_part(referral_code)}.pdf"
                zip_file.writestr(filename, pdf_data)

        zip_buffer.seek(0)

        return Response(
            content=zip_buffer.read(),
            media_type="application/zip",
            headers={
                "Content-Disposition": f"attachment; filename=posters_{safe_filename_part(batch_request.campaign_slug)}.zip"
            }
        )
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to generate poster zip")
        raise HTTPException(status_code=500, detail="Failed to generate poster zip")

@app.get("/{code:path}")
async def proxy_referral(code: str, request: Request):
    """
    Handle referral code redirects and catch-all paths.

    - Determines campaign from request host
    - Validates the referral code format (8 alphanumeric characters)
    - Validates the referral code exists in the database
    - Logs the access with IP address and campaign
    - Redirects to campaign target with ?ref=CODE if valid
    - Redirects to campaign target for invalid codes or paths
    """
    campaign = get_campaign_for_host(request.headers.get("host", ""))
    target_url = campaign["target"]
    campaign_slug = campaign["slug"]

    # Detect poster-style links: /p/<code> should still redirect via ?ref=
    raw_code = code.strip()
    poster_link = False

    if raw_code.lower().startswith("p/"):
        poster_link = True
        raw_code = raw_code[2:]  # drop "p/"
    elif "/" in raw_code:
        # Unexpected nested path
        return RedirectResponse(url=campaign_redirect_url(target_url), status_code=302)

    # Sanitize and validate referral code format (8 alphanumeric characters)
    code_clean = raw_code.upper()

    if not re.match(r"^[A-Z0-9]{8}$", code_clean):
        # Invalid format - redirect without ref parameter
        return RedirectResponse(url=campaign_redirect_url(target_url), status_code=302)

    pool = await get_db_pool()

    # Get real IP and user agent
    ip_address = get_real_ip(request)
    user_agent = request.headers.get("user-agent", "")

    async with pool.acquire() as conn:
        # Get campaign ID for filtering
        campaign_row = await conn.fetchrow(
            "SELECT id FROM campaigns WHERE slug = $1",
            campaign_slug
        )
        campaign_id = campaign_row["id"] if campaign_row else None

        # Validate against both posters and users depending on link type
        is_valid = False
        kind = "referral"
        poster_id = None

        if poster_link:
            # Check for poster with this code, optionally filtered by campaign
            if campaign_id:
                poster = await conn.fetchrow(
                    "SELECT id FROM posters WHERE referral_code = $1 AND campaign_id = $2",
                    code_clean, campaign_id
                )
            else:
                poster = await conn.fetchrow(
                    "SELECT id FROM posters WHERE referral_code = $1",
                    code_clean
                )
            is_valid = poster is not None
            poster_id = poster["id"] if poster else None
            kind = "poster"
        else:
            # Check for user with this code (users are global, not campaign-specific)
            user = await conn.fetchrow(
                "SELECT id FROM users WHERE referral_code = $1",
                code_clean
            )
            is_valid = user is not None
            if not is_valid:
                # Fallback: poster codes might be shared without /p/
                if campaign_id:
                    poster = await conn.fetchrow(
                        "SELECT id FROM posters WHERE referral_code = $1 AND campaign_id = $2",
                        code_clean, campaign_id
                    )
                else:
                    poster = await conn.fetchrow(
                        "SELECT id FROM posters WHERE referral_code = $1",
                        code_clean
                    )
                is_valid = poster is not None
                poster_id = poster["id"] if poster else None
                kind = "poster" if is_valid else "referral"

        # Log the access - use poster_scans for poster hits, referral_code_logs for user referrals
        if kind == "poster" and poster_id:
            await conn.execute(
                """
                INSERT INTO poster_scans (poster_id, ip_address, user_agent, metadata, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                poster_id,
                ip_address,
                user_agent,
                json.dumps({"source": "proxy", "referral_type": "poster_proxy", "campaign": campaign_slug}),
                datetime.utcnow(),
                datetime.utcnow()
            )
        else:
            await conn.execute(
                """
                INSERT INTO referral_code_logs (referral_code, ip_address, user_agent, metadata, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                code_clean,
                ip_address,
                user_agent,
                json.dumps({"source": "proxy", "kind": kind, "campaign": campaign_slug}),
                datetime.utcnow(),
                datetime.utcnow()
            )

    # Redirect based on validity (poster links also go through ?ref=)
    if is_valid:
        return RedirectResponse(url=campaign_redirect_url(target_url, ref=code_clean), status_code=302)

    # Invalid code fallback
    return RedirectResponse(url=campaign_redirect_url(target_url), status_code=302)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "4446")))
