"""Images from a host that will not let a browser have them.

The catalogue's posters answer with no `access-control-allow-origin` at all. A
browser still fetches them — the network panel says 200 and shows the bytes —
and then Flutter cannot paint one: the pixels taint the canvas, and a tainted
canvas cannot be uploaded as a texture. So the images appear to load and nothing
is drawn, which is the most confusing shape this failure could possibly take.

Hence this. It is the same fix as the catalogue module's, applied to bytes
instead of JSON: our own origin, so the browser is allowed to use what it got.

sweet.tv's channel icons need none of this — they answer `*` already, and are
left pointing straight at their own host. Relaying bytes nobody has a problem
with would be paying for nothing.
"""
