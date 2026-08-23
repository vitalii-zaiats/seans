"""What a caller has to be ready for.

Four, and they mean four different things: the service said no, the request
never got there, what came back is not the shape we know, and the channel is not
one the free tier will open. Only the second is worth a blind retry.
"""


class SweetTvError(Exception):
    """Anything this package raises on purpose."""


class HTTPError(SweetTvError):
    """The service answered, with a status outside 2xx."""

    def __init__(self, status_code: int, url: str, body: str | None = None) -> None:
        super().__init__(f"HTTP {status_code} for {url}")
        self.status_code = status_code
        self.url = url
        self.body = body

    @property
    def is_not_found(self) -> bool:
        return self.status_code == 404

    @property
    def is_server_error(self) -> bool:
        return self.status_code >= 500


class NetworkError(SweetTvError):
    """The request never produced a response: DNS, TLS, socket, or a timeout."""

    def __init__(self, url: str, cause: BaseException) -> None:
        super().__init__(f"network failure for {url}: {cause}")
        self.url = url
        self.cause = cause


class SerializationError(SweetTvError):
    """The response arrived but could not be read as the expected shape."""

    def __init__(self, message: str, cause: BaseException | None = None) -> None:
        super().__init__(message)
        self.cause = cause


class Refused(SweetTvError):
    """The service declined to open the stream.

    The one that matters is `NoAuth`: the channel is not free, and this package
    has no account to offer it. Everything on the free list opens; anything else
    is a channel somebody found another way.
    """

    def __init__(self, result: str | None, url: str) -> None:
        super().__init__(
            {
                "NoAuth": "that channel is not free to watch",
                None: "the service answered with no result",
            }.get(result, f"the service refused: {result}")
        )
        self.result = result
        self.url = url

    @property
    def needs_account(self) -> bool:
        return self.result == "NoAuth"
