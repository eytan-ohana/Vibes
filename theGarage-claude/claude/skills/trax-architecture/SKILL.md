---
name: trax-architecture
description: >-
  How theGarage is structured and how its deployable units work — use when
  navigating the repo, locating a service/API/job, understanding or modifying
  deployment config (scaling, resources, scheduling, queues), or working on the
  code behind one. Covers the three unit types: queue-based services, FastAPI/
  Knative APIs, and Simon jobs (cron). Trigger phrases: "where is service X",
  "how is X deployed", "add a new job/API/service", "what handles this queue",
  "change scaling/resources/schedule", "find the controller for this endpoint".
---

# theGarage architecture & navigation

Almost everything deployable is one of three types. Each separates a **deployment
file** (how it runs — resources, scaling, scheduling, `executable_path`) from its
**app code** (what it does).

| Type | Deployment file | App code root                | Reference |
| ---- | --------------- |------------------------------| --------- |
| Queue-based service | `Trax/Deployment/Services/<Name>.py` | `Trax/Apps/Services/<Name>/` | [services.md](services.md) |
| FastAPI / Knative API | `Trax/Deployment/Services/<Name>.py` | `Trax/Apps/APIs/<Name>/` or `Trax/Apps/Services/<Name>/` | [apis.md](apis.md) |
| Simon job (cron) | `Trax/Deployment/Jobs/<Name>.py` | `Trax/Apps/Jobs/…/<Name>.py` | [jobs.md](jobs.md) |

## Navigating: deployment ⇄ code

- **Deployment → code:** open the deployment file and read `executable_path()`
  (services/APIs/jobs) — it's the relative path to the entrypoint. For
  `SimpleAPIDeployment`s the entrypoint is generic (`Trax/Apps/APIs/Utils/Server.py`)
  and the real code is named in `controller_paths` / `api_module_path`.
- **Code → deployment:** grep `Trax/Deployment/Services/` and `Trax/Deployment/Jobs/`
  for the `executable_path` of the file you're in.
- **Deployment base class tells you the type:** `K8SDeployment`(+`MultiProcessUpstartService`)
  → queue service; `KnativeDeployment` / `SimpleAPIDeployment[38]` → API;
  `JobBaseDeployment` → cron job.

## Deployment base classes (shared vocabulary)

Defined in `Trax/Deployment/Services/Base.py`, `…/WebServices/`, `…/Jobs/Base.py`:

- `Deployment` — root; every subclass overrides `executable_path()`,
  `config_path(env)`, `system_mailing_list()`, `test_directories()`.
- `K8SDeployment` / `DockerDeployment` — k8s + container concerns: `memory()`,
  `cpu()`, `service_account()`, `health_checks()`, `input_queues()` (queue svcs).
- `Python38Deployment` / `Python3Deployment` — pin the conda env / base image
  (py3.8 = `garage38`, py3.7 = `garage3`). Most new code is 3.8.
- `KnativeDeployment[38]` / `SimpleAPIDeployment[38]` — API specifics (see apis.md).
- `JobBaseDeployment` (+ `Python38JobBaseDeployment`) — cron jobs (see jobs.md).

Reach for the per-type reference file when adding to or editing one of these.
