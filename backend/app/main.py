import os

import psycopg
from fastapi import FastAPI, HTTPException

from app.routing import router as routing_router

app = FastAPI(
    title="Iran Navigator API",
    version="0.2.0",
    description="Shared API scaffold and server-side routing provider proxy for Iran Navigator.",
)

app.include_router(routing_router)


@app.get("/healthz", tags=["system"])
def healthz() -> dict[str, str]:
    """Liveness check; does not require the database."""
    return {"status": "ok", "service": "iran-navigator-api"}


@app.get("/readyz", tags=["system"])
def readyz() -> dict[str, str]:
    """Readiness check; confirms PostgreSQL is reachable."""
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise HTTPException(status_code=503, detail="DATABASE_URL is not configured")

    try:
        with psycopg.connect(database_url, connect_timeout=3) as connection:
            connection.execute("SELECT 1")
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database is unavailable") from exc

    return {"status": "ready", "database": "connected"}
