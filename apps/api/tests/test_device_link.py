"""A phone signing a television in — the whole dance, and the ways it fails."""

import uuid
from datetime import timedelta

import httpx2
import pytest
from api.core.models import utcnow
from api.core.security import token_digest
from api.errors import Conflict, Invalid, NotFound
from api.modules.accounts.models import AuthSession, DeviceLink
from api.modules.accounts.service import AccountService
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

CREDENTIALS = {"email": "vi@example.com", "password": "hunter2hunter2"}


def auth(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


# --- the service ------------------------------------------------------------


async def test_a_pairing_starts_with_nobody_signed_in(db: AsyncSession) -> None:
    request = await AccountService(db).start_link(device_name="Android TV")

    assert len(request.code) == 6
    assert request.code.isupper()
    assert request.secret
    assert request.expires_at > utcnow()


async def test_the_code_avoids_letters_read_wrong_off_a_screen(
    db: AsyncSession,
) -> None:
    accounts = AccountService(db)

    for _ in range(20):
        code = (await accounts.start_link()).code
        assert not set(code) & set("O0I1")


async def test_the_secret_is_never_stored(db: AsyncSession) -> None:
    request = await AccountService(db).start_link()

    stored = await db.get(DeviceLink, 1)

    assert stored is not None
    assert stored.secret_digest == token_digest(request.secret)
    assert request.secret not in stored.secret_digest


async def test_collecting_before_approval_is_not_an_error(db: AsyncSession) -> None:
    accounts = AccountService(db)
    request = await accounts.start_link()

    # The ordinary answer while somebody walks to their phone.
    assert await accounts.collect_link(request.secret) is None


async def test_the_whole_dance(db: AsyncSession) -> None:
    accounts = AccountService(db)
    phone = await accounts.register(**CREDENTIALS)
    signed_in = await accounts.identify(phone.token)
    assert signed_in is not None

    request = await accounts.start_link(device_name="Android TV")
    status = await accounts.link_for(request.code)
    assert status.device_name == "Android TV"
    assert not status.approved

    approved = await accounts.approve_link(request.code, signed_in)
    assert approved.approved

    collected = await accounts.collect_link(request.secret)
    assert collected is not None
    assert collected.token is not None
    assert collected.account.id == phone.account.id
    # A session of the television's own, not the phone's.
    assert collected.token != phone.token


async def test_a_collection_happens_once(db: AsyncSession) -> None:
    accounts = AccountService(db)
    phone = await accounts.register(**CREDENTIALS)
    user = await accounts.identify(phone.token)
    assert user is not None
    request = await accounts.start_link()
    await accounts.approve_link(request.code, user)
    await accounts.collect_link(request.secret)

    with pytest.raises(Invalid, match="already collected"):
        await accounts.collect_link(request.secret)


async def test_an_unknown_secret_is_a_not_found(db: AsyncSession) -> None:
    with pytest.raises(NotFound):
        await AccountService(db).collect_link("nothing anybody issued")


async def test_an_expired_code_cannot_be_approved_or_collected(
    db: AsyncSession,
) -> None:
    accounts = AccountService(db)
    phone = await accounts.register(**CREDENTIALS)
    user = await accounts.identify(phone.token)
    assert user is not None
    request = await accounts.start_link()

    link = await db.get(DeviceLink, 1)
    assert link is not None
    link.expires_at = utcnow() - timedelta(seconds=1)
    await db.commit()

    with pytest.raises(Invalid, match="expired"):
        await accounts.approve_link(request.code, user)
    with pytest.raises(Invalid, match="expired"):
        await accounts.collect_link(request.secret)


async def test_a_code_somebody_else_already_used_is_refused(db: AsyncSession) -> None:
    accounts = AccountService(db)
    first = await accounts.register(**CREDENTIALS)
    second = await accounts.register(email="other@example.com", password="hunter2hunter2")
    one = await accounts.identify(first.token)
    two = await accounts.identify(second.token)
    assert one is not None and two is not None

    request = await accounts.start_link()
    await accounts.approve_link(request.code, one)

    with pytest.raises(Conflict, match="somebody else"):
        await accounts.approve_link(request.code, two)


async def test_approving_twice_as_the_same_person_is_fine(db: AsyncSession) -> None:
    accounts = AccountService(db)
    phone = await accounts.register(**CREDENTIALS)
    user = await accounts.identify(phone.token)
    assert user is not None
    request = await accounts.start_link()

    await accounts.approve_link(request.code, user)
    again = await accounts.approve_link(request.code, user)

    assert again.approved


async def test_a_code_is_read_case_insensitively(db: AsyncSession) -> None:
    accounts = AccountService(db)
    request = await accounts.start_link()

    status = await accounts.link_for(f"  {request.code.lower()}  ")

    assert status.code == request.code


async def test_the_sweep_forgets_what_nobody_finished(db: AsyncSession) -> None:
    accounts = AccountService(db)
    await accounts.start_link()
    link = await db.get(DeviceLink, 1)
    assert link is not None
    link.expires_at = utcnow() - timedelta(seconds=1)
    await db.commit()

    assert await accounts.sweep_links() == 1
    assert await accounts.links.count() == 0


# --- over HTTP --------------------------------------------------------------


async def test_the_dance_over_http(client: httpx2.AsyncClient) -> None:
    # The television, which has just been through /init and is a guest.
    started = await client.post(
        "/init",
        json={
            "id": str(uuid.uuid4()),
            "platform": "android",
            "vendor": "com.android.vending",
            "ver": "1.0.0",
        },
    )
    tv_token = started.json()["session"]["token"]

    asked = await client.post("/auth/device", headers=auth(tv_token))
    assert asked.status_code == 201
    link = asked.json()
    assert link["verify_path"] == f"/r/{link['code']}"
    assert link["expires_in"] > 0

    # The phone, on its own.
    phone = (await client.post("/auth/register", json=CREDENTIALS)).json()

    waiting = await client.get(f"/auth/device/{link['code']}")
    assert waiting.status_code == 200
    assert waiting.json()["approved"] is False

    pending = await client.post("/auth/device/collect", json={"secret": link["secret"]})
    assert pending.json() == {"status": "pending", "identity": None}

    approved = await client.post(
        "/auth/device/approve",
        json={"code": link["code"]},
        headers=auth(phone["session"]["token"]),
    )
    assert approved.status_code == 200
    assert approved.json()["approved"] is True

    collected = await client.post("/auth/device/collect", json={"secret": link["secret"]})
    assert collected.status_code == 200
    assert collected.json()["status"] == "linked"
    identity = collected.json()["identity"]
    assert identity["account"]["id"] == phone["account"]["id"]
    assert identity["account"]["is_guest"] is False

    # The television is now the phone's account, on a session of its own.
    me = await client.get("/auth/me", headers=auth(identity["session"]["token"]))
    assert me.json()["email"] == CREDENTIALS["email"]


async def test_approving_needs_an_account_of_your_own(
    client: httpx2.AsyncClient,
) -> None:
    link = (await client.post("/auth/device")).json()

    assert (
        await client.post("/auth/device/approve", json={"code": link["code"]})
    ).status_code == 401


async def test_a_code_nobody_issued_is_a_404(client: httpx2.AsyncClient) -> None:
    assert (await client.get("/auth/device/ZZZZZZ")).status_code == 404


async def test_the_session_a_television_collects_remembers_its_install(
    client: httpx2.AsyncClient, db: AsyncSession
) -> None:
    started = await client.post(
        "/init",
        json={"id": str(uuid.uuid4()), "platform": "linux", "ver": "1.0.0"},
    )
    tv_token = started.json()["session"]["token"]
    link = (await client.post("/auth/device", headers=auth(tv_token))).json()

    phone = (await client.post("/auth/register", json=CREDENTIALS)).json()
    await client.post(
        "/auth/device/approve",
        json={"code": link["code"]},
        headers=auth(phone["session"]["token"]),
    )
    collected = (await client.post("/auth/device/collect", json={"secret": link["secret"]})).json()

    accounts = AccountService(db)
    session = await accounts.sessions.by_digest(
        token_digest(collected["identity"]["session"]["token"])
    )
    assert session is not None
    assert session.install_id is not None


# A browser's `User-Agent` is 117 characters for an ordinary Chrome, and the
# column that has to hold it is 80. Postgres refuses the insert; SQLite, which
# these tests run on, ignores the width — so this asserts the *clamp* rather
# than the absence of an exception. Testing that it "does not raise" would pass
# here whether the fix existed or not.

CHROME_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36"
)


async def test_a_browser_user_agent_is_cut_to_the_column_that_holds_it(
    db: AsyncSession,
) -> None:
    accounts = AccountService(db)
    request = await accounts.start_link(device_name=CHROME_UA)

    stored = await db.scalar(select(DeviceLink).where(DeviceLink.code == request.code))
    assert stored is not None
    assert stored.device_name is not None
    assert len(stored.device_name) <= DeviceLink.device_name.type.length
    assert stored.device_name == CHROME_UA[: DeviceLink.device_name.type.length]


async def test_a_session_user_agent_is_cut_the_same_way(db: AsyncSession) -> None:
    # The same hazard one column over, already handled before this test existed —
    # here so that widening or narrowing either column keeps both honest.
    credential = await AccountService(db).guest(user_agent="x" * 500)

    stored = await db.scalar(
        select(AuthSession).where(AuthSession.token_hash == token_digest(credential.token or ""))
    )
    assert stored is not None
    assert stored.user_agent is not None
    assert len(stored.user_agent) == AuthSession.user_agent.type.length


async def test_a_box_may_name_itself(client: httpx2.AsyncClient, db: AsyncSession) -> None:
    answer = await client.post(
        "/auth/device",
        json={"device_name": "Android TV"},
        headers={"user-agent": CHROME_UA},
    )

    assert answer.status_code == 201
    stored = await db.scalar(select(DeviceLink).where(DeviceLink.code == answer.json()["code"]))
    assert stored is not None
    # What the box said, not what the browser did.
    assert stored.device_name == "Android TV"


async def test_a_box_that_says_nothing_still_gets_the_old_behaviour(
    client: httpx2.AsyncClient, db: AsyncSession
) -> None:
    # No body at all — a build shipped before the field existed.
    answer = await client.post("/auth/device", headers={"user-agent": "Some TV/1.0"})

    assert answer.status_code == 201
    stored = await db.scalar(select(DeviceLink).where(DeviceLink.code == answer.json()["code"]))
    assert stored is not None and stored.device_name == "Some TV/1.0"


async def test_a_blank_name_is_not_a_name(client: httpx2.AsyncClient, db: AsyncSession) -> None:
    answer = await client.post(
        "/auth/device", json={"device_name": "   "}, headers={"user-agent": "Some TV/1.0"}
    )

    stored = await db.scalar(select(DeviceLink).where(DeviceLink.code == answer.json()["code"]))
    assert stored is not None
    # Falls through to the header rather than storing whitespace.
    assert stored.device_name == "Some TV/1.0"


async def test_an_over_long_name_is_refused_rather_than_cut(
    client: httpx2.AsyncClient,
) -> None:
    # The clamp exists for the `User-Agent`, which the client did not choose.
    # A name it *did* choose is worth telling it about instead of silently
    # storing four fifths of it.
    answer = await client.post("/auth/device", json={"device_name": "x" * 81})

    assert answer.status_code == 422
