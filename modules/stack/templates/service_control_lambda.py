import json
import os
import re
import hashlib
import hmac


import boto3

ecs = boto3.client("ecs")
elbv2 = boto3.client("elbv2")
ecr = boto3.client("ecr")
codebuild = boto3.client("codebuild")
ssm = boto3.client("ssm")

CLUSTER_ARN = os.environ["CLUSTER_ARN"]
CLUSTER_NAME = CLUSTER_ARN.split("/")[-1] if CLUSTER_ARN else ""
START_DESIRED = int(os.environ.get("START_DESIRED", "1"))
SERVICE_CONTROL_SSM_PATH = os.environ.get("SERVICE_CONTROL_SSM_PATH", "")
SERVICE_CONTROL_DEFAULT_REALM = os.environ.get("SERVICE_CONTROL_DEFAULT_REALM", "")
KEYCLOAK_ADMIN_USERNAME_PARAMETER = os.environ.get("KEYCLOAK_ADMIN_USERNAME_SSM_PARAMETER")
KEYCLOAK_ADMIN_PASSWORD_PARAMETER = os.environ.get("KEYCLOAK_ADMIN_PASSWORD_SSM_PARAMETER")
ODOO_ADMIN_USERNAME = os.environ.get("ODOO_ADMIN_USERNAME", "admin")
ODOO_ADMIN_PASSWORD_PARAMETER = os.environ.get("ODOO_ADMIN_PASSWORD_SSM_PARAMETER")
PGADMIN_ADMIN_USERNAME = os.environ.get("PGADMIN_ADMIN_USERNAME", "admin")
PGADMIN_PASSWORD_PARAMETER = os.environ.get("PGADMIN_PASSWORD_SSM_PARAMETER")
SULU_IMAGE_BUILDER_PROJECT_NAME = os.environ.get("SULU_IMAGE_BUILDER_PROJECT_NAME", "")
SULU_ECR_REPOSITORIES = json.loads(os.environ.get("SULU_ECR_REPOSITORIES", "[]"))
SERVICE_CONTROL_AUTH_TOKEN_SSM_PARAMETER = os.environ.get("SERVICE_CONTROL_AUTH_TOKEN_SSM_PARAMETER", "")
_SERVICE_CONTROL_AUTH_TOKEN = None


def _load_json_config(env_key, ssm_param_env_key, default=None):
    default = default or {}
    raw = os.environ.get(env_key)
    if raw:
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            print({"warning": f"{env_key} is not valid JSON"})
    param_name = os.environ.get(ssm_param_env_key)
    if param_name:
        try:
            resp = ssm.get_parameter(Name=param_name)
            return json.loads(resp["Parameter"]["Value"])
        except ssm.exceptions.ParameterNotFound:
            print({"warning": "ssm parameter not found", "parameter": param_name})
        except Exception as exc:  # pylint: disable=broad-except
            print({"warning": "failed to load ssm parameter", "parameter": param_name, "error": str(exc)})
    return default.copy() if isinstance(default, dict) else default


SERVICE_ARNS = _load_json_config("SERVICE_ARNS", "SERVICE_ARNS_SSM_PARAMETER", {})
TARGET_GROUP_ARNS = _load_json_config("TARGET_GROUP_ARNS", "TARGET_GROUP_ARNS_SSM_PARAMETER", {})
IMAGE_TAG_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def _service_control_auth_token():
    global _SERVICE_CONTROL_AUTH_TOKEN  # pylint: disable=global-statement
    if _SERVICE_CONTROL_AUTH_TOKEN is not None:
        return _SERVICE_CONTROL_AUTH_TOKEN
    if not SERVICE_CONTROL_AUTH_TOKEN_SSM_PARAMETER:
        raise RuntimeError("service control authentication token is not configured")
    response = ssm.get_parameter(Name=SERVICE_CONTROL_AUTH_TOKEN_SSM_PARAMETER, WithDecryption=True)
    _SERVICE_CONTROL_AUTH_TOKEN = str(response.get("Parameter", {}).get("Value") or "")
    if not _SERVICE_CONTROL_AUTH_TOKEN:
        raise RuntimeError("service control authentication token is empty")
    return _SERVICE_CONTROL_AUTH_TOKEN


def _event_header(event, name):
    headers = event.get("headers") or {}
    wanted = name.lower()
    for key, value in headers.items():
        if str(key).lower() == wanted:
            return str(value or "")
    return ""


def _is_authorized(event):
    raw = _event_header(event, "authorization") or _event_header(event, "x-aiops-workflows-token")
    provided = re.sub(r"^Bearer\s+", "", raw.strip(), flags=re.IGNORECASE)
    return hmac.compare_digest(provided, _service_control_auth_token())


def _approval_canonical(action, realm, payload):
    evidence = payload.get("approvalEvidence") or payload.get("approval_evidence") or {}
    fields = [
        action,
        str(realm or ""),
        str(payload.get("imageTag") or payload.get("image_tag") or ""),
        str(evidence.get("changeId") or evidence.get("change_id") or ""),
        str(evidence.get("issueUrl") or evidence.get("issue_url") or ""),
        str(evidence.get("approvedAt") or evidence.get("approved_at") or ""),
        str(evidence.get("approvedBy") or evidence.get("approved_by") or ""),
    ]
    if not all(fields[1:]):
        raise ValueError("complete CAB approval evidence is required for a real change")
    return "\n".join(fields), evidence


def _verify_approval_signature(action, realm, payload):
    canonical, evidence = _approval_canonical(action, realm, payload)
    provided = str(payload.get("approvalSignature") or payload.get("approval_signature") or "")
    expected = hmac.new(
        _service_control_auth_token().encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    if not provided or not hmac.compare_digest(provided, expected):
        raise ValueError("CAB approval signature is invalid")
    return evidence


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,Authorization,X-AIOps-Workflows-Token",
        },
        "body": json.dumps(body),
    }


def _select_by_realm(value, realm):
    if not isinstance(value, dict):
        return value, ""
    chosen = realm or SERVICE_CONTROL_DEFAULT_REALM or ""
    if chosen and chosen in value:
        return value.get(chosen), chosen
    for key in sorted(value.keys()):
        if value.get(key):
            return value.get(key), key
    return None, chosen


def _get_service_arn(service_key, realm):
    raw = SERVICE_ARNS.get(service_key)
    if raw is None:
        raise ValueError(f"unknown service: {service_key}")
    service_arn, resolved_realm = _select_by_realm(raw, realm)
    if not service_arn:
        raise ValueError(f"service arn not configured: {service_key} (realm={realm or resolved_realm or '-'})")
    return service_arn, resolved_realm


def _get_target_group_arn(service_key, realm):
    raw = TARGET_GROUP_ARNS.get(service_key)
    if raw is None:
        return None, ""
    tg_arn, resolved_realm = _select_by_realm(raw, realm)
    return (tg_arn or None), resolved_realm


def _describe(service_arn):
    resp = ecs.describe_services(cluster=CLUSTER_ARN, services=[service_arn])
    services = resp.get("services", [])
    failures = resp.get("failures", [])
    if not services:
        reason = failures[0].get("reason", "NOT_FOUND") if failures else "NOT_FOUND"
        raise ValueError(f"service not found: {service_arn} ({reason})")
    svc = services[0]

    image = None
    image_tag = None
    ecr_latest_tag = None
    task_def_arn = svc.get("taskDefinition")
    if task_def_arn:
        try:
            td = ecs.describe_task_definition(taskDefinition=task_def_arn).get("taskDefinition", {})
            containers = td.get("containerDefinitions", [])
            target = next(
                (c for c in containers if str(c.get("name", "")).startswith("php-fpm-") and c.get("image")),
                None,
            )
            target = target or next(
                (c for c in containers if c.get("essential", True) and c.get("image")),
                None,
            )
            target = target or (containers[0] if containers else None)
            image = target.get("image") if target else None
            if image:
                image_tag = image.rsplit(":", 1)[-1] if ":" in image else image
                # ECR の最新タグを取得（イメージが ECR の場合のみ）
                try:
                    parts = image.split("/", 1)
                    if len(parts) == 2 and ".dkr.ecr." in parts[0]:
                        repository = parts[1].split(":")[0]
                        latest_detail = None
                        paginator = ecr.get_paginator("describe_images")
                        for page in paginator.paginate(repositoryName=repository, PaginationConfig={"PageSize": 100}):
                            for detail in page.get("imageDetails", []):
                                pushed = detail.get("imagePushedAt")
                                if not pushed:
                                    continue
                                if latest_detail is None or pushed > latest_detail.get("imagePushedAt"):
                                    latest_detail = detail
                        if latest_detail:
                            tags = latest_detail.get("imageTags") or []
                            ecr_latest_tag = tags[0] if tags else None
                except Exception as exc:  # pylint: disable=broad-except
                    print({"warning": "ecr_describe_images failed", "error": str(exc), "image": image})
        except Exception as exc:  # pylint: disable=broad-except
            print({"warning": "describe_task_definition failed", "error": str(exc)})

    return {
        "desiredCount": svc.get("desiredCount", 0),
        "runningCount": svc.get("runningCount", 0),
        "status": svc.get("status", "UNKNOWN"),
        "taskDefinition": task_def_arn,
        "image": image,
        "imageTag": image_tag,
        "ecrLatestTag": ecr_latest_tag,
        "deployments": [
            {
                key: deployment.get(key)
                for key in [
                    "id",
                    "status",
                    "taskDefinition",
                    "desiredCount",
                    "pendingCount",
                    "runningCount",
                    "rolloutState",
                    "rolloutStateReason",
                ]
                if deployment.get(key) is not None
            }
            for deployment in svc.get("deployments", [])
        ],
    }


def _describe_tg_health(tg_arn):
    resp = elbv2.describe_target_health(TargetGroupArn=tg_arn)
    health = resp.get("TargetHealthDescriptions", [])
    summary = {
        "healthy": 0,
        "unhealthy": 0,
        "initial": 0,
        "draining": 0,
        "unused": 0,
        "unknown": 0,
        "total": len(health),
    }
    details = []
    for h in health:
        state = h.get("TargetHealth", {}).get("State", "unknown")
        summary[state] = summary.get(state, 0) + 1
        details.append(
            {
                "id": h.get("Target", {}).get("Id"),
                "port": h.get("Target", {}).get("Port"),
                "state": state,
                "reason": h.get("TargetHealth", {}).get("Reason"),
                "description": h.get("TargetHealth", {}).get("Description"),
            }
        )
    return {"summary": summary, "targets": details}


def _load_ssm_parameter_value(name, label):
    if not name:
        return None
    try:
        resp = ssm.get_parameter(Name=name, WithDecryption=True)
        return resp.get("Parameter", {}).get("Value")
    except Exception as exc:  # pylint: disable=broad-except
        print({"warning": f"failed to load {label}", "parameter": name, "error": str(exc)})
        return None


def _get_keycloak_admin_credentials():
    return {
        "username": _load_ssm_parameter_value(KEYCLOAK_ADMIN_USERNAME_PARAMETER, "Keycloak admin username"),
        "password": _load_ssm_parameter_value(KEYCLOAK_ADMIN_PASSWORD_PARAMETER, "Keycloak admin password"),
    }

def _get_odoo_admin_credentials():
    return {
        "username": ODOO_ADMIN_USERNAME,
        "password": _load_ssm_parameter_value(ODOO_ADMIN_PASSWORD_PARAMETER, "Odoo admin password"),
    }


def _get_pgadmin_admin_credentials():
    return {
        "username": PGADMIN_ADMIN_USERNAME,
        "password": _load_ssm_parameter_value(PGADMIN_PASSWORD_PARAMETER, "pgAdmin admin password"),
    }


def _update(service_arn, desired):
    ecs.update_service(cluster=CLUSTER_ARN, service=service_arn, desiredCount=desired)
    return _describe(service_arn)


def _truthy(value):
    return str(value or "").strip().lower() in {"1", "true", "yes", "y", "on"}


def _validate_image_tag(value):
    image_tag = str(value or "").strip()
    if not image_tag:
        raise ValueError("imageTag is required")
    if image_tag.lower() == "latest":
        raise ValueError("imageTag must be an explicit version tag; latest is not allowed")
    if not IMAGE_TAG_PATTERN.fullmatch(image_tag):
        raise ValueError("imageTag contains unsupported characters")
    return image_tag


def _parse_ecr_image(image):
    without_digest = str(image or "").split("@", 1)[0]
    if "/" not in without_digest:
        raise ValueError(f"image is not an ECR repository URI: {image}")
    registry, repository_and_tag = without_digest.split("/", 1)
    if ".dkr.ecr." not in registry:
        raise ValueError(f"image is not an ECR repository URI: {image}")
    repository = repository_and_tag.rsplit(":", 1)[0]
    return registry, repository


def _with_image_tag(image, image_tag):
    registry, repository = _parse_ecr_image(image)
    return f"{registry}/{repository}:{image_tag}", repository


def _build_sulu_task_definition_plan(service_arn, image_tag):
    service_response = ecs.describe_services(cluster=CLUSTER_ARN, services=[service_arn])
    services = service_response.get("services", [])
    if not services:
        raise ValueError(f"service not found: {service_arn}")
    service = services[0]
    current_task_definition_arn = service.get("taskDefinition")
    if not current_task_definition_arn:
        raise ValueError("current task definition is not available")

    task_definition = ecs.describe_task_definition(taskDefinition=current_task_definition_arn).get("taskDefinition", {})
    container_definitions = json.loads(json.dumps(task_definition.get("containerDefinitions", [])))
    planned_images = []
    repositories = set()
    found_php = False
    found_nginx = False

    for container in container_definitions:
        name = str(container.get("name", ""))
        image = str(container.get("image", ""))
        if not image:
            continue
        try:
            target_image, repository = _with_image_tag(image, image_tag)
        except ValueError:
            continue
        is_php = repository.endswith("/sulu") and (name.startswith("php-fpm-") or name.startswith("init-db-"))
        is_nginx = repository.endswith("/sulu-nginx") and name.startswith("nginx-")
        if not (is_php or is_nginx):
            continue
        found_php = found_php or is_php
        found_nginx = found_nginx or is_nginx
        repositories.add(repository)
        planned_images.append({"container": name, "from": image, "to": target_image})
        container["image"] = target_image

    if not found_php or not found_nginx:
        raise ValueError("Sulu PHP and Nginx containers were not both found in the current task definition")

    for repository in sorted(repositories):
        try:
            ecr.describe_images(repositoryName=repository, imageIds=[{"imageTag": image_tag}])
        except ecr.exceptions.ImageNotFoundException as exc:
            raise ValueError(f"ECR image tag not found: {repository}:{image_tag}") from exc
        except ecr.exceptions.RepositoryNotFoundException as exc:
            raise ValueError(f"ECR repository not found: {repository}") from exc

    register_keys = [
        "family",
        "taskRoleArn",
        "executionRoleArn",
        "networkMode",
        "volumes",
        "placementConstraints",
        "requiresCompatibilities",
        "cpu",
        "memory",
        "pidMode",
        "ipcMode",
        "proxyConfiguration",
        "inferenceAccelerators",
        "ephemeralStorage",
        "runtimePlatform",
    ]
    register_payload = {
        key: task_definition[key]
        for key in register_keys
        if task_definition.get(key) is not None
    }
    register_payload["containerDefinitions"] = container_definitions
    tags = ecs.list_tags_for_resource(resourceArn=current_task_definition_arn).get("tags", [])
    if tags:
        register_payload["tags"] = tags

    return {
        "current_task_definition": current_task_definition_arn,
        "current_desired_count": service.get("desiredCount", 0),
        "planned_images": planned_images,
        "register_payload": register_payload,
    }


def _deploy_sulu_version(service_arn, realm, payload):
    image_tag = _validate_image_tag(payload.get("imageTag") or payload.get("image_tag") or payload.get("version"))
    dry_run = (
        True
        if payload.get("dryRun") is None and payload.get("dry_run") is None
        else _truthy(payload.get("dryRun", payload.get("dry_run")))
    )
    allow_service_change = _truthy(payload.get("allowServiceChange", payload.get("allow_service_change")))
    if not dry_run and not allow_service_change:
        raise ValueError("allowServiceChange=true is required when dryRun=false")
    approval_evidence = None
    if not dry_run:
        approval_evidence = _verify_approval_signature("deploy", realm, payload)

    plan = _build_sulu_task_definition_plan(service_arn, image_tag)
    if not dry_run and int(plan["current_desired_count"] or 0) < 1:
        raise ValueError("Sulu must be running before a version deployment")
    result = {
        "status": "validated" if dry_run else "accepted",
        "service": "sulu",
        "imageTag": image_tag,
        "dryRun": dry_run,
        "applied": False,
        "currentDesiredCount": plan["current_desired_count"],
        "currentTaskDefinition": plan["current_task_definition"],
        "plannedImages": plan["planned_images"],
        "approvalEvidence": approval_evidence,
    }
    if dry_run:
        return result

    registered = ecs.register_task_definition(**plan["register_payload"]).get("taskDefinition", {})
    new_task_definition_arn = registered.get("taskDefinitionArn")
    if not new_task_definition_arn:
        raise RuntimeError("ECS did not return a new task definition ARN")
    ecs.update_service(
        cluster=CLUSTER_ARN,
        service=service_arn,
        taskDefinition=new_task_definition_arn,
        forceNewDeployment=True,
    )
    result.update({
        "applied": True,
        "newTaskDefinition": new_task_definition_arn,
    })
    return result


def _validate_source_ref(value):
    source_ref = str(value or "").strip()
    if not source_ref:
        raise ValueError("sourceRef is required")
    if source_ref.startswith("-") or ".." in source_ref:
        raise ValueError("sourceRef contains unsupported traversal syntax")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,199}", source_ref):
        raise ValueError("sourceRef contains unsupported characters")
    return source_ref


def _ecr_tag_exists(repository, image_tag):
    try:
        response = ecr.describe_images(repositoryName=repository, imageIds=[{"imageTag": image_tag}])
        return bool(response.get("imageDetails"))
    except ecr.exceptions.ImageNotFoundException:
        return False
    except ecr.exceptions.RepositoryNotFoundException as exc:
        raise ValueError(f"ECR repository not found: {repository}") from exc


def _build_sulu_images(payload):
    image_tag = _validate_image_tag(payload.get("imageTag") or payload.get("image_tag") or payload.get("version"))
    source_version = _validate_image_tag(payload.get("sourceVersion") or payload.get("source_version") or image_tag)
    source_ref = _validate_source_ref(payload.get("sourceRef") or payload.get("source_ref") or "main")
    dry_run = (
        True
        if payload.get("dryRun") is None and payload.get("dry_run") is None
        else _truthy(payload.get("dryRun", payload.get("dry_run")))
    )
    allow_ecr_push = _truthy(payload.get("allowEcrPush", payload.get("allow_ecr_push")))
    if not SULU_IMAGE_BUILDER_PROJECT_NAME:
        raise ValueError("Sulu image builder is not configured")
    if len(SULU_ECR_REPOSITORIES) < 2:
        raise ValueError("Sulu ECR repositories are not configured")
    if not dry_run and not allow_ecr_push:
        raise ValueError("allowEcrPush=true is required when dryRun=false")

    existing_tags = {
        repository: _ecr_tag_exists(repository, image_tag)
        for repository in SULU_ECR_REPOSITORIES
    }
    result = {
        "status": "validated" if dry_run else "accepted",
        "service": "sulu",
        "imageTag": image_tag,
        "sourceVersion": source_version,
        "sourceRef": source_ref,
        "dryRun": dry_run,
        "applied": False,
        "projectName": SULU_IMAGE_BUILDER_PROJECT_NAME,
        "repositories": SULU_ECR_REPOSITORIES,
        "existingTags": existing_tags,
        "latestTagPreserved": True,
        "approvalEvidence": payload.get("approvalEvidence") or payload.get("approval_evidence"),
        "sourceGeneration": {
            "mode": "codebuild-target-version",
            "sourceVersion": source_version,
            "sourceRef": source_ref,
        },
    }
    if dry_run:
        result["canBuild"] = not any(existing_tags.values())
        return result
    if any(existing_tags.values()):
        existing = [f"{repository}:{image_tag}" for repository, exists in existing_tags.items() if exists]
        raise ValueError(f"new image tag already exists and will not be overwritten: {', '.join(existing)}")

    correlation_id = str(payload.get("correlationId") or payload.get("correlation_id") or "").strip()
    rfc_url = str(payload.get("rfcUrl") or payload.get("rfc_url") or "").strip()
    environment_overrides = [
        {"name": "SULU_IMAGE_TAG", "value": image_tag, "type": "PLAINTEXT"},
        {"name": "SULU_SOURCE_VERSION", "value": source_version, "type": "PLAINTEXT"},
        {"name": "SOURCE_REF", "value": source_ref, "type": "PLAINTEXT"},
        {"name": "ALLOW_TAG_OVERWRITE", "value": "false", "type": "PLAINTEXT"},
        {"name": "CORRELATION_ID", "value": correlation_id or "unassigned", "type": "PLAINTEXT"},
        {"name": "RFC_URL", "value": rfc_url or "unassigned", "type": "PLAINTEXT"},
    ]
    build = codebuild.start_build(
        projectName=SULU_IMAGE_BUILDER_PROJECT_NAME,
        environmentVariablesOverride=environment_overrides,
    ).get("build", {})
    build_id = build.get("id")
    if not build_id:
        raise RuntimeError("CodeBuild did not return a build id")
    result.update({
        "applied": True,
        "buildId": build_id,
        "buildArn": build.get("arn"),
        "buildStatus": build.get("buildStatus", "IN_PROGRESS"),
    })
    return result


def _sulu_image_build_status(build_id):
    build_id = str(build_id or "").strip()
    if not build_id:
        raise ValueError("build_id is required")
    response = codebuild.batch_get_builds(ids=[build_id])
    builds = response.get("builds", [])
    if not builds:
        raise ValueError(f"CodeBuild build not found: {build_id}")
    build = builds[0]
    status = build.get("buildStatus", "UNKNOWN")
    environment = {
        entry.get("name"): entry.get("value")
        for entry in build.get("environment", {}).get("environmentVariables", [])
        if entry.get("name") in {"SULU_IMAGE_TAG", "SULU_SOURCE_VERSION", "SOURCE_REF", "CORRELATION_ID", "RFC_URL"}
    }
    image_tag = environment.get("SULU_IMAGE_TAG")
    images = []
    if image_tag and status == "SUCCEEDED":
        images = [
            {"repository": repository, "imageTag": image_tag, "exists": _ecr_tag_exists(repository, image_tag)}
            for repository in SULU_ECR_REPOSITORIES
        ]
    return {
        "status": status,
        "buildId": build.get("id"),
        "buildArn": build.get("arn"),
        "projectName": build.get("projectName"),
        "startTime": build.get("startTime").isoformat() if build.get("startTime") else None,
        "endTime": build.get("endTime").isoformat() if build.get("endTime") else None,
        "currentPhase": build.get("currentPhase"),
        "phases": [
            {
                "phaseType": phase.get("phaseType"),
                "phaseStatus": phase.get("phaseStatus"),
                "contexts": phase.get("contexts", []),
            }
            for phase in build.get("phases", [])
        ],
        "logs": {
            "groupName": build.get("logs", {}).get("groupName"),
            "streamName": build.get("logs", {}).get("streamName"),
            "deepLink": build.get("logs", {}).get("deepLink"),
        },
        "request": environment,
        "images": images,
        "latestTagPreserved": True,
    }


def _schedule_parameter_name(service_key):
    return f"{SERVICE_CONTROL_SSM_PATH.rstrip('/')}/{service_key}/schedule"

DEFAULT_SCHEDULE = {
    "enabled": False,
    "start_time": "17:00",
    "stop_time": "22:00",
    "weekday_start_time": "17:00",
    "weekday_stop_time": "22:00",
    "holiday_start_time": "08:00",
    "holiday_stop_time": "23:00",
    "idle_minutes": 60,
}
TIME_PATTERN = re.compile(r"^\d{2}:\d{2}$")

def _validate_time(value):
    if not isinstance(value, str) or not TIME_PATTERN.match(value):
        raise ValueError("time must be in HH:MM format")

def _get_schedule(service_key):
    if not SERVICE_CONTROL_SSM_PATH:
        return dict(DEFAULT_SCHEDULE)
    try:
        resp = ssm.get_parameter(Name=_schedule_parameter_name(service_key))
        payload = json.loads(resp["Parameter"]["Value"])
        return {**DEFAULT_SCHEDULE, **payload}
    except ssm.exceptions.ParameterNotFound:
        return dict(DEFAULT_SCHEDULE)

def _put_schedule(service_key, schedule):
    if not SERVICE_CONTROL_SSM_PATH:
        return
    ssm.put_parameter(
        Name=_schedule_parameter_name(service_key),
        Value=json.dumps(schedule),
        Type="String",
        Overwrite=True,
    )

def _update_schedule(service_key, payload):
    schedule = _get_schedule(service_key)
    if "enabled" in payload:
        schedule["enabled"] = bool(payload["enabled"])
    for key in ["start_time", "stop_time", "weekday_start_time", "weekday_stop_time", "holiday_start_time", "holiday_stop_time"]:
        if key in payload and payload[key] is not None:
            _validate_time(payload[key])
            schedule[key] = payload[key]
    if "idle_minutes" in payload and payload["idle_minutes"] is not None:
        schedule["idle_minutes"] = int(payload["idle_minutes"])
    _put_schedule(service_key, schedule)
    return schedule


def handler(event, context):
    route = event.get("requestContext", {}).get("http", {}).get("path", "")
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    params = event.get("queryStringParameters") or {}
    service_key = params.get("service")
    realm = params.get("realm")

    if method == "OPTIONS":
        return _response(200, {"message": "ok"})

    try:
        print({"route": route, "method": method, "service_key": service_key, "realm": realm})
        if route.endswith("/keycloak-admin-credentials") and method == "GET":
            return _response(200, _get_keycloak_admin_credentials())
        if route.endswith("/odoo-admin-credentials") and method == "GET":
            return _response(200, _get_odoo_admin_credentials())
        if route.endswith("/pgadmin-admin-credentials") and method == "GET":
            return _response(200, _get_pgadmin_admin_credentials())
        protected_release_route = any(
            route.endswith(suffix) for suffix in ["/deploy", "/build", "/build-status"]
        )
        if protected_release_route and not _is_authorized(event):
            return _response(401, {"message": "unauthorized"})
        service_arn, resolved_realm = _get_service_arn(service_key, realm)
        if route.endswith("/status") and method == "GET":
            body = _describe(service_arn)
            body["resolvedRealm"] = resolved_realm or None
            tg_arn, _ = _get_target_group_arn(service_key, realm)
            if tg_arn:
                body["targetGroupHealth"] = _describe_tg_health(tg_arn)
            return _response(200, body)
        if route.endswith("/start") and method == "POST":
            body = _update(service_arn, START_DESIRED)
            body["resolvedRealm"] = resolved_realm or None
            return _response(200, body)
        if route.endswith("/stop") and method == "POST":
            body = _update(service_arn, 0)
            body["resolvedRealm"] = resolved_realm or None
            return _response(200, body)
        if route.endswith("/deploy") and method == "POST":
            if service_key != "sulu":
                raise ValueError("version deployment is supported only for service=sulu")
            payload = json.loads(event.get("body") or "{}")
            body = _deploy_sulu_version(service_arn, realm or resolved_realm, payload)
            body["resolvedRealm"] = resolved_realm or None
            return _response(200, body)
        if route.endswith("/build") and method == "POST":
            if service_key != "sulu":
                raise ValueError("image build is supported only for service=sulu")
            payload = json.loads(event.get("body") or "{}")
            dry_run = (
                True
                if payload.get("dryRun") is None and payload.get("dry_run") is None
                else _truthy(payload.get("dryRun", payload.get("dry_run")))
            )
            if not dry_run:
                payload["approvalEvidence"] = _verify_approval_signature("build", realm or resolved_realm, payload)
            body = _build_sulu_images(payload)
            body["resolvedRealm"] = resolved_realm or None
            return _response(200, body)
        if route.endswith("/build-status") and method == "GET":
            if service_key != "sulu":
                raise ValueError("image build status is supported only for service=sulu")
            return _response(200, _sulu_image_build_status(params.get("build_id") or params.get("buildId")))
        if route.endswith("/schedule"):
            if method == "GET":
                return _response(200, _get_schedule(service_key))
            if method == "POST":
                payload = json.loads(event.get("body") or "{}")
                return _response(200, _update_schedule(service_key, payload))
        return _response(404, {"message": "Not found"})
    except ValueError as exc:
        return _response(400, {"message": str(exc)})
    except Exception as exc:  # pylint: disable=broad-except
        # ここで何が起きたか分かるように詳細を返す
        print({"error": str(exc)})
        return _response(500, {"message": str(exc), "route": route, "service": service_key})
