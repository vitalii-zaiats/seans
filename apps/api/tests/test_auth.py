"""The auth routes, over HTTP."""

import httpx2
import pytest
from api.core.security import token_digest
from api.modules.accounts.models import AuthSession, Role, User
from api.modules.accounts.service import AccountService
from sqlalchemy.ext.asyncio import AsyncSession

CREDENTIALS = {"email": "vi@example.com", "password": "hunter2hunter2"}


def auth(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


@pytest.fixture
async def guest(client: httpx2.AsyncClient) -> dict[str, object]:
    return (await client.post("/auth/guest")).json()


async def test_me_refuses_a_caller_it_does_not_know(client: httpx2.AsyncClient) -> None:
    assert (await client.get("/auth/me")).status_code == 401
    assert (await client.get("/auth/me", headers=auth("nonsense"))).status_code == 401


async def test_me_never_creates_an_account_as_a_side_effect(
    client: httpx2.AsyncClient, db: AsyncSession
) -> None:
    await client.get("/auth/me")

    assert await AccountService(db).users.count() == 0


async def test_a_guest_can_ask_who_they_are(
    client: httpx2.AsyncClient, guest: dict[str, object]
) -> None:
    session = guest["session"]
    assert isinstance(session, dict)

    answer = await client.get("/auth/me", headers=auth(str(session["token"])))

    assert answer.status_code == 200
    assert answer.json()["is_guest"] is True


async def test_guest_is_unconditional(client: httpx2.AsyncClient) -> None:
    first = (await client.post("/auth/guest")).json()
    second = (await client.post("/auth/guest")).json()

    assert first["account"]["id"] != second["account"]["id"]


async def test_claim_turns_the_guest_into_an_account(
    client: httpx2.AsyncClient, guest: dict[str, object]
) -> None:
    session = guest["session"]
    assert isinstance(session, dict)
    token = str(session["token"])

    answer = await client.post("/auth/claim", json=CREDENTIALS, headers=auth(token))

    assert answer.status_code == 201
    claimed = answer.json()
    assert claimed["account"]["id"] == guest["account"]["id"]
    assert claimed["account"]["is_guest"] is False
    # The old token was rotated away.
    assert (await client.get("/auth/me", headers=auth(token))).status_code == 401


async def test_claim_needs_somebody_to_claim(client: httpx2.AsyncClient) -> None:
    assert (await client.post("/auth/claim", json=CREDENTIALS)).status_code == 401


async def test_register_needs_nobody(client: httpx2.AsyncClient) -> None:
    answer = await client.post("/auth/register", json=CREDENTIALS)

    assert answer.status_code == 201
    assert answer.json()["account"]["is_guest"] is False


async def test_a_taken_email_is_a_conflict(client: httpx2.AsyncClient) -> None:
    await client.post("/auth/register", json=CREDENTIALS)

    again = await client.post("/auth/register", json=CREDENTIALS)

    assert again.status_code == 409


async def test_a_password_below_the_floor_never_reaches_the_service(
    client: httpx2.AsyncClient,
) -> None:
    answer = await client.post(
        "/auth/register", json={"email": "vi@example.com", "password": "short"}
    )

    assert answer.status_code == 422


async def test_login_and_logout(client: httpx2.AsyncClient) -> None:
    await client.post("/auth/register", json=CREDENTIALS)

    signed_in = await client.post("/auth/login", json=CREDENTIALS)
    token = signed_in.json()["session"]["token"]
    assert signed_in.status_code == 200
    assert (await client.get("/auth/me", headers=auth(token))).status_code == 200

    assert (await client.post("/auth/logout", headers=auth(token))).status_code == 204
    assert (await client.get("/auth/me", headers=auth(token))).status_code == 401


async def test_a_wrong_password_is_a_401(client: httpx2.AsyncClient) -> None:
    await client.post("/auth/register", json=CREDENTIALS)

    answer = await client.post("/auth/login", json=CREDENTIALS | {"password": "not the password"})

    assert answer.status_code == 401


async def test_rename(client: httpx2.AsyncClient, guest: dict[str, object]) -> None:
    session = guest["session"]
    assert isinstance(session, dict)

    answer = await client.patch(
        "/auth/me",
        json={"display_name": "Vitalii"},
        headers=auth(str(session["token"])),
    )

    assert answer.json()["display_name"] == "Vitalii"


async def test_forget_is_the_way_back_to_nothing(
    client: httpx2.AsyncClient, guest: dict[str, object], db: AsyncSession
) -> None:
    session = guest["session"]
    assert isinstance(session, dict)
    token = str(session["token"])

    assert (await client.delete("/auth/me", headers=auth(token))).status_code == 204

    assert (await client.get("/auth/me", headers=auth(token))).status_code == 401
    assert await AccountService(db).users.count() == 0


async def test_the_admin_listing_is_shut_to_everyone_else(
    client: httpx2.AsyncClient, guest: dict[str, object]
) -> None:
    session = guest["session"]
    assert isinstance(session, dict)

    assert (await client.get("/users")).status_code == 401
    assert (await client.get("/users", headers=auth(str(session["token"])))).status_code == 403


async def test_an_admin_can_read_the_listing(client: httpx2.AsyncClient, db: AsyncSession) -> None:
    accounts = AccountService(db)
    admin = await accounts.register(
        email="boss@example.com", password="hunter2hunter2", role=Role.admin
    )
    assert admin.token is not None

    answer = await client.get("/users", headers=auth(admin.token))

    assert answer.status_code == 200
    assert answer.json()["total"] == 1


async def test_a_session_row_points_at_the_user_that_owns_it(
    client: httpx2.AsyncClient, db: AsyncSession, guest: dict[str, object]
) -> None:
    session = guest["session"]
    assert isinstance(session, dict)

    stored = await AccountService(db).sessions.by_digest(token_digest(str(session["token"])))

    assert stored is not None
    assert isinstance(stored, AuthSession)
    owner = await db.get(User, stored.user_id)
    assert owner is not None and owner.public_id == guest["account"]["id"]
    # Nobody announced an install, so the session is not tied to one.
    assert stored.install_id is None
