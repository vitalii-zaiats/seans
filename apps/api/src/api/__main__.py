"""Entry point: `uv run api`.

Three things a shell needs from this app: run it, put the first admin in the
database, and build the catalogue. The admin command exists because the role
cannot be granted over HTTP by anybody who does not already have it — which is
correct, and which leaves the very first one with no way in. The catalogue one
exists because loading it is minutes of work over files somebody scraped, and
that is not a request.

    uv run api                                  serve
    uv run api serve
    uv run api admin boss@example.com           create, or promote if it exists
    uv run api titles .data                     merge the catalogue dumps and load them
"""

import argparse
import asyncio
import getpass
import sys
from pathlib import Path

import uvicorn

from api.core.services import services
from api.errors import ApiError
from api.modules.accounts.models import Role
from api.settings import settings


def serve() -> None:
    uvicorn.run(
        "api.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.reload,
    )


async def _admin(email: str, password: str | None, display_name: str | None) -> int:
    async with services() as api:
        existing = await api.accounts.find(email)
        if existing is not None:
            if existing.is_admin:
                print(f"{email} is already an admin ({existing.id})")
                return 0
            account = await api.accounts.set_role(existing.id, Role.admin)
            print(f"promoted {account.email} to admin ({account.id})")
            return 0

        # Only asked for when the account has to be created — promoting one does
        # not need it, and prompting anyway would suggest it was being changed.
        secret = password or getpass.getpass("password: ")
        credential = await api.accounts.register(
            email=email, password=secret, display_name=display_name, role=Role.admin
        )
        print(f"created admin {credential.account.email} ({credential.account.id})")
        return 0


async def _titles(folder: Path, replace: bool) -> int:
    """Read the dumps, merge, and write the result as one transaction."""
    async with services() as api:
        if replace:
            await api.titles.clear()
        loaded = await api.titles.rebuild(folder)
        await api.session.commit()

    print(
        f"{loaded.titles} titles from {loaded.sources} source rows: "
        f"{loaded.identifiers} identifiers, {loaded.aliases} aliases, "
        f"{loaded.seasons} seasons, {loaded.episodes} episodes, "
        f"{loaded.streams} streams, {loaded.keys} keypad codes"
    )
    if loaded.contested:
        # Each of these is a merge that should have happened and did not. Worth
        # reading; never worth failing the load over.
        print(f"{len(loaded.contested)} contested identifiers, first few:")
        for line in loaded.contested[:10]:
            print(f"  {line}")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(prog="api", description="Super Movies API")
    commands = parser.add_subparsers(dest="command")

    commands.add_parser("serve", help="run the HTTP API (the default)")

    admin = commands.add_parser("admin", help="create or promote an administrator")
    admin.add_argument("email")
    admin.add_argument(
        "--password",
        help="skip the prompt. Only read when the account is being created — "
        "and it lands in your shell history, so prefer the prompt.",
    )
    admin.add_argument("--name", dest="display_name", help="defaults to the part before the @")

    titles = commands.add_parser("titles", help="merge the catalogue dumps and load them")
    titles.add_argument("folder", type=Path, help="where the .jsonl dumps are")
    titles.add_argument(
        "--keep",
        action="store_true",
        help="do not empty the tables first. Only useful on an empty database — "
        "a load writes the whole catalogue and does not reconcile with what is there.",
    )

    arguments = parser.parse_args()

    if arguments.command not in ("admin", "titles"):
        serve()
        return

    try:
        if arguments.command == "titles":
            raise SystemExit(asyncio.run(_titles(arguments.folder, not arguments.keep)))
        raise SystemExit(
            asyncio.run(_admin(arguments.email, arguments.password, arguments.display_name))
        )
    except ApiError as refusal:
        # A domain refusal is the expected way this fails — a password that is
        # too short, an email already taken. It is a message, not a traceback.
        print(f"error: {refusal}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
