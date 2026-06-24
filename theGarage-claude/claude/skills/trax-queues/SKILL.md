---
name: trax-queues
description: >-
  How to publish to and consume from cloud message queues (AWS SQS and GCP
  Pub/Sub, plus Kafka and a local Redis backend) in theGarage using the blessed
  QueueFactory wrapper. Use whenever a task touches a queue — e.g. "enqueue a
  message", "publish an event", "read/drain a queue", "move messages between
  queues", "purge a dead queue", "get the queue a service listens to", "re-queue
  failed messages", "queue depth/count". Always prefer the factory + adapter over
  raw boto3 SQS or google-cloud-pubsub clients.
---

# Cloud message queues in theGarage

Never instantiate a raw `boto3` SQS client/resource or a `google.cloud.pubsub_v1`
publisher/subscriber directly. Always go through `QueueFactory`
(`Trax/Cloud/Services/Queues/Factory.py`), which hands back a `QueueAdapter`
whose API is identical across clouds — code written against it is cloud-agnostic.

All adapters subclass `QueueAdapter` (`Trax/Cloud/Services/Queues/Base.py`), so
the same method names work whatever the backend is:
- AWS SQS: `Trax/Cloud/Providers/AWS/Queues/SqsQueue.py` (`SqsQueueAdapter`)
- GCP Pub/Sub: `Trax/Cloud/Providers/GCP/Queues/GCPQueue.py` (`GCPQueueAdapter`)
- Kafka (AWS only): `Trax/Cloud/Providers/Kafka/Queues/KafkaQueue.py` (`KafkaQueueAdapter`)
- Local Redis (tests / local runs): `Trax/Cloud/Providers/Local/Queues/LocalRedisQueue.py`

The factory picks the backend from the pinned `Config.get_cloud()`. On AWS,
`is_kafka=True` selects the Kafka adapter; otherwise SQS. Running locally routes
to the Redis backend (and requires external-resource test permissions).

## Required bootstrap

Like every cloud access in this repo, initialize config and pin an env + cloud
first. Envs are `INT`/`PROD`, clouds are `AWS`/`GCP`; default to **PROD/AWS**.
Standard preamble:

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer

LoggerInitializer.init('Simon')              # also initializes Config — no separate Config.init()
Config.set_env_and_cloud(*Config.PROD_AWS)   # or Config.INT_AWS / Config.PROD_GCP
```

Run anything that touches a queue through the `garage38ai` env:
`conda run -n garage38ai python <script>`.

## Queue naming & the env prefix

Real queue names are `<ENV>_<FlavorName>`, e.g. `PROD_KEngineHigh`,
`INT_PostRecognitionEngineHigh`. Related queues share the base name with a suffix:
a **dead queue** is `<name>_DEADQ`, plus there are **error** and **TTL** variants.

The factory adds the `<ENV>_` prefix for you when you describe a queue by its
parts. When you already hold a fully-qualified name (env included), pass
`no_env=True` so the prefix isn't added twice — this matters especially on GCP:

```python
queue = QueueFactory.get_queue(queue='PROD_KEngineHigh', no_env=True)
```

## Getting a queue (`QueueFactory`)

Pick the entry point by what you have in hand:

| You have… | Use |
| --------- | --- |
| a full queue name (env included) | `QueueFactory.get_queue(queue='PROD_KEngineHigh', no_env=True)` |
| a service's app/flavor name | `QueueFactory.get_queue(app_flavor_name='KEngineHigh')` — or the swallow-errors variant `get_queue_by_app_flavor_name(...)` returning `None` on miss |
| entity + action convention | `QueueFactory.get_queue(system_or_app_name='Dagger', entity_name='session', action_or_state='processed')` |
| a unified service queue | `QueueFactory.get_queue(system_or_app_name='Dagger', is_unified=True)` |
| every queue a service consumes | `QueueFactory.get_queues(app_flavor_name='KEngineHigh')` → `list[QueueAdapter]` (also tunes long-polling) |
| all queues under a prefix | `QueueFactory.get_queues_by_system_prefix('PostRecognitionEngine')` |

Related-queue flags compose with any of the above: `is_dead=True` (the `_DEADQ`),
`is_error=True`, `is_ttl=True`. Other useful kwargs: `region=`, `project=`,
`suffix=` (freestyle), `is_kafka=True` (AWS Kafka).

```python
from Trax.Cloud.Services.Queues.Factory import QueueFactory

live   = QueueFactory.get_queue(queue='PROD_KEngineHigh', no_env=True)
deadq  = QueueFactory.get_queue(queue='PROD_KEngineHigh', no_env=True, is_dead=True)  # PROD_KEngineHigh_DEADQ

# Existence / creation
QueueFactory.is_queue_exists('KEngineHigh')                       # bool
QueueFactory.create_queue('MyNewService', visibility_timeout=300) # creates queue (+ its _DEADQ)
```

Adapters are cached per name inside the factory, so repeated `get_queue` calls
for the same queue return the same instance — cheap to call.

`QueueFactory.get_queue` raises `QueueNotFoundError`
(`Trax/Cloud/Services/Queues/Exceptions.py`) when the queue doesn't exist; catch
that rather than a bare `Exception`.

## Common operations (the shared `QueueAdapter` API)

```python
# --- Publish ---
queue.enqueue(msg_dict)                       # dict body — formatted via FormatMessage (adds wave/output fields)
queue.enqueue(msg_dict, enforce_wave=False)   # skip wave gating — typical for jobs / manual re-publishing
queue.enqueue(json_string, enforce_wave=False)# pre-serialized str is sent as-is (use to preserve a message verbatim)
queue.send_messages([msg1, msg2, ...])        # AWS SQS batch send (≤10 per call)

# --- Consume ---
messages = queue.dequeue(num_messages=10)     # list of MESSAGE_TUPLE namedtuples (see below); [] when empty
for msg in messages:
    body = msg.json_parsed_message            # the message as a dict
    ...                                        # do work
    queue.delete_message(msg.raw_message)      # ack / remove after successful processing

# --- Visibility / lifecycle ---
queue.return_message_to_queue(msg.raw_message)            # make it visible again immediately (on failure)
queue.update_message_ack_deadline(msg.raw_message, 600)   # extend in-flight/visibility timeout (seconds)

# --- Inspect ---
queue.count()                  # approximate depth (AWS SQS; GCP Pub/Sub doesn't expose this)
queue.name                     # full queue name, e.g. 'PROD_KEngineHigh'
queue.set_wait_timeout_seconds(20)   # long-poll window for subsequent dequeues
```

### The dequeued message object

`dequeue()` returns a list of `MESSAGE_TUPLE` namedtuples
(`Trax/Cloud/Services/Queues/MessageAttributes.py`) with four fields:
- `json_parsed_message` — the message body as a **dict** (what you usually read).
- `raw_message` — the provider adapter message; pass this back to
  `delete_message` / `return_message_to_queue`. Its `.parsed_message` is the dict
  body; AWS also exposes `.receipt_handle` and `.attributes`.
- `dequeue_timestamp` — when it was pulled.
- `context_attributes` — log/telemetry extras (e.g. receive count).

### `enforce_wave`

`enqueue` defaults to `enforce_wave=True`, which routes the dict through
`FormatMessage.update_output_message` (wave gating + standard output fields). When
you're a job publishing or re-publishing messages yourself — as in
`LightningRecalcJob` and `QueueUtils` — pass `enforce_wave=False`. To move a
message **verbatim** (no reformatting), `json.dumps` it yourself and enqueue the
string.

## Cloud-specific notes

The interface is shared, but a few details differ:
- **`count()`** is meaningful on AWS SQS; GCP Pub/Sub returns `None`. For GCP
  depth use the monitoring helpers (`get_unacked_messages_num`,
  `get_oldest_message_age`). On AWS, `get_visible_messages_num()` /
  `get_inflight_messages_num()` give visible vs in-flight counts.
- **`enqueue`** on GCP accepts `is_dead_queue=True` to publish to the topic's
  dead-letter; AWS reaches the dead queue by getting it via `is_dead=True`.
- **Long ack deadlines:** GCP caps a single ack-deadline modification at 600s and
  spins a background extender thread for longer leases; SQS sets visibility
  timeout directly.
- **Kafka** is AWS-only and selected with `is_kafka=True`.

Prefer the shared `QueueAdapter` methods so code stays portable across clouds.

## Bulk queue operations — don't hand-roll a drain loop

For moving / copying / removing / deduping messages in bulk, or cleaning a dead
queue, there's already a job: **`QueueUtils`**
(`Trax/Apps/Jobs/QueueJobs/QueueUtils.py`), with tools `remove`, `move_all`,
`move_unique`, `deadq_cleaner`, `copy`, `statistic`. It supports filters (project,
event, region), dry-run, batch size, and emits an Excel summary. Launch it as a
job (see `LightningRecalcJob._purge_recalc_dead_queue` for an `execute_job`
example) rather than re-implementing a poll/move loop. See the `trax-architecture`
skill for how queue-based services consume these queues end-to-end.
