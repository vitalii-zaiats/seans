"""Guests, claims, logins — and the token that carries all three."""

import uuid
from datetime import timedelta

import pytest
from api.core.models import utcnow
from api.core.security import hash_password, verify_password
from api.errors import Conflict, Forbidden, Invalid, NotFound, Unauthorized
from api.modules.accounts.models import AuthSession, Role, User
from api.modules.accounts.service import AccountService
from api.modules.installs.models import Install, Platform
from sqlalchemy.ext.asyncio import AsyncSession


async def an_install(db: AsyncSession) -> Install:
    install = Install(public_id=uuid.uuid4(), platform=Platform.linux, vendor=None, version="1.0.0")
    db.add(install)
    await db.commit()
    return install


# --- passwords ---------------------------------------------------------------


def test_a_password_verifies_against_its_own_hash() -> None:
    encoded = hash_password("correct horse battery")

    assert verify_password("correct horse battery", encoded)
    assert not verify_password("Correct horse battery", encoded)


def test_the_hash_is_salted_so_two_of_the_same_password_differ() -> None:
    assert hash_password("same") != hash_password("same")


def test_an_account_with_no_password_matches_nothing() -> None:
    # A guest has `password_hash = None`. Treating that as "any password works"
    # would be a way into every unclaimed account there is.
    assert not verify_password("", None)
    assert not verify_password("anything", None)


# --- guests ------------------------------------------------------------------


async def test_a_guest_arrives_already_signed_in(db: AsyncSession) -> None:
    install = await an_install(db)

    credential = await AccountService(db).guest(install_id=install.id)

    assert credential.token is not None
    assert credential.account.is_guest
    assert credential.account.email is None
    assert credential.account.display_name.startswith("Guest ")


async def test_two_guests_are_tellable_apart(db: AsyncSession) -> None:
    accounts = AccountService(db)

    first, second = await accounts.guest(), await accounts.guest()

    assert first.account.id != second.account.id
    assert first.account.display_name != second.account.display_name


async def test_establish_mints_when_there_is_nothing_to_keep(db: AsyncSession) -> None:
    install = await an_install(db)

    credential = await AccountService(db).establish(install.id)

    assert credential.token is not None
    assert credential.expires_at > utcnow()


async def test_establish_keeps_a_live_token(db: AsyncSession) -> None:
    install = await an_install(db)
    accounts = AccountService(db)
    first = await accounts.establish(install.id)

    again = await accounts.establish(install.id, first.token)

    assert again.token is None
    assert again.account.id == first.account.id


async def test_establish_honours_a_token_whatever_install_sends_it(
    db: AsyncSession,
) -> None:
    # The token is a bearer credential. Refusing it because the install uuid
    # changed would sign out somebody who restored a backup, and protect nothing.
    old, new = await an_install(db), await an_install(db)
    accounts = AccountService(db)
    first = await accounts.establish(old.id)

    again = await accounts.establish(new.id, first.token)

    assert again.token is None
    assert again.account.id == first.account.id


async def test_establish_replaces_a_dead_token(db: AsyncSession) -> None:
    install = await an_install(db)
    accounts = AccountService(db)
    first = await accounts.establish(install.id)

    expired = await db.get(AuthSession, 1)
    assert expired is not None
    expired.expires_at = utcnow() - timedelta(seconds=1)
    await db.commit()

    again = await accounts.establish(install.id, first.token)

    assert again.token is not None and again.token != first.token
    # A dead session is not resurrected: whoever sent it is a new guest.
    assert again.account.id != first.account.id


# --- identity ----------------------------------------------------------------


async def test_identify_shrugs_at_nothing(db: AsyncSession) -> None:
    accounts = AccountService(db)

    assert await accounts.identify(None) is None
    assert await accounts.identify("") is None
    assert await accounts.identify("not a token anybody issued") is None


async def test_the_token_itself_is_never_stored(db: AsyncSession) -> None:
    credential = await AccountService(db).guest()
    assert credential.token is not None

    stored = await db.get(AuthSession, 1)

    assert stored is not None
    assert credential.token not in stored.token_hash
    assert len(stored.token_hash) == 64


async def test_logout_takes_the_token_back(db: AsyncSession) -> None:
    accounts = AccountService(db)
    credential = await accounts.guest()

    await accounts.logout(credential.token)

    assert await accounts.identify(credential.token) is None


# --- claiming ----------------------------------------------------------------


async def test_claim_keeps_the_row_the_guest_was_using(db: AsyncSession) -> None:
    accounts = AccountService(db)
    guest = await accounts.guest()
    user = await accounts.identify(guest.token)
    assert user is not None

    claimed = await accounts.claim(user, email="Vi@Example.COM ", password="hunter2hunter2")

    assert claimed.account.id == guest.account.id  # same account, new name on it
    assert claimed.account.email == "vi@example.com"
    assert not claimed.account.is_guest
    assert claimed.account.display_name == "vi"


async def test_claim_rotates_the_token(db: AsyncSession) -> None:
    accounts = AccountService(db)
    guest = await accounts.guest()
    user = await accounts.identify(guest.token)
    assert user is not None

    claimed = await accounts.claim(user, email="vi@example.com", password="hunter2hunter2")

    assert claimed.token is not None and claimed.token != guest.token
    # The old one was handed out under weaker terms — anyone who saw it would
    # now have a whole account.
    assert await accounts.identify(guest.token) is None


async def test_claim_refuses_an_account_that_already_has_a_name(db: AsyncSession) -> None:
    accounts = AccountService(db)
    guest = await accounts.guest()
    user = await accounts.identify(guest.token)
    assert user is not None
    await accounts.claim(user, email="vi@example.com", password="hunter2hunter2")

    with pytest.raises(Conflict, match="already claimed"):
        await accounts.claim(user, email="other@example.com", password="hunter2hunter2")


async def test_claim_refuses_a_taken_email(db: AsyncSession) -> None:
    accounts = AccountService(db)
    await accounts.register(email="vi@example.com", password="hunter2hunter2")
    guest = await accounts.guest()
    user = await accounts.identify(guest.token)
    assert user is not None

    with pytest.raises(Conflict, match="taken"):
        await accounts.claim(user, email="VI@example.com", password="hunter2hunter2")


async def test_a_short_password_is_refused(db: AsyncSession) -> None:
    accounts = AccountService(db)

    with pytest.raises(Invalid, match="at least 8"):
        await accounts.register(email="vi@example.com", password="short")


# --- registering and logging in ----------------------------------------------


async def test_register_makes_a_claimed_account_with_no_guest_behind_it(
    db: AsyncSession,
) -> None:
    credential = await AccountService(db).register(
        email="vi@example.com", password="hunter2hunter2", display_name="Vitalii"
    )

    assert credential.token is not None
    assert not credential.account.is_guest
    assert credential.account.display_name == "Vitalii"


async def test_login_opens_a_second_session_on_the_same_row(db: AsyncSession) -> None:
    accounts = AccountService(db)
    registered = await accounts.register(email="vi@example.com", password="hunter2hunter2")

    signed_in = await accounts.login("VI@Example.com", "hunter2hunter2")

    assert signed_in.account.id == registered.account.id
    assert signed_in.token != registered.token
    # Both still work: signing in somewhere else does not sign you out here.
    assert await accounts.identify(registered.token) is not None
    assert await accounts.identify(signed_in.token) is not None


async def test_a_wrong_password_and_an_unknown_email_look_the_same(
    db: AsyncSession,
) -> None:
    accounts = AccountService(db)
    await accounts.register(email="vi@example.com", password="hunter2hunter2")

    with pytest.raises(Unauthorized) as wrong:
        await accounts.login("vi@example.com", "not the password")
    with pytest.raises(Unauthorized) as unknown:
        await accounts.login("nobody@example.com", "hunter2hunter2")

    assert str(wrong.value) == str(unknown.value)


async def test_a_guest_cannot_be_logged_into(db: AsyncSession) -> None:
    accounts = AccountService(db)
    await accounts.guest()

    with pytest.raises(Unauthorized):
        await accounts.login("", "")


# --- the way back ------------------------------------------------------------


async def test_forget_deletes_the_account_and_its_sessions(db: AsyncSession) -> None:
    accounts = AccountService(db)
    credential = await accounts.guest()
    user = await accounts.identify(credential.token)
    assert user is not None

    await accounts.forget(user)

    assert await accounts.identify(credential.token) is None
    assert await accounts.sessions.count() == 0
    assert await accounts.users.count() == 0


# --- administration ----------------------------------------------------------


async def test_a_guest_cannot_be_made_an_admin(db: AsyncSession) -> None:
    accounts = AccountService(db)
    guest = await accounts.guest()

    with pytest.raises(Invalid, match="claim the account"):
        await accounts.set_role(guest.account.id, Role.admin)


async def test_the_last_admin_cannot_be_demoted(db: AsyncSession) -> None:
    accounts = AccountService(db)
    admin = await accounts.register(
        email="boss@example.com", password="hunter2hunter2", role=Role.admin
    )

    with pytest.raises(Forbidden, match="last admin"):
        await accounts.set_role(admin.account.id, Role.user)


async def test_setting_a_role_on_nobody_is_a_not_found(db: AsyncSession) -> None:
    with pytest.raises(NotFound):
        await AccountService(db).set_role("deadbeef", Role.admin)


async def test_listing_can_be_narrowed_to_guests(db: AsyncSession) -> None:
    accounts = AccountService(db)
    await accounts.guest()
    await accounts.register(email="vi@example.com", password="hunter2hunter2")

    guests, guest_total = await accounts.all_users(guests=True)
    claimed, claimed_total = await accounts.all_users(guests=False)
    everyone, total = await accounts.all_users()

    assert guest_total == 1 and guests[0].is_guest
    assert claimed_total == 1 and not claimed[0].is_guest
    assert total == 2 and len(everyone) == 2


async def test_rename_trims_and_refuses_nothing(db: AsyncSession) -> None:
    accounts = AccountService(db)
    credential = await accounts.guest()
    user = await accounts.identify(credential.token)
    assert user is not None

    assert (await accounts.rename(user, "  Vitalii  ")).display_name == "Vitalii"
    with pytest.raises(Invalid):
        await accounts.rename(user, "   ")


async def test_a_user_row_knows_whether_it_is_an_admin(db: AsyncSession) -> None:
    user = User(display_name="x", role=Role.admin, claimed_at=utcnow())
    db.add(user)
    await db.commit()

    assert user.is_admin and not user.is_guest
