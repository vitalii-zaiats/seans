"""POST /init, end to end."""

import uuid

import httpx2
from api.modules.accounts.models import User
from api.modules.installs.models import Install
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession


def body(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "id": str(uuid.uuid4()),
        "platform": "android",
        "vendor": "com.android.vending",
        "ver": "1.0.0",
    }
    return payload | overrides


async def test_a_first_launch_registers_the_install(client: httpx2.AsyncClient) -> None:
    payload = body()
    response = await client.post("/init", json=payload)

    assert response.status_code == 200
    answer = response.json()
    assert answer["install"]["id"] == payload["id"]
    assert answer["install"]["first_run"] is True
    assert answer["session"]["token"]
    assert answer["account"]["is_guest"] is True
    assert answer["account"]["email"] is None
    assert answer["update"]["channel"] == "store"
    # A Play Store build, so the sections Google would object to come back off.
    assert answer["features"] == {"catalog": False, "tv": False, "playlists": False}
    assert answer["server_time"]


async def test_a_second_launch_finds_the_same_install(
    client: httpx2.AsyncClient, db: AsyncSession
) -> None:
    payload = body()
    first = (await client.post("/init", json=payload)).json()
    second = (await client.post("/init", json=payload | {"ver": "1.1.0"})).json()

    assert first["install"]["first_run"] is True
    assert second["install"]["first_run"] is False
    assert second["install"]["registered_at"] == first["install"]["registered_at"]
    assert await db.scalar(select(func.count()).select_from(Install)) == 1

    # The row remembers what the app is running *now*.
    install = await db.scalar(select(Install))
    assert install is not None and install.version == "1.1.0"


async def test_a_token_that_still_works_is_not_replaced(client: httpx2.AsyncClient) -> None:
    payload = body()
    token = (await client.post("/init", json=payload)).json()["session"]["token"]

    again = await client.post("/init", json=payload, headers={"authorization": f"Bearer {token}"})

    assert again.json()["session"]["token"] is None
    assert again.json()["session"]["expires_at"]


async def test_a_live_token_survives_a_new_install_id(client: httpx2.AsyncClient) -> None:
    # A restored backup: same person, same token, an install uuid we have never
    # seen. The token is the credential, so it is honoured.
    first = (await client.post("/init", json=body())).json()
    token = first["session"]["token"]

    answer = await client.post("/init", json=body(), headers={"authorization": f"Bearer {token}"})

    assert answer.json()["session"]["token"] is None
    assert answer.json()["account"]["id"] == first["account"]["id"]


async def test_every_launch_without_a_token_mints_one(client: httpx2.AsyncClient) -> None:
    payload = body()
    first = (await client.post("/init", json=payload)).json()
    second = (await client.post("/init", json=payload)).json()

    assert first["session"]["token"] != second["session"]["token"]
    # A client that loses its token is a new guest, not the old one back.
    assert first["account"]["id"] != second["account"]["id"]


async def test_a_client_that_sends_no_id_is_not_written_down(
    client: httpx2.AsyncClient, db: AsyncSession
) -> None:
    payload = body()
    del payload["id"]

    answer = await client.post("/init", json=payload)

    assert answer.status_code == 200
    said = answer.json()
    assert said["install"] is None
    assert said["account"] is None
    assert said["session"] is None
    # The half that needs no row still comes back — including what this build
    # may switch on, which does not depend on being remembered.
    assert said["update"]["channel"] == "store"
    assert said["features"] == {"catalog": False, "tv": False, "playlists": False}
    assert said["server_time"]

    assert await db.scalar(select(func.count()).select_from(Install)) == 0
    assert await db.scalar(select(func.count()).select_from(User)) == 0


async def test_local_only_still_gets_told_to_update(client: httpx2.AsyncClient) -> None:
    # Declining an account does not mean declining to hear the app is too old.
    payload = body(ver="0.0.1")
    del payload["id"]

    answer = await client.post("/init", json=payload)

    assert answer.status_code == 200
    assert answer.json()["update"]["action"] in {"none", "optional", "required"}


async def test_a_desktop_install_updates_itself(client: httpx2.AsyncClient) -> None:
    answer = await client.post("/init", json=body(platform="linux", vendor=None))

    assert answer.status_code == 200
    assert answer.json()["update"]["channel"] == "self"


async def test_a_vendor_outside_android_is_refused(client: httpx2.AsyncClient) -> None:
    answer = await client.post("/init", json=body(platform="web", vendor="com.android.vending"))

    assert answer.status_code == 400
    assert "vendor" in answer.json()["detail"]


async def test_a_version_we_cannot_read_is_refused_before_anything_is_written(
    client: httpx2.AsyncClient, db: AsyncSession
) -> None:
    answer = await client.post("/init", json=body(ver="nightly"))

    assert answer.status_code == 400
    assert await db.scalar(select(func.count()).select_from(Install)) == 0


async def test_an_unknown_platform_never_reaches_the_service(
    client: httpx2.AsyncClient,
) -> None:
    answer = await client.post("/init", json=body(platform="symbian", vendor=None))

    assert answer.status_code == 422


async def test_an_id_that_is_not_a_uuid_never_reaches_the_service(
    client: httpx2.AsyncClient,
) -> None:
    assert (await client.post("/init", json=body(id="not-a-uuid"))).status_code == 422


async def test_health(client: httpx2.AsyncClient) -> None:
    assert (await client.get("/health")).json()["status"] == "ok"


async def test_a_play_store_build_is_told_what_it_may_not_have(
    client: httpx2.AsyncClient,
) -> None:
    # Google reviews that build, and third-party streams are what gets one
    # pulled. The names are the launcher's own section ids, so the app reads
    # them without a translation table.
    answer = await client.post("/init", json=body(vendor="com.android.vending"))

    features = answer.json()["features"]
    assert features["catalog"] is False
    assert features["tv"] is False
    # Nobody vets what is on somebody else's M3U, which is the same argument
    # only more so.
    assert features["playlists"] is False


async def test_the_same_build_from_anywhere_else_keeps_them(
    client: httpx2.AsyncClient,
) -> None:
    for vendor in ("org.fdroid.fdroid", None):
        answer = await client.post("/init", json=body(platform="android", vendor=vendor))
        assert answer.json()["features"] == {}


async def test_a_section_nobody_mentioned_is_simply_absent(
    client: httpx2.AsyncClient,
) -> None:
    # Which is how a client reading `features[id] ?? true` gets a new section
    # for free, with no deploy on this side.
    features = (await client.post("/init", json=body(vendor="com.android.vending"))).json()[
        "features"
    ]

    assert "storage" not in features
