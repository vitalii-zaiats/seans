"""Starting up: remember this install, and answer everything it needs to run.

One call rather than three, because a cold start over a phone connection pays
for every round trip, and because the three answers are useless apart: there is
no point telling a client its feature flags if the next thing it learns is that
it must update before it may use them.

The order below is deliberate. Everything that can be refused is checked before
anything is written, so a client sending a nonsense version does not leave a row
behind.
"""

import uuid
from collections import Counter
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from api.core.models import utcnow
from api.errors import Invalid
from api.modules.installs.models import Install, Platform
from api.modules.installs.ports import Identity, Releases, Session, UpdatePlan
from api.modules.installs.repository import InstallRepository
from api.modules.installs.statistics import Day, Record, Records, Slice, Statistics


@dataclass(frozen=True, slots=True)
class Registration:
    """The install row, as the caller cares about it."""

    public_id: uuid.UUID
    #: True only for the call that created the row — the app's first ever start.
    first_run: bool
    registered_at: datetime


@dataclass(frozen=True, slots=True)
class Device:
    """An install, seen as something a person could point a remote at.

    A DTO rather than the row: whoever reads this is outside the module, and a
    live `Install` would make them decide which columns are safe to show.
    """

    id: int
    public_id: uuid.UUID
    platform: str
    version: str
    last_seen_at: datetime

    @classmethod
    def of(cls, install: Install) -> "Device":
        return cls(
            id=install.id,
            public_id=install.public_id,
            platform=install.platform.value,
            version=install.version,
            last_seen_at=install.last_seen_at,
        )


@dataclass(frozen=True, slots=True)
class Initialised:
    """Everything `POST /init` answers with, assembled from three modules.

    `install` and `session` are both `None` for a client that sent no install
    id — see `InstallService.initialise`.
    """

    install: Registration | None
    session: Session | None
    update: UpdatePlan
    features: Mapping[str, bool]
    #: So a client with a wrong clock can still expire things correctly.
    server_time: datetime


@dataclass(slots=True)
class InstallService:
    session: AsyncSession
    identity: Identity
    releases: Releases

    @property
    def installs(self) -> InstallRepository:
        return InstallRepository(self.session)

    async def initialise(
        self,
        *,
        install_id: uuid.UUID | None,
        platform: Platform,
        vendor: str | None,
        version: str,
        token: str | None = None,
        user_agent: str | None = None,
    ) -> Initialised:
        if vendor is not None and platform is not Platform.android:
            # Silently dropping it would let a client believe it had told us
            # something. It hasn't: outside android there is no installer
            # package to report.
            raise Invalid(f"vendor is only meaningful on android, not {platform.value}")

        # Raises on a version we cannot read, before anything is written.
        plan = self.releases.plan(platform=platform, vendor=vendor, version=version)
        features = self.releases.features(vendor=vendor)

        if install_id is None:
            # The user declined to be remembered, so there is nothing to
            # remember them by. What is left is the half of the answer that
            # needs no row: whether to update, and what this build may switch
            # on. Nothing is written, here or anywhere else in this request.
            return Initialised(
                install=None,
                session=None,
                update=plan,
                features=features,
                server_time=utcnow(),
            )

        install, first_run = await self._remember(
            public_id=install_id, platform=platform, vendor=vendor, version=version
        )

        return Initialised(
            install=Registration(
                public_id=install.public_id,
                first_run=first_run,
                registered_at=install.created_at,
            ),
            session=await self.identity.establish(install.id, token, user_agent=user_agent),
            update=plan,
            features=features,
            server_time=utcnow(),
        )

    async def _remember(
        self, *, public_id: uuid.UUID, platform: Platform, vendor: str | None, version: str
    ) -> tuple[Install, bool]:
        """Insert on the first launch, refresh on every one after it."""
        found = await self.installs.by_public_id(public_id)
        if found is not None:
            self._refresh(found, platform, vendor, version)
            await self.session.commit()
            return found, False

        install = Install(public_id=public_id, platform=platform, vendor=vendor, version=version)
        try:
            await self.installs.add(install)
            await self.session.commit()
        except IntegrityError:
            # Two launches racing on a cold start — the app opening while a
            # background task also calls init. The unique index is the referee;
            # this just accepts its verdict.
            await self.session.rollback()
            found = await self.installs.by_public_id(public_id)
            if found is None:  # pragma: no cover — the index said it was there
                raise
            self._refresh(found, platform, vendor, version)
            await self.session.commit()
            return found, False

        return install, True

    def _refresh(
        self, install: Install, platform: Platform, vendor: str | None, version: str
    ) -> None:
        """A launch reports what the app is *now* — the row keeps the latest,
        not the first."""
        install.platform = platform
        install.vendor = vendor
        install.version = version
        install.last_seen_at = utcnow()

    async def devices(self, ids: Iterable[int]) -> tuple[Device, ...]:
        """The installs behind these ids, newest-seen first."""
        return tuple(Device.of(row) for row in await self.installs.by_ids(ids))

    async def device(self, public_id: uuid.UUID) -> Device | None:
        found = await self.installs.by_public_id(public_id)
        return None if found is None else Device.of(found)

    # --- statistics -----------------------------------------------------------
    #
    # Read-only, and the only caller is an admin dashboard. It reaches these
    # through a port it wrote itself, so nothing below knows who is asking.

    async def statistics(
        self, *, since: datetime, until: datetime, active_since: datetime, top: int
    ) -> Statistics:
        """The whole overview for one window, in one place.

        `previous_*` measures the window immediately before this one — same
        length, ending where this one starts — so "up 12%" compares like with
        like however long a window the caller asked for.
        """
        installs = self.installs
        span = until - since

        return Statistics(
            total=await installs.count(),
            created=await installs.count_created_between(since, until),
            seen=await installs.count_seen_between(since, until),
            previous_created=await installs.count_created_between(since - span, since),
            previous_seen=await installs.count_seen_between(since - span, since),
            daily=self._daily(
                since,
                until,
                await installs.created_between(since, until),
                await installs.seen_between(since, until),
            ),
            platforms=tuple(
                Slice(name, count, active)
                for name, count, active in await installs.by_platform(active_since=active_since)
            ),
            versions=tuple(
                Slice(name, count, active)
                for name, count, active in await installs.by_version(
                    active_since=active_since, limit=top
                )
            ),
            vendors=tuple(
                Slice(name, count, active)
                for name, count, active in await installs.by_vendor(
                    active_since=active_since, limit=top
                )
            ),
        )

    async def records(
        self, *, limit: int, offset: int, platform: str | None = None, query: str | None = None
    ) -> Records:
        """A page of the table itself, newest-seen first."""
        rows, total = await self.installs.page(
            limit=limit, offset=offset, platform=self._platform(platform), query=query
        )
        return Records(
            items=tuple(
                Record(
                    public_id=row.public_id,
                    platform=row.platform.value,
                    vendor=row.vendor,
                    version=row.version,
                    registered_at=row.created_at,
                    last_seen_at=row.last_seen_at,
                )
                for row in rows
            ),
            total=total,
        )

    @staticmethod
    def _platform(name: str | None) -> Platform | None:
        if name is None:
            return None
        try:
            return Platform(name)
        except ValueError:
            # A platform this build has never heard of is a refusal, not an
            # empty page: "nobody is on Solaris" and "there is no such platform"
            # are different answers and a dashboard would draw them the same.
            raise Invalid(f"unknown platform: {name}") from None

    @staticmethod
    def _daily(
        since: datetime, until: datetime, created: Sequence[datetime], seen: Sequence[datetime]
    ) -> tuple[Day, ...]:
        """Bucket the window into UTC days, including the empty ones.

        Emitting only the days that had something is how a chart comes to draw a
        quiet week as a straight line between two busy days. Every day in the
        window gets a row, and a silent one sits on the floor where it belongs.
        """
        new = Counter(moment.astimezone(UTC).date() for moment in created)
        live = Counter(moment.astimezone(UTC).date() for moment in seen)

        day = since.astimezone(UTC).date()
        # `until` is exclusive, so the last day of the window is the one the
        # instant before it falls in.
        last = (until.astimezone(UTC) - timedelta(microseconds=1)).date()

        days: list[Day] = []
        while day <= last:
            days.append(Day(day=day, created=new[day], seen=live[day]))
            day += timedelta(days=1)
        return tuple(days)
