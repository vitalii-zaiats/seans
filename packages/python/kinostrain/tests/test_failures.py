"""What a caller sees when it goes wrong."""

import re

import pytest
from conftest import FakeTransport
from kinostrain import (
    HTTPError,
    KinostrainApi,
    NetworkError,
    SerializationError,
)


def api_for(transport: FakeTransport) -> KinostrainApi:
    return KinostrainApi(transport)  # type: ignore[arg-type]


def test_maps_a_non_2xx_status_to_http_error() -> None:
    transport = FakeTransport.json('{"message": "Not found"}', status_code=404)

    with pytest.raises(HTTPError) as caught:
        api_for(transport).content("nope")

    error = caught.value
    assert error.status_code == 404
    assert error.is_not_found
    assert not error.is_rate_limited
    assert not error.is_server_error
    assert error.body is not None and "Not found" in error.body
    assert "/content/nope" in error.url


def test_flags_retryable_server_errors() -> None:
    for status, rate_limited, server in ((429, True, False), (503, False, True)):
        with pytest.raises(HTTPError) as caught:
            api_for(FakeTransport.json("{}", status_code=status)).trending()
        assert caught.value.is_rate_limited is rate_limited
        assert caught.value.is_server_error is server


def test_clips_a_long_error_body() -> None:
    transport = FakeTransport.json("x" * 2000, status_code=500)

    with pytest.raises(HTTPError) as caught:
        api_for(transport).trending()

    body = caught.value.body
    assert body is not None
    assert len(body) == 513 and body.endswith("…")


def test_wraps_a_transport_failure_in_network_error() -> None:
    boom = OSError("connection reset")
    transport = FakeTransport.failing(boom)

    with pytest.raises(NetworkError) as caught:
        api_for(transport).trending()

    assert caught.value.cause is boom
    assert caught.value.url.endswith("/trending")


def test_treats_a_timeout_as_a_network_failure() -> None:
    with pytest.raises(NetworkError):
        api_for(FakeTransport.failing(TimeoutError())).trending()


def test_rejects_a_body_that_is_not_json() -> None:
    with pytest.raises(SerializationError, match="not valid JSON"):
        api_for(FakeTransport.json("<html>nope</html>")).trending()


def test_rejects_a_json_array_where_an_object_is_expected() -> None:
    with pytest.raises(SerializationError, match="expected a JSON object"):
        api_for(FakeTransport.json("[1, 2, 3]")).trending()


def test_names_the_offending_field_when_a_required_one_is_missing() -> None:
    body = (
        '{"data": [{"originalName": "Dune", "slug": "duna", "type": "movie",'
        ' "format": "film", "posterUrl": "p"}]}'
    )

    with pytest.raises(SerializationError, match=re.escape("`ContentCard.name`")):
        api_for(FakeTransport.json(body)).trending()


def test_names_the_field_when_a_required_one_changed_type() -> None:
    body = (
        '{"data": [{"name": 7, "originalName": "Dune", "slug": "duna", "type": "movie",'
        ' "format": "film", "posterUrl": "p"}]}'
    )
    wanted = re.escape("expected str at `ContentCard.name`, got int")

    with pytest.raises(SerializationError, match=wanted):
        api_for(FakeTransport.json(body)).trending()


def test_reports_a_paginated_response_that_lost_its_meta_block() -> None:
    with pytest.raises(SerializationError, match=re.escape("`meta` object")):
        api_for(FakeTransport.json('{"data": []}')).catalog()


def test_reports_a_content_response_that_lost_its_data_block() -> None:
    with pytest.raises(SerializationError, match=re.escape("`data` object for content `x`")):
        api_for(FakeTransport.json('{"meta": {}}')).content("x")


def test_a_serialization_error_is_not_reported_as_a_network_failure() -> None:
    # The parse happens after the transport returned, so a bad payload must not
    # be swallowed by the `except Exception` that builds NetworkError.
    with pytest.raises(SerializationError):
        api_for(FakeTransport.json("[]")).trending()
