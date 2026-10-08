"""Read-only, demonstration-only multi-organisation API.

No personal records, authentication, or administrative mutations are provided.
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Community Ride Platform", version="0.1.0")
# Only local development origins. Set explicit production origins later.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8088", "http://127.0.0.1:8088"],
    allow_methods=["GET"],
    allow_headers=["Content-Type"],
)

class Theme(BaseModel):
    primary: str
    accent: str
    background: str

class Organisation(BaseModel):
    slug: str
    name: str
    short_name: str
    tagline: str
    theme: Theme
    features: dict[str, bool]

ORGANISATIONS = {
    "lr": Organisation(
        slug="lr",
        name="Widows Sons L&R",
        short_name="L&R",
        tagline="Ride together. Get home safely.",
        theme=Theme(primary="#20252e", accent="#c5a365", background="#10141b"),
        features={"events": True, "rides": True, "messages": False,
                  "intercom": False, "video": False, "email": False, "guardian": False},
    ),
    "demo": Organisation(
        slug="demo",
        name="Example Riding Association",
        short_name="Example",
        tagline="Your community, your identity.",
        theme=Theme(primary="#123b4a", accent="#37d6ba", background="#091c25"),
        features={"events": True, "rides": True, "messages": False,
                  "intercom": False, "video": False, "email": False, "guardian": False},
    ),
}
EXAMPLE_EVENTS = {
    "lr": [{"id": "lr-demo-event", "title": "Sample chapter ride-out",
            "starts_at": "2026-11-07T10:00:00+00:00", "status": "example"}],
    "demo": [{"id": "demo-event", "title": "Example social meeting",
              "starts_at": "2026-11-08T18:00:00+00:00", "status": "example"}],
}

@app.get("/health")
def health():
    return {"status": "ok", "environment": "demonstration"}

@app.get("/api/v1/organisations/{slug}", response_model=Organisation)
def organisation(slug: str):
    record = ORGANISATIONS.get(slug)
    if record is None:
        raise HTTPException(status_code=404, detail="Organisation not found")
    return record

@app.get("/api/v1/organisations/{slug}/events")
def events(slug: str):
    if slug not in ORGANISATIONS:
        raise HTTPException(status_code=404, detail="Organisation not found")
    return {"organisation": slug, "events": EXAMPLE_EVENTS[slug]}
