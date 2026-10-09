"""Regression checks for the read-only, tenant-scoped prototype."""
from fastapi.testclient import TestClient
from app import app

client = TestClient(app)

def test_health():
    assert client.get("/health").json()["status"] == "ok"

def test_distinct_branding():
    lr = client.get("/api/v1/organisations/lr").json()
    demo = client.get("/api/v1/organisations/demo").json()
    assert lr["name"] == "Widows Sons L&R"
    assert lr["theme"] != demo["theme"]

def test_isolated_events():
    lr = client.get("/api/v1/organisations/lr/events").json()
    demo = client.get("/api/v1/organisations/demo/events").json()
    assert all(e["id"].startswith("lr-") for e in lr["events"])
    assert all(e["id"].startswith("demo-") for e in demo["events"])

def test_unknown_tenant_is_not_found():
    assert client.get("/api/v1/organisations/unknown").status_code == 404
    assert client.get("/api/v1/organisations/unknown/events").status_code == 404

def test_no_admin_write_endpoints():
    assert client.post("/api/v1/organisations/lr/events", json={}).status_code == 405
