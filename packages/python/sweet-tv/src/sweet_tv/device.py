"""Who the client says it is.

The stream API wants an `x-device` header that is not a name but five numbers
joined by semicolons, and an `x-device-id` that is a uuid the client invents for
itself and registers nowhere. Together they are what stands in for an account on
the free channels.
"""

import uuid
from dataclasses import dataclass, field

#: `DT_Web_Browser`. The only value seen in captured traffic — what an Android TV
#: build of their own app sends is not known, and a guess here would be a guess
#: about whether the stream opens at all.
WEB_BROWSER = 22
#: `DST_MACOS`.
MACOS = 39
#: `AT_SWEET_TV_Player`.
PLAYER = 2


def new_uuid() -> str:
    return str(uuid.uuid4())


@dataclass(frozen=True, slots=True)
class Device:
    """Invent one, then keep it.

    Two different uuids are two different devices as far as the service is
    concerned, and a fresh one per launch looks like a fleet of boxes.
    """

    uuid: str = field(default_factory=new_uuid)
    version_code: int = 1
    type: int = WEB_BROWSER
    sub_type: int = MACOS
    application: int = PLAYER
    version: str = "9.0.24"

    @property
    def header(self) -> str:
        """`1;22;39;2;9.0.24`"""
        return ";".join(
            str(part)
            for part in (
                self.version_code,
                self.type,
                self.sub_type,
                self.application,
                self.version,
            )
        )
