from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from backend.app import Base, Board, BoardColumn, Project, Task, User, list_projects


def test_list_projects_includes_board_and_project_task_counts():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)

    with Session(engine) as db:
        user = User(username="tester", display_name="Test User", password_hash="unused")
        db.add(user)
        db.flush()

        project = Project(name="House", owner_id=user.id)
        empty_project = Project(name="Empty", owner_id=user.id)
        db.add_all([project, empty_project])
        db.flush()

        board = Board(name="Kitchen", owner_id=user.id, project_id=project.id)
        empty_board = Board(name="Bathroom", owner_id=user.id, project_id=project.id)
        db.add_all([board, empty_board])
        db.flush()

        column = BoardColumn(board_id=board.id, name="Backlog", position=0)
        db.add(column)
        db.flush()
        db.add_all([
            Task(column_id=column.id, title="Open one", created_by_id=user.id, completed=False),
            Task(column_id=column.id, title="Open two", created_by_id=user.id, completed=False),
            Task(column_id=column.id, title="Done", created_by_id=user.id, completed=True),
        ])
        db.commit()

        projects = list_projects(db, user)

    assert projects == [
        {
            "id": project.id,
            "name": "House",
            "boards": [
                {
                    "id": board.id,
                    "name": "Kitchen",
                    "project_id": project.id,
                    "task_count": 3,
                    "open_task_count": 2,
                    "completed_task_count": 1,
                },
                {
                    "id": empty_board.id,
                    "name": "Bathroom",
                    "project_id": project.id,
                    "task_count": 0,
                    "open_task_count": 0,
                    "completed_task_count": 0,
                },
            ],
            "board_count": 2,
            "task_count": 3,
            "open_task_count": 2,
            "completed_task_count": 1,
        },
        {
            "id": empty_project.id,
            "name": "Empty",
            "boards": [],
            "board_count": 0,
            "task_count": 0,
            "open_task_count": 0,
            "completed_task_count": 0,
        },
    ]
