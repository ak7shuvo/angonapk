# Production-style image for the ANGON API. NOTE: written for V1 but not built or
# run in the development environment; verify it in your own pipeline.
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY alembic.ini ./
COPY app ./app
COPY migrations ./migrations

# Never run as root.
RUN useradd --system --uid 10001 --no-create-home angon
USER angon

EXPOSE 8000
# --proxy-headers/--forwarded-allow-ips: trust X-Forwarded-For only from your
# reverse proxy (set FORWARDED_ALLOW_IPS), so rate limits see real client IPs.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips=\"${FORWARDED_ALLOW_IPS:-127.0.0.1}\""]
