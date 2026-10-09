"""Read-only public PostgreSQL API. No personal member data exposed."""
import psycopg
from fastapi import APIRouter, HTTPException

router = APIRouter(prefix="/api/v1/public", tags=["public"])
DSN = "dbname=widowssons user=www-data host=/var/run/postgresql"

@router.get("/{slug}/profile")
def public_profile(slug: str):
    with psycopg.connect(DSN) as connection:
        record = connection.execute(
            "SELECT slug, name, display_name, theme FROM organisations WHERE slug=%s",
            (slug,),
        ).fetchone()
    if record is None:
        raise HTTPException(404, "Organisation not found")
    return {"slug": record[0], "name": record[1], "display_name": record[2], "theme": record[3]}

@router.get("/{slug}/events")
def public_events(slug: str):
    with psycopg.connect(DSN) as connection:
        exists = connection.execute(
            "SELECT id FROM organisations WHERE slug=%s", (slug,)
        ).fetchone()
        if exists is None:
            raise HTTPException(404, "Organisation not found")
        rows = connection.execute(
            """SELECT e.id, e.title, e.description, e.begins_at
               FROM chapter_events e
               JOIN organisations o ON e.organisation_id=o.id
               WHERE o.slug=%s AND e.status='published'
               ORDER BY e.begins_at LIMIT 100""",
            (slug,),
        ).fetchall()
    return {"organisation": slug,
            "events": [{"id": str(row[0]), "title": row[1], "description": row[2],
                        "starts_at": row[3].isoformat(), "status": "published"}
                       for row in rows]}
