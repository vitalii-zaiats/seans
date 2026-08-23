# proto

The same API, described for gRPC.

`contracts/openapi.json` is the HTTP half of this, and it *is* generated —
`uv run openapi` dumps it straight out of the running app, and `uv run openapi
--check` fails when it has drifted. These files are not: they were written
against the Python schemas and checked against that same OpenAPI (35 HTTP
operations, 33 RPCs, plus `/health` and the image proxy, both deliberately not
RPCs). So the two halves are not equally trustworthy — the JSON cannot be wrong
about the app, and these files can. Where any of this disagrees with the Python,
the Python is what is actually running.

Nothing here is compiled. There is no generated code in the tree and no plugin
wired into the build — these files are the description, and a `protoc` run is
somebody's next decision, not a thing that already happened.

## One file per module

`installs`, `accounts`, `remote`, `stats`, `tv`, `catalogue` — the same folders
as `apps/api/src/api/modules/`, for the same reason. A service that grew out of
one module stays in that module's file, and no file imports another.

That last part is deliberate rather than incidental. Two files both describe a
page envelope of `total`/`limit`/`offset`, and two describe a platform. Sharing
them would be three fields saved and a coupling bought: the rule in `CLAUDE.md`
is that vocabularies are spelled out independently so a rename shows up as a
mismatch at the seam instead of leaking through to the wire. It reads the same
way here.

`proxy` has no file. `GET /proxy/{path}` streams somebody else's image bytes
back with the content type they came with — a CDN passthrough, where the useful
things are range requests and cache headers. gRPC has neither, and a
`bytes` field is not an improvement over what it already does. It stays HTTP.

## Conventions

**Nullability is explicit.** Wherever the JSON contract can send `null` and
means something by it, the field is `optional`. There are a lot of these and
they are load-bearing: a null `token` means "the one you already hold still
works", a null `vendor` means "not android, so there is no installer to name",
a null `change` means "there was nothing to compare against". A default value
would say something different in every one of those cases.

**Enums for closed vocabularies, with the raw string kept.** `ContentType` can
be null in JSON while `type_raw` still carries what upstream said, so a client
can render a section this API has not learned yet rather than dropping the row.
The proto keeps both, for the same reason. Adding a value to an enum is
wire-compatible, which is the same property the database columns were chosen
for — `Enum(..., native_enum=False)` so that adding `ios` needs no `ALTER TYPE`.

**Timestamps are `google.protobuf.Timestamp`.** Days are strings: `stats` and
`tv` both carry a calendar day with no time and no zone, and `2026-08-23` says
that where a Timestamp at midnight would invite somebody to convert it.

**Uninterpreted payloads are `google.protobuf.Struct`.** A remote-control
command's `params` and a device's reported `state` are app data the server
deliberately does not read — the one place `CLAUDE.md` allows a loose type, and
`Struct` is the honest spelling of it. The byte ceilings the HTTP layer enforces
(4 KiB and 16 KiB) are not expressible here and remain the server's job.

## Authentication

The bearer token travels in metadata, not in a field:

```
authorization: Bearer <token>
```

Same token as HTTP, from the same `POST /api/v1/auth/login`. Nothing in these files
takes a token as an argument, because a credential in a request body is a
credential in every log that ever writes a request body.

## Refusals

`apps/api/src/api/errors.py` exists so that a service can refuse without
importing a transport, and `main.py` has the table that turns a refusal into an
HTTP status. This is the other half of that table — the same errors, the codes
gRPC calls them:

| `api.errors` | HTTP | gRPC |
|---|---|---|
| `Invalid` | 400 | `INVALID_ARGUMENT` |
| `Unauthorized` | 401 | `UNAUTHENTICATED` |
| `Forbidden` | 403 | `PERMISSION_DENIED` |
| `NotFound` | 404 | `NOT_FOUND` |
| `Conflict` | 409 | `ALREADY_EXISTS` |
| `Upstream` | 502 | `UNAVAILABLE` |

`Conflict` is `ALREADY_EXISTS` rather than `ABORTED` because every place that
raises it means a unique constraint said no — a taken email, a second sign-up
racing the first. If it ever comes to mean "retry the transaction", that is when
it becomes `ABORTED`, and the two should not be merged before then.

## Health

There is no `Health` service here. `grpc.health.v1.Health` is the standard one
and `GET /health` is its counterpart; a hand-rolled third spelling would only be
a thing to keep in step.

## Streaming

Three RPCs stream, and they are the reason this is worth describing at all.
`WatchCommands` and `WatchDeviceState` are SSE today, and the two notes in
`CLAUDE.md` about that — the browser's `EventSource` being unable to send an
`Authorization` header, and `ASGITransport` never returning from an endless
`client.stream()` — are both artefacts of SSE rather than facts about the
problem. Neither survives the move: metadata carries the token, and a streaming
stub is something a test can drive directly.

What does survive is the reason there are no resumption ids: replaying a command
is exactly wrong, because an instruction is about *now* and a television that
missed "play" while its Wi-Fi blinked must not act on it a minute later.
