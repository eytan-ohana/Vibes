---
name: trax-k8s-access
description: >-
  How to get kubectl access to theGarage's AWS EKS and GCP GKE clusters for
  debugging — checking a CronJob's schedule/status, pod state, job execution
  history. Use whenever a task needs to inspect live k8s state for a service
  or job, on either cloud — e.g. "why didn't this job run", "check the pod
  status", "describe this cronjob". Covers a real GKE gotcha where kubectl
  looks flaky (connection resets) when it's actually pointed at the wrong
  (public) endpoint. Not about deploying — see trax-shipit-deploy for that.
---

# Getting kubectl access to theGarage's clusters

theGarage runs on clusters across two clouds. This is about getting access for
debugging (cronjob schedules, pod/job status, live state) — see
**trax-shipit-deploy** for the deploy pipeline itself.

**These commands only set up authentication, not authorization.** `aws eks
update-kubeconfig` / `gcloud container clusters get-credentials` just point
kubectl at a cluster using your existing identity — they grant nothing and
enforce no scope by themselves. Whatever RBAC/IAM permissions that identity
already has on the cluster are what you get, which for an engineer's own
account is very likely broader than read-only. Stick to non-mutating verbs
(`get`, `describe`, `logs`) for debugging — nothing here prevents `kubectl
delete`/`edit`/`apply` from working if your identity is allowed to.

## AWS EKS clusters

```bash
aws eks update-kubeconfig --name prod-cluster --region us-east-1
# other clusters: int-pyinfra-v2, prod-knative
```
This just works if your AWS credentials/SSO session is valid. One gotcha
shared with the GCP side: it also sets the newly-configured cluster as
`current-context` — see the context-switching note below.

## GCP GKE clusters — the endpoint gotcha

```bash
gcloud auth login                      # if your token expired (traxretail.com tokens do)
gcloud container clusters get-credentials prod-cluster --region us-central1 \
  --project trax-retail --internal-ip
```

**Always pass `--internal-ip`.** Without it, `gcloud` points kubectl at the
cluster's **public** endpoint. `prod-cluster` (and possibly others) has
`masterAuthorizedNetworksConfig.enabled: true` — a strict IP allowlist checked
against the *client's* source IP when it hits the public endpoint. If your
traffic isn't egressing through one of those exact allowlisted IPs (it might
not, even on a VPN that otherwise works fine for internal sites — this is a
separate, cluster-specific allowlist, not general network access), every
kubectl call **connects fine at the TCP layer, then resets during the TLS
handshake** — `read: connection reset by peer` on essentially every request,
sometimes with one lucky exception that makes it look intermittent rather than
structural. This looks exactly like "the VPN is flaky," but it isn't — it's
the wrong endpoint. `--internal-ip` switches kubectl to the private endpoint
(e.g. `10.108.255.13`) instead, which isn't gated by that allowlist at all —
it's reached through the VPC's private peering/VPN route, a completely
separate access path from the public endpoint's IP-allowlist check.

To check whether a given cluster is affected before you burn time debugging
"flaky" connections:
```bash
gcloud container clusters describe <cluster> --region <region> --project trax-retail \
  --format="yaml(masterAuthorizedNetworksConfig,privateClusterConfig)"
```
Look for `masterAuthorizedNetworksConfig.enabled: true` and the
`publicEndpoint`/`privateEndpoint` values under `privateClusterConfig`.

Both clouds happen to have a cluster literally named `prod-cluster`. kubectl
context names disambiguate them (`arn:aws:eks:...:cluster/prod-cluster` vs.
`gke_trax-retail_us-central1_prod-cluster`), but **always check `kubectl config
current-context`** before running anything — fetching new credentials for
*either* cloud (`aws eks update-kubeconfig` just as much as `gcloud container
clusters get-credentials`) silently switches the current context, and it's
easy to end up querying the wrong cloud's identically-named cluster after
switching back and forth without noticing.

## Alternative: skip kubectl entirely for Simon job/cronjob status

For Simon cron jobs specifically, `Trax.Cloud.Utils` has helpers that hit an
internal HTTP API (`infra.trax-cloud.com` for AWS, `ginfra.trax-cloud.com` for
GCP) instead of the k8s API — no kubectl/VPN/cluster-credentials setup needed
at all, and it works over the open internet:

```python
from Trax.Utils.Conf.Configuration import Config
Config.init(use_cla=False, default_env_and_cloud=Config.PROD_AWS)
from Trax.Cloud.Utils import get_cronjob, get_all_cronjobs, get_job_status_contents, get_deploy_info

get_deploy_info('QATCancelReport', Config.PROD, Config.AWS)   # deploy history for any system (service or job)
get_all_cronjobs(Config.GCP, Config.PROD)                     # every cronjob's spec (schedule, suspend, args, resources)
get_cronjob('Simon_MaskingAccuracyReport_Weekly_EMEA', Config.GCP, Config.PROD)   # one cronjob's spec
get_job_status_contents('Simon_MaskingAccuracyReport_Weekly_EMEA', Config.GCP, Config.PROD)  # execution history
```

Naming gotcha: pass the `job_name` value used in the deployed env vars (e.g.
`Simon_<JobDefinitionName>`, matching the `JOB_NAME` env var on the pod), not
the bare deployment key. `get_cronjob_name()` just lowercases and hyphenates
whatever you pass, and the real k8s object name is `simon-<...>` — so the
input needs the `Simon_` prefix to resolve; the bare key (without prefix)
404s/400s even when the cronjob genuinely exists.

This is read-only and reflects the **registered/desired** state — not a
substitute for kubectl when you need real-time `status` fields (e.g.
`lastScheduleTime`, actual pod phase), but it's the fastest way to sanity-check
a job's config without touching kubectl, VPN, or cloud credentials at all.

## See also
- **trax-shipit-deploy** for deploying, rolling back, or executing jobs/services.
- **trax-architecture** for where deployment files and app code live.
