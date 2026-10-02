"""1.16.0: Nabava group + "Pošalji obavijest" + file rename.

Covers:
  1. nabava_group setting roundtrip (admin PUT, non-admin 403, stale-ID cleanup),
  2. notify_nabava_group — exact message text, in-app rows, one channel call per
     user, the sender is NOT notified, deleted group members are skipped,
  3. POST /api/nabava/notify — ok/notified counts and the empty-group reason,
  4. PATCH /api/files/{id} — rename display name, validation errors.
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app import (
    Base,
    FileRenameIn,
    Notification,
    Project,
    SettingsIn,
    StoredFile,
    User,
    get_nabava_group,
    notify_nabava,
    notify_nabava_group,
    rename_file,
    set_nabava_group,
    update_settings,
)
import backend.app as app_module


NABAVA_MESSAGE = "Dodane nove stvari za nabavu"


@pytest.fixture()
def db():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine)
    with SessionLocal() as session:
        yield session


def _user(db, name, is_admin=False):
    u = User(username=name, display_name=name.title(), password_hash="unused", is_admin=is_admin)
    db.add(u)
    db.commit()
    return u


# ------------------------------- 1. settings --------------------------------


def test_nabava_group_setting_roundtrip(db):
    branko = _user(db, "branko", is_admin=True)
    ivana = _user(db, "ivana")

    set_nabava_group(db, [branko.id, ivana.id])
    db.commit()
    assert get_nabava_group(db) == [branko.id, ivana.id]

    # update_settings persists the group and filters out unknown IDs / duplicates
    result = update_settings(
        SettingsIn(app_name="SolRay", nabava_group=[ivana.id, 999, ivana.id]),
        db,
        branko,
    )
    assert result.nabava_group == [ivana.id]
    assert get_nabava_group(db) == [ivana.id]


def test_nabava_group_non_admin_forbidden(db):
    branko = _user(db, "branko", is_admin=True)
    ivana = _user(db, "ivana")
    from backend.app import HTTPException

    with pytest.raises(HTTPException) as exc:
        update_settings(SettingsIn(app_name="SolRay", nabava_group=[branko.id]), db, ivana)
    assert exc.value.status_code == 403


# -------------------------- 2. notify_nabava_group --------------------------


def test_notify_group_sends_exact_message(db, monkeypatch):
    branko = _user(db, "branko", is_admin=True)
    ivana = _user(db, "ivana")
    luka = _user(db, "luka")
    set_nabava_group(db, [branko.id, ivana.id, luka.id])
    db.commit()

    calls = {"fcm": [], "ntfy": [], "webpush": []}
    monkeypatch.setattr(app_module, "send_fcm", lambda db, user, message, **kw: calls["fcm"].append(user.id) or True)
    monkeypatch.setattr(app_module, "send_ntfy", lambda user, title, message: calls["ntfy"].append(user.id) or True)
    monkeypatch.setattr(app_module, "send_webpush", lambda db, user, title, body, **kw: calls["webpush"].append(user.id) or 1)

    delivered = notify_nabava_group(db, branko, 3)
    assert delivered == 2  # sender (branko) is skipped
    rows = db.scalars(select(Notification)).all()
    assert sorted(n.user_id for n in rows) == sorted([ivana.id, luka.id])
    for n in rows:
        assert n.message == NABAVA_MESSAGE  # the exact text the user asked for
    # FCM accepted → ntfy fallback stays silent; web push always tried
    assert calls["fcm"] == sorted([ivana.id, luka.id])
    assert calls["ntfy"] == []
    assert sorted(calls["webpush"]) == sorted([ivana.id, luka.id])


def test_notify_group_fcm_failure_falls_back_to_ntfy(db, monkeypatch):
    branko = _user(db, "branko", is_admin=True)
    ivana = _user(db, "ivana")
    set_nabava_group(db, [ivana.id])
    db.commit()

    ntfy_calls = []
    monkeypatch.setattr(app_module, "send_fcm", lambda db, user, message, **kw: False)
    monkeypatch.setattr(app_module, "send_ntfy", lambda user, title, message: ntfy_calls.append(user.id) or True)
    monkeypatch.setattr(app_module, "send_webpush", lambda db, user, title, body, **kw: 0)

    assert notify_nabava_group(db, branko, 1) == 1
    assert ntfy_calls == [ivana.id]


def test_notify_group_skips_deleted_members(db, monkeypatch):
    branko = _user(db, "branko", is_admin=True)
    ivana = _user(db, "ivana")
    set_nabava_group(db, [ivana.id, 4242])  # 4242 never existed
    db.commit()

    pushed = []
    monkeypatch.setattr(app_module, "send_fcm", lambda db, user, message, **kw: pushed.append(user.id) or True)
    monkeypatch.setattr(app_module, "send_ntfy", lambda user, title, message: True)
    monkeypatch.setattr(app_module, "send_webpush", lambda db, user, title, body, **kw: 1)

    assert notify_nabava_group(db, branko, 1) == 1
    assert pushed == [ivana.id]


# ----------------------------- 3. notify endpoint ---------------------------


def test_notify_endpoint_counts_and_empty_reason(db, monkeypatch):
    branko = _user(db, "branko", is_admin=True)
    ivana = _user(db, "ivana")
    user_id = branko.id
    SessionLocal = sessionmaker(bind=db.get_bind())

    def override_db():
        session = SessionLocal()
        try:
            yield session
        finally:
            session.close()

    app_module.app.dependency_overrides[app_module.db_session] = override_db
    app_module.app.dependency_overrides[app_module.current_user] = (lambda: db.get(User, user_id))
    monkeypatch.setattr(app_module, "send_fcm", lambda db, user, message, **kw: True)
    monkeypatch.setattr(app_module, "send_ntfy", lambda user, title, message: True)
    monkeypatch.setattr(app_module, "send_webpush", lambda db, user, title, body, **kw: 1)
    try:
        client = TestClient(app_module.app)

        # empty group → honest reason, ok False
        r = client.post("/api/nabava/notify")
        assert r.status_code == 200
        body = r.json()
        assert body["ok"] is False and body["notified"] == 0
        assert "Postavkama" in body["reason"]

        set_nabava_group(db, [ivana.id])
        db.commit()
        r = client.post("/api/nabava/notify")
        assert r.status_code == 200
        body = r.json()
        assert body["ok"] is True and body["notified"] == 1
    finally:
        app_module.app.dependency_overrides.clear()


# ------------------------------ 4. file rename ------------------------------


def _file(db, user, name="stara_slika.jpg"):
    project = Project(name="P", owner_id=user.id)
    db.add(project)
    db.flush()
    row = StoredFile(
        original_name=name,
        stored_name=f"uuid_{name}",
        content_type="image/jpeg",
        size=123,
        uploaded_by_id=user.id,
        project_id=project.id,
    )
    db.add(row)
    db.commit()
    return row


def test_rename_file_updates_display_name(db):
    user = _user(db, "branko", is_admin=True)
    row = _file(db, user)
    result = rename_file(row.id, FileRenameIn(name="  Novi naziv  "), db, user)
    assert result == {"id": row.id, "name": "Novi naziv"}
    assert db.get(StoredFile, row.id).original_name == "Novi naziv"
    # stored_name (the on-disk name) must never change
    assert db.get(StoredFile, row.id).stored_name == f"uuid_stara_slika.jpg"


def test_rename_file_validation(db):
    user = _user(db, "branko", is_admin=True)
    row = _file(db, user)
    from backend.app import HTTPException

    with pytest.raises(HTTPException) as exc:
        rename_file(row.id, FileRenameIn(name="   "), db, user)
    assert exc.value.status_code == 400

    with pytest.raises(HTTPException) as exc:
        rename_file(99999, FileRenameIn(name="x"), db, user)
    assert exc.value.status_code == 404
