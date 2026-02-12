#!/usr/bin/env python

import logging

try:
    from pyngrok import ngrok
except Exception as exc:
    raise SystemExit(
        "pyngrok is not installed. Install it with: pip install pyngrok"
    ) from exc


logging.basicConfig(level=logging.INFO)

# Connect to your FastAPI backend running on port 8000
BACKEND_PORT = 8000

tunnel = ngrok.connect(BACKEND_PORT, "http")
logging.info("=" * 60)
logging.info("🚀 Ngrok tunnel connected to FastAPI backend!")
logging.info("=" * 60)
logging.info("Public URL: %s", tunnel.public_url)
logging.info("Local backend: http://127.0.0.1:%s", BACKEND_PORT)
logging.info("")
logging.info("Try these endpoints:")
logging.info("  • %s/healthz", tunnel.public_url)
logging.info("  • %s/llm/interpret-query", tunnel.public_url)
logging.info("  • %s/llm/similarity", tunnel.public_url)
logging.info("=" * 60)
logging.info("Press Ctrl+C to stop the tunnel.")

try:
    # Keep the tunnel open
    import time
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    logging.info("Shutting down tunnel...")
    ngrok.disconnect(tunnel.public_url)
    ngrok.kill()
    logging.info("Tunnel stopped cleanly.")