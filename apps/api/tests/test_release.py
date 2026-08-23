"""The update policy and the shop's veto. No database in sight."""

import pytest
from api.errors import Invalid
from api.modules.release.service import PLAY_STORE, ReleaseService
from api.modules.release.versions import parse
from api.settings import Settings


def service(**overrides: object) -> ReleaseService:
    return ReleaseService(Settings(**overrides))  # type: ignore[arg-type]


def test_parses_the_shapes_flutter_writes() -> None:
    assert parse("1") == (1, 0, 0, 0)
    assert parse("1.4") == (1, 4, 0, 0)
    assert parse("1.4.2") == (1, 4, 2, 0)
    assert parse("1.4.2+37") == (1, 4, 2, 37)
    assert parse(" 1.4.2 ") == (1, 4, 2, 0)


def test_refuses_anything_that_is_not_a_version() -> None:
    for value in ("", "v1.0.0", "1.0.0-beta", "latest", "1.0.0+", "1.2.3.4"):
        assert parse(value) is None


def test_a_build_number_breaks_a_tie() -> None:
    assert parse("1.4.2") < parse("1.4.2+1")  # type: ignore[operator]


def test_below_the_floor_is_a_required_update() -> None:
    plan = service(min_version="1.2.0", latest_version="1.5.0").plan(
        platform="android", vendor=None, version="1.1.9"
    )
    assert plan.action == "required"


def test_between_the_floor_and_the_ceiling_is_optional() -> None:
    plan = service(min_version="1.0.0", latest_version="1.5.0").plan(
        platform="android", vendor=None, version="1.2.0"
    )
    assert plan.action == "optional"


def test_on_the_latest_is_nothing_to_do() -> None:
    plan = service(min_version="1.0.0", latest_version="1.5.0").plan(
        platform="android", vendor=None, version="1.5.0"
    )
    assert plan.action == "none"


def test_a_platform_override_wins_over_the_global_floor() -> None:
    releases = service(
        min_version="1.0.0", latest_version="1.0.0", min_versions={"windows": "2.0.0"}
    )
    assert releases.plan(platform="windows", vendor=None, version="1.5.0").action == "required"
    assert releases.plan(platform="linux", vendor=None, version="1.5.0").action == "none"


def test_play_store_installs_are_sent_to_the_listing() -> None:
    plan = service(android_package="com.example.movies").plan(
        platform="android", vendor=PLAY_STORE, version="1.0.0"
    )
    assert plan.channel == "store"
    assert plan.url == "https://play.google.com/store/apps/details?id=com.example.movies"


def test_everything_else_on_android_updates_itself() -> None:
    plan = service(self_update_url="https://example.test/app.apk").plan(
        platform="android", vendor="org.fdroid.fdroid", version="1.0.0"
    )
    assert plan.channel == "self"
    assert plan.url == "https://example.test/app.apk"


def test_a_sideloaded_desktop_build_updates_itself_too() -> None:
    plan = service().plan(platform="windows", vendor=None, version="1.0.0")
    assert plan.channel == "self"


def test_the_web_build_has_nothing_to_update() -> None:
    plan = service(self_update_url="https://example.test/app.apk").plan(
        platform="web", vendor=None, version="1.0.0"
    )
    assert plan.channel == "auto"
    assert plan.url is None


def test_an_unreadable_version_is_refused_rather_than_guessed_at() -> None:
    with pytest.raises(Invalid, match="not a version"):
        service().plan(platform="android", vendor=None, version="nightly")


def test_an_unparseable_floor_never_orders_an_update() -> None:
    # A typo in configuration must not force every install to update.
    plan = service(min_version="oops", latest_version="oops").plan(
        platform="android", vendor=None, version="1.0.0"
    )
    assert plan.action == "none"


def test_the_shop_vetoes_the_features_it_reviews() -> None:
    releases = service(
        features={"downloads": True, "external_players": True},
        store_disabled_features=["external_players"],
    )

    assert releases.features(vendor=PLAY_STORE) == {
        "downloads": True,
        "external_players": False,
    }
    assert releases.features(vendor="org.fdroid.fdroid") == {
        "downloads": True,
        "external_players": True,
    }
    assert releases.features(vendor=None) == {"downloads": True, "external_players": True}
