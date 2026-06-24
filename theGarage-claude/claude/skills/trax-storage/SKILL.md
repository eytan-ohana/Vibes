---
name: trax-storage
description: >-
  How to read/write objects in cloud blob storage (AWS S3 and GCP Cloud Storage)
  in theGarage using the blessed StorageFactory wrapper. Use whenever a task
  touches a bucket — e.g. "upload a file to S3", "read this object from GCS",
  "download from a gs:// or s3:// url", "list files under a prefix", "delete a
  blob", "generate a presigned/temporary download URL", "copy between buckets".
  Always prefer the factory + connector over raw boto3 / google-cloud-storage clients.
---

# Cloud blob storage in theGarage

Never instantiate a raw `boto3` S3 client/resource or a `google.cloud.storage.Client`
directly. Always go through `StorageFactory`
(`Trax/Cloud/Services/Storage/Factory.py`), which hands back a connector whose
API is identical across AWS and GCP — code written against it is cloud-agnostic.

Both backends subclass `BaseConnector` (`Trax/Cloud/Services/Storage/Base.py`),
so the same method names work whether the bucket lives on S3 or GCS:
- AWS: `Trax/Cloud/Providers/AWS/Storage/StorageConnector.py` (`AwsStorageConnector`)
- GCP: `Trax/Cloud/Providers/GCP/Storage/Connector.py` (`GcpStorageConnector`)

## Required bootstrap

Like every data-store access in this repo, initialize config and pin an
env + cloud first. Envs are `INT`/`PROD`, clouds are `AWS`/`GCP`; default to
**PROD/AWS**. Standard preamble:

```python
from Trax.Utils.Conf.Configuration import Config
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer

LoggerInitializer.init('Simon')              # also initializes Config — no separate Config.init()
Config.set_env_and_cloud(*Config.PROD_AWS)   # or Config.INT_AWS / Config.PROD_GCP
```

Run anything that touches a bucket through the `garage38ai` env:
`conda run -n garage38ai python <script>`.

## Getting a connector

`StorageFactory` has four entry points — pick by what you have in hand:

| You have… | Use | Notes |
| --------- | --- | ----- |
| a bucket name | `StorageFactory.get_connector(bucket, cloud=None, region=None, credentials=None)` | `cloud` defaults to the pinned `Config.get_cloud()`; pass `Config.AWS` / `Config.GCP` to override |
| a `s3://…` or `gs://…` URL | `StorageFactory.from_url(url)` | scheme picks the cloud; returns a connector for that bucket |
| an `https://…` storage URL | `StorageFactory.get_connector_from_https_link(url)` | handles `storage.googleapis.com` and `s3.amazonaws.com` (path- or vhost-style) |
| a local/temp scratch bucket | `StorageFactory.get_temp_connector(bucket)` | backed by `LocalStorageConnector` (filesystem) — handy in tests |

```python
from Trax.Cloud.Services.Storage.Factory import StorageFactory

# By bucket name on the pinned cloud (PROD/AWS here):
conn = StorageFactory.get_connector('my-bucket')

# Force a cloud regardless of what's pinned:
gcs = StorageFactory.get_connector('my-gcs-bucket', cloud=Config.GCP)

# From a fully-qualified URL — cloud inferred from the scheme:
conn = StorageFactory.from_url('s3://my-bucket')          # or 'gs://my-bucket'
path = StorageFactory.get_path_from_https_link(
    'https://storage.googleapis.com/my-bucket/reports/2026/q2.json')
```

## Path model

Every method takes paths **relative to the bucket** (no bucket name, no
`s3://`/`gs://` prefix). Many methods split the object key into
`(file_path, file_name)` which the connector joins for you — pass the directory
as `file_path` and the file as `file_name`, or pass the whole key as `file_path`
and `file_name=None`. Leading `/` is tolerated and stripped.

```python
conn.save_string('reports/2026', 'q2.json', '{"ok": true}')   # -> reports/2026/q2.json
data = conn.read_string('reports/2026/q2.json')               # whole key, file_name omitted
```

## Common operations

The names below are the shared interface — same call on S3 and GCS.

```python
# --- Write ---
conn.save_string(file_path, file_name, content, **kwargs)      # bytes/str body
conn.save_file(file_path, file_name, local_file_to_upload)     # upload a local file (sets Content-Type)
conn.save_file_stream(file_path, file_name, file_obj)          # upload an open file/stream
conn.upload_folder(local_directory, key)                        # recursively upload a dir

# --- Read ---
body = conn.read_string('path/to/object')                       # returns bytes
with open('/tmp/out.bin', 'wb+') as f:
    conn.download_file('path/to/object', f)                     # streams into the file obj
for chunk in conn.iter_download_filestream('path/to/object'):   # chunked (default 1MB)
    ...
conn.download_directory(remote_prefix, '/tmp/dest_dir')         # pull a whole prefix locally

# --- List / inspect ---
keys = conn.get_files_list('some/prefix')                       # list keys under a prefix
keys_with_dates = conn.get_files_list_with_update_date('some/prefix')
latest = conn.get_latest_file_in_dir('some/prefix', '.json')
exists = conn.exists('path/to/object')                          # bool
md = conn.get_metadata('path/to/object')
ts = conn.get_file_last_modification_time(file_path, file_name)
chk = conn.get_file_checksum('path/to/object')                  # {'ETag': ...} on AWS, {'md5': ...} on GCP

# --- Copy / delete ---
conn.copy_file(source_bucket_name, source_path, destination_path)   # into THIS connector's bucket
conn.copy_folder(source_bucket_name, source_prefix, dest_prefix)
conn.remove_file(file_path, file_name)
conn.remove_folder('some/prefix')

# --- Presigned URL (temporary, expires after `expiration` seconds) ---
url = conn.get_temporary_download_url('path/to/object', expiration=3600)
```

`disable_cache=True` on the save methods sets a `no-cache` header. To set a
content type or custom metadata, pass `metadata={'Content-Type': 'application/json', ...}`.

## Cloud-specific notes

The interface is shared, but a few details differ:
- **Checksums:** AWS returns `{'ETag': ...}`, GCP returns `{'md5': ...}`.
- **`get_temporary_download_url` kwargs:** AWS honors `response_content_type` and
  `response_content_disposition`; GCP ignores them.
- **AWS-only helpers:** `upload_file(local_file_path, bucket, key, metadata=None)`
  (note: takes an explicit bucket/key, unlike the relative-path methods).
- **GCP-only helpers:** `save_large_file_stream(...)` (smaller chunk size for big
  uploads), `get_file_creation_time(file_path)`.

Prefer the shared `BaseConnector` methods so code stays portable across clouds;
reach for a cloud-specific method only when you actually need it.
