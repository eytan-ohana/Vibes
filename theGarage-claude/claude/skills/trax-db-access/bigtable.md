# Bigtable

Source: `Trax/Cloud/Providers/GCP/Connector/DataBase.py` (`ServicesInternalDatabase`).
Always use namespace constants from
`Trax/Cloud/Providers/GCP/Connector/Constants.py` (`BigTableNamespaces`) —
never raw strings. 

Rows are keyed by a namespace + an `OrderedDict` of entity fields ("nested" key).
Key/value helpers: `get_nested_value` / `set_nested_value`,
`get_nested_values`, `get_values_with_prefix`, `get_value`, `delete_nested_row`.

```python
from collections import OrderedDict

from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer
from Trax.Cloud.Providers.GCP.Connector.DataBase import ServicesInternalDatabase
from Trax.Cloud.Providers.GCP.Connector.Constants import BigTableNamespaces

LoggerInitializer.init('Simon')              # inits Config too; then pin env/cloud
Config.set_env_and_cloud(*Config.PROD_AWS)

db = ServicesInternalDatabase()

entity_map = OrderedDict({'project': 'walmart_us', 'scene_uid': 'abc', 'image_uid': 'def'})

# read
value = db.get_nested_value(BigTableNamespaces.ProbeDetections, entity_map)

# write
db.set_nested_value(BigTableNamespaces.ProbeDetections, entity_map, values, column_family)
```

Notes:
- `column_family` defaults to `ColumnFamilyNames.SHORT_TERM` (others: `BASE`,
  `LONG_TERM`, `PERSISTENT`) — imported from the same module.
- `mode` defaults to `AccessModes.WRITE`; that's also what you want when reading
  immediately after a write (read-after-write consistency).
- Prefix scans: `get_values_with_prefix(...)` / `get_nested_keys(...)`.
