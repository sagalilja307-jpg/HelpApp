#!/usr/bin/env python3
from pathlib import Path
import json

from fastapi.testclient import TestClient

from helpershelp.api.app import app

client = TestClient(app)

def post(query: str):
    resp = client.post("/query", json={"query": query})
    print("Status:", resp.status_code)
    print(json.dumps(resp.json(), indent=2, ensure_ascii=False))

if __name__ == "__main__":
    # Example queries - adjust to test updated intents
    post("Vad har jag inplanerat idag?")
    post("Hur många olästa mejl har jag just nu?")
    post("När är nästa uppgift planerad?")
