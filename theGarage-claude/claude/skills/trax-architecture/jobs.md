# Simon jobs (cron)

Scheduled one-shot runs on Kubernetes. Every job has the same shape: a deployment
that schedules it + a module exposing `run(*args)`.

## Layout

- **Deployment:** `Trax/Deployment/Jobs/<Name>.py` — subclass of
  **`Python38JobBaseDeployment`**. Defines `executable_path()` and a `jobs_info`
  property giving the schedule + resources.

  > ⚠️ **Always use `Python38JobBaseDeployment` for new jobs.** The bare
  > `JobBaseDeployment` runs under the legacy **Python 2** image — do not use it.
  > `Python38JobBaseDeployment` (`JobBaseDeployment` + `Python38Deployment`) pins
  > the Python 3.8 base image. (`Python3JobBaseDeployment` exists too, but prefer
  > the 3.8 variant.) Some old jobs still subclass `JobBaseDeployment` directly —
  > don't copy them; treat them as needing migration, not as the pattern.

  ```python
  from Trax.Deployment.Jobs.Base import Python38JobBaseDeployment

  class MyReportJobDeployment(Python38JobBaseDeployment):
      @classmethod
      def executable_path(cls):
          return 'Trax/Apps/Jobs/…/MyReport.py'
  ```
- **App code:** `Trax/Apps/Jobs/…/<Name>.py` — must define a module-level
  `run(*args)`.

## The `run` contract

The deployment launches every job through `Trax/Apps/Core/Jobs/Wrapper.py`, which
loads your module and calls `job.run(*custom_args)`. So your job file must define
a module-level `run(*args)`.

**Let the wrapper handle errors — don't wrap your whole job in try/except.**
`JobWrapper.start` already calls `run` inside a try/except: on any exception it
logs with the traceback, sends a Slack failure notice, emails the deployment's
`system_mailing_list()` (with a Loggly link), and exits non-zero. If you swallow
the exception yourself you lose all of that. Only catch where you can genuinely
recover; otherwise let it propagate.

Return value is the exit code, but it's optional — returning nothing exits 0.
`Config` and logging are already initialized before `run` is called.

```python
import argparse

from Trax.Cloud.Services.Jobs.JobArgumentParser import job_argument_parse


def run(*args):
    parser = argparse.ArgumentParser()
    parser.add_argument('--interval', required=True)
    parser.add_argument('--start_date', default=None)
    parser.add_argument('--end_date', default=None)
    parser.add_argument('--send_email', action='store_true')
    params = job_argument_parse(parser, args)   # parses, logs, Slacks help/errors

    report = AltriaUSFacingReport(interval=params.interval)
    report.create_reports(start_date=params.start_date,
                          end_date=params.end_date,
                          send_email=params.send_email)
    # no try/except, no explicit return needed — exceptions bubble to the wrapper
```

**Parse args with `job_argument_parse`** (`Trax/Cloud/Services/Jobs/JobArgumentParser.py`)
rather than positional `args[0]`/`args[1]` indexing — it gives you named,
validated arguments and handles `--help`/parse-error reporting to Slack. Pass it
your `argparse` parser and the raw `args`; it returns the parsed `Namespace`. The
custom args themselves are configured per scheduled variant in the deployment's
`jobs_info` (below).

## Scheduling (`jobs_info`)

```python
from Trax.Cloud.Providers.AWS.Jobs.Constants import WEEKLY, ENVIRONMENT_VARIABLES, SCHEDULING
from Trax.Utils.Scheduling.Enums import SchedulingKeys, Days

@property
def jobs_info(self):
    return {
        self.job_name + WEEKLY: {
            SCHEDULING: {SchedulingKeys.EXPRESSION_TYPE: SchedulingKeys.CRON,
                         SchedulingKeys.MINUTES: '1', SchedulingKeys.HOURS: '12',
                         SchedulingKeys.DAY_OF_WEEK: Days.MON},
            ENVIRONMENT_VARIABLES: self.environment_variables(additional_fields='TWO_WEEK'),
        }
    }
```

One deployment can register several scheduled variants (keys built off
`self.job_name`), each with its own cron expression and custom args (passed via
env vars → become `run`'s `*args`). Override `memory`/`vcpus`/`execution_timeout`/
`attempts` for per-job resources.

**To add a job:** create `Trax/Apps/Jobs/…/<Name>.py` with `run(*args)`, then a
`Trax/Deployment/Jobs/<Name>.py` pointing `executable_path()` at it with a
`jobs_info` schedule.
