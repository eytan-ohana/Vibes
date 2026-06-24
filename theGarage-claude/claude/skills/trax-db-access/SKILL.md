---
name: trax-db-access
description: >-
  How to connect to and query theGarage's data stores using the blessed wrapper
  modules. Use whenever a task involves reading/writing MongoDB, SQL (MySQL via
  the ORM), BigQuery, Bigtable, or Redis in this repo — e.g. "query mongo",
  "fetch from bigquery", "read from bigtable", "look up a project in the db",
  "cache this in redis", or running a script/test that touches these stores.
  Always prefer these wrappers over raw pymongo/redis/sqlalchemy/bigquery clients.
---

# Accessing data stores in theGarage

Never instantiate a raw client (`pymongo.MongoClient`, `redis.Redis`,
`create_engine`, `google.cloud.bigquery.Client`, …). Always use the wrappers
below.

## Required bootstrap

Before touching any store you must initialize config **and** pin an env + cloud.
Envs are `INT`/`PROD`, clouds are `AWS`/`GCP`; default to **PROD/AWS**. Standard
preamble for any script:

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer

LoggerInitializer.init('Simon')              # also initializes Config — no separate Config.init()
Config.set_env_and_cloud(*Config.PROD_AWS)   # or Config.INT_AWS / Config.PROD_GCP
```

`Config.PROD_AWS` is the `(PROD, AWS)` tuple. To hit another deployment without
changing the global, pass `override_env_cloud=(env, cloud)` to a connector.

Pick the store and read its reference file for imports + real query examples:

| Store    | Use                                                   | Reference            |
| -------- | ----------------------------------------------------- | -------------------- |
| Mongo    | `MongoConnector` / `AsyncMongoConnector`              | [mongo.md](mongo.md) |
| SQL      | `OrmSession` / `AsyncProjectsSessionMaker`            | [sql.md](sql.md)     |
| BigQuery | `BigQueryFactory`                                     | [bigquery.md](bigquery.md) |
| Bigtable | `ServicesInternalDatabase` + `BigTableNamespaces`     | [bigtable.md](bigtable.md) |
| Redis    | `CacheFactory` / `AsyncCacheFactory`                  | [redis.md](redis.md) |

Run anything that uses these through the `garage38ai` env:
`conda run -n garage38ai python <script>`.

Notes that apply across stores:
- Most wrappers are cloud/env-aware via `Config`; many accept
  `override_env_cloud=(env, cloud)` to target a specific environment.
- Sync connectors are context managers (`with ... as conn:`); async ones use
  `async with`.
