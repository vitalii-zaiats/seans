"""Entry point: `uv run api`.

Two things a shell needs from this app: run it, and put the first admin in the
database. The second exists because the role cannot be granted over HTTP by
anybody who does not already have it — which is correct, and which leaves the
very first one with no way in.

    uv run api                                  serve
    uv run api serve
    uv run api admin boss@example.com           create, or promote if it exists
"""

import argparse
import asyncio
import getpass
import sys

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

    arguments = parser.parse_args()

    if arguments.command != "admin":
        serve()
        return

    try:
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
