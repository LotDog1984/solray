"""1.20.0/1.21.0: project archiving (Arhiva).

Contract points verified here (direct call style, like the other suites):
- archive_project/unarchive_project flip projects.archived
- list_projects returns ONLY active projects, each row flagged archived False
- list_archived_projects returns ONLY archived ones (archived True), same
  shape incl. boards + counts — nothing inside the project is filtered
- search_everything skips archived projects, their boards, tasks and Nabava
- a projectless board lands in the first ACTIVE project, never an archived one
- 1.21.0: NO new boards into an archived project, NO new tasks on its boards
  (Arhiva is read-only for additions — existing content stays fully editable)
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from backend.app import (
    Base,
    Board,
    BoardColumn,
    BoardIn,
    Project,
    Task,
    TodoEntry,
    TodoList,
    User,
    archive_project,
    create_board,
    list_archived_projects,
    list_projects,
    search_everything,
    unarchive_project,
)


def _setup():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)
    return engine, Session(engine)


def _user(db: Session) -> User:
    user = User(username="tester", display_name="Test User", password_hash="unused")
    db.add(user)
    db.flush()
    return user


def test_archive_unarchive_and_project_lists():
    engine, db = _setup()
    user = _user(db)
    active = Project(name="Aktivan", owner_id=user.id)
    done = Project(name="Gotov", owner_id=user.id)
    db.add_all([active, done])
    db.flush()
    db.add(Board(name="Aktivna ploča", owner_id=user.id, project_id=active.id))
    done_board = Board(name="Arhivirana ploča", owner_id=user.id, project_id=done.id)
    db.add(done_board)
    db.commit()

    # before: everything is active
    ids = {p["id"] for p in list_projects(db, user)}
    assert ids == {active.id, done.id}

    result = archive_project(done.id, db, user)
    assert result == {"id": done.id, "name": "Gotov", "archived": True}

    active_rows = {p["id"]: p for p in list_projects(db, user)}
    assert set(active_rows) == {active.id}
    assert active_rows[active.id]["archived"] is False

    archived_rows = {p["id"]: p for p in list_archived_projects(db, user)}
    assert set(archived_rows) == {done.id}
    assert archived_rows[done.id]["archived"] is True
    assert archived_rows[done.id]["board_count"] == 1
    assert archived_rows[done.id]["boards"][0]["name"] == "Arhivirana ploča"

    # unarchive: back on the projects page, Arhiva empties out
    assert unarchive_project(done.id, db, user) == {
        "id": done.id,
        "name": "Gotov",
        "archived": False,
    }
    assert {p["id"] for p in list_projects(db, user)} == {active.id, done.id}
    assert list_archived_projects(db, user) == []


def test_missing_project_archive_404():
    import pytest
    from fastapi import HTTPException

    engine, db = _setup()
    user = _user(db)
    with pytest.raises(HTTPException) as exc:
        archive_project(99999, db, user)
    assert exc.value.status_code == 404


def test_search_skips_archived_projects():
    engine, db = _setup()
    user = _user(db)
    active = Project(name="Boja", owner_id=user.id)
    done = Project(name="Boja uskoro", owner_id=user.id)
    db.add_all([active, done])
    db.flush()
    active_board = Board(name="Plava ploča", owner_id=user.id, project_id=active.id)
    db.add(active_board)
    done_board = Board(name="Zatvorena ploča", owner_id=user.id, project_id=done.id)
    db.add(done_board)
    db.flush()
    column = BoardColumn(board_id=done_board.id, name="Todo", position=0)
    db.add(column)
    db.flush()
    db.add(Task(column_id=column.id, title="sijena", created_by_id=user.id))
    todo = TodoList(board_id=done_board.id)
    db.add(todo)
    db.flush()
    db.add(TodoEntry(todo_list_id=todo.id, title="sijena boje"))
    db.commit()

    q = "sijena"
    before = [(r["type"], r["board_id"], r["project_id"]) for r in search_everything(db, user, q)["results"]]
    assert ("task", done_board.id, done.id) in before
    assert ("nabava", done_board.id, done.id) in before

    archive_project(done.id, db, user)
    after = [(r["type"], r["board_id"], r["project_id"]) for r in search_everything(db, user, q)["results"]]
    assert ("task", done_board.id, done.id) not in after
    assert ("nabava", done_board.id, done.id) not in after

    # the active project's board still matches by name
    board_hits = [r["label"] for r in search_everything(db, user, "Plava")["results"]]
    assert "Plava ploča" in board_hits

    # unarchive → everything reappears in search
    unarchive_project(done.id, db, user)
    restored = [(r["type"], r["board_id"], r["project_id"]) for r in search_everything(db, user, q)["results"]]
    assert ("task", done_board.id, done.id) in restored


def test_projectless_board_skips_archived_projects():
    engine, db = _setup()
    user = _user(db)
    done = Project(name="Old", owner_id=user.id)
    active = Project(name="Live", owner_id=user.id)
    db.add_all([done, active])
    db.commit()
    archive_project(done.id, db, user)

    created = create_board(BoardIn(name="Sama ploča"), db, user)
    assert created["project_id"] == active.id

    by_id = {p["id"]: p for p in list_projects(db, user)}
    board_names = [b["name"] for b in by_id[active.id]["boards"]]
    assert "Sama ploča" in board_names


def _archived_project_with_board_and_column(db: Session, user: User):
    active = Project(name="Aktivan", owner_id=user.id)
    done = Project(name="Gotov", owner_id=user.id)
    db.add_all([active, done])
    db.flush()
    board = Board(name="Ploča od Gotov", owner_id=user.id, project_id=done.id)
    db.add(board)
    db.flush()
    column = BoardColumn(board_id=board.id, name="Todo", position=0)
    db.add(column)
    db.commit()
    archive_project(done.id, db, user)
    return active, board, column


def test_no_new_board_into_archived_project():
    import pytest
    from fastapi import HTTPException

    engine, db = _setup()
    user = _user(db)
    active, done_board, _col = _archived_project_with_board_and_column(db, user)

    with pytest.raises(HTTPException) as exc:
        create_board(BoardIn(name="Nova u Arhivi", project_id=done_board.project_id), db, user)
    assert exc.value.status_code == 403
    assert "Arhivi" in exc.value.detail

    # unarchive → adding works again; adding to a still-archived project is refused,
    # and adding to the active project was never blocked
    unarchive_project(done_board.project_id, db, user)
    ok = create_board(BoardIn(name="Nova nakon vraćanja", project_id=done_board.project_id), db, user)
    assert ok["project_id"] == done_board.project_id
    assert create_board(BoardIn(name="Nova u aktivnom", project_id=active.id), db, user)["project_id"] == active.id


def test_no_new_task_on_archived_board():
    import pytest
    from fastapi import HTTPException

    from backend.app import TaskIn, create_task

    engine, db = _setup()
    user = _user(db)
    _active, done_board, column = _archived_project_with_board_and_column(db, user)

    with pytest.raises(HTTPException) as exc:
        create_task(TaskIn(column_id=column.id, title="Nova zadaća"), db, user)
    assert exc.value.status_code == 403
    assert "Arhivi" in exc.value.detail

    # unarchive → tasks flow again into the same column
    unarchive_project(done_board.project_id, db, user)
    created = create_task(TaskIn(column_id=column.id, title="Nova zadaća"), db, user)
    assert created["id"]
