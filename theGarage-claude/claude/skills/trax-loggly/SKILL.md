---
name: trax-loggly
description: >-
  How to query theGarage's Loggly logs programmatically (search + iterate the
  Loggly API with the org's credentials). Use whenever a task involves reading
  application logs from Loggly — e.g. "how often does service X do Y", "count
  errors for app Z last week", "find WaveMaker/Simon log lines", "estimate call
  frequency from logs", or building a log-based report. Loggly retains ~1 month.
---

# Querying Loggly in theGarage

Loggly is the central log store. Query it via its HTTP API using the org's
`ps_loggly` bearer token (resolved through the blessed `CredentialsFactory`).
Canonical production example: `Trax/Apps/Jobs/ProfessionalServicesReports/Global/PSLogglySimonReport.py`.

## Bootstrap + auth

Run through the `garage38ai` env. Standard preamble (initializes Config; the
credential lookup needs it):

```python
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer
from Trax.Utils.Conf.Configuration import Config
LoggerInitializer.init('Simon')
Config.set_env_and_cloud(*Config.PROD_AWS)

from Trax.Cloud.Services.Connector.Credentials import CredentialsFactory
key = CredentialsFactory.get_secret('integrations', 'ps_loggly')['key']
headers = {'Authorization': f'bearer {key}'}
```

## Endpoints

- Base: `https://trax.loggly.com/`
- **Iterate** (bulk, paginated): `https://trax.loggly.com/apiv2/events/iterate/`
- Search UI (for humans / building links): `https://trax.loggly.com/search`

## Query params

`q` (Loggly query string), `from` (e.g. `-1d`, `-7d`, or ISO `2026-07-01T00:00:00Z`),
`until` (`now` or ISO), `size` (max `1000`). The iterate response is
`{"events": [...], "next": "<url>"}`; follow `next` until absent to page through
all matches. `next` is a fully-formed URL — request it **without** re-passing
`params`.

```python
import requests

def iterate(q, frm='-1d', until='now', size=1000, max_pages=60):
    """Return all events for a query (capped at max_pages to avoid runaway)."""
    events, url, params, pages = [], 'https://trax.loggly.com/apiv2/events/iterate/', \
        {'q': q, 'from': frm, 'until': until, 'size': size}, 0
    while url and pages < max_pages:
        r = requests.get(url, params=(params if pages == 0 else None), headers=headers, timeout=60)
        r.raise_for_status()
        data = r.json()
        events.extend(data.get('events', []))
        url = data.get('next')
        pages += 1
    return events
```

## Query syntax

Fields are dotted JSON paths. Common ones:

- `json.application:WaveMaker` — the app name (Simon jobs / services set this).
- `json.severity:ERROR` (also `CRITICAL`, `WARNING`, `INFO`).
- `json.project_name:ccza`, `json.session_uid:...`, `json.environment:PROD`, `json.cloud:AWS`.
- Free-text phrase match: `"total_mb_billed"` (matches anywhere in the log).
- Combine with `AND` / `OR` / `-` (exclude): `json.application:WaveMaker AND json.severity:ERROR`.

## Reading an event

Each event from the iterate API looks like
`{"timestamp": <epoch_ms>, "event": {"json": {...}}, "logmsg": "...", ...}`.
The useful payload is under `event.json`; the **timestamp is a top-level field**
on the event (Unix epoch **milliseconds**), *not* under `event.syslog` — there is
no `event.syslog` on iterate results, so reading `ev['event']['syslog']['timestamp']`
raises `KeyError`.

```python
j = ev['event']['json']            # dict of structured fields
msg   = j.get('message')           # the log line text
sev   = j.get('severity')
app   = j.get('application')
ts    = ev.get('timestamp')        # top-level, epoch MILLISECONDS (use .get to be safe)
# human-readable:
from datetime import datetime, timezone
when = datetime.fromtimestamp(int(ts) / 1000, tz=timezone.utc) if ts else None
```

## Counting / frequency estimates

The iterate API returns raw events, not aggregate counts. To estimate frequency:
iterate a representative window and count (extrapolate to a month), or sum a
value parsed from the message. Keep windows modest and `max_pages` bounded for
high-volume apps — say what window you sampled so the estimate is honest. For
authoritative counts over long ranges prefer the source of truth when one exists
(e.g. BigQuery `INFORMATION_SCHEMA.JOBS` for query counts) and use Loggly to
corroborate.

## Notes

- Retention is ~1 month; older logs aren't available.
- `429`/`5xx` happen under load — retry a few times (the PS report retries 3×).
- This is read-only log access; never log or echo the bearer token.
