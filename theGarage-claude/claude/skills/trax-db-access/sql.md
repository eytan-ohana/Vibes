# SQL (MySQL via the ORM)

Per-project MySQL databases are accessed through the SQLAlchemy ORM layer — not
a raw connector. The session is created per `project_name`; the wrapper resolves
the right RDS host and credentials from the project's Mongo record.

Source: `Trax/Data/Orm/OrmCore.py` (sync `OrmSession`),
`Trax/Data/Orm/AsyncSessionMaker.py` (async `AsyncProjectsSessionMaker`).
ORM model classes live under `Trax/Data/Orm/` (e.g. `Scene`, `Probe` in
`Trax.Data.Orm.OrmProbeDataObjects`).

## Sync — `OrmSession`

Use `OrmSession` as a context manager — `__exit__` disconnects the session for
you (commits/closes on a writable session). It proxies a SQLAlchemy `Session`,
so `.query(...)` / `.execute(...)` work directly. Read-only by default; pass
`writable=True` to write.

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer
from Trax.Data.Orm.OrmCore import OrmSession
from Trax.Data.Orm.OrmProbeDataObjects import Scene, Probe   # import the models you need

LoggerInitializer.init('Simon')              # inits Config too; then pin env/cloud
Config.set_env_and_cloud(*Config.PROD_AWS)

with OrmSession('walmart_us') as session:
    scenes = (session.query(Scene)
              .filter(Scene.number_of_probes >= 10)
              .order_by(Scene.pk.desc())
              .limit(100))
    scene_pks = [s.pk for s in scenes]
```

### Raw SQL

Use `sqlalchemy.text` with **bound parameters** for dynamic values — never
f-string / `%`-format user input into the query (SQL injection + breaks quoting).

```python
from sqlalchemy import text

min_probes = 10
scene_uids = ['abc', 'def', 'ghi']

with OrmSession('walmart_us') as session:
    rows = session.execute(
        text("""
            SELECT pk, number_of_probes
            FROM scene
            WHERE number_of_probes >= :min_probes
              AND scene_uid IN :scene_uids
            ORDER BY pk DESC
        """).bindparams(expanding=True),   # expanding=True lets a list bind to IN (...)
        {'min_probes': min_probes, 'scene_uids': scene_uids},
    ).fetchall()
    for row in rows:
        print(row.pk, row.number_of_probes)
```

For a single scalar value, `session.execute(text("... :x"), {'x': val}).scalar()`.

### Writes

```python
with OrmSession('walmart_us', writable=True, autocommit=False) as session:
    session.execute(
        text("UPDATE scene SET number_of_probes = :n WHERE pk = :pk"),
        {'n': 5, 'pk': 123},
    )
    # ... or mutate ORM objects ...
# __exit__ commits (or rolls back on error) and closes
```

## Async — `AsyncProjectsSessionMaker`

Use when the calling code is async. It's an async context manager yielding an
`AsyncSession`; on `writable=True` it commits on success / rolls back on error.
Send each query in its own session (connections return to the pool on close).

```python
from Trax.Data.Orm.AsyncSessionMaker import AsyncProjectsSessionMaker
from sqlalchemy import select, text
from Trax.Data.Orm.OrmProbeDataObjects import Scene

# ORM query
async with AsyncProjectsSessionMaker('walmart_us') as session:
    result = await session.execute(select(Scene).limit(100))
    scenes = result.scalars().all()

# raw SQL with bound params (same injection rule as sync)
async with AsyncProjectsSessionMaker('walmart_us') as session:
    result = await session.execute(
        text("SELECT pk FROM scene WHERE number_of_probes >= :min_probes"),
        {'min_probes': 10},
    )
    scene_pks = [row.pk for row in result.fetchall()]
```
