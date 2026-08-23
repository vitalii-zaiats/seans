"""Whether to update, where from, and what this build may switch on.

Where an update comes from is decided by who installed the app, not by us:

    com.android.vending   Google's. It updates itself through the Play Store,
                          and a build that sideloads its own APK is a build
                          that gets pulled from the shop. So: `store`, and the
                          answer is a link to the listing.
    anything else         an APK from our own site, an .exe, a .deb — nobody
                          else is going to update it, so it updates itself.
    web                   there is nothing to update. A reload *is* the new
                          version.

The same split decides features. A Play Store build is reviewed, and some of
what this app does is easier to ship when Google is not reading the manifest —
`store_disabled_features` names those, and they come back off no matter what
the base configuration says.

The vocabulary below is duplicated, on purpose, by every module that consumes
it: they are `Literal`s rather than a shared enum precisely so that no module
has to import this one to name a value.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Literal

from api.errors import Invalid
from api.modules.release.versions import parse
from api.settings import Settings

#: The installer package Google Play reports on an Android install.
PLAY_STORE = "com.android.vending"
#: The one platform that updates itself without being told to.
SELF_UPDATING_PLATFORM = "web"

Action = Literal["none", "optional", "required"]
Channel = Literal["store", "self", "auto"]


@dataclass(frozen=True, slots=True)
class Plan:
    """What the client should do about the version it is running."""

    action: Action
    channel: Channel
    #: Echoed back so a log line reads on its own.
    current: str
    latest: str
    minimum: str
    #: Where to go. `None` when there is nowhere to go — `auto`, or a
    #: self-updating build with no download configured yet.
    url: str | None


@dataclass(slots=True)
class ReleaseService:
    settings: Settings

    def plan(self, *, platform: str, vendor: str | None, version: str) -> Plan:
        current = parse(version)
        if current is None:
            raise Invalid(f"{version!r} is not a version")

        minimum = self.settings.min_for(platform)
        latest = self.settings.latest_for(platform)
        channel = self._channel(platform, vendor)

        return Plan(
            action=self._action(current, minimum, latest),
            channel=channel,
            current=version,
            latest=latest,
            minimum=minimum,
            url=self._url(channel),
        )

    def features(self, *, vendor: str | None) -> Mapping[str, bool]:
        """The switches this build may see, with the shop's veto applied."""
        flags = dict(self.settings.feature_flags)
        if vendor == PLAY_STORE:
            for name in self.settings.store_disabled:
                flags[name] = False
        return flags

    def _action(self, current: tuple[int, ...], minimum: str, latest: str) -> Action:
        # A floor or a ceiling we cannot parse is a configuration mistake, and
        # the safe reading of one is "do not order anybody to update".
        floor = parse(minimum)
        if floor is not None and current < floor:
            return "required"
        ceiling = parse(latest)
        if ceiling is not None and current < ceiling:
            return "optional"
        return "none"

    def _channel(self, platform: str, vendor: str | None) -> Channel:
        if platform == SELF_UPDATING_PLATFORM:
            return "auto"
        return "store" if vendor == PLAY_STORE else "self"

    def _url(self, channel: Channel) -> str | None:
        if channel == "store":
            return self.settings.store_url
        if channel == "self":
            return self.settings.self_update_url
        return None
