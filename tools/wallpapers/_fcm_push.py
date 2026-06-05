# -*- coding: utf-8 -*-
"""FCM HTTP v1 API helper — sends data-only push notifications to topics.

Used by wp_admin_server.py to notify Pixora clients that CMS strings have
changed and they should invalidate their Hive cache. The Flutter client
subscribes to topic 'text_cms_update' via PushNotificationService.

Auth uses a Firebase service account JSON (separate from KEYS_LOCAL.md — it
lives in the orbixprivate repo so it stays out of Pixora-IA git history).

If the service account JSON is missing or the request fails, this module
returns False without raising. The dashboard upsert still succeeds (the
cache will just refresh on the user's next TTL tick / resume / pull).
"""
from __future__ import annotations
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleAuthRequest

# Path to the Firebase Admin SDK service account JSON.
# Lives in the orbixprivate repo (not in Pixora-IA) so it's never accidentally
# committed. If this file is missing, send_text_cms_update() returns False.
SERVICE_ACCOUNT_PATH = Path(
    r"D:/Orbix/orbixprivate/secrets/pixora-firebase/firebase-service-account.json"
)

# Firebase project ID (matches Pixora's android/app/google-services.json).
PROJECT_ID = "device-streaming-bab2df46"

# Scope required to send FCM messages via HTTP v1 API.
_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

# Cached credentials + token to avoid re-reading the JSON on every push.
_creds: service_account.Credentials | None = None
_token: str | None = None
_token_exp: float = 0.0


def _get_access_token() -> str | None:
    """Return a valid OAuth2 access token for FCM, refreshing if needed.
    Tokens are cached for ~50 min (Google issues 60-min tokens, we refresh
    10 min early to be safe). Returns None if the service account file is
    missing or auth fails — caller handles that as a soft failure."""
    global _creds, _token, _token_exp
    if not SERVICE_ACCOUNT_PATH.exists():
        return None
    now = time.time()
    if _token is not None and now < _token_exp:
        return _token
    try:
        if _creds is None:
            _creds = service_account.Credentials.from_service_account_file(
                str(SERVICE_ACCOUNT_PATH),
                scopes=[_FCM_SCOPE],
            )
        _creds.refresh(GoogleAuthRequest())
        _token = _creds.token
        # Refresh 10 minutes before actual expiry.
        _token_exp = now + (50 * 60)
        return _token
    except Exception as e:
        print(f"[FCM] auth failed: {e}")
        return None


def send_to_topic(topic: str, data: dict[str, Any]) -> bool:
    """Send a data-only push to all devices subscribed to [topic].
    Returns True on HTTP 200, False otherwise (including missing creds).
    All values in [data] must be strings (FCM v1 requirement)."""
    token = _get_access_token()
    if token is None:
        return False
    url = f"https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send"
    # FCM v1 requires all data values to be strings.
    stringified = {k: str(v) for k, v in data.items()}
    body = {
        "message": {
            "topic": topic,
            "data": stringified,
            # android.priority HIGH ensures wake-up on background apps.
            "android": {"priority": "HIGH"},
        }
    }
    try:
        res = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json; UTF-8",
            },
            data=json.dumps(body),
            timeout=10,
        )
        if res.status_code == 200:
            return True
        print(f"[FCM] push failed HTTP {res.status_code}: {res.text[:200]}")
        return False
    except Exception as e:
        print(f"[FCM] push exception: {e}")
        return False


def send_text_cms_update() -> bool:
    """Convenience wrapper — push the text_cms_invalidate signal to all
    Pixora clients. Called by wp_admin_server.py after every upsert."""
    return send_to_topic(
        topic="text_cms_update",
        data={
            "type": "text_cms_invalidate",
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        },
    )


# Valid scopes accepted by the Flutter client's
# PushNotificationService._handleCatalogInvalidate(). Any other value is
# logged and ignored by the app.
VALID_CATALOG_SCOPES = {
    "wallpapers",
    "live",
    "stories",
    "day_cycle",
    "ringtones",
    "events",
    "aura",
    "realm",
    "all",
}


def send_catalog_invalidate(scope: str) -> bool:
    """Push the catalog_invalidate signal to all Pixora clients (Tier 3,
    2026-05-18). The Flutter client clears the matching service's cache;
    the next user scroll / pull-to-refresh / app resume picks up the
    fresh content from Supabase Storage or Postgres.

    [scope] must be one of VALID_CATALOG_SCOPES — falsy or unknown values
    return False without sending."""
    if scope not in VALID_CATALOG_SCOPES:
        print(f"[FCM] invalid catalog scope: {scope!r}")
        return False
    return send_to_topic(
        topic="new_content",
        data={
            "type": "catalog_invalidate",
            "scope": scope,
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        },
    )


if __name__ == "__main__":
    # Direct invocation: send a test push and report result.
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "catalog":
        target = sys.argv[2] if len(sys.argv) > 2 else "all"
        ok = send_catalog_invalidate(target)
        print(f"send_catalog_invalidate({target!r}) -> {ok}")
    else:
        ok = send_text_cms_update()
        print(f"send_text_cms_update -> {ok}")
