# Queue-based services

Long-running workers that consume messages off queues. Scale on queue depth.

## Layout

- **Deployment:** `Trax/Deployment/Services/<Name>.py` — subclass of
  `K8SDeployment` (usually `+ DockerGradualDeployment + Python38Deployment`, and
  `+ MultiProcessUpstartService` for multi-process servers). Defines
  `executable_path()` → the server, plus `memory()`/`cpu()`/`max_replicas()`/
  `spares()`/`input_queues()`/`system_flavor_names`. Example:
  `Trax/Deployment/Services/FlexEngine.py`, `…/KEngine.py`.
- **App code:** `Trax/Apps/Services/<Name>/` — the `Server.py` named by
  `executable_path()`, plus one or more **handler** classes. Handler file/class
  names have **no convention** — don't go looking for `Handler.py`; find them via
  the server's `register_handlers` (below).

## How a message reaches your code

Two pieces cooperate. The **server** (your code) registers handlers; the shared
**controller** (`Trax/Apps/Core/QueueServer/Controller.py`) runs the message loop
and picks which registered handler actually handles each message.

```
Trax/Deployment/Services/<Name>.py   executable_path()
        │
        ▼
Trax/Apps/Services/<Name>/Server.py            class <Name>Server(QueueServerBase)
        │   register_handlers():  HandlersContainer().add_handler(<SomeHandler>())
        │                         ── attaches handler instance(s) to the singleton
        ▼
HandlersContainer (singleton, Trax/Apps/Core/QueueServer/Handlers.py)
        ▲
        │   message loop iterates ALL registered handlers
QueueServerController._process_message → _perform_handlers   (Controller.py)
        │   for handler in HandlersContainer(): handler.perform(self, json_message, delete_delegate)
        ▼
HandlerBase.perform   (Handlers.py)
        │   if self._validate_message(json_message, delete_delegate):   ← handler self-selects here
        │       self._process_message(json_message, parent_controller, timer, delete_delegate)
        ▼
    your <SomeHandler>._process_message(...)   ← the real per-message work
```

Key points:
- **Registration, not naming, wires a handler in.** `register_handlers` in the
  server adds handler instances to the `HandlersContainer` singleton. The class
  can be named anything.
- **Handler selection is by `_validate_message`, not by the controller.** The
  controller loops over *every* registered handler and calls `perform`; each
  handler's `_validate_message(json_message, …)` returns truthy only for messages
  it should handle, and only then does its `_process_message` run. (Some services
  register one handler that handles everything; others register several that each
  validate a subset / entity type via `handled_entity_type`.)
- A handler also controls its ack-deadline via `get_processing_duration_timeout`.

Base classes (both in `Trax/Apps/Core/QueueServer/`):
- `QueueServerBase` — `Server.py`
- `HandlerBase` — `Handlers.py` (abstract `_validate_message` + `_process_message`;
  concrete `perform` is the validate→process gate shown above)

## Where the work lives

`_process_message` is the entrypoint for handling one message. In bigger services
it's itself a dispatcher (e.g. `KEngineMainHandler._process_message` in
`Trax/Apps/Services/KEngine/Handlers/MainHandler.py`) that routes to inner
handlers; in small ones it's the work directly.

**To find what a service does:** open its `Server.py`, read `register_handlers`
to see which handler class(es) it attaches, then read each handler's
`_validate_message` (what it accepts) and `_process_message` (what it does).
**To add behavior:** add/extend a handler class and register it in
`register_handlers`.
