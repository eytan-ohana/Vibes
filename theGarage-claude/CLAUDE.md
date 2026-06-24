# theGarage — project guide for Claude

The main Python package is `Trax/`. Everything imports as `Trax.*` (e.g.
`from Trax.DB.Mongo.Connector import MongoConnector`). Source of truth for layout
is `Trax/` — top-level areas: `Algo`, `Analytics`, `Apps`, `Aws`, `Cloud`,
`Clients`, `DB`, `Data`, `Deployment`, `DevOps`, `K8S`, `Tools`, `Utils`.

## Architecture: three kinds of deployable units

The repo is split along three deployment types. Each has a **deployment file**
(scaling/resources/scheduling + `executable_path`) separate from its **app code**.
See the **`trax-architecture` skill** for the full anatomy of each.

| Type | Deployment file | App code                     | Entry contract |
| ---- | --------------- |------------------------------| -------------- |
| Queue-based service | `Trax/Deployment/Services/<Name>.py` (`K8SDeployment` + …) | `Trax/Apps/Services/<Name>/` | `Server.py` registers a handler; handler's `_process_message` does the work |
| FastAPI / Knative API | `Trax/Deployment/Services/<Name>.py` (`KnativeDeployment` or `SimpleAPIDeployment`) | `Trax/Apps/APIs/<Name>/` or `Trax/Apps/Services/<Name>/` | `Server.py` builds a FastAPI app / controllers |
| Simon job (cron) | `Trax/Deployment/Jobs/<Name>.py` (`JobBaseDeployment`) | `Trax/Apps/Jobs/…/<Name>.py` | module-level `run(*args)` returning an exit code |

The deployment file's `executable_path()` points at the app-code entrypoint — use
it to jump from a deployment to the code it runs (and vice-versa). Jobs are all
launched via `Trax/Apps/Core/Jobs/Wrapper.py`, which calls your module's `run()`.

### RTFM — Service and API overview docs (supplementary)

`~/dev/RTFM` (also at `https://github.com/trax-retail/RTFM`) contains high-level
documentation about many of the services in theGarage — purpose, inputs/outputs,
key concepts, and inter-service relationships.

**Use it as a starting point** when you need to understand what a service does
before diving into the code. **Do not treat it as authoritative** — docs may be
stale or incomplete. Always verify against the actual code in `Trax/`.

## Running code & tests

Always run Python and tests through the `garage38ai` conda env — do **not** rely
on an activated shell:

```bash
conda run -n garage38ai python <script.py>
conda run -n garage38ai python -m pytest <path/to/test.py>
```

- Tests use the `Trax.pytest_garage_plugin` pytest plugin (see `conftest.py`).
- pytest config is in `setup.cfg`. `Trax/Miscellaneous/`, `API`, `.dvc`, `data`
  are ignored — don't add tests or look for runnable code there.
- `Trax/Miscellaneous/` is personal/scratch space; treat it as non-authoritative
  examples, never as the canonical way to do something.

## Accessing data stores (Mongo / SQL / BigQuery / Bigtable / Redis)

There are blessed wrapper modules for every data store — never hand-roll a
`pymongo.MongoClient`, `redis.Redis`, raw `create_engine`, etc. Use the
**`trax-db-access` skill** (`.claude/skills/trax-db-access/`), which has a
per-store reference with the correct imports and real query examples. Quick map:

| Store    | Sync                          | Async                              |
| -------- | ----------------------------- | ---------------------------------- |
| Mongo    | `MongoConnector`              | `AsyncMongoConnector`              |
| SQL      | `OrmSession`                  | `AsyncProjectsSessionMaker`        |
| BigQuery | `BigQueryFactory`             | —                                  |
| Bigtable | `ServicesInternalDatabase`    | —                                  |
| Redis    | `CacheFactory`                | `AsyncCacheFactory`                |

### Bootstrap (required before any data-store access)

Every script that touches a data store must initialize config **and** pin an
env + cloud first. We work with envs `INT`/`PROD` and clouds `AWS`/`GCP`;
default to **PROD/AWS** unless there's a reason not to. Standard preamble:

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer

LoggerInitializer.init('Simon')              # also initializes Config — no separate Config.init()
Config.set_env_and_cloud(*Config.PROD_AWS)   # or Config.INT_AWS / Config.PROD_GCP
```

(`Config.PROD_AWS` is the `(PROD, AWS)` tuple.) To target another deployment,
either swap the tuple above or pass `override_env_cloud=(env, cloud)` to an
individual connector.

## Cloud blob storage (S3 / GCS)

For object storage in buckets — uploading/reading files, listing a prefix,
copying between buckets, presigned URLs — never instantiate a raw `boto3` S3
client or `google.cloud.storage.Client`. Use `StorageFactory`
(`Trax/Cloud/Services/Storage/Factory.py`), which returns a cloud-agnostic
connector with an identical API across AWS and GCP. See the **`trax-storage`
skill** (`.claude/skills/trax-storage/`) for the factory entry points, the
relative-path model, and the shared read/write/list/copy/delete operations.
The same bootstrap preamble above applies.

## Message queues (AWS SQS / GCP Pub/Sub / Kafka)

For publishing to and consuming from queues — enqueue/dequeue, acking, dead-queue
handling, queue depth, bulk moves — never instantiate a raw `boto3` SQS client or
`google.cloud.pubsub_v1` publisher/subscriber. Use `QueueFactory`
(`Trax/Cloud/Services/Queues/Factory.py`), which returns a cloud-agnostic
`QueueAdapter` with an identical API across AWS, GCP, Kafka, and a local Redis
backend. See the **`trax-queues` skill** (`.claude/skills/trax-queues/`) for the
factory entry points (by full name, app/flavor name, or entity+action
convention), the `<ENV>_<FlavorName>` naming + `no_env` rule, the shared
`enqueue`/`dequeue`/`delete_message` operations, the dequeued message tuple, and
the `QueueUtils` job for bulk move/copy/remove/dead-queue cleaning. The same
bootstrap preamble above applies.
