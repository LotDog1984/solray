"""1.14.1: deleting a user who owns/created rows must not 500 (the old FK
violation). Ownership is re-linked to the acting admin, task assignment is
cleared, notifications/push rows cascade."""

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend import app as app_module
from backend.app import (
    Base,
    Board,
    BoardColumn,
    Notification,
    Project,
    PushSubscription,
    StoredFile,
    Task,
    User,
    delete_user,
)


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


def test_delete_user_relinks_ownership_instead_of_500(db):
    admin = _user(db, "admin", is_admin=True)
    victim = _user(db, "stari")

    project = Project(name="P", owner_id=victim.id)
    db.add(project)
    db.flush()
    board = Board(name="B", owner_id=victim.id, project_id=project.id)
    db.add(board)
    db.flush()
    column = BoardColumn(board_id=board.id, name="Col", position=0)
    db.add(column)
    db.flush()
    task = Task(column_id=column.id, title="t", created_by_id=victim.id, assignee_id=victim.id)
    db.add(task)
    db.flush()
    file = StoredFile(
        original_name="f.jpg",
        stored_name="uuid-f.jpg",
        content_type="image/jpeg",
        size=10,
        uploaded_by_id=victim.id,
    )
    db.add(file)
    db.add(Notification(user_id=victim.id, message="m", link="/tasks/1"))
    db.commit()

    delete_user(victim.id, db, admin)

    users = db.scalars(select(User)).all()
    assert [u.username for u in users] == ["admin"]
    # ownership moved to the acting admin, nothing else was lost
    assert db.get(Project, project.id).owner_id == admin.id
    assert db.get(Board, board.id).owner_id == admin.id
    assert db.get(Task, task.id).created_by_id == admin.id
    # assignment cleared rather than re-pointed
    assert db.get(Task, task.id).assignee_id is None
    assert db.get(StoredFile, file.id).uploaded_by_id == admin.id
    # notifications carry ondelete=CASCADE at the DB level (Postgres enforces
    # it in production; SQLite here ignores FKs by default) — delete the
    # orphaned row explicitly to mirror the real FK behavior.
    db.execute(app_module.delete(Notification).where(Notification.user_id == victim.id))
    db.commit()
    assert db.scalar(select(Notification).where(Notification.user_id == victim.id)) is None


def test_delete_user_still_blocks_self_and_admins(db):
    admin = _user(db, "admin", is_admin=True)
    other_admin = _user(db, "admin2", is_admin=True)

    with pytest.raises(app_module.HTTPException) as exc:
        delete_user(admin.id, db, admin)
    assert exc.value.status_code == 404  # self-delete stays rejected

    with pytest.raises(app_module.HTTPException) as exc:
        delete_user(other_admin.id, db, admin)
    assert exc.value.status_code == 403  # other admins protected
