import io
import os
import re
import shutil
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated

import base64

import requests
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from PIL import Image
from pydantic import BaseModel, ConfigDict
from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    create_engine, 
    select, 
    func,
    or_,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, relationship, sessionmaker


# Compose contract: POSTGRES_PASSWORD (or DB_PASSWORD) env var feeds the default
# connection string so a single inline secret in the compose file configures
# everything (postgres + backend) with no .env file.
_db_pw = os.getenv("DB_PASSWORD") or os.getenv("POSTGRES_PASSWORD") or "workspace_password"
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    f"postgresql+psycopg2://workspace:{_db_pw}@db:5432/workspace",
)
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret")
JWT_ALGORITHM = "HS256"
STORAGE_DIR = Path(os.getenv("STORAGE_DIR", "./uploads"))
NTFY_URL = os.getenv("NTFY_URL", "").rstrip("/")
# Public address of this instance's ntfy (e.g. https://ntfy.example.com) — served
# via GET /api/settings so mobile clients can subscribe without baked-in domains.
# Public ntfy URL handed to mobile clients for their WebSocket subscription.
# Prefer NTFY_PUBLIC_URL (e.g. https://ntfy.example.com, reachable from
# phones); fall back to NTFY_BASE_URL so stacks that only set the shared
# var still expose *something* (LAN-only, works at home).
NTFY_PUBLIC_URL = (os.getenv("NTFY_PUBLIC_URL") or os.getenv("NTFY_BASE_URL") or "").rstrip("/")
CORS_ORIGINS = [origin.strip() for origin in os.getenv("CORS_ORIGINS", "http://localhost:8080").split(",")]

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
passwords = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(80))
    password_hash: Mapped[str] = mapped_column(String(255))
    ntfy_topic: Mapped[str | None] = mapped_column(String(160), nullable=True)
    # Flag indicating whether this account has administrative privileges.
    # Only admins may create new users via the API. The default is ``False`` so
    # that existing accounts remain unchanged unless explicitly promoted.
    is_admin: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    boards: Mapped[list["Board"]] = relationship(cascade="all, delete-orphan", order_by="Board.created_at")


class Board(Base):
    __tablename__ = "boards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    project_id: Mapped[int | None] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    columns: Mapped[list["BoardColumn"]] = relationship(cascade="all, delete-orphan", order_by="BoardColumn.position")


class BoardColumn(Base):
    __tablename__ = "columns"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    board_id: Mapped[int] = mapped_column(ForeignKey("boards.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(80))
    position: Mapped[int] = mapped_column(Integer, default=0)
    tasks: Mapped[list["Task"]] = relationship(cascade="all, delete-orphan", order_by="Task.position")


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    column_id: Mapped[int] = mapped_column(ForeignKey("columns.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(160))
    description: Mapped[str] = mapped_column(Text, default="")
    assignee_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_by_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    assignee: Mapped[User | None] = relationship(foreign_keys=[assignee_id])
    items: Mapped[list["TaskItem"]] = relationship(cascade="all, delete-orphan", order_by="TaskItem.position")


class TaskItem(Base):
    __tablename__ = "task_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    task_id: Mapped[int] = mapped_column(ForeignKey("tasks.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(255))
    is_done: Mapped[bool] = mapped_column(Boolean, default=False)
    position: Mapped[int] = mapped_column(Integer, default=0)


class StoredFile(Base):
    __tablename__ = "files"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    original_name: Mapped[str] = mapped_column(String(255))
    stored_name: Mapped[str] = mapped_column(String(255), unique=True)
    content_type: Mapped[str] = mapped_column(String(160), default="application/octet-stream")
    size: Mapped[int] = mapped_column(Integer)
    uploaded_by_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    # 1.4.0: files are organized per project (NULL = uploaded before folders existed)
    project_id: Mapped[int | None] = mapped_column(ForeignKey("projects.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    uploaded_by: Mapped[User] = relationship()


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    message: Mapped[str] = mapped_column(String(255))
    link: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Setting(Base):
    __tablename__ = "settings"

    key: Mapped[str] = mapped_column(String(80), primary_key=True)
    value: Mapped[str] = mapped_column(String(255), nullable=False, default="")


class BoardMember(Base):
    __tablename__ = "board_members"
    __table_args__ = (UniqueConstraint("board_id", "user_id"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    board_id: Mapped[int] = mapped_column(ForeignKey("boards.id", ondelete="CASCADE"))
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    display_name: str
    ntfy_topic: str | None = None
    is_admin: bool = False


class RegisterIn(BaseModel):
    username: str
    display_name: str
    password: str


class LoginIn(BaseModel):
    username: str
    password: str


class BoardIn(BaseModel):
    name: str
    project_id: int | None = None


class ProjectIn(BaseModel):
    name: str


class ColumnIn(BaseModel):
    board_id: int
    name: str
    position: int = 0


class TaskItemIn(BaseModel):
    id: int | None = None
    title: str
    is_done: bool = False
    position: int | None = None  # None = keep current position (partial updates)


class TaskIn(BaseModel):
    column_id: int
    title: str
    description: str = ""
    assignee_id: int | None = None
    position: int = 0
    completed: bool | None = None
    items: list[TaskItemIn] | None = None  # None = don't touch checklist; list = replace it


class TaskMoveIn(BaseModel):
    column_id: int
    position: int = 0


class NtfyIn(BaseModel):
    topic: str | None = None


DEFAULT_APP_NAME = "Private Workspace"
APP_NAME_KEY = "app_name"
DEFAULT_COLUMNS_KEY = "default_columns"
DEFAULT_COLUMNS = ["Backlog", "U tijeku", "Gotovo"]


class SettingsOut(BaseModel):
    app_name: str = DEFAULT_APP_NAME
    default_columns: list[str] = DEFAULT_COLUMNS
    # Mobile clients read this to open the notification WebSocket; empty = not configured.
    # FROZEN CONTRACT: fields may only be added (optional), never renamed/removed.
    ntfy_base_url: str = ""


class SettingsIn(BaseModel):
    app_name: str
    default_columns: list[str] | None = None


def get_default_columns(db: Session) -> list[str]:
    raw = get_setting(db, DEFAULT_COLUMNS_KEY)
    if not raw:
        return list(DEFAULT_COLUMNS)
    names = [line.strip() for line in raw.splitlines() if line.strip()]
    return names or list(DEFAULT_COLUMNS)


def db_session():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


Db = Annotated[Session, Depends(db_session)]


def create_token(user: User) -> str:
    expires = datetime.now(timezone.utc) + timedelta(days=7)
    return jwt.encode({"sub": str(user.id), "exp": expires}, JWT_SECRET, algorithm=JWT_ALGORITHM)


def current_user(token: Annotated[str, Depends(oauth2_scheme)], db: Db) -> User:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = int(payload["sub"])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Neispravan token")
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="Korisnik ne postoji")
    return user


CurrentUser = Annotated[User, Depends(current_user)]


def ensure_board_access(db: Session, user: User, board_id: int) -> Board:
    """Shared workspace: every logged-in user can open and work with every board."""
    board = db.get(Board, board_id)
    if not board:
        raise HTTPException(status_code=404, detail="Ploča ne postoji")
    return board


def task_board_id(db: Session, column_id: int) -> int:
    column = db.get(BoardColumn, column_id)
    if not column:
        raise HTTPException(status_code=404, detail="Kolona ne postoji")
    return column.board_id


def send_ntfy(user: User, title: str, message: str) -> bool:
    """Push to the user's phone via ntfy. Returns True when the server accepted it."""
    if not NTFY_URL or not user.ntfy_topic:
        return False
    safe_topic = re.sub(r"[^A-Za-z0-9_-]", "", user.ntfy_topic)
    if not safe_topic:
        return False
    try:
        requests.post(
            f"{NTFY_URL}/{safe_topic}",
            data=message.encode("utf-8"),
            headers={"Title": title.encode("utf-8").decode("latin1", "ignore")},
            timeout=3,
        )
        return True
    except requests.RequestException:
        return False


def project_folder_name(name: str) -> str:
    """Filesystem-safe folder name derived from a project's name."""
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", name.strip()).strip("._-")
    return (safe[:60] or "projekt")


def project_upload_dir(db: Session, project_id: int | None) -> Path:
    """Uploads live in per-project folders named after the project.
    Files uploaded before this feature stay at the storage root."""
    if not project_id:
        return STORAGE_DIR
    project = db.get(Project, project_id)
    if not project:
        return STORAGE_DIR
    folder = STORAGE_DIR / project_folder_name(project.name)
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def user_from_token(token: str, db: Session) -> User:
    """Resolve a user from a raw JWT — also used for <img>/download URLs,
    where the browser cannot send an Authorization header."""
    try:
        payload = jwt.decode(token or "", JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = int(payload["sub"])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Neispravan token")
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="Korisnik ne postoji")
    return user


def user_from_query_token(
    token: Annotated[str | None, Query()] = None, db: Db = None
) -> User:
    """Dependency for media endpoints (<img src=...?token=JWT>)."""
    if not token:
        raise HTTPException(status_code=401, detail="Nedostaje token")
    return user_from_token(token, db)


def user_mentioned_in_task(task: Task, user: User) -> bool:
    """True if this user is tagged in the task (@username in title/description
    or directly assigned). Used to highlight the task in that user's view."""
    if user.id and task.assignee_id == user.id:
        return True
    if not user.username:
        return False
    pattern = re.compile(rf"@{re.escape(user.username)}\b", re.IGNORECASE)
    return bool(pattern.search(f"{task.title or ''} {task.description or ''}"))


def notify_task_users(db: Session, actor: User, task: Task) -> None:
    """Notify every user tagged in the task (@username) or assigned to it —
    INCLUDING the actor themselves (self-tagging must show in notifications)."""
    usernames = set(re.findall(r"@([A-Za-z0-9_.-]{2,40})", f"{task.title} {task.description}"))
    user_ids = {u.id for u in db.scalars(select(User).where(User.username.in_(usernames))).all()}
    if task.assignee_id:
        user_ids.add(task.assignee_id)
    for user_id in user_ids:
        if not user_id:
            continue
        user = db.get(User, user_id)
        message = f"{actor.display_name} vas je tagirao/la u tasku: {task.title}"
        db.add(Notification(user_id=user.id, message=message, link=f"/tasks/{task.id}"))
        send_ntfy(user, "Novi tag", message)


THUMB_SIZE = (420, 420)  # max thumbnail dimensions (JPEG, quality 80)

app = FastAPI(title="Private Workspace")
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup() -> None:
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    # Migration: boards.project_id was added later; ensure the column exists on
    # databases created before projects were introduced.
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE boards ADD COLUMN IF NOT EXISTS project_id INTEGER"))
        # 1.3.0: task completion + checklist items
        conn.execute(text("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS completed BOOLEAN NOT NULL DEFAULT FALSE"))
        conn.execute(text("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ NULL"))
        # 1.4.0: files organized per project
        conn.execute(text("ALTER TABLE files ADD COLUMN IF NOT EXISTS project_id INTEGER"))
    # Backfill: put every existing board into a default project so nothing is lost.
    db = SessionLocal()
    try:
        orphan_count = db.scalar(select(func.count()).select_from(Board).where(Board.project_id.is_(None)))  # type: ignore
        if orphan_count:
            first_board = db.scalar(select(Board).where(Board.project_id.is_(None)).order_by(Board.created_at))
            owner_id = first_board.owner_id if first_board else (db.scalar(select(User.id).order_by(User.id)) or 1)
            project = db.scalar(select(Project).where(Project.name == "Glavni projekt", Project.owner_id == owner_id))
            if not project:
                project = Project(name="Glavni projekt", owner_id=owner_id)
                db.add(project)
                db.flush()
            db.execute(
                Board.__table__.update().where(Board.project_id.is_(None)).values(project_id=project.id)
            )
            db.commit()
    finally:
        db.close()


@app.get("/api/auth/status")
def auth_status(db: Db):
    """Public info for the login screen: is first-run registration still open?"""
    user_count = db.scalar(select(func.count()).select_from(User))  # type: ignore
    return {"registration_open": not user_count}


def get_setting(db: Session, key: str) -> str | None:
    row = db.get(Setting, key)
    return row.value if row else None


@app.get("/api/settings", response_model=SettingsOut)
def read_settings(db: Db):
    """Public: app name is shown on the login screen before authenticating."""
    return SettingsOut(
        app_name=get_setting(db, APP_NAME_KEY) or DEFAULT_APP_NAME,
        default_columns=get_default_columns(db),
        ntfy_base_url=NTFY_PUBLIC_URL,
    )


@app.put("/api/settings", response_model=SettingsOut)
def update_settings(payload: SettingsIn, db: Db, user: CurrentUser):
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Nemate dozvolu za mijenjanje postavki")
    name = payload.app_name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Naziv ne može biti prazan")
    if len(name) > 80:
        raise HTTPException(status_code=400, detail="Naziv je predugačak (max 80 znakova)")
    row = db.get(Setting, APP_NAME_KEY)
    if row:
        row.value = name
    else:
        row = Setting(key=APP_NAME_KEY, value=name)
        db.add(row)

    if payload.default_columns is not None:
        names = []
        for raw in payload.default_columns:
            cleaned = raw.strip()
            if not cleaned:
                continue
            if len(cleaned) > 80:
                raise HTTPException(status_code=400, detail="Naziv kolone je predugačak (max 80 znakova)")
            if any(cleaned.lower() == existing.lower() for existing in names):
                continue
            names.append(cleaned)
        if not names:
            raise HTTPException(status_code=400, detail="Potrebna je barem jedna kolona")
        if len(names) > 20:
            raise HTTPException(status_code=400, detail="Najviše 20 kolona")
        value = "\n".join(names)
        col_row = db.get(Setting, DEFAULT_COLUMNS_KEY)
        if col_row:
            col_row.value = value
        else:
            db.add(Setting(key=DEFAULT_COLUMNS_KEY, value=value))

    db.commit()
    return SettingsOut(
        app_name=name,
        default_columns=get_default_columns(db),
    )


@app.post("/api/auth/register", response_model=TokenResponse)
def register(payload: RegisterIn, db: Db):
    username = payload.username.strip().lower()
    if not re.fullmatch(r"[a-z0-9_.-]{2,40}", username):
        raise HTTPException(status_code=400, detail="Korisničko ime smije imati slova, brojeve, točku, crticu i podvlaku")
    if len(payload.password) < 8:
        raise HTTPException(status_code=400, detail="Lozinka mora imati barem 8 znakova")
    # Only allow registration when the database is empty (first user).  All
    # subsequent users must be created by an authenticated admin via a different
    # endpoint.
    existing_user = db.scalar(select(User).where(User.username == username))
    if existing_user:
        raise HTTPException(status_code=409, detail="Korisnik već postoji")

    user_count = db.scalar(select(func.count()).select_from(User))  # type: ignore
    if user_count and user_count > 0:
        # After the first user exists we block registration.
        raise HTTPException(status_code=403, detail="Registracija je zabranjena")
    new_user = User(
        username=username,
        display_name=payload.display_name.strip() or username,
        password_hash=passwords.hash(payload.password),
        is_admin=(user_count == 0)  # first user becomes admin
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return TokenResponse(access_token=create_token(new_user))


@app.post("/api/auth/login", response_model=TokenResponse)
def login(payload: LoginIn, db: Db):
    user = db.scalar(select(User).where(User.username == payload.username.strip().lower()))
    if not user or not passwords.verify(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Neispravno korisničko ime ili lozinka")
    return TokenResponse(access_token=create_token(user))


@app.get("/api/me", response_model=UserOut)
def me(user: CurrentUser):
    return user


@app.patch("/api/me/ntfy", response_model=UserOut)
def update_ntfy(payload: NtfyIn, db: Db, user: CurrentUser):
    user.ntfy_topic = payload.topic.strip() if payload.topic else None
    db.commit()
    db.refresh(user)
    return user


@app.post("/api/me/ntfy/test")
def test_ntfy(db: Db, user: CurrentUser):
    """Send a test push so the user can verify their phone setup."""
    if not NTFY_URL:
        return {"ok": False, "reason": "ntfy poslužitelj nije postavljen na serveru"}
    if not user.ntfy_topic:
        return {"ok": False, "reason": "Prvo spremite svoj ntfy topic"}
    ok = send_ntfy(user, "SolRay test", "Ovo je testna obavijest iz SolRaya. Ako je vidite na telefonu, sve radi.")
    if not ok:
        return {"ok": False, "reason": "ntfy poslužitelj nije odgovorio (provjerite NTFY_URL)"}
    return {"ok": True, "topic": user.ntfy_topic}


@app.get("/api/users", response_model=list[UserOut])
def users(db: Db, _: CurrentUser):
    return db.scalars(select(User).order_by(User.username)).all()


@app.post("/api/users", response_model=UserOut)
def create_user(payload: RegisterIn, db: Db, user: CurrentUser):
    # Only allow admin users to create new users
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Nemate dozvolu za stvaranje korisnika")
    
    existing = db.scalar(select(User).where(User.username == payload.username.strip().lower()))
    if existing:
        raise HTTPException(status_code=409, detail="Korisničko ime već postoji")

    new_user = User(
        username=payload.username.strip().lower(),
        display_name=payload.display_name.strip() or payload.username.strip(),
        password_hash=passwords.hash(payload.password),
        is_admin=False,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user


@app.delete("/api/users/{user_id}")
def delete_user(user_id: int, db: Db, user: CurrentUser):
    # Only allow admin users to delete other users
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Nemate dozvolu za brisanje korisnika")
    
    target = db.get(User, user_id)
    if not target or target.id == user.id:
        raise HTTPException(status_code=404, detail="Korisnik ne postoji")
        
    # Don't allow deletion of admin users (except self for security)
    if target.is_admin and target.id != user.id:
        raise HTTPException(status_code=403, detail="Nemate dozvolu za brisanje administratora")

    db.delete(target)
    db.commit()
    return {"ok": True}


def ensure_project_manage(db: Session, user: User, project: Project) -> None:
    """Shared workspace: any user may manage any project (rename/delete/move boards)."""
    return None


@app.get("/api/projects")
def list_projects(db: Db, user: CurrentUser):
    """Shared workspace: all projects and all boards are visible to every user."""
    board_rows = db.scalars(select(Board).order_by(Board.created_at)).all()
    projects = db.scalars(select(Project).order_by(Project.created_at)).all()
    out = []
    for project in projects:
        boards = [
            {"id": b.id, "name": b.name, "project_id": b.project_id}
            for b in board_rows
            if b.project_id == project.id
        ]
        out.append({"id": project.id, "name": project.name, "boards": boards})
    return out


@app.post("/api/projects")
def create_project(payload: ProjectIn, db: Db, user: CurrentUser):
    project = Project(name=payload.name.strip()[:120] or "Novi projekt", owner_id=user.id)
    db.add(project)
    db.commit()
    db.refresh(project)
    project_upload_dir(db, project.id)  # create the per-project uploads folder right away
    return {"id": project.id, "name": project.name}


@app.patch("/api/projects/{project_id}")
def rename_project(project_id: int, payload: ProjectIn, db: Db, user: CurrentUser):
    project = db.get(Project, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Projekt ne postoji")
    ensure_project_manage(db, user, project)
    old_dir = project_upload_dir(db, project.id)
    project.name = payload.name.strip()[:120] or project.name
    db.commit()
    new_dir = project_upload_dir(db, project.id)
    if old_dir != new_dir and old_dir.exists():
        try:
            if new_dir.exists():
                # name collision (rare) — move file-by-file instead of failing
                for f in old_dir.iterdir():
                    shutil.move(str(f), str(new_dir / f.name))
                old_dir.rmdir()
            else:
                old_dir.rename(new_dir)
            for f in db.scalars(select(StoredFile).where(StoredFile.project_id == project.id)).all():
                if not (STORAGE_DIR / f.stored_name).exists() and (new_dir / Path(f.stored_name).name).exists():
                    f.stored_name = f"{new_dir.name}/{Path(f.stored_name).name}"
            db.commit()
        except OSError:
            pass  # files stay readable at the old path; nothing breaks
    return {"id": project.id, "name": project.name}


@app.delete("/api/projects/{project_id}")
def delete_project(project_id: int, db: Db, user: CurrentUser):
    project = db.get(Project, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Projekt ne postoji")
    ensure_project_manage(db, user, project)
    # ORM cascade removes boards -> columns -> tasks; board_members rows go
    # through the FK ON DELETE CASCADE. Uploaded files keep living in their
    # folder on disk — detach them first so the FK doesn't block deletion.
    db.execute(
        StoredFile.__table__.update().where(StoredFile.project_id == project_id).values(project_id=None)
    )
    db.delete(project)
    db.commit()
    return {"ok": True}


@app.post("/api/boards")
def create_board(payload: BoardIn, db: Db, user: CurrentUser):
    if payload.project_id is not None:
        project = db.get(Project, payload.project_id)
        if not project:
            raise HTTPException(status_code=404, detail="Projekt ne postoji")
        ensure_project_manage(db, user, project)
    else:
        # Shared workspace: a board without an explicit project goes into the
        # first existing project — never into a per-user "Glavni projekt".
        project = db.scalar(select(Project).order_by(Project.created_at))
        if not project:
            project = Project(name="Glavni projekt", owner_id=user.id)
            db.add(project)
            db.flush()
    board = Board(name=payload.name.strip() or "Nova ploča", owner_id=user.id, project_id=project.id)
    db.add(board)
    db.flush()
    db.add_all(
        BoardColumn(board_id=board.id, name=name, position=position)
        for position, name in enumerate(get_default_columns(db))
    )
    db.commit()
    return {"id": board.id, "name": board.name, "project_id": board.project_id}


@app.get("/api/boards")
def list_boards(db: Db, user: CurrentUser):
    """Shared workspace: every user sees every board."""
    rows = db.scalars(select(Board).order_by(Board.created_at.desc())).all()
    return [{"id": b.id, "name": b.name, "owner_id": b.owner_id, "project_id": b.project_id} for b in rows]


@app.get("/api/search")
def search_everything(db: Db, user: CurrentUser, q: str = ""):
    query = (q or "").strip()
    if len(query) < 2:
        return {"results": []}
    like = f"%{query}%"
    lowered = query.lower()

    # Shared workspace: search across everything — same visibility for all users.
    board_rows = db.scalars(select(Board)).all()
    projects = db.scalars(select(Project)).all()
    project_map = {p.id: p for p in projects}

    results = []

    # 1) Projects
    for project in projects:
        if lowered in project.name.lower():
            results.append(
                {
                    "type": "project",
                    "project_id": project.id,
                    "project_name": project.name,
                    "label": project.name,
                    "detail": "Projekt",
                }
            )

    # 2) Boards
    for board in board_rows:
        if lowered in board.name.lower():
            project = project_map.get(board.project_id)
            results.append(
                {
                    "type": "board",
                    "project_id": board.project_id,
                    "project_name": project.name if project else "",
                    "board_id": board.id,
                    "board_name": board.name,
                    "label": board.name,
                    "detail": f"Ploča · {project.name if project else 'bez projekta'}",
                }
            )

    # 3) Tasks (title + description) inside visible boards
    board_ids = [b.id for b in board_rows]
    if board_ids:
        task_rows = db.execute(
            select(Task, BoardColumn)
            .join(BoardColumn, Task.column_id == BoardColumn.id)
            .where(BoardColumn.board_id.in_(board_ids))
            .where(or_(Task.title.ilike(like), Task.description.ilike(like)))
            .order_by(Task.created_at.desc())
            .limit(50)
        ).all()
        for task, column in task_rows:
            board = next((b for b in board_rows if b.id == column.board_id), None)
            project = project_map.get(board.project_id) if board else None
            description = task.description or ""
            snippet = ""
            if description:
                idx = description.lower().find(lowered)
                if idx >= 0:
                    start = max(0, idx - 40)
                    snippet = (
                        ("…" if start > 0 else "")
                        + description[start : idx + len(query) + 60].strip()
                        + "…"
                    )
                else:
                    snippet = description[:120] + ("…" if len(description) > 120 else "")
            results.append(
                {
                    "type": "task",
                    "project_id": board.project_id if board else None,
                    "project_name": project.name if project else "",
                    "board_id": board.id if board else None,
                    "board_name": board.name if board else "",
                    "task_id": task.id,
                    "label": task.title,
                    "detail": f"Zadatak · {board.name if board else ''} · {column.name}",
                    "snippet": snippet,
                }
            )

    return {"results": results}


@app.get("/api/boards/{board_id}")
def get_board(board_id: int, db: Db, user: CurrentUser):
    board = ensure_board_access(db, user, board_id)
    return {
        "id": board.id,
        "name": board.name,
        "columns": [
            {
                "id": col.id,
                "name": col.name,
                "position": col.position,
                "tasks": [
                    {**serialize_task(task), "mentions_me": user_mentioned_in_task(task, user)}
                    for task in sorted_tasks(col.tasks)
                ],
            }
            for col in board.columns
        ],
    }


@app.patch("/api/boards/{board_id}")
def update_board(board_id: int, payload: BoardIn, db: Db, user: CurrentUser):
    board = db.get(Board, board_id)
    if not board:
        raise HTTPException(status_code=404, detail="Ploča ne postoji")
    board.name = payload.name.strip() or board.name
    if payload.project_id is not None and payload.project_id != board.project_id:
        project = db.get(Project, payload.project_id)
        if not project:
            raise HTTPException(status_code=404, detail="Projekt ne postoji")
        ensure_project_manage(db, user, project)
        board.project_id = project.id
    db.commit()
    return {"id": board.id, "name": board.name, "project_id": board.project_id}


@app.delete("/api/boards/{board_id}")
def delete_board(board_id: int, db: Db, user: CurrentUser):
    board = db.get(Board, board_id)
    if not board:
        raise HTTPException(status_code=404, detail="Ploča ne postoji")
    db.delete(board)
    db.commit()
    return {"ok": True}


@app.post("/api/boards/{board_id}/members")
def add_member(board_id: int, db: Db, user: CurrentUser, username: Annotated[str, Form(...)]):
    """Membership is a no-op in the shared workspace — every user already has
    full access to every board. Kept for API compatibility."""
    ensure_board_access(db, user, board_id)
    return {"ok": True}


@app.post("/api/columns")
def create_column(payload: ColumnIn, db: Db, user: CurrentUser):
    ensure_board_access(db, user, payload.board_id)
    column = BoardColumn(board_id=payload.board_id, name=payload.name.strip() or "Nova kolona", position=payload.position)
    db.add(column)
    db.commit()
    db.refresh(column)
    return {"id": column.id, "name": column.name, "position": column.position}


class ColumnPatchIn(BaseModel):
    name: str


@app.patch("/api/columns/{column_id}")
def rename_column(column_id: int, payload: ColumnPatchIn, db: Db, user: CurrentUser):
    """Rename a column (mobile parity with the web app's inline rename)."""
    column = db.get(BoardColumn, column_id)
    if not column:
        raise HTTPException(status_code=404, detail="Kolona ne postoji")
    ensure_board_access(db, user, column.board_id)
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Naziv ne može biti prazan")
    column.name = name[:80]
    db.commit()
    return {"id": column.id, "name": column.name, "position": column.position}


@app.delete("/api/columns/{column_id}")
def delete_column(column_id: int, db: Db, user: CurrentUser):
    """Delete a column with all its tasks (cascades, same as the web app)."""
    column = db.get(BoardColumn, column_id)
    if not column:
        raise HTTPException(status_code=404, detail="Kolona ne postoji")
    ensure_board_access(db, user, column.board_id)
    db.delete(column)
    db.commit()
    return {"ok": True}


def serialize_task(task: Task) -> dict:
    items = sorted(task.items, key=lambda i: i.position)
    return {
        "id": task.id,
        "title": task.title,
        "description": task.description,
        "assignee_id": task.assignee_id,
        "assignee": task.assignee.display_name if task.assignee else None,
        "position": task.position,
        "completed": task.completed,
        "completed_at": task.completed_at.isoformat() if task.completed_at else None,
        "items": [
            {"id": i.id, "title": i.title, "is_done": i.is_done, "position": i.position}
            for i in items
        ],
    }


def recompute_task_completion(db: Session, task: Task) -> None:
    """A task with checklist items is completed iff ALL items are done.
    Counts directly in the DB so concurrent item updates can't leave a stale flag."""
    # The session runs with autoflush=False: pending item changes (the tick that
    # triggered this recompute) are still only in memory, so a COUNT here would
    # read the pre-change values. Flush first so the count sees the new state.
    db.flush()
    total = db.scalar(select(func.count()).select_from(TaskItem).where(TaskItem.task_id == task.id)) or 0
    if total > 0:
        done = db.scalar(select(func.count()).select_from(TaskItem).where(TaskItem.task_id == task.id, TaskItem.is_done.is_(True))) or 0
        task.completed = done == total
    task.completed_at = datetime.now(timezone.utc) if task.completed else None


def lock_task_for_update(db: Session, task_id: int) -> None:
    """Serialize concurrent checklist mutations on one task (SELECT ... FOR UPDATE).
    Without this, two near-simultaneous item PATCHes each count before the other
    commits and the last writer leaves a stale completed flag."""
    db.execute(select(Task).where(Task.id == task_id).with_for_update())


def sorted_tasks(tasks: list[Task]) -> list[Task]:
    """Open tasks first (by position), completed ones at the bottom (newest completion first)."""
    return sorted(
        tasks,
        key=lambda t: (1 if t.completed else 0, t.completed_at or t.created_at, t.position),
        reverse=False,
    )


@app.post("/api/tasks")
def create_task(payload: TaskIn, db: Db, user: CurrentUser):
    board_id = task_board_id(db, payload.column_id)
    ensure_board_access(db, user, board_id)
    task = Task(
        column_id=payload.column_id,
        title=payload.title.strip() or "Novi task",
        description=payload.description,
        assignee_id=payload.assignee_id,
        position=payload.position,
        created_by_id=user.id,
    )
    db.add(task)
    db.flush()  # assigns task.id — items need it
    for idx, item in enumerate(payload.items or []):
        if item.title.strip():
            db.add(TaskItem(task_id=task.id, title=item.title.strip()[:255], is_done=item.is_done, position=idx))
    db.flush()
    recompute_task_completion(db, task)
    notify_task_users(db, user, task)
    db.commit()
    db.refresh(task)
    return {"id": task.id}


@app.patch("/api/tasks/{task_id}")
def update_task(task_id: int, payload: TaskIn, db: Db, user: CurrentUser):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task ne postoji")
    ensure_board_access(db, user, task_board_id(db, task.column_id))
    task.column_id = payload.column_id
    task.title = payload.title.strip() or task.title
    task.description = payload.description
    task.assignee_id = payload.assignee_id
    task.position = payload.position
    # Checklist editor may replace items wholesale (matched by id when present).
    if payload.items is not None:
        existing = {i.id: i for i in task.items}
        incoming_ids = {item.id for item in payload.items if item.id}
        for idx, item in enumerate(payload.items):
            title = item.title.strip()
            if not title:
                continue
            if item.id and item.id in existing:
                row = existing[item.id]
                row.title = title
                row.is_done = item.is_done
                row.position = idx
            else:
                db.add(TaskItem(task_id=task.id, title=title[:255], is_done=item.is_done, position=idx))
        for row_id, row in existing.items():
            if row_id not in incoming_ids:
                db.delete(row)
    if payload.completed is not None and not task.items:
        task.completed = payload.completed
    recompute_task_completion(db, task)
    notify_task_users(db, user, task)
    db.commit()
    return {"ok": True}


@app.patch("/api/tasks/{task_id}/completed")
def toggle_completed(task_id: int, db: Db, user: CurrentUser):
    """Manual completion toggle — allowed only for tasks WITHOUT checklist items.
    Tasks with items complete themselves when every item is checked."""
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task ne postoji")
    ensure_board_access(db, user, task_board_id(db, task.column_id))
    if task.items:
        raise HTTPException(status_code=400, detail="Zadatak sa popisom završava se kad su sve stavke označene")
    task.completed = not task.completed
    task.completed_at = datetime.now(timezone.utc) if task.completed else None
    db.commit()
    return {"ok": True, "completed": task.completed}


@app.post("/api/tasks/{task_id}/items")
def add_task_item(task_id: int, payload: TaskItemIn, db: Db, user: CurrentUser):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task ne postoji")
    ensure_board_access(db, user, task_board_id(db, task.column_id))
    lock_task_for_update(db, task.id)
    title = payload.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="Stavka ne smije biti prazna")
    position = payload.position if payload.position is not None else len(task.items)
    item = TaskItem(task_id=task.id, title=title[:255], is_done=False, position=position)
    db.add(item)
    db.flush()
    was_completed = task.completed
    recompute_task_completion(db, task)
    db.commit()
    return {"id": item.id, "completed_changed": task.completed != was_completed}


@app.patch("/api/tasks/{task_id}/items/{item_id}")
def update_task_item(task_id: int, item_id: int, payload: TaskItemIn, db: Db, user: CurrentUser):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task ne postoji")
    ensure_board_access(db, user, task_board_id(db, task.column_id))
    item = db.get(TaskItem, item_id)
    if not item or item.task_id != task.id:
        raise HTTPException(status_code=404, detail="Stavka ne postoji")
    lock_task_for_update(db, task.id)
    was_completed = task.completed
    if payload.title.strip():
        item.title = payload.title.strip()[:255]
    item.is_done = payload.is_done
    if payload.position is not None:
        item.position = payload.position
    recompute_task_completion(db, task)
    db.commit()
    return {"ok": True, "completed": task.completed, "completed_changed": task.completed != was_completed}


@app.delete("/api/tasks/{task_id}/items/{item_id}")
def delete_task_item(task_id: int, item_id: int, db: Db, user: CurrentUser):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task ne postoji")
    ensure_board_access(db, user, task_board_id(db, task.column_id))
    item = db.get(TaskItem, item_id)
    if not item or item.task_id != task.id:
        raise HTTPException(status_code=404, detail="Stavka ne postoji")
    lock_task_for_update(db, task.id)
    db.delete(item)
    was_completed = task.completed
    recompute_task_completion(db, task)
    db.commit()
    return {"ok": True, "completed": task.completed, "completed_changed": task.completed != was_completed}


@app.patch("/api/tasks/{task_id}/move")
def move_task(task_id: int, payload: TaskMoveIn, db: Db, user: CurrentUser):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task ne postoji")
    ensure_board_access(db, user, task_board_id(db, task.column_id))
    ensure_board_access(db, user, task_board_id(db, payload.column_id))
    task.column_id = payload.column_id
    task.position = payload.position
    db.commit()
    return {"ok": True}


@app.delete("/api/tasks/{task_id}")
def delete_task(task_id: int, db: Db, user: CurrentUser):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task ne postoji")
    ensure_board_access(db, user, task_board_id(db, task.column_id))
    db.delete(task)
    db.commit()
    return {"ok": True}


@app.get("/api/projects/{project_id}/files")
def list_project_files(project_id: int, db: Db, user: CurrentUser):
    project = db.get(Project, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Projekt ne postoji")
    # Shared workspace: any authenticated user may see the project's files.
    files = db.scalars(
        select(StoredFile).where(StoredFile.project_id == project_id).order_by(StoredFile.created_at.desc())
    ).all()
    return [
        {
            "id": f.id,
            "name": f.original_name,
            "size": f.size,
            "content_type": f.content_type,
            "uploaded_by": f.uploaded_by.display_name,
            "created_at": f.created_at.isoformat(),
        }
        for f in files
    ]


@app.get("/api/files")
def list_files(db: Db, _: CurrentUser):
    files = db.scalars(select(StoredFile).order_by(StoredFile.created_at.desc())).all()
    return [
        {
            "id": f.id,
            "name": f.original_name,
            "size": f.size,
            "content_type": f.content_type,
            "uploaded_by": f.uploaded_by.display_name,
            "created_at": f.created_at.isoformat(),
        }
        for f in files
    ]


def is_image(ct: str) -> bool:
    return (ct or "").lower().startswith("image/")


def is_image(ct: str) -> bool:
    return (ct or "").lower().startswith("image/")


def make_thumbnail(path: Path) -> bytes | None:
    """JPEG thumbnail bytes for an image file; None when not an image or broken."""
    try:
        with Image.open(path) as im:
            im.thumbnail(THUMB_SIZE)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=80)
        return buf.getvalue()
    except Exception:
        return None  # broken/unsupported image: download still works, thumb shows icon


def store_upload(db: Session, user: User, file: UploadFile, project_id: int | None) -> dict:
    """Save an upload into the project's folder (root for legacy/no-project),
    generate a thumbnail for images, record it, return {"id", "name"}."""
    folder = project_upload_dir(db, project_id)
    stored_name = f"{uuid.uuid4().hex}_{Path(file.filename or 'file').name}"
    target = folder / stored_name
    with target.open("wb") as handle:
        shutil.copyfileobj(file.file, handle)
    thumb_bytes = make_thumbnail(target) if is_image(file.content_type or "") else None
    row = StoredFile(
        original_name=file.filename or stored_name,
        # relative path under STORAGE_DIR — "Folder/uuid_name" for project files,
        # flat name for legacy files (they live at the storage root)
        stored_name=f"{folder.name}/{stored_name}" if project_id else stored_name,
        content_type=file.content_type or "application/octet-stream",
        size=target.stat().st_size,
        uploaded_by_id=user.id,
        project_id=project_id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    if thumb_bytes is not None:
        thumbnail_path(target).write_bytes(thumb_bytes)
    return {"id": row.id, "name": row.original_name}


@app.post("/api/projects/{project_id}/files")
def upload_project_file(
    project_id: int,
    db: Db,
    user: CurrentUser,
    file: UploadFile = File(...),
):
    project = db.get(Project, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Projekt ne postoji")
    # Shared workspace: any authenticated user may upload to the project.
    return store_upload(db, user, file, project_id)


@app.post("/api/files")
def upload_file(db: Db, user: CurrentUser, file: UploadFile = File(...), project_id: int | None = Form(None)):
    return store_upload(db, user, file, project_id)


def storage_path(row: StoredFile) -> Path:
    """Absolute path of a stored file; guards against path escapes."""
    path = (STORAGE_DIR / row.stored_name).resolve()
    if not path.is_relative_to(STORAGE_DIR.resolve()):
        raise HTTPException(status_code=400, detail="Neispravna putanja datoteke")
    return path


def thumbnail_path(original: Path) -> Path:
    return original.with_name(original.name + ".thumb.jpg")


@app.get("/api/files/{file_id}/thumb")
def file_thumb(
    file_id: int,
    db: Db,
    _: User = Depends(user_from_query_token),
):
    """JPEG thumbnail for <img> tags (auth via ?token= — browsers can't add
    Authorization headers to image requests). Falls back to a 1px placeholder
    when no thumbnail exists (non-images, legacy files)."""
    row = db.get(StoredFile, file_id)
    if not row:
        raise HTTPException(status_code=404, detail="Datoteka ne postoji")
    path = storage_path(row)
    thumb = thumbnail_path(path)
    if not thumb.exists():
        # 1x1 transparent JPEG — keeps <img> clean for non-image/legacy files
        return Response(
            content=base64.b64decode("/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwA//Z"),
            media_type="image/jpeg",
        )
    return FileResponse(thumb, media_type="image/jpeg", filename="thumb.jpg")


@app.get("/api/files/{file_id}/download")
def download_file(file_id: int, db: Db, _: CurrentUser):
    row = db.get(StoredFile, file_id)
    if not row:
        raise HTTPException(status_code=404, detail="Datoteka ne postoji")
    path = storage_path(row)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Datoteka nije pronađena na disku")
    return FileResponse(path, media_type=row.content_type, filename=row.original_name)


@app.get("/api/notifications")
def notifications(db: Db, user: CurrentUser):
    rows = db.scalars(select(Notification).where(Notification.user_id == user.id).order_by(Notification.created_at.desc())).all()
    out = []
    for n in rows:
        task_id = None
        board_id = None
        if n.link and n.link.startswith("/tasks/"):
            try:
                task = db.get(Task, int(n.link.split("/")[2]))
                if task:
                    task_id = task.id
                    board_id = task_board_id(db, task.column_id)
            except (ValueError, IndexError):
                pass
        out.append(
            {"id": n.id, "message": n.message, "link": n.link, "is_read": n.is_read,
             "task_id": task_id, "board_id": board_id, "created_at": n.created_at.isoformat()}
        )
    return out


@app.get("/api/notifications/unread-count")
def unread_count(db: Db, user: CurrentUser):
    count = db.scalar(
        select(func.count(Notification.id)).where(Notification.user_id == user.id, Notification.is_read == False)  # noqa: E712
    )
    return {"count": count or 0}


@app.patch("/api/notifications/read-all")
def mark_all_read(db: Db, user: CurrentUser):
    rows = db.scalars(
        select(Notification).where(Notification.user_id == user.id, Notification.is_read == False)  # noqa: E712
    ).all()
    for row in rows:
        row.is_read = True
    db.commit()
    return {"ok": True, "updated": len(rows)}


@app.patch("/api/notifications/{notification_id}/read")
def mark_read(notification_id: int, db: Db, user: CurrentUser):
    row = db.get(Notification, notification_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Obavijest ne postoji")
    row.is_read = True
    db.commit()
    return {"ok": True}
