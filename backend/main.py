"""FastAPI backend for MVP: user auth (signup/login), health check, and route planning."""

import os
from typing import List, Tuple

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, EmailStr

from database import get_db, init_db
from passlib.context import CryptContext

app = FastAPI(title="MVP Backend")


@app.exception_handler(HTTPException)
def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "message": exc.detail if isinstance(exc.detail, str) else str(exc.detail)},
    )


@app.exception_handler(RequestValidationError)
def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = exc.errors()
    msg = errors[0].get("msg", "Invalid request") if errors else "Invalid request"
    if errors and "email" in str(errors[0].get("loc", [])):
        msg = "Invalid email format"
    return JSONResponse(status_code=400, content={"success": False, "message": msg})

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Backend-only Google Maps API key.
# Set this environment variable before running the app, for example:
#   export GOOGLE_MAPS_SERVER_API_KEY="YOUR_SERVER_SIDE_API_KEY"
GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_SERVER_API_KEY")


class SignupRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RouteRequest(BaseModel):
    """Request body for route planning."""

    origin: str
    destination: str


class RoutePoint(BaseModel):
    lat: float
    lng: float


def decode_polyline(encoded: str) -> List[Tuple[float, float]]:
    """Decode a polyline that was encoded using the Google Maps algorithm.

    Returns a list of (lat, lng) tuples.
    """
    points: List[Tuple[float, float]] = []
    index = 0
    lat = 0
    lng = 0

    while index < len(encoded):
        result = 0
        shift = 0
        while True:
            if index >= len(encoded):
                break
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1F) << shift
            shift += 5
            if b < 0x20:
                break
        dlat = ~(result >> 1) if (result & 1) else (result >> 1)
        lat += dlat

        result = 0
        shift = 0
        while True:
            if index >= len(encoded):
                break
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1F) << shift
            shift += 5
            if b < 0x20:
                break
        dlng = ~(result >> 1) if (result & 1) else (result >> 1)
        lng += dlng

        points.append((lat / 1e5, lng / 1e5))

    return points


@app.on_event("startup")
def startup():
    init_db()


@app.get("/health")
def health():
    return {"success": True}


@app.post("/signup")
def signup(body: SignupRequest):
    if not body.email or not body.password:
        raise HTTPException(status_code=400, detail="Email and password are required")
    if len(body.password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    password_hash = pwd_context.hash(body.password)
    with get_db() as conn:
        cur = conn.execute(
            "SELECT id FROM users WHERE email = ?",
            (body.email.lower(),),
        )
        if cur.fetchone():
            raise HTTPException(status_code=400, detail="Email already registered")

        conn.execute(
            "INSERT INTO users (email, password_hash) VALUES (?, ?)",
            (body.email.lower(), password_hash),
        )
    return {"success": True}


@app.post("/login")
def login(body: LoginRequest):
    if not body.email or not body.password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    with get_db() as conn:
        cur = conn.execute(
            "SELECT id, password_hash FROM users WHERE email = ?",
            (body.email.lower(),),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not pwd_context.verify(body.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return {"success": True}


@app.post("/route")
def get_route(body: RouteRequest):
    """Fetch a route between origin and destination using Google Directions API.

    The frontend should send:
      {
        "origin": "Bremen Central Station",
        "destination": "Bremen Airport"
      }

    The response will be:
      {
        "success": true,
        "distance_text": "...",
        "duration_text": "...",
        "points": [{"lat": ..., "lng": ...}, ...]
      }
    """
    if not body.origin or not body.destination:
        return {
            "success": False,
            "message": "Both origin and destination are required.",
        }

    if not GOOGLE_MAPS_API_KEY:
        return {
            "success": False,
            "message": "Server is not configured with GOOGLE_MAPS_SERVER_API_KEY.",
        }

    params = {
        "origin": body.origin,
        "destination": body.destination,
        "key": GOOGLE_MAPS_API_KEY,
    }

    try:
        with httpx.Client(timeout=10) as client:
            resp = client.get(
                "https://maps.googleapis.com/maps/api/directions/json",
                params=params,
            )
    except httpx.HTTPError:
        return {
            "success": False,
            "message": "Route could not be fetched (network error).",
        }

    if resp.status_code != 200:
        return {
            "success": False,
            "message": f"Route could not be fetched (status {resp.status_code}).",
        }

    data = resp.json()
    status = data.get("status")
    if status != "OK":
        return {
            "success": False,
            "message": f"Route could not be fetched (status={status}).",
        }

    routes = data.get("routes") or []
    if not routes:
        return {
            "success": False,
            "message": "No routes found.",
        }

    route = routes[0]
    legs = route.get("legs") or []
    leg = legs[0] if legs else {}

    distance_text = (leg.get("distance") or {}).get("text")
    duration_text = (leg.get("duration") or {}).get("text")

    overview_polyline = (route.get("overview_polyline") or {}).get("points")
    if not overview_polyline:
        return {
            "success": False,
            "message": "Route could not be fetched (missing polyline).",
        }

    coords = decode_polyline(overview_polyline)
    points = [{"lat": lat, "lng": lng} for lat, lng in coords]

    return {
        "success": True,
        "distance_text": distance_text,
        "duration_text": duration_text,
        "points": points,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
