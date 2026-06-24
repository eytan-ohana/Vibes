# BigQuery

Source: `Trax/Cloud/Services/Connector/Factory.py` (`BigQueryFactory`). It returns
a cross-cloud connector that runs queries and converts to a pandas DataFrame.
Project-name constants are in `Trax/Cloud/Providers/GCP/Connector/Constants.py`
(`DEFAULT_PROJECT_NAME = "trax-retail"`, plus `BQ_PROJECT_NAMES`).

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer
from Trax.Cloud.Services.Connector.Factory import BigQueryFactory
from Trax.Cloud.Providers.GCP.Connector.Constants import DEFAULT_PROJECT_NAME

LoggerInitializer.init('Simon')              # inits Config too; then pin env/cloud
Config.set_env_and_cloud(*Config.PROD_AWS)

connector = BigQueryFactory().get_bigquery_client(DEFAULT_PROJECT_NAME)
df = connector.run_query("SELECT * FROM raw.some_table LIMIT 100").to_dataframe()
```

- `get_bigquery_client(gcp_project=DEFAULT_PROJECT_NAME)` — the query client.
- `get_dataset(dataset, create_if_not_exists=False, gcp_project=...)` — dataset handle.
- Dataset/table name constants: `BQDatasetNames` (`RAW`, `SANDBOX`),
  `BQTableNames` in the same Constants module.
