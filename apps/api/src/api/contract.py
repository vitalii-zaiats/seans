"""The HTTP contract, written down.

FastAPI already knows the whole shape of this API — every path, every schema,
every status it answers with. This dumps that knowledge to
`contracts/openapi.json` so a client can be written, reviewed and typed against
a file in the repo instead of against a server somebody has to be running.

    uv run openapi              # rewrite contracts/openapi.json
    uv run openapi --check      # say so, and fail, when it is out of date

Generated rather than hand-kept, for the reason the `.proto` files carry a
warning instead of a guarantee: a description nobody regenerates drifts, and a
drifted contract is worse than no contract, because it is believed.
"""

import json
import sys
from pathlib import Path

from api.main import app

#: `src/api/contract.py` → `apps/api/src/api` → … → the checkout's root. Held as
#: a path rather than looked up from the working directory so the command means
#: the same thing from anywhere in the tree; an installed wheel has no repo
#: around it and would have to be told where to write.
DEFAULT = Path(__file__).resolve().parents[4] / "contracts" / "openapi.json"


def document() -> str:
    """The schema as it is committed: two-space indent, Cyrillic left alone.

    Not sorted. The order FastAPI emits is the order the routers are registered
    in, which groups the paths by module — the same grouping `contracts/proto/`
    keeps, and worth more in a diff than alphabetical would be.
    """
    return json.dumps(app.openapi(), indent=2, ensure_ascii=False) + "\n"


def main() -> None:
    argv = sys.argv[1:]
    check = "--check" in argv
    rest = [one for one in argv if one != "--check"]
    target = Path(rest[0]) if rest else DEFAULT

    fresh = document()
    if check:
        stale = not target.exists() or target.read_text(encoding="utf-8") != fresh
        if stale:
            print(f"{target} is out of date — run `uv run openapi`", file=sys.stderr)
            raise SystemExit(1)
        print(f"{target} is up to date")
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(fresh, encoding="utf-8")
    print(f"wrote {target} ({len(app.openapi()['paths'])} paths)")


if __name__ == "__main__":
    main()
