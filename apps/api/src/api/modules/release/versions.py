"""Comparing the version a client reports against the ones we ship.

Flutter writes `1.4.2+37`: a name people read and a build number stores order
by. Both matter here — a hotfix that keeps the name and bumps the build is still
a newer build — so the number becomes a fourth component and an absent one
sorts first, making `1.4.2` older than `1.4.2+1`.
"""

import re

#: `1`, `1.2`, `1.2.3`, `1.2.3+45`. Anything else is a build misconfiguration,
#: not a version, and is refused rather than guessed at.
PATTERN = re.compile(r"^(\d{1,5})(?:\.(\d{1,5}))?(?:\.(\d{1,5}))?(?:\+(\d{1,9}))?$")

Version = tuple[int, int, int, int]


def parse(version: str) -> Version | None:
    """The four components, or `None` when the string is not a version."""
    found = PATTERN.match(version.strip())
    if found is None:
        return None
    major, minor, patch, build = found.groups()
    return int(major), int(minor or 0), int(patch or 0), int(build or 0)
