import os
import re
import json
from datetime import datetime
from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse
import asyncpg

app = FastAPI(title="proxy", docs_url=None, redoc_url=None)

# Database connection pool
db_pool = None

# Campaign subdomain mapping - maps incoming subdomains to campaign slugs and target domains
CAMPAIGN_DOMAINS = {
    "flavortown.hack.club": {"slug": "flavortown", "target": "https://flavortown.hackclub.com"},
    "aces.hack.club": {"slug": "aces", "target": "https://aces.hackclub.com"},
    "construct.hack.club": {"slug": "construct", "target": "https://construct.hackclub.com"},
    "sleepover.hack.club": {"slug": "sleepover", "target": "https://sleepover.hackclub.com"},
}

DEFAULT_CAMPAIGN = {"slug": "flavortown", "target": "https://flavortown.hackclub.com"}

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

def get_campaign_for_host(host: str) -> dict:
    """Determine campaign based on request host"""
    # Remove port if present
    host_clean = host.split(":")[0].lower()
    return CAMPAIGN_DOMAINS.get(host_clean, DEFAULT_CAMPAIGN)

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
        return RedirectResponse(url=f"{target_url}/?ref={ref_param}", status_code=302)
    
    return RedirectResponse(url=f"{target_url}/", status_code=302)

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
        return RedirectResponse(url=f"{target_url}/", status_code=302)

    # Sanitize and validate referral code format (8 alphanumeric characters)
    code_clean = raw_code.upper()

    if not re.match(r"^[A-Z0-9]{8}$", code_clean):
        # Invalid format - redirect without ref parameter
        return RedirectResponse(url=f"{target_url}/", status_code=302)

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
        return RedirectResponse(url=f"{target_url}/?ref={code_clean}", status_code=302)

    # Invalid code fallback
    return RedirectResponse(url=f"{target_url}/", status_code=302)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "4446")))
