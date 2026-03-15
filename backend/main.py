"""FastAPI backend for MVP: user auth (signup/login) and health check."""

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


class SignupRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
