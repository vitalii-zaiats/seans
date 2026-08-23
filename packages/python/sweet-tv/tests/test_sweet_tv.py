"""The port, checked against the payloads the Dart package is checked against."""

import json
import re
from datetime import UTC, date, datetime, timedelta

import pytest
from conftest import AsyncFakeTransport, FakeTransport
from sweet_tv import (
    ALL_CATEGORY,
    AsyncSweetTv,
    Device,
    HTTPError,
    NetworkError,
    Refused,
    SerializationError,
    Site,
    SweetTv,
    secure,
)
from sweet_tv.transport import Request, Response

DEVICE = Device(uuid="7f3a-fixed-uuid")


def tv(transport: FakeTransport) -> SweetTv:
    return SweetTv(transport, device=DEVICE)  # type: ignore[arg-type]


# --- the catalogue ------------------------------------------------------------


def test_the_channel_list_is_asked_for_as_a_browser() -> None:
    transport = FakeTransport.fixture("channel-list")
    tv(transport).channels()

    request = transport.last_request
    assert request.method == "GET"
    assert request.url == "https://sweet.tv/webapi/v2/public/ua-uk/free-tv/channel_list"
    # That host wants the literal string, not the five-number device line.
    assert request.headers["x-device"] == "web"


def test_channels_parse() -> None:
    catalogue = tv(FakeTransport.fixture("channel-list")).channels()

    assert len(catalogue.channels) == 6
    first = catalogue.channels[0]
    assert first.id == 3554
    assert first.name == "SWEET.TV Originals HD"
    assert first.slug == "3554-zradniki-hd"
    assert first.free_to_watch
    assert ALL_CATEGORY in first.categories
    assert first.now_playing


def test_an_icon_is_rewritten_to_https_rather_than_proxied() -> None:
    # The catalogue hands these out as plain http, which a page on https refuses
    # as mixed content. The same file is there over https.
    catalogue = tv(FakeTransport.fixture("channel-list")).channels()

    icon = catalogue.channels[0].icon_url
    assert icon is not None and icon.startswith("https://static.sweet.tv/")
    assert secure("http://x/y") == "https://x/y"
    assert secure("https://x/y") == "https://x/y"
    assert secure(None) is None


def test_categories_come_back_in_the_order_the_site_shows_them() -> None:
    catalogue = tv(FakeTransport.fixture("channel-list")).channels()

    orders = [category.order for category in catalogue.categories]
    assert orders == sorted(orders)
    assert catalogue.categories[0].is_all
    assert catalogue.categories[0].slug is None


def test_a_catalogue_can_be_sliced_and_searched() -> None:
    catalogue = tv(FakeTransport.fixture("channel-list")).channels()

    assert catalogue.by_id(3554) is not None
    assert catalogue.by_id(1) is None
    assert len(catalogue.in_category(ALL_CATEGORY)) == len(catalogue.channels)


def test_catchup_is_zero_unless_the_channel_says_otherwise() -> None:
    body = json.dumps(
        {
            "channels": [
                {"id": 1, "name": "A", "catchup": False, "catchup_duration": 7},
                {"id": 2, "name": "B", "catchup": True, "catchup_duration": 7},
            ]
        }
    )
    catalogue = tv(FakeTransport.json(body)).channels()

    assert catalogue.channels[0].catchup_days == 0
    assert not catalogue.channels[0].has_catchup
    assert catalogue.channels[1].catchup_days == 7
    assert catalogue.channels[1].has_catchup


# --- the schedule -------------------------------------------------------------


def test_the_schedule_url_is_day_first_not_iso() -> None:
    transport = FakeTransport.fixture("epg-day")
    tv(transport).schedule(3554, date(2026, 8, 21))

    assert transport.last_request.url == (
        "https://static.sweet.tv/tv/epg/v3/3554/21-08-2026/uk.json"
    )


def test_a_day_parses_in_order() -> None:
    schedule = tv(FakeTransport.fixture("epg-day")).schedule(3554, date(2026, 8, 21))

    assert len(schedule) == 33
    first = schedule.programmes[0]
    assert first.title == "Вгадай мелодію Серія 7"
    assert first.start.tzinfo is not None
    assert first.stop > first.start
    assert first.length == first.stop - first.start


def test_what_is_on_and_what_follows() -> None:
    schedule = tv(FakeTransport.fixture("epg-day")).schedule(3554, date(2026, 8, 21))
    first, second = schedule.programmes[0], schedule.programmes[1]

    midway = first.start + first.length / 2
    assert schedule.on_at(midway) == first
    assert schedule.after(midway) == second
    assert 0.4 < first.progress_at(midway) < 0.6
    assert first.progress_at(first.start - timedelta(hours=1)) == 0.0
    assert first.progress_at(first.stop + timedelta(hours=1)) == 1.0


def test_nothing_is_on_outside_the_day_this_covers() -> None:
    schedule = tv(FakeTransport.fixture("epg-day")).schedule(3554, date(2026, 8, 21))

    assert schedule.on_at(datetime(1999, 1, 1, tzinfo=UTC)) is None
    # Before the first programme, "what follows" is the first one.
    assert schedule.after(datetime(1999, 1, 1, tzinfo=UTC)) == schedule.programmes[0]
    # Inside the last, there is no next: it belongs to tomorrow's answer, and
    # this does not stitch two days together behind the caller's back.
    last = schedule.programmes[-1]
    assert schedule.after(last.start + timedelta(seconds=1)) is None


def test_a_schedule_that_is_not_a_list_is_refused() -> None:
    with pytest.raises(SerializationError, match="expected a JSON array"):
        tv(FakeTransport.json('{"nope": 1}')).schedule(3554, date(2026, 8, 21))


# --- streams ------------------------------------------------------------------


def test_opening_a_stream_sends_what_stands_in_for_an_account() -> None:
    transport = FakeTransport.fixture("open-stream")
    tv(transport).open_stream(3554)

    request = transport.last_request
    assert request.method == "POST"
    assert request.url == "https://api.sweet.tv/TvService/OpenStream.json"
    assert request.headers["x-device"] == "1;22;39;2;9.0.24"
    assert request.headers["x-device-id"] == DEVICE.uuid
    assert request.headers["referer"] == "https://sweet.tv/"
    assert json.loads(request.body or b"") == {
        "channel_id": 3554,
        "multistream": True,
        "uuid": DEVICE.uuid,
        "consent": None,
        "accept_scheme": ["HTTP_HLS"],
    }


def test_a_stream_is_a_lease() -> None:
    stream = tv(FakeTransport.fixture("open-stream")).open_stream(3554)

    assert stream.url.startswith("https://")
    assert stream.stream_id
    assert stream.refresh_after == timedelta(minutes=5)
    # Built out of the `http_stream` block, which is what that block is for.
    assert stream.plain_url is not None
    assert stream.plain_url.startswith("http://stitch-")
    assert ":80" not in stream.plain_url


def test_a_port_that_is_not_eighty_is_kept() -> None:
    body = json.dumps(
        {
            "result": "OK",
            "url": "https://x/y.m3u8",
            "http_stream": {"host": {"address": "h", "port": 8080}, "url": "/p.m3u8"},
        }
    )
    stream = tv(FakeTransport.json(body)).open_stream(1)

    assert stream.plain_url == "http://h:8080/p.m3u8"


def test_a_channel_outside_the_free_tier_says_so() -> None:
    with pytest.raises(Refused) as caught:
        tv(FakeTransport.json('{"result": "NoAuth"}')).open_stream(1)

    assert caught.value.needs_account
    assert "not free" in str(caught.value)


def test_any_other_refusal_carries_what_the_service_said() -> None:
    with pytest.raises(Refused, match="Whatever"):
        tv(FakeTransport.json('{"result": "Whatever"}')).open_stream(1)


def test_a_result_with_no_address_is_not_a_stream() -> None:
    with pytest.raises(SerializationError, match="no stream address"):
        tv(FakeTransport.json('{"result": "OK"}')).open_stream(1)


def test_closing_a_stream_never_raises() -> None:
    # Without an account the service answers NoAuth and the lease expires on its
    # own. A failure here is not worth showing anybody.
    transport = FakeTransport.json('{"result": "NoAuth"}')
    tv(transport).close_stream(42)

    assert json.loads(transport.last_request.body or b"") == {"stream_id": 42}


def test_closing_survives_a_dead_network() -> None:
    tv(FakeTransport.failing(OSError("reset"))).close_stream(42)


# --- failures -----------------------------------------------------------------


def test_a_non_2xx_status_is_an_http_error() -> None:
    with pytest.raises(HTTPError) as caught:
        tv(FakeTransport.json("nope", status_code=503)).channels()

    assert caught.value.is_server_error


def test_a_transport_failure_is_wrapped() -> None:
    boom = OSError("no route to host")

    with pytest.raises(NetworkError) as caught:
        tv(FakeTransport.failing(boom)).channels()

    assert caught.value.cause is boom


def test_a_body_that_is_not_json_is_refused() -> None:
    with pytest.raises(SerializationError, match="not valid JSON"):
        tv(FakeTransport.json("<html>no</html>")).channels()


def test_a_json_array_where_an_object_belongs_is_refused() -> None:
    with pytest.raises(SerializationError, match="expected a JSON object"):
        tv(FakeTransport.json("[1, 2]")).channels()


def test_a_missing_required_field_names_itself() -> None:
    with pytest.raises(SerializationError, match=re.escape("`Channel.id`")):
        tv(FakeTransport.json('{"channels": [{"name": "A"}]}')).channels()


def test_close_closes_the_transport() -> None:
    transport = FakeTransport.fixture("channel-list")
    with tv(transport):
        pass

    assert transport.closed


# --- a locale other than the default -----------------------------------------


def test_a_different_locale_changes_both_paths() -> None:
    # The catalogue is addressed by locale, the schedule files by language
    # alone — two different halves of the same setting.
    from conftest import fixture

    def answer(request: Request) -> Response:
        body = fixture("channel-list") if "channel_list" in request.url else "[]"
        return Response(status_code=200, body=body.encode())

    transport = FakeTransport(answer)
    client = SweetTv(transport, device=DEVICE, site=Site(locale="ua-en", language="en"))  # type: ignore[arg-type]

    client.channels()
    assert "/ua-en/" in transport.last_request.url

    client.schedule(1, date(2026, 8, 21))
    assert transport.last_request.url.endswith("/en.json")


# --- the same thing, awaited --------------------------------------------------


async def test_the_async_client_reads_the_same_payloads() -> None:
    transport = AsyncFakeTransport.fixture("channel-list")
    catalogue = await AsyncSweetTv(transport, device=DEVICE).channels()  # type: ignore[arg-type]

    assert len(catalogue.channels) == 6


async def test_the_async_client_opens_a_stream() -> None:
    transport = AsyncFakeTransport.fixture("open-stream")
    stream = await AsyncSweetTv(transport, device=DEVICE).open_stream(3554)  # type: ignore[arg-type]

    assert stream.url
    assert transport.last_request.headers["x-device-id"] == DEVICE.uuid


async def test_the_async_client_refuses_a_paid_channel() -> None:
    transport = AsyncFakeTransport.json('{"result": "NoAuth"}')

    with pytest.raises(Refused):
        await AsyncSweetTv(transport, device=DEVICE).open_stream(1)  # type: ignore[arg-type]


async def test_the_async_context_manager_closes() -> None:
    transport = AsyncFakeTransport.fixture("channel-list")
    async with AsyncSweetTv(transport, device=DEVICE) as client:  # type: ignore[arg-type]
        await client.channels()

    assert transport.closed


def test_a_device_invents_a_uuid_and_keeps_it() -> None:
    one, two = Device(), Device()

    assert one.uuid != two.uuid
    assert one.header == "1;22;39;2;9.0.24"
