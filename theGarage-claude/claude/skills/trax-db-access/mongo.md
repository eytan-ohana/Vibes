# MongoDB

Source: `Trax/DB/Mongo/Connector.py` (sync), `Trax/DB/Mongo/AsyncConnector.py` (async).

**Database names** — use `DatabaseNames` from `Trax/DB/Mongo/ConnectorBase.py`
instead of hardcoded strings (`DatabaseNames.SMART`, `.DATA`, `.VOTING`,
`.ONLINE`, `.REPOSITORY`, `.WAREHOUSE`, `.PS_DATA`, …). The connector also
re-exposes them (`MongoConnector.SMART` works), but `DatabaseNames` is the
canonical source.

**Collection names** — defined in `Trax/DB/Mongo/Schema.py`, with one Enum class
per database, named after that DB: `SmartDB`, `Data`, `VotingDB`, `WarehouseDB`,
`Online`, `Repository` (the `Repo` DB), `PSData`, `PSTool`, `TraxApi`,
`IotDB`, etc. So a collection in the `Smart` DB → `SmartDB.PROJECTS_PROJECT`, a
collection in the `Data` DB → `Data.ALGO_CONFIG`. Not every collection has a
constant — if one's missing, a hardcoded string is acceptable (consider adding
the constant).

`.db` is a real `pymongo` database, so use the normal pymongo query API on it.

## Sync — `MongoConnector`

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer
from Trax.DB.Mongo.Connector import MongoConnector
from Trax.DB.Mongo.ConnectorBase import DatabaseNames
from Trax.DB.Mongo.Schema import SmartDB

LoggerInitializer.init('Simon')              # inits Config too; then pin env/cloud
Config.set_env_and_cloud(*Config.PROD_AWS)

with MongoConnector(DatabaseNames.SMART) as connector:
    doc = connector.db[SmartDB.PROJECTS_PROJECT].find_one({'project_name': 'walmart_us'})
    cursor = connector.db[SmartDB.PROJECTS_PROJECT].find(
        {'rds_name': {'$exists': True}},
        projection={'rds_name': 1, 'project_name': 1},
    )
```

Target a specific environment with `override_env_cloud`:

```python
with MongoConnector(DatabaseNames.SMART, override_env_cloud=(Config.PROD, Config.AWS)) as connector:
    ...
```

Pass `close_connection_on_exit=True` for one-off scripts so the pooled client is
torn down on exit instead of kept process-persistent.

## Async — `AsyncMongoConnector`

Must be used with `async with` (raw `with` raises). Same `.db` query API.

```python
from Trax.DB.Mongo.AsyncConnector import AsyncMongoConnector
from Trax.DB.Mongo.ConnectorBase import DatabaseNames
from Trax.DB.Mongo.Schema import SmartDB

async with AsyncMongoConnector(DatabaseNames.SMART) as connector:
    doc = await connector.db[SmartDB.PROJECTS_PROJECT].find_one({'project_name': 'walmart_us'})
```
