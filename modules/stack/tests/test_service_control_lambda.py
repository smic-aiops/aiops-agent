#!/usr/bin/env python3
"""Unit OQ for the guarded Sulu build/deploy control plane."""

import datetime
import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import sys
import types
import unittest


ROOT = Path(__file__).resolve().parents[3]
LAMBDA_SOURCE = ROOT / "modules/stack/templates/service_control_lambda.py"
DEPLOY_WORKFLOW = ROOT / "apps/workflow_manager/service_request/workflows/aiops_sulu_version_deploy.json"


class ImageNotFoundException(Exception):
    """Fake ECR exception."""


class RepositoryNotFoundException(Exception):
    """Fake ECR exception."""


class ParameterNotFound(Exception):
    """Fake SSM exception."""


class FakeClient:
    def __init__(self):
        self.exceptions = types.SimpleNamespace(
            ImageNotFoundException=ImageNotFoundException,
            RepositoryNotFoundException=RepositoryNotFoundException,
            ParameterNotFound=ParameterNotFound,
        )


CLIENTS = {name: FakeClient() for name in ["ecs", "elbv2", "ecr", "codebuild", "ssm"]}
fake_boto3 = types.ModuleType("boto3")
fake_boto3.client = lambda name: CLIENTS[name]
sys.modules.setdefault("boto3", fake_boto3)

os.environ.update(
    {
        "CLUSTER_ARN": "arn:aws:ecs:ap-northeast-1:111111111111:cluster/test",
        "SERVICE_ARNS": json.dumps({"sulu": {"aiops": "arn:aws:ecs:ap-northeast-1:111111111111:service/test/sulu"}}),
        "TARGET_GROUP_ARNS": "{}",
        "SULU_IMAGE_BUILDER_PROJECT_NAME": "test-sulu-builder",
        "SULU_ECR_REPOSITORIES": json.dumps(["test/sulu", "test/sulu-nginx"]),
        "SERVICE_CONTROL_AUTH_TOKEN_SSM_PARAMETER": "/test/workflows-token",
    }
)

spec = importlib.util.spec_from_file_location("service_control_lambda_under_test", LAMBDA_SOURCE)
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)


class ServiceControlReleaseGuardsTest(unittest.TestCase):
    def setUp(self):
        service._SERVICE_CONTROL_AUTH_TOKEN = "oq-secret"
        service.ecs = FakeClient()
        service.ecr = FakeClient()
        service.codebuild = FakeClient()

    def test_unauthenticated_build_is_rejected(self):
        event = {
            "requestContext": {"http": {"path": "/build", "method": "POST"}},
            "queryStringParameters": {"service": "sulu", "realm": "aiops"},
            "headers": {},
            "body": json.dumps({"imageTag": "oq-new", "dryRun": True}),
        }
        response = service.handler(event, None)
        self.assertEqual(response["statusCode"], 401)

    def test_latest_and_invalid_tags_are_rejected(self):
        for value in ["latest", "../tag", "-tag", ""]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                service._validate_image_tag(value)

    def test_execution_flags_are_required(self):
        with self.assertRaisesRegex(ValueError, "allowEcrPush"):
            service._build_sulu_images({"imageTag": "oq-new", "dryRun": False})
        with self.assertRaisesRegex(ValueError, "allowServiceChange"):
            service._deploy_sulu_version("service", "aiops", {"imageTag": "oq-new", "dryRun": False})

    def test_existing_tag_in_either_repository_blocks_overwrite(self):
        existing = {"test/sulu": True, "test/sulu-nginx": False}
        service._ecr_tag_exists = lambda repository, image_tag: existing[repository]
        with self.assertRaisesRegex(ValueError, "will not be overwritten"):
            service._build_sulu_images(
                {"imageTag": "oq-existing", "dryRun": False, "allowEcrPush": True}
            )

    def test_partial_php_nginx_task_definition_is_rejected(self):
        service.ecs.describe_services = lambda **kwargs: {
            "services": [{"taskDefinition": "td:1", "desiredCount": 1}]
        }
        service.ecs.describe_task_definition = lambda **kwargs: {
            "taskDefinition": {
                "family": "sulu",
                "containerDefinitions": [
                    {
                        "name": "php-fpm-aiops",
                        "image": "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/test/sulu:old",
                    }
                ],
            }
        }
        with self.assertRaisesRegex(ValueError, "were not both found"):
            service._build_sulu_task_definition_plan("service", "oq-new")

    def test_cab_signature_binds_change_and_target(self):
        evidence = {
            "changeId": "RFC-123",
            "issueUrl": "https://gitlab.example/group/project/-/issues/123",
            "approvedAt": "2026-07-17T00:00:00Z",
            "approvedBy": "cab-user",
        }
        payload = {"imageTag": "oq-new", "approvalEvidence": evidence}
        canonical = "\n".join(
            ["build", "aiops", "oq-new", "RFC-123", evidence["issueUrl"], evidence["approvedAt"], "cab-user"]
        )
        payload["approvalSignature"] = hmac.new(
            b"oq-secret", canonical.encode("utf-8"), hashlib.sha256
        ).hexdigest()
        self.assertEqual(service._verify_approval_signature("build", "aiops", payload), evidence)
        payload["imageTag"] = "tampered"
        with self.assertRaisesRegex(ValueError, "signature is invalid"):
            service._verify_approval_signature("build", "aiops", payload)

    def test_build_source_is_generated_for_requested_version(self):
        service._ecr_tag_exists = lambda repository, image_tag: False
        requests = []

        def start_build(**kwargs):
            requests.append(kwargs)
            return {"build": {"id": "build:1", "arn": "arn:build:1", "buildStatus": "IN_PROGRESS"}}

        service.codebuild.start_build = start_build
        result = service._build_sulu_images(
            {
                "imageTag": "oq-generated",
                "sourceVersion": "3.0.4",
                "sourceRef": "agent/complete-aiops-itsm-validation",
                "dryRun": False,
                "allowEcrPush": True,
            }
        )
        overrides = {
            item["name"]: item["value"]
            for item in requests[0]["environmentVariablesOverride"]
        }
        self.assertEqual(result["sourceGeneration"]["mode"], "codebuild-target-version")
        self.assertEqual(result["sourceVersion"], "3.0.4")
        self.assertEqual(overrides["SULU_SOURCE_VERSION"], "3.0.4")
        self.assertEqual(overrides["SOURCE_REF"], "agent/complete-aiops-itsm-validation")
        self.assertEqual(overrides["ALLOW_TAG_OVERWRITE"], "false")

    def test_failed_and_timed_out_codebuild_are_reported(self):
        for build_status in ["FAILED", "TIMED_OUT"]:
            with self.subTest(build_status=build_status):
                service.codebuild.batch_get_builds = lambda **kwargs: {
                    "builds": [
                        {
                            "id": "build:1",
                            "buildStatus": build_status,
                            "projectName": "test-sulu-builder",
                            "startTime": datetime.datetime(2026, 7, 17, tzinfo=datetime.timezone.utc),
                            "environment": {"environmentVariables": []},
                        }
                    ]
                }
                self.assertEqual(service._sulu_image_build_status("build:1")["status"], build_status)

    def test_workflow_detects_rollout_failure_timeout_and_unhealthy_targets(self):
        workflow = json.loads(DEPLOY_WORKFLOW.read_text(encoding="utf-8"))
        verification = next(node for node in workflow["nodes"] if node["name"] == "Verify Version Deployment")
        code = verification["parameters"]["jsCode"]
        self.assertIn("rolloutState === 'FAILED'", code)
        self.assertIn("Timed out waiting for Sulu", code)
        self.assertIn("Number(health.unhealthy ?? 0) === 0", code)
        self.assertIn("Number(health.healthy ?? 0) >= 1", code)


if __name__ == "__main__":
    unittest.main(verbosity=2)
