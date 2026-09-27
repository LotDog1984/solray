"""1.14.1: PATCH /api/tasks/{id} treats column_id/position as OPTIONAL —
omitting them must keep the task in its column (older mobile clients used to
silently move edited tasks to the first column)."""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app import (
    Base,
    Board,
    BoardColumn,
    Project,
    Task,
    TaskIn,
    User,
    create_task,
    update_task,
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


def _board_with_two_columns(db):
    user = User(username="u", display_name="U", password_hash="unused")
    db.add(user)
    project = Project(name="P", owner_id=1)
    db.add(project)
    db.flush()
    board = Board(name="B", owner_id=user.id, project_id=project.id)
    db.add(board)
    db.flush()
    col1 = BoardColumn(board_id=board.id, name="Col1", position=0)
    col2 = BoardColumn(board_id=board.id, name="Col2", position=1)
    db.add_all([col1, col2])
    db.commit()
    return user, col1, col2


def test_create_then_edit_without_column_id_stays_in_column(db):
    user, col1, col2 = _board_with_two_columns(db)

    created = create_task(
        TaskIn(column_id=col2.id, title="Nova stavka"), db, user
    )
    task_id = created["id"]
    assert db.get(Task, task_id).column_id == col2.id

    # Edit WITHOUT column_id (the 1.14.1 mobile behavior): task must NOT move.
    update_task(task_id, TaskIn(column_id=None, title="Izmijenjeno"), db, user)
    assert db.get(Task, task_id).column_id == col2.id
    assert db.get(Task, task_id).title == "Izmijenjeno"

    # Explicit move still works.
    update_task(task_id, TaskIn(column_id=col1.id, title="Izmijenjeno"), db, user)
    assert db.get(Task, task_id).column_id == col1.id

    # position omitted = untouched.
    original_position = db.get(Task, task_id).position
    update_task(task_id, TaskIn(column_id=None, title="Izmijenjeno"), db, user)
    assert db.get(Task, task_id).position == original_position
