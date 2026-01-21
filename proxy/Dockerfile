FROM python:3.13-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libjpeg-dev \
    libpng-dev \
    zlib1g-dev \
    libfreetype6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

# Copy poster PDF templates from Rails app assets
COPY app/assets/images/ /app/assets/images/

COPY proxy/pyproject.toml .

# Install dependencies declared in pyproject.toml without needing a full python package build.
RUN python -c "import tomllib; from pathlib import Path; data = tomllib.loads(Path('pyproject.toml').read_text()); deps = data.get('project', {}).get('dependencies', []); Path('requirements.txt').write_text('\n'.join(deps) + '\n')"

RUN uv pip install --system --no-cache -r requirements.txt

COPY proxy/main.py .

# Health check for rolling/blue-green deployments
HEALTHCHECK --interval=10s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -fsS http://localhost:4446/health || exit 1

EXPOSE 4446

CMD ["python", "main.py"]
