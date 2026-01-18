FROM python:3.13-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libzbar0 \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    poppler-utils \
    imagemagick \
    ghostscript \
    && rm -rf /var/lib/apt/lists/*

# Allow ImageMagick to process PDFs (security policy)
RUN sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml 2>/dev/null || true

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

COPY pyproject.toml .

# Install dependencies declared in pyproject.toml without needing a full python package build.
RUN python -c "import tomllib; from pathlib import Path; data = tomllib.loads(Path('pyproject.toml').read_text()); deps = data.get('project', {}).get('dependencies', []); Path('requirements.txt').write_text('\n'.join(deps) + '\n')"

RUN uv pip install --system --no-cache -r requirements.txt

COPY main.py .

# Health check for rolling/blue-green deployments
HEALTHCHECK --interval=10s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -fsS http://localhost:4445/health || exit 1

EXPOSE 4445

CMD ["python", "main.py"]
