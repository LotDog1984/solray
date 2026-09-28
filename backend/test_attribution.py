"""1.15.0: per-user attribution — who created a task/Stavka, who marked it
done and who edited it last. All fields are additive; legacy rows keep NULL
attribution and everything degrades to no badge.

Covers the three "who" questions the feature asks:
  1. created_by on tasks and todo entries (set at creation),
  2. completed_by / done_by on marking done (cleared on untick),
  3. edited_by on every mutation (PATCH, checklist tick, move, rename),
  4. deleting a user must not 500 on the new attribution FKs.
"""

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
    TaskItemIn,
    TaskMoveIn,
    TodoEntryIn,
    User,
    add_nabava_item,
    add_todo_entry,
    create_task,
    delete_user,
    get_global_todo_list,
    move_task,
    serialize_task,
    serialize_todo_entries,
    toggle_completed,
    update_nabava_item,
    update_task,
    update_task_item,
    update_todo_entry,
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


def _board_with_column(db, owner):
    project = Project(name="P", owner_id=owner.id)
    db.add(project)
    db.flush()
    board = Board(name="B", owner_id=owner.id, project_id=project.id)
    db.add(board)
    db.flush()
    column = BoardColumn(board_id=board.id, name="Col", position=0)
    db.add(column)
    db.commit()
    return board, column

def test_task_created_by_and_completed_by(db):
    branko = _user(db, "branko")
    luka = _user(db, "luka")
    board, column = _board_with_column(db, branko)

    task_id = create_task(TaskIn(column_id=column.id, title="Zadatak"), db, branko)["id"]

    data = serialize_task(db.get(Task, task_id))
    assert data["created_by"] == "Branko"
    assert data["completed_by"] is None

    # Luka marks it done — the badge must show Luka, not the creator.
    toggle_completed(task_id, db, luka)
    data = serialize_task(db.get(Task, task_id))
    assert data["completed"] is True
    assert data["completed_by"] == "Luka"

    # Unticking clears the marker again.
    toggle_completed(task_id, db, luka)
    data = serialize_task(db.get(Task, task_id))
    assert data["completed"] is False
    assert data["completed_by"] is None


def test_task_edit_records_last_editor(db):
    branko, column = _board_with_column(db, _user(db, "branko"))
    luka = _user(db, "luka")

    task_id = create_task(TaskIn(column_id=column.id, title="Start"), db, branko)["id"]

    update_task(task_id, TaskIn(column_id=None, title="Uređeno"), db, luka)
    data = serialize_task(db.get(Task, task_id))
    assert data["edited_by"] == "Luka"
    assert data["edited_at"] is not None

    # Moving a task is an edit too.
    col2 = BoardColumn(board_id=1, name="C2", position=1)
    db.add(col2)
    db.commit()
    move_task(task_id, TaskMoveIn(column_id=col2.id, position=0), db, branko)
    data = serialize_task(db.get(Task, task_id))
    assert data["edited_by"] == "Branko"


def test_checklist_completion_attributes_last_item_actor(db):
    branko, column = _board_with_column(db, _user(db, "branko"))
    luka = _user(db, "luka")

    task_id = create_task(
        TaskIn(
            column_id=column.id,
            title="Popis",
            items=[TaskItemIn(title="Prva", is_done=False), TaskItemIn(title="Druga", is_done=False)],
        ),
        db,
        branko,
    )["id"]
    items = sorted(db.get(Task, task_id).items, key=lambda i: i.position)

    # Branko ticks the first item — task not yet complete.
    update_task_item(task_id, items[0].id, TaskItemIn(title="Prva", is_done=True), db, branko)
    assert db.get(Task, task_id).completed is False

    # Luka ticks the last one — Luka completed the task.
    update_task_item(task_id, items[1].id, TaskItemIn(title="Druga", is_done=True), db, luka)
    data = serialize_task(db.get(Task, task_id))
    assert data["completed"] is True
    assert data["completed_by"] == "Luka"


def test_todo_entry_created_done_and_edited_by(db):
    owner = _user(db, "branko")
    board, _ = _board_with_column(db, owner)
    luka = _user(db, "luka")

    entry_id = add_todo_entry(board.id, TodoEntryIn(title="Ekruv"), db, owner)["id"]

    data = serialize_todo_entries(board.todo_list.entries)[0]
    assert data["created_by"] == "Branko"
    assert data["done_by"] is None

    # Luka ticks it as bought.
    update_todo_entry(board.id, entry_id, TodoEntryIn(title=None, is_done=True), db, luka)
    data = serialize_todo_entries(board.todo_list.entries)[0]
    assert data["is_done"] is True
    assert data["done_by"] == "Luka"

    # Unticking clears the marker; a rename records the editor.
    update_todo_entry(board.id, entry_id, TodoEntryIn(title="Ekruvi", is_done=False), db, luka)
    data = serialize_todo_entries(board.todo_list.entries)[0]
    assert data["done_by"] is None
    assert data["edited_by"] == "Luka"
    assert data["title"] == "Ekruvi"


def test_nabava_manual_item_attribution(db):
    branko = _user(db, "branko")
    luka = _user(db, "luka")

    entry_id = add_nabava_item(TodoEntryIn(title="Čavli"), db, branko)["id"]
    update_nabava_item(entry_id, TodoEntryIn(is_done=True), db, luka)

    data = serialize_todo_entries(get_global_todo_list(db).entries)[0]
    assert data["created_by"] == "Branko"
    assert data["done_by"] == "Luka"


def test_delete_user_clears_attribution_without_500(db):
    admin = _user(db, "admin", is_admin=True)
    victim = _user(db, "stari")
    board, column = _board_with_column(db, admin)

    task_id = create_task(TaskIn(column_id=column.id, title="t"), db, victim)["id"]
    entry_id = add_todo_entry(board.id, TodoEntryIn(title="s"), db, victim)["id"]
    toggle_completed(task_id, db, victim)
    update_todo_entry(board.id, entry_id, TodoEntryIn(is_done=True), db, victim)
    update_task(task_id, TaskIn(title="t2"), db, victim)

    delete_user(victim.id, db, admin)

    data = serialize_task(db.get(Task, task_id))
    # Creation survives (re-linked to the acting admin), completion/edit are cleared.
    assert data["created_by"] == "Admin"
    assert data["completed_by"] is None
    assert data["edited_by"] is None
    entry = serialize_todo_entries(board.todo_list.entries)[0]
    assert entry["created_by"] == "Admin"
    assert entry["done_by"] is None
    assert entry["edited_by"] is None
