"""1.15.1: GET /api/me/webpush/subscriptions returns the push endpoints stored
for the current account — the PWA compares its live browser subscription
against this list and silently re-uploads it when the server row went missing
(wiped DB, fresh install), which used to look like "push mysteriously stopped
working". """

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app import Base, PushSubscription, User, webpush_subscriptions


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


def _user(db, username):
    user = User(username=username, display_name=username.title(), password_hash="x")
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def test_subscriptions_returns_only_own_endpoints(db):
    alice = _user(db, "alice")
    bob = _user(db, "bob")
    db.add_all(
        [
            PushSubscription(
                user_id=alice.id, endpoint="https://push/a", p256dh="k1", auth="a1"
            ),
            PushSubscription(
                user_id=alice.id, endpoint="https://push/b", p256dh="k2", auth="a2"
            ),
            PushSubscription(
                user_id=bob.id, endpoint="https://push/c", p256dh="k3", auth="a3"
            ),
        ]
    )
    db.commit()

    result = webpush_subscriptions(db, alice)

    assert sorted(result["endpoints"]) == ["https://push/a", "https://push/b"]


def test_subscriptions_empty_when_no_devices(db):
    alice = _user(db, "carol")

    assert webpush_subscriptions(db, alice) == {"endpoints": []}
