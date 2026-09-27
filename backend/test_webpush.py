"""1.14.0: Web Push (PWA) pipeline tests — VAPID key persistence, subscribe
endpoints, delivery + stale-pruning via a stubbed push service."""

import base64

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from backend import app as app_module
from backend.app import (
    Base,
    PushSubscription,
    User,
    VAPID_PRIVATE_KEY,
    WebPushSubscribeIn,
    _vapid_keys,
    get_setting,
    send_webpush,
    webpush_subscribe,
)


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine)
    with SessionLocal() as session:
        yield session


def _user(db: Session) -> User:
    user = User(username="pwa", display_name="PWA User", password_hash="unused")
    db.add(user)
    db.commit()
    return user


def _sub(user_id: int, endpoint: str) -> PushSubscription:
    return PushSubscription(
        user_id=user_id,
        endpoint=endpoint,
        p256dh=base64.urlsafe_b64encode(b"k" * 65).decode().rstrip("="),
        auth=base64.urlsafe_b64encode(b"a" * 16).decode().rstrip("="),
    )


def test_vapid_keys_generated_once_and_stable(db):
    first = _vapid_keys(db)
    assert first is not None, "cryptography+py_vapid must be available in the image"
    private_b64, public_b64 = first
    # stored in the settings table so it survives restarts
    assert get_setting(db, VAPID_PRIVATE_KEY) == private_b64
    # standard p256dh: 65-byte uncompressed EC point, b64url, no padding
    assert len(base64.urlsafe_b64decode(public_b64 + "==")) == 65
    second = _vapid_keys(db)
    assert second == first, "keys must never rotate implicitly"


def test_subscribe_upserts_by_endpoint(db):
    user = _user(db)
    payload = WebPushSubscribeIn(
        endpoint="https://fcm.googleapis.com/fcm/send/abc-1",
        keys_p256dh="p" * 80,
        keys_auth="a" * 20,
    )
    webpush_subscribe(payload, db, user)
    row = db.scalar(select(PushSubscription).where(PushSubscription.user_id == user.id))
    assert row.endpoint == payload.endpoint
    # re-subscribe with rotated keys must UPDATE, not duplicate
    payload2 = WebPushSubscribeIn(
        endpoint=payload.endpoint, keys_p256dh="q" * 80, keys_auth="b" * 20
    )
    webpush_subscribe(payload2, db, user)
    rows = db.scalars(select(PushSubscription)).all()
    assert len(rows) == 1
    assert rows[0].p256dh == payload2.keys_p256dh
    # the same browser re-subscribing under another account MOVES the row
    other = User(username="pwa2", display_name="Other", password_hash="unused")
    db.add(other)
    db.commit()
    webpush_subscribe(payload2, db, other)
    moved = db.scalar(select(PushSubscription).where(PushSubscription.endpoint == payload.endpoint))
    assert moved.user_id == other.id


def test_send_webpush_delivers_and_prunes_gone(db, monkeypatch):
    user = _user(db)
    db.add(_sub(user.id, "https://push.example.com/ok-1"))
    db.add(_sub(user.id, "https://push.example.com/gone-1"))
    db.commit()

    class FakeResp:
        def __init__(self, code):
            self.status_code = code

    calls = {}

    def fake_send(self, *args, **kwargs):
        endpoint = self.subscription_info["endpoint"]
        calls[endpoint] = kwargs
        return FakeResp(410 if "gone" in endpoint else 201)

    from pywebpush import WebPusher

    monkeypatch.setattr(WebPusher, "send", fake_send)

    delivered = send_webpush(db, user, "My Team", "Zdravo PWA", board_id=7)

    assert delivered == 1
    # payload travelled as JSON with title/body/boardId
    import json as _json

    sent_payload = _json.loads(calls["https://push.example.com/ok-1"]["data"])
    assert sent_payload == {"title": "My Team", "body": "Zdravo PWA", "boardId": 7}
    # the 410 (gone) subscription was pruned on the spot
    remaining = db.scalars(select(PushSubscription)).all()
    assert [r.endpoint for r in remaining] == ["https://push.example.com/ok-1"]


def test_notify_task_users_sends_webpush_in_addition_to_fcm(db, monkeypatch):
    """Channel contract: webpush is ADDITIVE (PWA users may not own the
    FCM-registered phone); FCM-not-delivered still falls back to ntfy."""
    from backend.app import Board, BoardColumn, Task, notify_task_users

    actor = _user(db)
    target = User(username="branko", display_name="Branko", password_hash="unused")
    db.add(target)
    board = Board(name="B", owner_id=actor.id)
    db.add(board)
    db.flush()
    column = BoardColumn(board_id=board.id, name="Col", position=0)
    db.add(column)
    db.flush()
    task = Task(column_id=column.id, title="hello @branko", created_by_id=actor.id)
    db.add(task)
    db.commit()

    pushed = {"webpush": [], "fcm": 0, "ntfy": 0}

    monkeypatch.setattr(
        app_module, "send_webpush",
        lambda db, user, title, body, board_id=None: pushed["webpush"].append(user.username) or 1,
    )
    monkeypatch.setattr(
        app_module, "send_fcm",
        lambda db, user, message, board_id=None, board_name="": False,
    )
    monkeypatch.setattr(
        app_module, "send_ntfy",
        lambda user, title, message: pushed.__setitem__("ntfy", pushed["ntfy"] + 1) or True,
    )
    monkeypatch.setattr(app_module, "duplicate_push_recently", lambda task_id, message: False)

    notify_task_users(db, actor, task)

    assert pushed["webpush"] == ["branko"], "webpush fires even when FCM delivered"
    assert pushed["ntfy"] == 1, "ntfy fallback still runs when FCM returns False"


def test_pwa_http_flow_vapid_subscribe_test(db, monkeypatch):
    """End-to-end HTTP flow the PWA performs: fetch VAPID key, subscribe,
    run the server-side test push."""
    from fastapi.testclient import TestClient
    from sqlalchemy.pool import StaticPool

    # one SHARED in-memory connection: schema + data visible from every
    # request thread TestClient spawns
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine)
    with SessionLocal() as setup:
        user = User(username="pwa3", display_name="PWA HTTP", password_hash="unused")
        setup.add(user)
        setup.commit()
        user_id = user.id

    def override_db():
        session = SessionLocal()
        try:
            yield session
        finally:
            session.close()

    app_module.app.dependency_overrides[app_module.db_session] = override_db
    app_module.app.dependency_overrides[app_module.current_user] = (
        lambda: SessionLocal().get(User, user_id)
    )
    monkeypatch.setattr(app_module, "send_webpush",
                        lambda db, user, title, body, board_id=None: 1)
    try:
        client = TestClient(app_module.app)
        r = client.get("/api/me/webpush/vapid")
        assert r.status_code == 200
        public_key = r.json()["public_key"]
        assert len(base64.urlsafe_b64decode(public_key + "==")) == 65

        r = client.post("/api/me/webpush/subscribe", json={
            "endpoint": "https://fcm.googleapis.com/fcm/send/test-123",
            "keys_p256dh": "p" * 80,
            "keys_auth": "a" * 20,
        })
        assert r.status_code == 200 and r.json()["ok"] is True

        r = client.post("/api/me/webpush/test", json={})
        assert r.status_code == 200
        body = r.json()
        assert body["ok"] is True and body["devices"] == 1
    finally:
        app_module.app.dependency_overrides.clear()
