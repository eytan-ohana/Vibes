---
name: trax-shipit-deploy
description: >-
  How to deploy and operate theGarage's deployable units with the Shipit tool
  (Trax/Deployment/Tools/Shipit/Main.py). Use whenever asked to deploy, ship,
  roll back, or restart a service/API, or to deploy/execute/rollback/enable/
  disable a Simon cron job — e.g. "deploy AIPlatform to int", "shipit deploy
  X to prod", "ship it", "roll back service Y", "promote the build to prod",
  "run/execute job Z", "deploy this branch". APIs are deployed as services.
  Critical: services whose deployment class inherits DockerGradualDeployment
  (e.g. FlexEngine) have a PROD canary stage that must be deployed and watched
  before a prod full rollout.
---

# Deploying with Shipit

Shipit (`Trax/Deployment/Tools/Shipit/Main.py`) is a CLI that **triggers a
Jenkins deploy pipeline** — it does not deploy directly. It validates inputs,
computes a version tag, and kicks off Jenkins, then prints a build URL. The
actual build/test/deploy runs in Jenkins; **watch that URL for the result and
never report a deploy as done until Jenkins finishes.**

It deploys the **current git checkout's branch + latest commit**. Run it from
the checkout (or git worktree) that is on the branch you want to deploy.

## Pre-flight (do this before every deploy)

1. **Right branch, committed, and PUSHED.** Shipit aborts with *"Latest commit
   not in remote, please PUSH before deploy"* if `HEAD` isn't on the remote. Push first.
2. **`garage38ai` conda env** must be active (or invoke under it — see below).
3. **Know the env + tag policy — it differs for services vs. jobs:**
   - **Services**: mint a new version in `int` (`build`/`minor`/`major`), then
     **promote that exact tag** to `prod` (`prod` only allows `last` or a
     specific tag — you can't mint a new version directly in prod;
     `DEPLOYMENT_CHOICES` in `Resources.py` is env-gated this way).
   - **Jobs** (`deploy_job`): **not** env-gated the same way (`SCHEDULED_JOBS_CHOICES`
     allows `build`/`minor`/`major`/`last`/specific-tag in **both** int and prod).
     `shipit deploy_job <Job> prod build` is valid on its own — no int step
     required. Doing this means the job is deployed **only to prod**, with no
     int build and no int verification first — **say that explicitly to the
     user before running it** so they can decide if they want an int pass
     first anyway, rather than silently skipping it.
4. **Is it a gradual (canary) service?** If its deployment class subclasses
   `DockerGradualDeployment`, prod needs a **canary first** (see below).

## How to run it

**Human form** (with the alias from `ship.sh`, env active):
```bash
shipit <task> [system] [env] [tag]      # e.g. shipit deploy AIPlatform int build
```
`shipit` with no/partial args is fully interactive (menus for task/system/env/tag).

**Agent / headless form** (what to use here — non-interactive, can't hang):
```bash
cd <checkout-on-the-target-branch>
SHIPIT_CLEARS_TERMINAL=false PYTHONPATH=<checkout> \
  conda run -n garage38ai --no-capture-output \
  python Trax/Deployment/Tools/Shipit/Main.py <task> <system> <env> <tag> < /dev/null
```
- Pass **all** positional args so no prompt appears.
- `< /dev/null` makes any unexpected prompt hit EOF and error out instead of hanging.
- `SHIPIT_CLEARS_TERMINAL=false` keeps output readable (skips the `clear`).
- `PYTHONPATH=<checkout>` ensures the worktree's code is used (not an editable install).

**Success looks like:** `Initiating Jenkins Deployment Pipeline...` followed by a
`Jenkins build url: https://new-jenkins.trax-cloud.com/...`. Report that URL.

## Services & APIs

APIs are deployed as services (Knative/`SimpleAPIDeployment`/`K8SDeployment`).

```bash
shipit deploy <System> <env> <tag>
# e.g.  shipit deploy AIPlatform int build      # new build version into INT
#       shipit deploy AIPlatform prod last      # promote latest existing tag to PROD
#       shipit deploy AIPlatform prod AIPlatform_v1.4.2   # promote a specific tag
```

Other service tasks: `docker_rollback`, `restart_service`,
`set_service_log_level_severity`, `set_service_scaling_bounds`, `service_info`.

## Jobs (Simon cron jobs)

```bash
shipit deploy_job <Job> <env> <tag>       # task name is "Deploy job"
# e.g.  shipit deploy_job QATCancelReport int build    # mint + deploy to INT
#       shipit deploy_job QATCancelReport prod last    # promote latest existing tag to PROD
#       shipit deploy_job QATCancelReport prod build   # mint a NEW version straight in PROD — skips INT entirely, see below
```
Other job tasks: `execute_job` (run a job now; any trailing args become the job's
custom args, overriding its defaults), `rollback_job`, `enable_job`, `disable_job`, `delete_job`,
`cancel_job`, `kill_job_instance`, `get_job_status`, `get_job_metadata`,
`job_info`, `set_job_log_level_severity`. Job tasks prompt for cloud (AWS/GCP).

**Jobs can build directly in prod, unlike services.** `deploy_job`'s tag choices
come from `SCHEDULED_JOBS_CHOICES` (`Resources.py`), which is the same
`build`/`minor`/`major`/`last`/specific-tag list for every env — there's no
prod-only restriction like services have. So `shipit deploy_job <Job> prod build`
mints a new version and deploys it straight to prod in one step, with **no int
build and no int verification along the way**. That can be exactly what's
wanted for a quick job fix, but **tell the user this explicitly before doing
it** — e.g. "this will deploy directly to prod with no int pass first, OK?" —
rather than assuming it or doing an unnecessary int step out of habit from the
services flow.

## Tags / versions

| Tag arg | Meaning |
| ------- | ------- |
| `build` / `minor` / `major` | Increment that segment of the system's latest git version tag → mints e.g. `AIPlatform_v1.2.3`. **INT only for services; jobs (`deploy_job`) allow this in prod too** — see below. |
| `last` | Redeploy the latest existing version (no new tag). The normal way to promote to **prod**. |
| `last_canary` | (INT full) deploy the version currently running on canary. |
| `<System>_vX.Y.Z` | A specific existing tag (matches `^.+_v\d+\.\d+\.\d+$`). Use to promote an exact build to prod. |

Allowed options depend on system type, and for services also on env + rollout:
- **Services** (`DEPLOYMENT_CHOICES`): **INT non-canary full** → major/minor/build/last/specific;
  **PROD** (canary or full) → last/specific only. Typical lifecycle: `build` in
  INT → verify → promote that tag to PROD.
- **Jobs** (`SCHEDULED_JOBS_CHOICES`): major/minor/build/last/specific are all
  allowed in **both** int and prod — no env restriction. `deploy_job <Job> prod
  build` mints a new version directly in prod, skipping int entirely. Tell the
  user when you're about to do that, since it's a real difference from how
  services normally get deployed.

## Canary services (DockerGradualDeployment) — read before prod

Services whose deployment class inherits `DockerGradualDeployment` (e.g.
`FlexEngineDeployment` in `Trax/Deployment/Services/FlexEngine.py`) run a
**canary** alongside the full deployment in **prod**. Procedure for these:

1. **Deploy canary to prod first**, then **watch it** (dashboards/logs/metrics)
   before touching full.
2. **Then promote full to prod.**

- **INT is always FULL** — there is no canary step in int (even for gradual services).
- In **prod**, Shipit asks **Canary vs Full** — but **only when fewer than 4 args
  are given**. If you fully specify `deploy <System> prod <tag>` (4 args), the
  prompt is skipped and it defaults to **FULL**, silently bypassing the canary
  safety step. **Footgun.**
- To deploy canary **non-interactively**, append `Canary` to the system name:
  ```bash
  shipit deploy <System>Canary prod last     # forces the canary rollout
  shipit deploy <System> prod last           # later: the full rollout
  ```
- For a prod gradual service, do **not** fully specify a full deploy in one shot —
  deploy `…Canary` first, confirm it's healthy, then run the full deploy.
- Rollback: `docker_rollback` can target canary, full, or both (it offers "Both"
  when canary and full are on the same version).

**How to check:** read the service's deployment file under
`Trax/Deployment/Services/<Name>.py` and look at the class bases. If
`DockerGradualDeployment` is among them → gradual/canary in prod. Otherwise it's a
single-step full deploy.

## Gotchas

- *"Latest commit not in remote, please PUSH before deploy"* → commit and push the branch.
- System-name matching is case-insensitive substring; an ambiguous match drops to
  an interactive picker (which will hang a headless run). Use the exact system name.
- Deploy asserts `env in {int, prod}`. (`dev` exists for some service tasks but not deploy.)
- Jenkins access / VPN may be required for the pipeline to start.
- Worktrees are first-class: each worktree's Shipit deploys that worktree's branch,
  so you can deploy different branches from different worktrees simultaneously.

## Reference

- Tool: `Trax/Deployment/Tools/Shipit/Main.py` · wrapper: `Trax/Deployment/Tools/Shipit/ship.sh`
- Tasks/choices: `Trax/Deployment/Constants/Resources.py` (`TASKS`, `DEPLOYMENT_CHOICES` for
  services, `SCHEDULED_JOBS_CHOICES` for jobs, `VERSION_ARGUMENTS`)
- Deploy → Jenkins: `ShipitManager.handle_deployment` → `JenkinsAdapter.start_deployment`
- Gradual base class: `DockerGradualDeployment` in `Trax/Deployment/Services/Base.py`
- See also the **trax-architecture** skill for where services/APIs/jobs and their deployment files live.
