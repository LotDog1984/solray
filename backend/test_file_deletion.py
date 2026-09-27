from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import backend.app as app


def test_delete_file_removes_stored_file_thumbnail_and_database_row(tmp_path, monkeypatch):
    engine = create_engine("sqlite:///:memory:")
    app.Base.metadata.create_all(bind=engine)
    monkeypatch.setattr(app, "STORAGE_DIR", tmp_path)
    events = []
    monkeypatch.setattr(app, "notify_change", lambda *args: events.append(args))

    with Session(engine) as db:
        user = app.User(username="tester", display_name="Test User", password_hash="unused")
        db.add(user)
        db.flush()
        project = app.Project(name="House", owner_id=user.id)
        db.add(project)
        db.flush()

        stored_path = tmp_path / "House" / "stored.txt"
        stored_path.parent.mkdir()
        stored_path.write_bytes(b"uploaded content")
        thumbnail = app.thumbnail_path(stored_path)
        thumbnail.write_bytes(b"thumbnail")

        uploaded = app.StoredFile(
            original_name="notes.txt",
            stored_name="House/stored.txt",
            content_type="text/plain",
            size=stored_path.stat().st_size,
            uploaded_by_id=user.id,
            project_id=project.id,
        )
        db.add(uploaded)
        db.commit()
        file_id = uploaded.id

        result = app.delete_file(file_id, db, user)

        assert result == {"ok": True}
        assert db.get(app.StoredFile, file_id) is None
        assert not stored_path.exists()
        assert not thumbnail.exists()
        assert events == [("files", project.id)]
