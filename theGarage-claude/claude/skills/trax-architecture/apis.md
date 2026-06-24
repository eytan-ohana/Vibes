# FastAPI / Knative APIs

HTTP services deployed on Knative. Two deployment styles — pick by how the app
is wired.

## Layout

- **Deployment:** `Trax/Deployment/Services/<Name>.py`. App-specific knobs:
  `resources_config(flavor, env)` (a `ResourceProfile`: `SUPER_LIGHT`/`LIGHT`/
  `MEDIUM`/`INTENSIVE`…), `auto_scaling_bounds(flavor, env, cloud)` (min/max/initial
  replicas), `auto_scaling_config(flavor)` (an `AutoScalingProfile`:
  `QUICK_RESPONSE`/`FAST_UP_SLOWLY_DOWN`…), `concurrency_limit(flavor)`,
  `request_timeout_limit_seconds(flavor)`, `supported_clouds()`.
- **App code:** `Trax/Apps/APIs/<Name>/`.

Base classes (`Trax/Deployment/Services/WebServices/`):
- `KnativeDeployment` / `KnativeDeployment38` (py3.7 / py3.8)
- `SimpleAPIDeployment` / `SimpleAPIDeployment38`

## Two styles

### A) KnativeDeployment — own FastAPI app

`executable_path()` points at the app's own `Server.py` which builds the FastAPI
app and mounts routers. Example: `Trax/Deployment/Services/LightningAPI.py` →
`Trax/Apps/APIs/LightningAPI/Server.py`:

```python
app = FastAPI(title=app_name)
app.include_router(Recalcs.router, dependencies=[Depends(check_authentication)])

@app.get('/healthz')
async def healthz():
    return {'status': 'ok'}
```

### B) SimpleAPIDeployment — controller-based

The deployment doesn't ship its own server; `executable_path()` is the generic
`Trax/Apps/APIs/Utils/Server.py`, which dynamically loads the classes named in
the deployment's `controller_paths` (or `api_module_path` + `api_class_name`).
Example: `Trax/Deployment/Services/TritonInferenceAPI.py`:

```python
@classproperty
def controller_paths(cls) -> List[str]:
    return ["Trax.Apps.APIs.AIPlatform.TritonInferenceAPI.InferenceController.v2."
            "InferenceController.InferenceController", ...]
```

A **controller** is a class decorated with `@controller(tag=…, version=…)` whose
methods are routes (`@route`, `@api_methods(["GET"])`, `@override_path("/…")`)
returning typed (Pydantic) responses and delegating to a Flow for the logic. They
live under `Trax/Apps/APIs/<Name>/…/<X>Controller/v<N>/`.

**To find the code behind an endpoint:** style A → the router modules
`include_router`'d in `Server.py`; style B → the classes in `controller_paths`.
