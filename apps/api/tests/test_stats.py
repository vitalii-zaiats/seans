"""The admin dashboard's numbers.

Rows are written straight to the table rather than through `POST /init`, because
half of what is being tested is *when* an install appeared, and init insists on
now. Writing `created_at` and `last_seen_at` by hand is the only way to ask what
last Tuesday looked like.
"""

import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

import httpx2
import pytest
from api.core.models import utcnow
from api.modules.accounts.models import Role
from api.modules.accounts.service import AccountService
from api.modules.installs.models import Install, Platform
from api.modules.installs.service import InstallService
from api.modules.release.service import ReleaseService
from api.modules.stats.service import StatsService
from api.settings import settings
from sqlalchemy.ext.asyncio import AsyncSession


def auth(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


def stats_for(db: AsyncSession) -> StatsService:
    """The same graph `deps.py` builds, without a request in sight."""
    accounts = AccountService(db)
    return StatsService(InstallService(db, accounts, ReleaseService(settings)))


@pytest.fixture
def install(db: AsyncSession) -> Callable[..., Install]:
    """Adds a row to the session; the caller commits when it has added them all."""

    def add(
        *,
        platform: Platform = Platform.android,
        vendor: str | None = "com.android.vending",
        version: str = "1.0.0",
        created: datetime | None = None,
        seen: datetime | None = None,
    ) -> Install:
        moment = created or utcnow()
        row = Install(
            public_id=uuid.uuid4(),
            platform=platform,
            vendor=vendor,
            version=version,
            last_seen_at=seen or moment,
        )
        row.created_at = moment
        db.add(row)
        return row

    return add


@pytest.fixture
async def admin_token(db: AsyncSession) -> str:
    credential = await AccountService(db).register(
        email="boss@example.com", password="hunter2hunter2", role=Role.admin
    )
    assert credential.token is not None
    return credential.token


# --- the window ---------------------------------------------------------------


def test_a_window_ends_at_midnight_after_today() -> None:
    now = datetime(2026, 8, 23, 14, 30, tzinfo=UTC)

    window = StatsService.window(days=7, active_days=3, now=now)

    # Not `now`: a window ending mid-afternoon puts a half-empty bar at the end
    # of every chart, and a half-empty bar reads as a collapse.
    assert window.until == datetime(2026, 8, 24, tzinfo=UTC)
    assert window.since == datetime(2026, 8, 17, tzinfo=UTC)
    assert window.active_since == datetime(2026, 8, 21, tzinfo=UTC)
    assert window.until - window.since == timedelta(days=7)


# --- counting -----------------------------------------------------------------


async def test_the_overview_counts_new_and_active_separately(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    # Installed a fortnight ago and still running.
    install(created=now - timedelta(days=14), seen=now - timedelta(hours=2))
    # Installed a fortnight ago and gone quiet.
    install(created=now - timedelta(days=14), seen=now - timedelta(days=13))
    # Installed today.
    install(created=now - timedelta(hours=1), seen=now - timedelta(hours=1))
    await db.commit()

    overview = await stats_for(db).overview(days=7, active_days=7, top=8)

    assert overview.total == 3
    # Only the one that arrived inside the window is new...
    assert overview.created.value == 1
    # ...but two have launched inside it.
    assert overview.active.value == 2


async def test_a_window_excludes_what_falls_before_it(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    install(created=now - timedelta(days=40))
    install(created=now - timedelta(days=3))
    await db.commit()

    week = await stats_for(db).overview(days=7, active_days=7, top=8)
    quarter = await stats_for(db).overview(days=90, active_days=90, top=8)

    assert week.created.value == 1
    assert quarter.created.value == 2
    # `total` ignores the window on purpose — it is the size of the table.
    assert week.total == quarter.total == 2


async def test_the_previous_window_is_the_one_immediately_before(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    # Two in the current week, one in the week before it, one long past.
    install(created=now - timedelta(days=1))
    install(created=now - timedelta(days=2))
    install(created=now - timedelta(days=9))
    install(created=now - timedelta(days=40))
    await db.commit()

    overview = await stats_for(db).overview(days=7, active_days=7, top=8)

    assert overview.created.value == 2
    assert overview.created.previous == 1
    assert overview.created.change == pytest.approx(1.0)


async def test_growth_from_nothing_is_not_a_percentage(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    install(created=utcnow() - timedelta(hours=1))
    await db.commit()

    overview = await stats_for(db).overview(days=7, active_days=7, top=8)

    # Nothing came before, so there is no rate to quote. Null, not zero and not
    # "+100%" — the dashboard prints a dash.
    assert overview.created.previous == 0
    assert overview.created.change is None


# --- the daily series ---------------------------------------------------------


async def test_every_day_of_the_window_gets_a_bucket(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    install(created=now - timedelta(days=5))
    await db.commit()

    overview = await stats_for(db).overview(days=7, active_days=7, top=8)

    # Seven days, including the silent ones: a chart that skips them draws a
    # straight line across a quiet week instead of a floor.
    assert len(overview.daily) == 7
    assert sum(day.created for day in overview.daily) == 1
    assert [day.day for day in overview.daily] == sorted(day.day for day in overview.daily)


async def test_the_series_buckets_by_utc_day(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    yesterday = (now - timedelta(days=1)).date()
    install(created=datetime.combine(yesterday, datetime.min.time(), tzinfo=UTC))
    install(created=datetime.combine(yesterday, datetime.min.time(), tzinfo=UTC))
    await db.commit()

    overview = await stats_for(db).overview(days=7, active_days=7, top=8)
    buckets = {day.day: day.created for day in overview.daily}

    assert buckets[yesterday] == 2


# --- breakdowns ---------------------------------------------------------------


async def test_breakdowns_split_by_platform_version_and_vendor(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    install(platform=Platform.android, version="1.0.0", seen=now)
    install(platform=Platform.android, version="1.0.0", seen=now - timedelta(days=30))
    install(platform=Platform.linux, vendor=None, version="1.1.0", seen=now)
    await db.commit()

    overview = await stats_for(db).overview(days=30, active_days=7, top=8)
    platforms = {item.name: item for item in overview.platforms}

    assert platforms["android"].installs == 2
    # Two android installs, but only one of them has launched this week.
    assert platforms["android"].active == 1
    assert platforms["linux"].installs == 1

    assert {item.name for item in overview.versions} == {"1.0.0", "1.1.0"}
    # A linux install has no installer package, and that is a null rather than
    # an invented "unknown".
    assert None in {item.name for item in overview.vendors}


async def test_a_breakdown_is_capped_and_ordered_by_size(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    for index in range(5):
        for _ in range(index + 1):
            install(version=f"1.0.{index}")
    await db.commit()

    overview = await stats_for(db).overview(days=30, active_days=7, top=3)

    assert len(overview.versions) == 3
    assert [item.installs for item in overview.versions] == [5, 4, 3]


# --- the table ----------------------------------------------------------------


async def test_records_come_back_newest_seen_first(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    install(version="old", seen=now - timedelta(days=3))
    install(version="new", seen=now)
    await db.commit()

    found = await stats_for(db).recent(limit=25, offset=0, platform=None, query=None)

    assert [record.version for record in found.items] == ["new", "old"]
    assert found.total == 2


async def test_records_page_without_losing_the_total(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    now = utcnow()
    for index in range(5):
        install(seen=now - timedelta(hours=index))
    await db.commit()

    page = await stats_for(db).recent(limit=2, offset=2, platform=None, query=None)

    assert len(page.items) == 2
    # The total describes the set the page was cut from, not the page.
    assert page.total == 5


async def test_a_search_matches_a_whole_uuid_or_part_of_a_version(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    wanted = install(version="2.0.0-beta", vendor="org.fdroid.fdroid")
    install(version="1.0.0")
    await db.commit()
    stats = stats_for(db)

    by_id = await stats.recent(limit=25, offset=0, platform=None, query=str(wanted.public_id))
    by_version = await stats.recent(limit=25, offset=0, platform=None, query="beta")
    by_vendor = await stats.recent(limit=25, offset=0, platform=None, query="FDROID")

    assert [record.public_id for record in by_id.items] == [wanted.public_id]
    assert [record.version for record in by_version.items] == ["2.0.0-beta"]
    # Case-insensitive on SQLite and on Postgres both — see `_matching`.
    assert [record.vendor for record in by_vendor.items] == ["org.fdroid.fdroid"]


async def test_a_search_for_a_uuid_nobody_has_is_empty_not_everything(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    install()
    await db.commit()

    found = await stats_for(db).recent(limit=25, offset=0, platform=None, query=str(uuid.uuid4()))

    assert found.items == () and found.total == 0


async def test_records_narrow_to_one_platform(
    db: AsyncSession, install: Callable[..., Install]
) -> None:
    install(platform=Platform.android)
    install(platform=Platform.web, vendor=None)
    await db.commit()

    found = await stats_for(db).recent(limit=25, offset=0, platform="web", query=None)

    assert [record.platform for record in found.items] == ["web"]


# --- over HTTP ----------------------------------------------------------------


async def test_the_dashboard_is_shut_to_everyone_but_an_admin(
    client: httpx2.AsyncClient,
) -> None:
    guest = (await client.post("/auth/guest")).json()

    assert (await client.get("/admin/stats/installs")).status_code == 401
    signed_in = await client.get("/admin/stats/installs", headers=auth(guest["session"]["token"]))
    assert signed_in.status_code == 403


async def test_an_admin_reads_the_overview(
    client: httpx2.AsyncClient, admin_token: str, db: AsyncSession, install: Callable[..., Install]
) -> None:
    install(version="1.4.2")
    await db.commit()

    answer = await client.get(
        "/admin/stats/installs?days=14&active_days=7", headers=auth(admin_token)
    )

    assert answer.status_code == 200
    body = answer.json()
    assert body["total"] == 1
    assert body["window"]["days"] == 14
    assert len(body["daily"]) == 14
    assert body["versions"][0]["name"] == "1.4.2"
    assert body["created"]["change"] is None


async def test_an_admin_reads_the_table(
    client: httpx2.AsyncClient, admin_token: str, db: AsyncSession, install: Callable[..., Install]
) -> None:
    install(version="1.4.2")
    await db.commit()

    answer = await client.get("/admin/stats/installs/recent", headers=auth(admin_token))

    assert answer.status_code == 200
    body = answer.json()
    assert body["total"] == 1
    assert body["items"][0]["version"] == "1.4.2"
    assert body["items"][0]["platform"] == "android"


async def test_a_platform_the_api_has_never_heard_of_is_refused(
    client: httpx2.AsyncClient, admin_token: str
) -> None:
    # 422 from FastAPI's own validation: `platform` is a Literal, so the seam
    # catches it before any of our code runs.
    answer = await client.get(
        "/admin/stats/installs/recent?platform=solaris", headers=auth(admin_token)
    )

    assert answer.status_code == 422


async def test_the_window_is_bounded(client: httpx2.AsyncClient, admin_token: str) -> None:
    assert (
        await client.get("/admin/stats/installs?days=0", headers=auth(admin_token))
    ).status_code == 422
    assert (
        await client.get("/admin/stats/installs?days=9000", headers=auth(admin_token))
    ).status_code == 422
