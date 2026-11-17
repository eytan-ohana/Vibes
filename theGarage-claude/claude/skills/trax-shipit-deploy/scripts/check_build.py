"""Read a Shipit-triggered Jenkins build's status (services and jobs).

Not a CLI: import and call ``check_build`` (see the trax-shipit-deploy skill):

    python -c "import runpy; runpy.run_path('<this file>')['check_build'](2279, kind='service')"

Uses the same Jenkins credentials Shipit uses (read-only API call).
"""
import jenkins

from Trax.Cloud.Services.Connector.Keys import ResourceUsers
from Trax.Cloud.Services.Connector.Logger import LoggerInitializer
from Trax.Deployment.Constants.Consts import JENKINS_URL, JOB_PIPELINE_GITHUB, SERVICE_PIPELINE_GITHUB
from Trax.Utils.Conf.Configuration import Config

PIPELINES = {'service': SERVICE_PIPELINE_GITHUB, 'job': JOB_PIPELINE_GITHUB}


def check_build(build_number: int, kind: str = 'service') -> dict:
    """Return and print the build's state.

    ``kind`` is 'service' (deploy of a service/API) or 'job' (deploy_job), matching the
    pipeline in the Jenkins URL Shipit printed: garage_deploy_service vs the job pipeline.
    ``building`` True means still running; ``result`` is SUCCESS/FAILURE/ABORTED when done.
    """
    LoggerInitializer.init('Simon')  # also initializes Config
    Config.set_env_and_cloud(*Config.PROD_AWS)  # needed to read the Jenkins credentials from Vault
    creds = ResourceUsers.JenkinsServiceRemoteDeployment
    server = jenkins.Jenkins(JENKINS_URL, username=creds.username, password=creds.token)
    info = server.get_build_info(PIPELINES[kind], build_number)
    state = {'pipeline': PIPELINES[kind], 'build': build_number, 'building': info['building'],
             'result': info['result'], 'url': info['url']}
    print(f'STATUS {state}')
    return state
