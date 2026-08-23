"""Becoming somebody, and staying that somebody across launches.

    no identity     `establish()` mints a guest *and* a session in one go
    a token         `identify()` returns that user, or nothing if it is stale
    guest + email   `claim()`    fills in the same row and rotates the token
    nothing + email `register()` an account with no guest behind it
    email + password`login()`    a second session on an existing row

`claim` never creates a user, so the progress and the history a guest built up
stay attached. `register` exists for the other way round: somebody who ran the
app locally, told us nothing, and only now wants an account — there is no guest
row to claim, and making a throwaway one first would be theatre.
"""

import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from api.core.models import utcnow
from api.core.security import hash_password, new_token, token_digest, verify_password
from api.errors import Conflict, Forbidden, Invalid, NotFound, Unauthorized
from api.modules.accounts.models import AuthSession, DeviceLink, Role, User
from api.modules.accounts.repository import (
    DeviceLinkRepository,
    SessionRepository,
    UserRepository,
)
from api.settings import settings

MIN_PASSWORD = 8

# How long a television has to be approved before its code stops meaning
# anything. Long enough to find a phone and unlock it, short enough that a code
# left on a screen in a shared flat goes stale on its own.
LINK_TTL = timedelta(minutes=10)

# No O or 0, no I or 1: this is read off a screen across a room, and sometimes
# read aloud.
LINK_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
LINK_LENGTH = 6


@dataclass(frozen=True, slots=True)
class Account:
    """A user as anybody outside this module is allowed to see them.

    A DTO rather than the row itself: `password_hash` is right there on the
    other one, and two presentation layers reading it would each have to know
    which columns are safe.
    """

    id: str
    display_name: str
    email: str | None
    is_guest: bool
    is_admin: bool

    @classmethod
    def of(cls, user: User) -> "Account":
        return cls(
            id=user.public_id,
            display_name=user.display_name,
            email=user.email,
            is_guest=user.is_guest,
            is_admin=user.is_admin,
        )


@dataclass(frozen=True, slots=True)
class DeviceRequest:
    """What a television is handed when it asks to be signed in.

    The code goes on the screen and into the QR; the secret stays in the box and
    is the only thing that can collect the session afterwards.
    """

    code: str
    secret: str
    expires_at: datetime


@dataclass(frozen=True, slots=True)
class DeviceStatus:
    """A pending pairing, as the page about to approve it needs to see it.

    A DTO rather than the row: two presentation layers read this, and handing
    them a live `DeviceLink` would mean both knowing which of its columns are
    safe to show — `secret_digest` is right there.
    """

    code: str
    device_name: str | None
    approved: bool
    expires_at: datetime

    @classmethod
    def of(cls, link: DeviceLink) -> "DeviceStatus":
        return cls(
            code=link.code,
            device_name=link.device_name,
            approved=not link.pending,
            expires_at=link.expires_at,
        )


@dataclass(frozen=True, slots=True)
class Credential:
    """A session, and the one and only time we say its token out loud.

    `token` is `None` when the caller already had one that still works — the
    client keeps what it has, and a token it already stored is never repeated
    back at it.
    """

    token: str | None
    expires_at: datetime
    account: Account


def _fits(value: str | None, limit: int | None) -> str | None:
    """Cut a header down to the column that has to hold it.

    Both callers store something a client chose the length of — a `User-Agent`,
    which is 117 characters for an ordinary Chrome and has no ceiling at all.
    Postgres refuses an over-long varchar with `StringDataRightTruncation`,
    which surfaces as a 500 on a request that was perfectly valid; SQLite
    ignores the width entirely, so the tests never saw it. That asymmetry is
    exactly the one `CLAUDE.md` warns about, and this is the seam it lands on.

    The limit is read off the column rather than written here, so widening the
    column is the only change widening the clamp needs.
    """
    if not value:
        return None
    return value[:limit] if limit else value


@dataclass(slots=True)
class AccountService:
    session: AsyncSession

    @property
    def users(self) -> UserRepository:
        return UserRepository(self.session)

    @property
    def sessions(self) -> SessionRepository:
        return SessionRepository(self.session)

    # --- identity -----------------------------------------------------------

    async def identify(self, token: str | None) -> User | None:
        """Resolve a token to a user. No token, no user, no exception.

        Callers decide what "nobody" means: `establish` mints a guest, a route
        that needs an account refuses.
        """
        if not token:
            return None

        auth = await self.sessions.by_digest(token_digest(token))
        if auth is None:
            return None
        if not auth.is_live():
            # Expired sessions are dropped on sight rather than by a cron job we
            # do not have yet.
            await self.sessions.delete(auth)
            await self.session.commit()
            return None

        now = utcnow()
        auth.last_used_at = now
        auth.user.last_seen_at = now
        await self.session.commit()
        return auth.user

    async def establish(
        self,
        install_id: int,
        token: str | None = None,
        *,
        user_agent: str | None = None,
    ) -> Credential:
        """What `POST /init` calls: keep the caller's session, or mint a guest.

        A live token is honoured whatever install sends it. It is a bearer
        credential — that is what one means — and refusing it because the
        install uuid changed would sign out somebody who restored a backup while
        protecting nothing: whoever holds the token could send the matching
        install id just as easily.
        """
        if token:
            auth = await self.sessions.by_digest(token_digest(token))
            if auth is not None and auth.is_live():
                now = utcnow()
                auth.last_used_at = now
                auth.user.last_seen_at = now
                await self.session.commit()
                return Credential(
                    token=None, expires_at=auth.expires_at, account=Account.of(auth.user)
                )
            if auth is not None:
                await self.sessions.delete(auth)
                await self.session.commit()

        return await self.guest(install_id=install_id, user_agent=user_agent)

    async def guest(
        self, *, install_id: int | None = None, user_agent: str | None = None
    ) -> Credential:
        """A brand new anonymous account, already signed in."""
        user = await self.users.add(User(display_name="Guest", role=Role.user))
        # The generated public_id only exists after the flush, and it is what
        # makes two guests on one screen tellable apart.
        user.display_name = f"Guest {user.public_id[:6]}"
        credential = await self._issue(user, install_id=install_id, user_agent=user_agent)
        await self.session.commit()
        return credential

    async def login(
        self,
        email: str,
        password: str,
        *,
        install_id: int | None = None,
        user_agent: str | None = None,
    ) -> Credential:
        user = await self.users.by_email(email)
        # One message for "no such email" and "wrong password" on purpose: the
        # difference is only useful to somebody enumerating accounts.
        if user is None or not verify_password(password, user.password_hash):
            raise Unauthorized("wrong email or password")

        credential = await self._issue(user, install_id=install_id, user_agent=user_agent)
        await self.session.commit()
        return credential

    async def logout(self, token: str | None) -> None:
        if not token:
            return
        auth = await self.sessions.by_digest(token_digest(token))
        if auth is not None:
            await self.sessions.delete(auth)
            await self.session.commit()

    # --- becoming somebody --------------------------------------------------

    async def claim(
        self,
        user: User,
        *,
        email: str,
        password: str,
        display_name: str | None = None,
        install_id: int | None = None,
        user_agent: str | None = None,
    ) -> Credential:
        """Put a name on the guest account that has already been watching.

        Same row, so everything half-finished as a guest is still there on a
        laptop later. The token is rotated because the old one was handed out
        under weaker terms — anyone who saw it now has a whole account.
        """
        if not user.is_guest:
            raise Conflict("this account is already claimed")

        email = self._check_credentials(email, password)
        if await self.users.by_email(email) is not None:
            raise Conflict("that email is taken")

        user.email = email
        user.password_hash = hash_password(password)
        user.display_name = (display_name or "").strip() or email.split("@")[0]
        user.claimed_at = utcnow()

        await self.sessions.revoke_all(user.id)
        credential = await self._issue(user, install_id=install_id, user_agent=user_agent)
        return await self._commit_or_conflict(credential)

    async def register(
        self,
        *,
        email: str,
        password: str,
        display_name: str | None = None,
        role: Role = Role.user,
        install_id: int | None = None,
        user_agent: str | None = None,
    ) -> Credential:
        """A claimed account with no guest behind it.

        Two callers: somebody who ran the app locally and only now wants to be
        remembered, and a shell creating the first admin before anyone has a
        session.
        """
        email = self._check_credentials(email, password)
        if await self.users.by_email(email) is not None:
            raise Conflict("that email is taken")

        user = await self.users.add(
            User(
                display_name=(display_name or "").strip() or email.split("@")[0],
                email=email,
                password_hash=hash_password(password),
                role=role,
                claimed_at=utcnow(),
            )
        )
        credential = await self._issue(user, install_id=install_id, user_agent=user_agent)
        return await self._commit_or_conflict(credential)

    async def rename(self, user: User, display_name: str) -> Account:
        name = display_name.strip()
        if not name:
            raise Invalid("display_name can't be empty")
        user.display_name = name[:80]
        await self.session.commit()
        return Account.of(user)

    async def forget(self, user: User) -> None:
        """Delete the account and everything cascading off it.

        The way back to local-only. There is no soft delete on purpose: an
        account somebody asked us to forget is not an account we keep a copy of.
        """
        await self.users.delete(user)
        await self.session.commit()

    # --- administration -----------------------------------------------------

    async def find(self, email: str) -> Account | None:
        """Whoever signed up with that address, if anybody did.

        For a shell. The API itself never needs it — a request arrives holding a
        token, and looking somebody up by email over HTTP is how an endpoint
        becomes a way to ask whether an address has an account here.
        """
        user = await self.users.by_email(email)
        return None if user is None else Account.of(user)

    async def all_users(
        self, *, limit: int = 50, offset: int = 0, guests: bool | None = None
    ) -> tuple[list[Account], int]:
        users, total = await self.users.page(limit=limit, offset=offset, guests=guests)
        return [Account.of(user) for user in users], total

    async def set_role(self, public_id: str, role: Role) -> Account:
        user = await self.users.by_public_id(public_id)
        if user is None:
            raise NotFound(f"no user {public_id!r}")
        if user.is_guest and role is Role.admin:
            raise Invalid("claim the account before making it an admin")
        if user.is_admin and role is not Role.admin and await self.users.count_admins() == 1:
            # Locking yourself out of your own stack is a bad afternoon.
            raise Forbidden("that's the last admin")

        user.role = role
        await self.session.commit()
        return Account.of(user)

    # --- internals ----------------------------------------------------------

    def _check_credentials(self, email: str, password: str) -> str:
        if len(password) < MIN_PASSWORD:
            raise Invalid(f"password must be at least {MIN_PASSWORD} characters")
        return email.strip().lower()

    async def _commit_or_conflict(self, credential: Credential) -> Credential:
        try:
            await self.session.commit()
        except IntegrityError as exc:
            # Two sign-ups racing for the same email. The unique index is the
            # referee; this only translates its verdict.
            await self.session.rollback()
            raise Conflict("that email is taken") from exc
        return credential

    async def _issue(
        self, user: User, *, install_id: int | None, user_agent: str | None
    ) -> Credential:
        token = new_token()
        expires_at = utcnow() + timedelta(days=settings.session_ttl_days)
        await self.sessions.add(
            AuthSession(
                user_id=user.id,
                install_id=install_id,
                token_hash=token_digest(token),
                expires_at=expires_at,
                user_agent=_fits(user_agent, AuthSession.user_agent.type.length),
            )
        )
        return Credential(token=token, expires_at=expires_at, account=Account.of(user))

    # --- signing in a device with no keyboard -------------------------------

    @property
    def links(self) -> DeviceLinkRepository:
        return DeviceLinkRepository(self.session)

    async def installs_for(self, user_id: int) -> set[int]:
        """The boxes this person is signed in on — and so the boxes they may
        drive. No table of its own: signing a box in *is* claiming it."""
        return await self.sessions.install_ids_for(user_id, now=utcnow())

    async def install_of(self, token: str | None) -> int | None:
        """Which install the caller's session was issued to, if any.

        Read rather than trusted from the request: a box could claim any number
        it liked, and this one comes off the session it is holding.
        """
        if not token:
            return None
        auth = await self.sessions.by_digest(token_digest(token))
        return auth.install_id if auth is not None and auth.is_live() else None

    async def start_link(
        self, *, device_name: str | None = None, install_id: int | None = None
    ) -> DeviceRequest:
        """Begin a pairing. Nobody is authenticated yet — that is the point."""
        secret = new_token()

        # Codes are short, so collisions are possible rather than theoretical.
        for _ in range(5):
            code = "".join(secrets.choice(LINK_ALPHABET) for _ in range(LINK_LENGTH))
            if await self.links.by_code(code) is None:
                break
        else:  # pragma: no cover — five in a row means something else is wrong
            raise Conflict("could not allocate a code")

        link = await self.links.add(
            DeviceLink(
                code=code,
                secret_digest=token_digest(secret),
                device_name=_fits(device_name, DeviceLink.device_name.type.length),
                install_id=install_id,
                expires_at=utcnow() + LINK_TTL,
            )
        )
        await self.session.commit()
        return DeviceRequest(code=link.code, secret=secret, expires_at=link.expires_at)

    async def link_for(self, code: str) -> DeviceStatus:
        """The pending request behind a code, for the page about to approve it."""
        return DeviceStatus.of(await self._live_link(code))

    async def approve_link(self, code: str, user: User) -> DeviceStatus:
        """Say yes, as somebody.

        The only step in this dance that needs an identity, and it is the
        phone's, not the television's.
        """
        link = await self._live_link(code)
        if not link.pending and link.user_id != user.id:
            raise Conflict("that code was already used by somebody else")

        link.user_id = user.id
        link.approved_at = utcnow()
        await self.session.commit()
        return DeviceStatus.of(link)

    async def collect_link(
        self, secret: str, *, user_agent: str | None = None
    ) -> Credential | None:
        """The television asking whether it may come in yet.

        `None` means "not yet" — the ordinary answer while somebody walks to
        their phone. Anything else is final: a session, or a refusal.

        The box's own guest account, if it had one, is left alone rather than
        merged. Nothing is lost, and what to do with a guest's history when it
        meets a real account is a decision worth making on purpose later.
        """
        link = await self.links.by_secret(token_digest(secret))
        if link is None:
            raise NotFound("unknown device")
        if link.expired(utcnow()):
            raise Invalid("that request has expired")
        # A token handed out twice is a token that can be replayed. Once is once.
        if link.consumed_at is not None:
            raise Invalid("that request was already collected")
        if link.pending or link.user is None:
            return None

        credential = await self._issue(link.user, install_id=link.install_id, user_agent=user_agent)
        link.consumed_at = utcnow()
        await self.session.commit()
        return credential

    async def sweep_links(self) -> int:
        """Housekeeping, for a job. Nothing calls it on a request path."""
        swept = await self.links.sweep(utcnow())
        await self.session.commit()
        return swept

    async def _live_link(self, code: str) -> DeviceLink:
        """The row, for the two methods above. Everything else gets a DTO."""
        link = await self.links.by_code(code)
        if link is None:
            raise NotFound("no such code")
        if link.expired(utcnow()):
            raise Invalid("that code has expired")
        return link
