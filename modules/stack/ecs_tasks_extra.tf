locals {
  zulip_error_log_shipper_snippet = <<-EOT
    set -euo pipefail

    log_file="/var/log/zulip/errors.log"
    log_dir="$(dirname "$${log_file}")"
    mkdir -p "$${log_dir}"
    chown zulip:zulip "$${log_dir}"
    touch "$${log_file}"
    chown zulip:zulip "$${log_file}"

    tail -n0 -F "$${log_file}" &
    tail_pid=$$!

    cleanup() {
      kill "$${tail_pid}" >/dev/null 2>&1 || true
    }

    trap cleanup EXIT
  EOT

  zulip_missing_dictionaries_snippet = <<-EOT
    crudini --set /etc/zulip/zulip.conf postgresql missing_dictionaries true
  EOT

  zulip_alb_oidc_header_login_snippet = <<-EOT
    cat > /etc/zulip/alb_oidc_auth.py <<'PY'
from __future__ import annotations

import base64
import json
import time
import urllib.request
from dataclasses import dataclass
from typing import Any, Optional

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa, utils
from django.conf import settings
from django.contrib.auth.backends import BaseBackend
from django.core.exceptions import PermissionDenied

from zerver.actions.create_user import do_create_user
from zerver.lib.email_validation import email_allowed_for_realm
from zerver.lib.subdomains import get_subdomain
from zerver.models import Realm, UserProfile
from zerver.models.realms import get_realm
from zerver.models.users import get_user_by_delivery_email


@dataclass(frozen=True)
class _CachedKey:
    key: Any
    fetched_at: float


_KEY_CACHE: dict[str, _CachedKey] = {}


def _b64url_decode(data: str) -> bytes:
    padded = data + ("=" * (-len(data) % 4))
    return base64.urlsafe_b64decode(padded.encode("ascii"))


def _jwt_parts(token: str) -> tuple[str, str, str]:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("JWT must have 3 parts")
    return parts[0], parts[1], parts[2]


def _fetch_alb_public_key_pem(region: str, kid: str) -> bytes:
    url = f"https://public-keys.auth.elb.{region}.amazonaws.com/{kid}"
    req = urllib.request.Request(url, headers={"User-Agent": "zulip-alb-oidc"})
    with urllib.request.urlopen(req, timeout=3) as resp:
        return resp.read()


def _get_public_key(region: str, kid: str) -> Any:
    ttl = getattr(settings, "ALB_OIDC_KEY_CACHE_SECONDS", 3600)
    now = time.time()
    cached = _KEY_CACHE.get(kid)
    if cached and (now - cached.fetched_at) < ttl:
        return cached.key

    pem = _fetch_alb_public_key_pem(region, kid)
    key = serialization.load_pem_public_key(pem)
    _KEY_CACHE[kid] = _CachedKey(key=key, fetched_at=now)
    return key


def _verify_jwt(token: str, region: str) -> dict[str, Any]:
    try:
        header_b64, payload_b64, sig_b64 = _jwt_parts(token)
    except Exception as e:
        raise PermissionDenied(f"Invalid JWT format: {e}")
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")

    try:
        header = json.loads(_b64url_decode(header_b64))
    except Exception as e:
        raise PermissionDenied(f"Invalid JWT header: {e}")

    kid = header.get("kid")
    alg = header.get("alg")
    if not isinstance(kid, str) or not kid:
        raise PermissionDenied("Missing kid in x-amzn-oidc-data")
    if alg not in ("ES256", "RS256"):
        raise PermissionDenied(f"Unsupported alg in x-amzn-oidc-data: {alg}")

    expected_signers = getattr(settings, "ALB_OIDC_EXPECTED_SIGNERS", None)
    signer = header.get("signer")
    if expected_signers:
        if not isinstance(signer, str) or signer not in expected_signers:
            raise PermissionDenied("ALB signer mismatch")

    try:
        claims = json.loads(_b64url_decode(payload_b64))
    except Exception as e:
        raise PermissionDenied(f"Invalid JWT payload: {e}")

    try:
        signature = _b64url_decode(sig_b64)
    except Exception as e:
        raise PermissionDenied(f"Invalid JWT signature encoding: {e}")

    public_key = _get_public_key(region, kid)

    try:
        if alg == "ES256":
            if len(signature) != 64:
                raise PermissionDenied("Invalid ES256 signature length")
            r = int.from_bytes(signature[:32], "big")
            s = int.from_bytes(signature[32:], "big")
            der_sig = utils.encode_dss_signature(r, s)
            if not isinstance(public_key, ec.EllipticCurvePublicKey):
                raise PermissionDenied("Public key type mismatch (expected EC)")
            public_key.verify(der_sig, signing_input, ec.ECDSA(hashes.SHA256()))
        elif alg == "RS256":
            if not isinstance(public_key, rsa.RSAPublicKey):
                raise PermissionDenied("Public key type mismatch (expected RSA)")
            public_key.verify(signature, signing_input, padding.PKCS1v15(), hashes.SHA256())
    except PermissionDenied:
        raise
    except Exception as e:
        raise PermissionDenied(f"JWT signature verification failed: {e}")

    leeway = getattr(settings, "ALB_OIDC_TIME_LEEWAY_SECONDS", 60)
    exp = claims.get("exp")
    if exp is not None:
        try:
            exp_ts = float(exp)
        except Exception:
            raise PermissionDenied("Invalid exp claim")
        if time.time() > (exp_ts + float(leeway)):
            raise PermissionDenied("Token expired")

    return claims


def _pick_email(claims: dict[str, Any]) -> Optional[str]:
    claim_keys = getattr(settings, "ALB_OIDC_EMAIL_CLAIMS", ["email", "preferred_username", "upn"])
    for key in claim_keys:
        v = claims.get(key)
        if isinstance(v, str) and "@" in v:
            return v.strip().lower()
    return None


def _display_name(claims: dict[str, Any], email: str) -> str:
    for key in ("name", "given_name"):
        v = claims.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return email.split("@", 1)[0]


class ALBOIDCHeaderAuthBackend(BaseBackend):
    def authenticate(self, request, **kwargs) -> Optional[UserProfile]:
        if request is None:
            return None

        token = request.META.get("HTTP_X_AMZN_OIDC_DATA")
        if not token:
            return None

        region = getattr(settings, "ALB_OIDC_AWS_REGION", None)
        if not isinstance(region, str) or not region:
            raise PermissionDenied("ALB_OIDC_AWS_REGION is not set")

        claims = _verify_jwt(token, region)

        email = _pick_email(claims)
        if not email:
            raise PermissionDenied("No usable email claim found in x-amzn-oidc-data")

        subdomain = get_subdomain(request)
        if not subdomain:
            return None

        try:
            realm: Realm = get_realm(subdomain)
        except Exception:
            return None

        try:
            email_allowed_for_realm(email, realm)
        except Exception:
            raise PermissionDenied("Email not allowed for this Zulip organization")

        try:
            return get_user_by_delivery_email(email, realm)
        except Exception:
            pass

        if getattr(settings, "ALB_OIDC_AUTO_CREATE_USERS", False):
            full_name = _display_name(claims, email)
            return do_create_user(email=email, password=None, realm=realm, full_name=full_name, acting_user=None)

        return None

    def get_user(self, user_id: int) -> Optional[UserProfile]:
        try:
            return UserProfile.objects.get(id=user_id)
        except Exception:
            return None
PY

    cat > /etc/zulip/alb_oidc_middleware.py <<'PY'
from __future__ import annotations

from django.contrib.auth import authenticate, login
from django.utils.deprecation import MiddlewareMixin


class ALBOIDCLoginMiddleware(MiddlewareMixin):
    def process_request(self, request):
        if getattr(request, "user", None) is not None and request.user.is_authenticated:
            return None

        if "HTTP_X_AMZN_OIDC_DATA" not in request.META:
            return None

        user = authenticate(request)
        if user is not None:
            login(request, user)
            return None
PY

    cat > /etc/zulip/alb_oidc_django_settings.py <<'PY'
from __future__ import annotations

import os
from typing import List


def _env_bool(key: str, default: bool) -> bool:
    v = os.environ.get(key)
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def _env_int(key: str, default: int) -> int:
    v = os.environ.get(key)
    if not v:
        return default
    try:
        return int(v)
    except Exception:
        return default


def _env_list(key: str, default: List[str]) -> List[str]:
    v = os.environ.get(key)
    if not v:
        return default
    return [s.strip() for s in v.split(",") if s.strip()]


from zproject.settings import *  # type: ignore  # noqa: F401,F403

middleware = "alb_oidc_middleware.ALBOIDCLoginMiddleware"
mw = list(MIDDLEWARE)
if middleware not in mw:
    try:
        idx = mw.index("django.contrib.auth.middleware.AuthenticationMiddleware")
        mw.insert(idx + 1, middleware)
    except ValueError:
        mw.append(middleware)
MIDDLEWARE = mw

backend = "alb_oidc_auth.ALBOIDCHeaderAuthBackend"
if backend not in AUTHENTICATION_BACKENDS:
    AUTHENTICATION_BACKENDS = (backend, *AUTHENTICATION_BACKENDS)

ALB_OIDC_AWS_REGION = os.environ.get("ALB_OIDC_AWS_REGION", "ap-northeast-1")
ALB_OIDC_KEY_CACHE_SECONDS = _env_int("ALB_OIDC_KEY_CACHE_SECONDS", 3600)
ALB_OIDC_TIME_LEEWAY_SECONDS = _env_int("ALB_OIDC_TIME_LEEWAY_SECONDS", 60)
ALB_OIDC_EMAIL_CLAIMS = _env_list("ALB_OIDC_EMAIL_CLAIMS", ["email", "preferred_username", "upn"])
ALB_OIDC_EXPECTED_SIGNERS = _env_list("ALB_OIDC_EXPECTED_SIGNERS", [])
ALB_OIDC_AUTO_CREATE_USERS = _env_bool("ALB_OIDC_AUTO_CREATE_USERS", False)
PY

    chmod 0644 /etc/zulip/alb_oidc_auth.py /etc/zulip/alb_oidc_middleware.py /etc/zulip/alb_oidc_django_settings.py

    if [ -z "$${ALB_OIDC_AWS_REGION:-}" ]; then
      export ALB_OIDC_AWS_REGION="${var.region}"
    fi
    if [ -z "$${ALB_OIDC_EXPECTED_SIGNERS:-}" ]; then
      export ALB_OIDC_EXPECTED_SIGNERS="${aws_lb.app[0].arn}"
    fi
    if [ -z "$${ALB_OIDC_KEY_CACHE_SECONDS:-}" ]; then
      export ALB_OIDC_KEY_CACHE_SECONDS="3600"
    fi
    if [ -z "$${ALB_OIDC_TIME_LEEWAY_SECONDS:-}" ]; then
      export ALB_OIDC_TIME_LEEWAY_SECONDS="60"
    fi
    if [ -z "$${ALB_OIDC_EMAIL_CLAIMS:-}" ]; then
      export ALB_OIDC_EMAIL_CLAIMS="email,preferred_username,upn"
    fi
    if [ -z "$${ALB_OIDC_AUTO_CREATE_USERS:-}" ]; then
      export ALB_OIDC_AUTO_CREATE_USERS="false"
    fi

    if [ -n "$${PYTHONPATH:-}" ]; then
      export PYTHONPATH="/etc/zulip:$${PYTHONPATH}"
    else
      export PYTHONPATH="/etc/zulip"
    fi

    if [ -z "$${DJANGO_SETTINGS_MODULE:-}" ]; then
      export DJANGO_SETTINGS_MODULE="alb_oidc_django_settings"
    fi
  EOT

  zulip_trusted_proxy_cidrs_input = coalesce(var.zulip_trusted_proxy_cidrs, [])
  zulip_trusted_proxy_cidrs       = length(local.zulip_trusted_proxy_cidrs_input) > 0 ? local.zulip_trusted_proxy_cidrs_input : [for s in local.public_subnets : s.cidr]
  zulip_loadbalancer_ips          = join(",", local.zulip_trusted_proxy_cidrs)
  zulip_trust_proxies_snippet     = <<-EOT
    crudini --set /etc/zulip/zulip.conf loadbalancer ips "${local.zulip_loadbalancer_ips}"
  EOT
  zulip_entrypoint_command = join("\n", compact([
    trimspace(local.zulip_error_log_shipper_snippet),
    trimspace(local.zulip_trust_proxies_snippet),
    var.enable_zulip_alb_oidc ? trimspace(local.zulip_alb_oidc_header_login_snippet) : "",
    var.zulip_missing_dictionaries ? trimspace(local.zulip_missing_dictionaries_snippet) : "",
    "exec /sbin/entrypoint.sh app:run"
  ]))
}

/*
resource "aws_ecs_task_definition" "knowledge" {
  count = var.create_ecs && var.create_growi ? 1 : 0

  family                   = "${local.name_prefix}-knowledge"
  cpu                      = coalesce(var.growi_task_cpu, var.ecs_task_cpu)
  memory                   = coalesce(var.growi_task_memory, var.ecs_task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.knowledge_efs_id != null ? [1] : []
    content {
      name = "knowledge-data"
      efs_volume_configuration {
        file_system_id     = local.knowledge_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    local.knowledge_efs_id != null ? [
      merge(local.ecs_base_container, {
        name       = "knowledge-fs-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            mkdir -p "${var.knowledge_filesystem_path}/uploads"
            chown -R 1000:1000 "${var.knowledge_filesystem_path}"
          EOT
        ]
        mountPoints = [{
          sourceVolume  = "knowledge-data"
          containerPath = var.knowledge_filesystem_path
          readOnly      = false
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "knowledge--knowledge-fs-init", aws_cloudwatch_log_group.ecs["knowledge"].name)
          })
        })
      })
    ] : [],
    !var.create_growi_docdb ? [
      merge(local.ecs_base_container, {
        name       = "knowledge-mongodb"
        image      = local.mongo_image
        user       = "0:0"
        entryPoint = ["sh", "-lc"]
        command = [
          <<-EOT
              set -eu
              mkdir -p "${var.knowledge_filesystem_path}/mongodb"
              rm -f /tmp/mongod.lock
              exec mongod --dbpath "${var.knowledge_filesystem_path}/mongodb" --bind_ip_all --lockFile /tmp/mongod.lock
            EOT
        ]
        portMappings = [{
          containerPort = 27017
          hostPort      = 27017
          protocol      = "tcp"
        }]
        mountPoints = local.knowledge_efs_id != null ? [{
          sourceVolume  = "knowledge-data"
          containerPath = var.knowledge_filesystem_path
          readOnly      = false
        }] : []
        dependsOn = local.knowledge_efs_id != null ? [
          {
            containerName = "knowledge-fs-init"
            condition     = "COMPLETE"
          }
        ] : []
        healthCheck = {
          command     = ["CMD-SHELL", "mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' | grep -q 1"]
          interval    = 10
          timeout     = 5
          retries     = 10
          startPeriod = 30
        }
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "knowledge--knowledge-mongodb", aws_cloudwatch_log_group.ecs["knowledge"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name      = "knowledge-redis"
        image     = local.redis_image
        essential = true
        portMappings = [{
          containerPort = 6379
          hostPort      = 6379
          protocol      = "tcp"
        }]
        healthCheck = {
          command     = ["CMD-SHELL", "redis-cli ping | grep PONG"]
          interval    = 10
          timeout     = 5
          retries     = 5
          startPeriod = 10
        }
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group"         = lookup(local.ecs_log_group_name_by_container, "knowledge--knowledge-redis", aws_cloudwatch_log_group.ecs["knowledge"].name)
            "awslogs-stream-prefix" = "redis"
          })
        })
      })
    ],
    var.enable_growi_keycloak ? [
      merge(local.ecs_base_container, {
        name       = "knowledge-oidc-config-init"
        image      = local.ecr_uri_knowledge
        essential  = false
        user       = "0:0"
        entryPoint = ["sh", "-lc"]
        command = [
          <<-EOT
		            set -eu
		            cd /opt/knowledge/apps/app
		            node <<'NODE'
	            const mongoose = require('mongoose');

	            const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
	            const required = (name) => {
	              const value = process.env[name];
	              if (value == null || value === '') {
	                throw new Error(`Missing env var: $${name}`);
	              }
	              return value;
	            };

	            const mongoUri = required('MONGO_URI');
	            const issuerHost = process.env.OIDC_ISSUER || process.env.OIDC_ISSUER_HOST || process.env.OIDC_ISSUER_URL;
	            if (issuerHost == null || issuerHost === '') {
	              throw new Error('Missing env var: OIDC_ISSUER');
	            }
	            const clientId = required('OIDC_CLIENT_ID');
	            const clientSecret = required('OIDC_CLIENT_SECRET');

	            const desiredConfigs = new Map([
	              ['security:passport-oidc:isEnabled', true],
	              ['security:passport-oidc:issuerHost', issuerHost],
	              ['security:passport-oidc:clientId', clientId],
	              ['security:passport-oidc:clientSecret', clientSecret],
	            ]);

	            const endpointMappings = [
	              ['OIDC_AUTHORIZATION_ENDPOINT', 'security:passport-oidc:authorizationEndpoint'],
	              ['OIDC_TOKEN_ENDPOINT', 'security:passport-oidc:tokenEndpoint'],
	              ['OIDC_USERINFO_ENDPOINT', 'security:passport-oidc:userInfoEndpoint'],
	            ];
	            for (const [envName, configKey] of endpointMappings) {
	              const value = process.env[envName];
	              if (value != null && value !== '') {
	                desiredConfigs.set(configKey, value);
	              }
	            }

	            const connectWithRetry = async (maxAttempts) => {
	              let lastError;
	              for (let attempt = 1; attempt <= maxAttempts; attempt++) {
	                try {
	                  await mongoose.connect(mongoUri, {
	                    serverSelectionTimeoutMS: 10000,
	                    socketTimeoutMS: 10000,
	                  });
	                  return;
	                }
	                catch (err) {
	                  lastError = err;
	                  await sleep(2000);
	                }
	              }
	              throw lastError;
	            };

	            (async () => {
	              await connectWithRetry(30);
	              const collection = mongoose.connection.collection('configs');

	              for (const [key, value] of desiredConfigs.entries()) {
	                await collection.updateOne(
	                  { key },
	                  { $set: { key, value: JSON.stringify(value) } },
	                  { upsert: true },
	                );
	              }

	              await mongoose.disconnect();
	            })().catch((err) => {
		              console.error('[knowledge-oidc-config-init] failed:', err);
		              process.exit(1);
		            });
		            NODE
		          EOT
        ]
        environment = [for k, v in merge(local.default_environment_knowledge, coalesce(var.knowledge_environment, {}), local.knowledge_keycloak_environment) : { name = k, value = v }]
        secrets = concat(
          var.knowledge_secrets,
          [for k, v in local.ssm_param_arns_knowledge : { name = k, valueFrom = v }],
          [for k, v in local.ssm_param_arns_knowledge_oidc : { name = k, valueFrom = v }]
        )
        dependsOn = concat(
          local.knowledge_efs_id != null ? [
            {
              containerName = "knowledge-fs-init"
              condition     = "COMPLETE"
            }
          ] : [],
          !var.create_growi_docdb ? [
            {
              containerName = "knowledge-mongodb"
              condition     = "HEALTHY"
            }
          ] : [],
          [
            {
              containerName = "knowledge-redis"
              condition     = "HEALTHY"
            }
          ]
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group"         = lookup(local.ecs_log_group_name_by_container, "knowledge--knowledge-oidc-config-init", aws_cloudwatch_log_group.ecs["knowledge"].name)
            "awslogs-stream-prefix" = "oidc-init"
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name  = "knowledge"
        image = local.ecr_uri_knowledge
        user  = "0:0"
        portMappings = [{
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }]
        environment = [for k, v in merge(local.default_environment_knowledge, coalesce(var.knowledge_environment, {}), local.knowledge_keycloak_environment) : { name = k, value = v }]
        secrets = concat(
          var.knowledge_secrets,
          [for k, v in local.ssm_param_arns_knowledge : { name = k, valueFrom = v }],
          var.enable_growi_keycloak ? [for k, v in local.ssm_param_arns_knowledge_oidc : { name = k, valueFrom = v }] : []
        )
        mountPoints = local.knowledge_efs_id != null ? [{
          sourceVolume  = "knowledge-data"
          containerPath = var.knowledge_filesystem_path
          readOnly      = false
        }] : []
        dependsOn = concat(
          local.knowledge_efs_id != null ? [
            {
              containerName = "knowledge-fs-init"
              condition     = "COMPLETE"
            }
          ] : [],
          !var.create_growi_docdb ? [
            {
              containerName = "knowledge-mongodb"
              condition     = "HEALTHY"
            }
          ] : [],
          var.enable_growi_keycloak ? [
            {
              containerName = "knowledge-oidc-config-init"
              condition     = "COMPLETE"
            }
          ] : [],
          [
            {
              containerName = "knowledge-redis"
              condition     = "HEALTHY"
            }
          ]
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "knowledge--knowledge", aws_cloudwatch_log_group.ecs["knowledge"].name)
          })
        })
      })
    ]
  ))

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-knowledge-td" })
}

*/
resource "aws_ecs_task_definition" "zulip" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  family                   = "${local.name_prefix}-zulip"
  cpu                      = coalesce(var.zulip_task_cpu, var.ecs_task_cpu)
  memory                   = coalesce(var.zulip_task_memory, var.ecs_task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.zulip_efs_id != null ? [1] : []
    content {
      name = "zulip-data"
      efs_volume_configuration {
        file_system_id     = local.zulip_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    local.zulip_efs_id != null ? [
      merge(local.ecs_base_container, {
        name       = "zulip-fs-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            mkdir -p "${var.zulip_filesystem_path}"
            chown -R 1000:1000 "${var.zulip_filesystem_path}"
          EOT
        ]
        mountPoints = [{
          sourceVolume  = "zulip-data"
          containerPath = var.zulip_filesystem_path
          readOnly      = false
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "zulip--zulip-fs-init", aws_cloudwatch_log_group.ecs["zulip"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name       = "zulip-db-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            apk add --no-cache postgresql15-client >/dev/null

            db_host="$${DB_HOST:-}"
            db_port="$${DB_PORT:-5432}"
            db_user="$${DB_USER:-}"
            db_pass="$${DB_PASSWORD:-}"
            db_name="$${DB_NAME:-zulip}"

            if [ -z "$${db_host}" ] || [ -z "$${db_user}" ] || [ -z "$${db_pass}" ] || [ -z "$${db_name}" ]; then
              echo "Database variables are incomplete."
              exit 1
            fi

            select_sql="SELECT 1 FROM pg_database WHERE datname = '$${db_name}'"
            create_sql="CREATE DATABASE \"$${db_name}\" OWNER \"$${db_user}\";"
            schema_check_sql="SELECT 1 FROM pg_namespace WHERE nspname = 'zulip';"
            create_schema_sql="CREATE SCHEMA IF NOT EXISTS zulip AUTHORIZATION \"$${db_user}\";"
            set_search_path_sql="ALTER ROLE \"$${db_user}\" SET search_path TO zulip,public;"

            export PGPASSWORD="$${db_pass}"
            until pg_isready -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" >/dev/null 2>&1; do
              sleep 3
            done

            db_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -Atc "$${select_sql}" || true)"
            if [ "$${db_exists}" != "1" ]; then
              psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -c "$${create_sql}"
            fi

            schema_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d "$${db_name}" -Atc "$${schema_check_sql}" || true)"
            if [ "$${schema_exists}" != "1" ]; then
              psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d "$${db_name}" -c "$${create_schema_sql}"
            fi
            psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d "$${db_name}" -c "$${set_search_path_sql}"
          EOT
        ]
        secrets = [for k, v in local.ssm_param_arns_zulip : { name = k, valueFrom = v }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "zulip--zulip-db-init", aws_cloudwatch_log_group.ecs["zulip"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name  = "zulip-memcached"
        image = local.memcached_image
        portMappings = [{
          containerPort = 11211
          hostPort      = 11211
          protocol      = "tcp"
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "zulip--zulip-memcached", aws_cloudwatch_log_group.ecs["zulip"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name       = "zulip-redis"
        image      = local.redis_image
        entryPoint = ["sh", "-lc"]
        command = [
          <<-EOT
            set -eu

            if [ -z "$${REDIS_PASSWORD:-}" ]; then
              echo "REDIS_PASSWORD is not set" >&2
              exit 1
            fi

            exec redis-server --save "" --appendonly no --requirepass "$${REDIS_PASSWORD}"
          EOT
        ]
        secrets = [{
          name      = "REDIS_PASSWORD"
          valueFrom = local.ssm_param_arns_zulip["SECRETS_redis_password"]
        }]
        portMappings = [{
          containerPort = 6379
          hostPort      = 6379
          protocol      = "tcp"
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "zulip--zulip-redis", aws_cloudwatch_log_group.ecs["zulip"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name  = "zulip-rabbitmq"
        image = local.rabbitmq_image
        portMappings = [{
          containerPort = 5672
          hostPort      = 5672
          protocol      = "tcp"
        }]
        environment = [{
          name  = "RABBITMQ_DEFAULT_VHOST"
          value = "/"
        }]
        secrets = concat(
          contains(keys(local.ssm_param_arns_zulip), "RABBITMQ_USERNAME") ? [{
            name      = "RABBITMQ_DEFAULT_USER"
            valueFrom = local.ssm_param_arns_zulip["RABBITMQ_USERNAME"]
          }] : [],
          contains(keys(local.ssm_param_arns_zulip), "RABBITMQ_PASSWORD") ? [{
            name      = "RABBITMQ_DEFAULT_PASS"
            valueFrom = local.ssm_param_arns_zulip["RABBITMQ_PASSWORD"]
          }] : []
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "zulip--zulip-rabbitmq", aws_cloudwatch_log_group.ecs["zulip"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name  = "zulip"
        image = local.ecr_uri_zulip
        portMappings = [{
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }]
        environment = [for k, v in merge(local.default_environment_zulip, var.zulip_environment) : { name = k, value = v }]
        secrets = concat(
          var.zulip_secrets,
          [for k, v in local.ssm_param_arns_zulip : { name = k, valueFrom = v }]
        )
        mountPoints = local.zulip_efs_id != null ? [{
          sourceVolume  = "zulip-data"
          containerPath = var.zulip_filesystem_path
          readOnly      = false
        }] : []
        dependsOn = concat(
          local.zulip_efs_id != null ? [
            {
              containerName = "zulip-fs-init"
              condition     = "COMPLETE"
            }
          ] : [],
          [
            {
              containerName = "zulip-db-init"
              condition     = "COMPLETE"
            },
            {
              containerName = "zulip-memcached"
              condition     = "START"
            },
            {
              containerName = "zulip-redis"
              condition     = "START"
            },
            {
              containerName = "zulip-rabbitmq"
              condition     = "START"
            }
          ]
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "zulip--zulip", aws_cloudwatch_log_group.ecs["zulip"].name)
          })
        })
        entryPoint = ["/bin/bash", "-c"]
        command    = [local.zulip_entrypoint_command]
      })
    ],
  ))

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-td" })
}
