## 0.1.0

- `Remote` — list boxes, send commands, watch state.
- `Receiver` — receive commands, report state, `serve` a handler map.
- `RemoteChannel` / `ReceiverChannel` seams, with API implementations over
  HTTP and server-sent events.
- A server-sent-event parser, and reconnection that lets go when told to.
