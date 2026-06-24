# Redis

Source: `Trax/Cloud/Services/Cache/Factory.py` (`CacheFactory`),
`Trax/Cloud/Services/Cache/Async/Factory.py` (`AsyncCacheFactory`). The factory
resolves the right Redis host per cloud/env (and enables SSL on AWS prod), so
never construct `redis.Redis` directly.

## Sync — `CacheFactory`

Two entry points:
- `get_redis_conn(host=None, cloud=None, env=None)` — a raw `redis.Redis` client
  (full redis command API: `get`/`set`/`hset`/…).
- `get_cache_db(default_cache_time=...)` — a higher-level `CacheRedisBase` with
  `insert_to_cache` / cache-time semantics.

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer
from Trax.Cloud.Services.Cache.Factory import CacheFactory

LoggerInitializer.init('Simon')              # inits Config too; then pin env/cloud
Config.set_env_and_cloud(*Config.PROD_AWS)

r = CacheFactory.get_redis_conn()
r.set('my_key', 'value')
val = r.get('my_key')

# or the cache wrapper with TTL semantics
cache = CacheFactory.get_cache_db()
cache.insert_to_cache('my_key', 1)
```

Target a specific deployment: `CacheFactory.get_redis_conn(cloud=Config.AWS, env=Config.PROD)`.

## Async — `AsyncCacheFactory`

```python
from Trax.Cloud.Services.Cache.Async.Factory import AsyncCacheFactory

r = AsyncCacheFactory.get_redis_conn()   # redis.asyncio client
await r.set('my_key', 'value')
val = await r.get('my_key')
```
