locals {
  gitlab_efs_indexer_enabled = (
    var.create_ecs
    && var.create_n8n
    && var.enable_gitlab_efs_indexer
    && local.n8n_efs_id != null
    && local.n8n_qdrant_enabled
  )

  openai_model_api_key_param_name_for_indexer = coalesce(
    lookup(local.openai_model_api_key_parameter_names_by_realm, local.n8n_primary_realm, null),
    local.openai_model_api_key_parameter_name
  )
  openai_model_api_key_param_name_for_indexer_normalized = (
    startswith(local.openai_model_api_key_param_name_for_indexer, "/")
    ? local.openai_model_api_key_param_name_for_indexer
    : "/${local.openai_model_api_key_param_name_for_indexer}"
  )
  openai_model_api_key_param_arn = format(
    "arn:aws:ssm:%s:%s:parameter%s",
    var.region,
    local.account_id,
    local.openai_model_api_key_param_name_for_indexer_normalized
  )
  gitlab_efs_indexer_log_group = local.gitlab_efs_indexer_enabled ? aws_cloudwatch_log_group.ecs["n8n"].name : null
  gitlab_efs_indexer_openai_base_url = coalesce(
    lookup(local.openai_base_url_by_realm_effective, local.n8n_primary_realm, null),
    "https://api.openai.com"
  )

  gitlab_efs_indexer_state_machine_definition = local.gitlab_efs_indexer_enabled ? jsonencode({
    Comment = "Looped GitLab EFS -> Qdrant indexer runner (per realm, sequential)"
    StartAt = "Init"
    States = {
      Init = {
        Type = "Pass"
        Result = {
          realms           = local.n8n_realms
          interval_seconds = var.gitlab_efs_indexer_interval_seconds
        }
        ResultPath = "$"
        Next       = "IndexAllRealms"
      }
      IndexAllRealms = {
        Type           = "Map"
        ItemsPath      = "$.realms"
        MaxConcurrency = 1
        ItemSelector = {
          "realm.$" = "$$.Map.Item.Value"
        }
        Iterator = {
          StartAt = "RunIndexerTask"
          States = {
            RunIndexerTask = {
              Type     = "Task"
              Resource = "arn:aws:states:::ecs:runTask.sync"
              Parameters = {
                Cluster        = try(aws_ecs_cluster.this[0].arn, null)
                TaskDefinition = try(aws_ecs_task_definition.gitlab_efs_indexer[0].arn, null)
                LaunchType     = "FARGATE"
                NetworkConfiguration = {
                  AwsvpcConfiguration = {
                    Subnets        = [local.service_subnet_id]
                    SecurityGroups = [try(aws_security_group.ecs_service[0].id, null)]
                    AssignPublicIp = "DISABLED"
                  }
                }
                Overrides = {
                  ContainerOverrides = [
                    {
                      Name = "gitlab-indexer"
                      Environment = [
                        { Name = "REALM", "Value.$" = "$.realm" }
                      ]
                    }
                  ]
                }
              }
              End = true
            }
          }
        }
        ResultPath = "$.last_run"
        Next       = "WaitInterval"
      }
      WaitInterval = {
        Type        = "Wait"
        SecondsPath = "$.interval_seconds"
        Next        = "IndexAllRealms"
      }
    }
  }) : null
}

resource "aws_ecs_task_definition" "gitlab_efs_indexer" {
  count = local.gitlab_efs_indexer_enabled ? 1 : 0

  family                   = "${local.name_prefix}-gitlab-efs-indexer"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  volume {
    name = "n8n-data"
    efs_volume_configuration {
      file_system_id     = local.n8n_efs_id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = null
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "gitlab-indexer"
      image     = local.python_image
      essential = true
      entryPoint = [
        "/bin/sh",
        "-c"
      ]
      environment = [
        { name = "N8N_FILESYSTEM_PATH", value = var.n8n_filesystem_path },
        { name = "HOSTED_ZONE_NAME", value = local.hosted_zone_name_input },
        { name = "QDRANT_SUBDOMAIN", value = local.qdrant_subdomain },
        { name = "QDRANT_COLLECTION_ALIAS", value = var.gitlab_efs_indexer_collection_alias },
        { name = "QDRANT_COLLECTION_ALIAS_MAP_JSON", value = jsonencode(var.gitlab_efs_indexer_collection_alias_map) },
        { name = "OPENAI_BASE_URL", value = local.gitlab_efs_indexer_openai_base_url },
        { name = "OPENAI_EMBEDDING_MODEL", value = var.gitlab_efs_indexer_embedding_model },
        { name = "INCLUDE_EXTS", value = join(" ", var.gitlab_efs_indexer_include_extensions) },
        { name = "MAX_FILE_BYTES", value = tostring(var.gitlab_efs_indexer_max_file_bytes) },
        { name = "CHUNK_SIZE_CHARS", value = tostring(var.gitlab_efs_indexer_chunk_size_chars) },
        { name = "CHUNK_OVERLAP_CHARS", value = tostring(var.gitlab_efs_indexer_chunk_overlap_chars) },
        { name = "POINTS_BATCH_SIZE", value = tostring(var.gitlab_efs_indexer_points_batch_size) },
        { name = "DRY_RUN", value = "false" }
      ]
      secrets = [
        { name = "OPENAI_API_KEY", valueFrom = local.openai_model_api_key_param_arn }
      ]
      mountPoints = [
        {
          sourceVolume  = "n8n-data"
          containerPath = var.n8n_filesystem_path
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.gitlab_efs_indexer_log_group
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
      command = [
        <<-EOT
set -euo pipefail

apk add --no-cache ca-certificates git >/dev/null
update-ca-certificates >/dev/null 2>&1 || true

python - <<'PY'
import hashlib
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Tuple


def env(name: str, default: Optional[str] = None) -> str:
  value = os.environ.get(name)
  if value is None or value == "":
    if default is None:
      raise RuntimeError(f"Missing required env: {name}")
    return default
  return value


def env_int(name: str, default: int) -> int:
  raw = os.environ.get(name)
  if raw is None or raw == "":
    return default
  return int(raw)


def run_git(args: List[str], *, git_dir: str, timeout: int = 60) -> str:
  cmd = ["git", f"--git-dir={git_dir}"] + args
  proc = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
  return proc.stdout.strip()


def http_json(method: str, url: str, payload: Optional[Dict[str, Any]] = None, headers: Optional[Dict[str, str]] = None, timeout: int = 60) -> Dict[str, Any]:
  body = None
  req_headers = {"Content-Type": "application/json"}
  if headers:
    req_headers.update(headers)
  if payload is not None:
    body = json.dumps(payload).encode("utf-8")
  req = urllib.request.Request(url, data=body, headers=req_headers, method=method)
  try:
    with urllib.request.urlopen(req, timeout=timeout) as resp:
      data = resp.read()
      if not data:
        return {}
      return json.loads(data.decode("utf-8"))
  except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8", errors="replace")
    raise RuntimeError(f"HTTP {method} {url} failed: {e.code} {e.reason}: {err_body}") from e


def normalize_openai_base_url(base: str) -> str:
  base = base.rstrip("/")
  if base.endswith("/v1"):
    return base
  return f"{base}/v1"


def embed_texts(openai_base_url: str, api_key: str, model: str, texts: List[str]) -> List[List[float]]:
  url = f"{openai_base_url}/embeddings"
  headers = {"Authorization": f"Bearer {api_key}"}
  out: List[List[float]] = []
  for text in texts:
    resp = http_json("POST", url, payload={"model": model, "input": text}, headers=headers, timeout=120)
    vec = resp["data"][0]["embedding"]
    out.append(vec)
  return out


def qdrant_url_for_realm(realm: str, hosted_zone: str, subdomain: str) -> str:
  return f"https://{realm}.{subdomain}.{hosted_zone}".rstrip("/")


def qdrant_get(url_base: str, path: str) -> Dict[str, Any]:
  return http_json("GET", f"{url_base}{path}", timeout=60)


def qdrant_put(url_base: str, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
  return http_json("PUT", f"{url_base}{path}", payload=payload, timeout=60)


def qdrant_post(url_base: str, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
  return http_json("POST", f"{url_base}{path}", payload=payload, timeout=120)


def qdrant_delete(url_base: str, path: str) -> Dict[str, Any]:
  return http_json("DELETE", f"{url_base}{path}", timeout=60)


def safe_collection_name(alias: str, suffix: str) -> str:
  base = "".join(ch if (ch.isalnum() or ch in "_-") else "_" for ch in alias)
  return f"{base}__{suffix}"


def list_aliases(url_base: str) -> Dict[str, str]:
  resp = qdrant_get(url_base, "/collections/aliases")
  mapping: Dict[str, str] = {}
  for item in resp.get("result", {}).get("aliases", []):
    mapping[item["alias_name"]] = item["collection_name"]
  return mapping


def ensure_new_collection(url_base: str, name: str, vector_size: int) -> None:
  qdrant_put(
    url_base,
    f"/collections/{name}",
    payload={
      "vectors": {"size": vector_size, "distance": "Cosine"},
    },
  )


def upsert_points(url_base: str, collection: str, points: List[Dict[str, Any]]) -> None:
  qdrant_post(
    url_base,
    f"/collections/{collection}/points?wait=true",
    payload={"points": points},
  )


def swap_alias(url_base: str, alias: str, new_collection: str) -> Optional[str]:
  aliases = list_aliases(url_base)
  old_collection = aliases.get(alias)
  actions: List[Dict[str, Any]] = []
  if old_collection is not None:
    actions.append({"delete_alias": {"alias_name": alias}})
  actions.append({"create_alias": {"alias_name": alias, "collection_name": new_collection}})
  qdrant_post(url_base, "/collections/aliases", payload={"actions": actions})
  return old_collection


def delete_collection(url_base: str, name: str) -> None:
  qdrant_delete(url_base, f"/collections/{name}?timeout=60")


def sha_id(parts: Iterable[str]) -> str:
  h = hashlib.sha256()
  for part in parts:
    h.update(part.encode("utf-8"))
    h.update(b"\\0")
  return h.hexdigest()


def chunk_text(text: str, size: int, overlap: int) -> List[str]:
  if size <= 0:
    return [text]
  overlap = max(0, min(overlap, size - 1))
  out: List[str] = []
  start = 0
  n = len(text)
  while start < n:
    end = min(n, start + size)
    out.append(text[start:end])
    if end >= n:
      break
    start = end - overlap
  return out


@dataclass(frozen=True)
class Repo:
  git_dir: str
  relative_path: str


def find_bare_repos(root: str) -> List[Repo]:
  repos: List[Repo] = []
  for dirpath, dirnames, filenames in os.walk(root):
    if dirpath.endswith(".git") and "HEAD" in filenames:
      rel = os.path.relpath(dirpath, root)
      repos.append(Repo(git_dir=dirpath, relative_path=rel))
      dirnames[:] = []
  return sorted(repos, key=lambda r: r.relative_path)


def should_index_path(path: str, allowed: List[str]) -> bool:
  normalized = path.lower()
  base = os.path.basename(path)
  if base in allowed:
    return True
  for ext in allowed:
    if ext.startswith(".") and normalized.endswith(ext.lower()):
      return True
  return False


def iter_repo_files(repo: Repo) -> Iterable[Tuple[str, int, str]]:
  head = run_git(["rev-parse", "HEAD"], git_dir=repo.git_dir)
  names = run_git(["ls-tree", "-r", "--name-only", "HEAD"], git_dir=repo.git_dir).splitlines()
  for name in names:
    name = name.strip()
    if not name:
      continue
    size_raw = run_git(["cat-file", "-s", f"HEAD:{name}"], git_dir=repo.git_dir)
    yield name, int(size_raw), head


def read_repo_file(repo: Repo, path: str, max_bytes: int) -> Optional[str]:
  try:
    content = subprocess.run(
      ["git", f"--git-dir={repo.git_dir}", "show", f"HEAD:{path}"],
      check=True,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      timeout=60,
    ).stdout
  except subprocess.CalledProcessError:
    return None
  if len(content) > max_bytes:
    return None
  return content.decode("utf-8", errors="replace")


def infer_management_domain_from_repo(repo_relative_path: str) -> Tuple[Optional[str], bool]:
  leaf = os.path.basename(repo_relative_path)
  name = leaf
  if name.endswith(".git"):
    name = name[:-4]
  is_wiki = False
  if name.endswith(".wiki"):
    is_wiki = True
    name = name[:-5]
  if name:
    name = name.replace("-", "_")
  return (name or None), is_wiki


def main() -> None:
  realm = env("REALM")
  n8n_fs = env("N8N_FILESYSTEM_PATH")
  hosted_zone = env("HOSTED_ZONE_NAME")
  qdrant_subdomain = env("QDRANT_SUBDOMAIN", "qdrant")
  qdrant_collection_alias = env("QDRANT_COLLECTION_ALIAS", "gitlab_efs")
  alias_map_raw = os.environ.get("QDRANT_COLLECTION_ALIAS_MAP_JSON") or ""
  alias_map: Dict[str, str] = {}
  if alias_map_raw.strip():
    try:
      parsed = json.loads(alias_map_raw)
      if isinstance(parsed, dict):
        for k, v in parsed.items():
          if isinstance(k, str) and isinstance(v, str) and k.strip() and v.strip():
            alias_map[k.strip()] = v.strip()
    except json.JSONDecodeError:
      alias_map = {}
  include_exts = [s.strip() for s in env("INCLUDE_EXTS", ".md").split() if s.strip()]
  max_file_bytes = env_int("MAX_FILE_BYTES", 262144)
  chunk_size = env_int("CHUNK_SIZE_CHARS", 1200)
  chunk_overlap = env_int("CHUNK_OVERLAP_CHARS", 200)
  batch_size = env_int("POINTS_BATCH_SIZE", 64)
  openai_base_url = normalize_openai_base_url(env("OPENAI_BASE_URL", "https://api.openai.com"))
  openai_model = env("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
  openai_api_key = env("OPENAI_API_KEY")
  dry_run = env("DRY_RUN", "false").lower() == "true"

  mirror_root = os.path.join(n8n_fs.rstrip("/"), "qdrant", realm, "gitlab")
  if not os.path.isdir(mirror_root):
    print(f"[index] mirror root not found: {mirror_root} (skip)")
    return

  qdrant_base = qdrant_url_for_realm(realm, hosted_zone, qdrant_subdomain)
  if alias_map:
    print(f"[index] realm={realm} mirror_root={mirror_root} qdrant={qdrant_base} domains={sorted(alias_map.keys())}")
  else:
    print(f"[index] realm={realm} mirror_root={mirror_root} qdrant={qdrant_base} collection={qdrant_collection_alias}")

  repos = find_bare_repos(mirror_root)
  if not repos:
    print("[index] no bare repos found (skip)")
    return

  qdrant_get(qdrant_base, "/collections")

  points_by_alias: Dict[str, List[Dict[str, Any]]] = {}
  vector_size: Optional[int] = None
  build_suffix = time.strftime("build__%Y%m%dT%H%M%SZ", time.gmtime())
  build_collection_by_alias: Dict[str, str] = {}

  def build_collection_for_alias(alias: str) -> str:
    if alias not in build_collection_by_alias:
      build_collection_by_alias[alias] = safe_collection_name(alias, build_suffix)
    return build_collection_by_alias[alias]


  def ensure_collection_for_alias(alias: str) -> str:
    nonlocal vector_size
    collection = build_collection_for_alias(alias)
    if vector_size is None:
      raise RuntimeError("vector_size is not determined yet")
    if dry_run:
      return collection
    ensure_new_collection(qdrant_base, collection, vector_size)
    return collection


  def flush(alias: str) -> None:
    batch = points_by_alias.get(alias) or []
    if not batch:
      return
    collection = build_collection_for_alias(alias)
    if dry_run:
      print(f"[index] DRY_RUN: would upsert {len(batch)} points into {alias}")
      points_by_alias[alias] = []
      return
    upsert_points(qdrant_base, collection, batch)
    points_by_alias[alias] = []

  for repo in repos:
    management_domain, is_wiki = infer_management_domain_from_repo(repo.relative_path)
    if management_domain is None:
      continue

    if alias_map:
      alias = alias_map.get(management_domain)
      if not alias:
        continue
    else:
      alias = qdrant_collection_alias

    for path, size, head in iter_repo_files(repo):
      if not should_index_path(path, include_exts):
        continue
      if size > max_file_bytes:
        continue
      text = read_repo_file(repo, path, max_file_bytes)
      if text is None or text.strip() == "":
        continue
      chunks = chunk_text(text, chunk_size, chunk_overlap)
      if not chunks:
        continue
      embeddings = embed_texts(openai_base_url, openai_api_key, openai_model, chunks)
      if vector_size is None:
        vector_size = len(embeddings[0])
        if alias_map:
          print(f"[index] vector_size={vector_size} (model={openai_model})")
        else:
          ensure_collection_for_alias(alias)
          print(f"[index] created build collection: {build_collection_for_alias(alias)} (vector_size={vector_size})")

      if alias_map and alias not in build_collection_by_alias:
        ensure_collection_for_alias(alias)
        print(f"[index] created build collection: {build_collection_for_alias(alias)} (alias={alias}, domain={management_domain})")

      for idx, (chunk, vec) in enumerate(zip(chunks, embeddings)):
        point_id = sha_id([realm, alias, repo.relative_path, path, str(idx)])
        points_by_alias.setdefault(alias, []).append(
          {
            "id": point_id,
            "vector": vec,
            "payload": {
              "content": chunk,
              "metadata": {
                "realm": realm,
                "management_domain": management_domain,
                "repo": repo.relative_path,
                "path": path,
                "is_wiki": is_wiki,
                "chunk_index": idx,
                "head": head,
              },
            },
          }
        )
        if len(points_by_alias.get(alias) or []) >= batch_size:
          flush(alias)

  for alias in list(points_by_alias.keys()):
    flush(alias)

  if vector_size is None:
    print("[index] no indexable documents found (skip)")
    return

  if dry_run:
    for alias in sorted(build_collection_by_alias.keys()):
      print(f"[index] DRY_RUN: would swap alias {alias} -> {build_collection_for_alias(alias)}")
    return

  def finalize_alias(alias: str) -> None:
    build_collection = build_collection_for_alias(alias)
    old_collection = swap_alias(qdrant_base, alias, build_collection)
    print(f"[index] alias swapped: {alias} -> {build_collection} (old={old_collection})")
    if old_collection and old_collection != build_collection:
      try:
        delete_collection(qdrant_base, old_collection)
        print(f"[index] deleted old collection: {old_collection}")
      except Exception as e:
        print(f"[index] warning: failed to delete old collection {old_collection}: {e}")

  for alias in sorted(build_collection_by_alias.keys()):
    finalize_alias(alias)


if __name__ == "__main__":
  main()
PY
        EOT
      ]
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-indexer-td" })
}

data "aws_iam_policy_document" "gitlab_efs_indexer_sfn_assume" {
  count = local.gitlab_efs_indexer_enabled ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "gitlab_efs_indexer_sfn_policy" {
  count = local.gitlab_efs_indexer_enabled ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "ecs:DescribeTasks",
      "ecs:DescribeTaskDefinition",
      "ecs:StopTask"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      # Step Functions can create/manage EventBridge "managed rules" in the account.
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource"
    ]
    resources = ["*"]
  }
  statement {
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution[0].arn,
      aws_iam_role.ecs_task[0].arn
    ]
  }
}

resource "aws_iam_role" "gitlab_efs_indexer_sfn" {
  count              = local.gitlab_efs_indexer_enabled ? 1 : 0
  name               = "${local.name_prefix}-gitlab-efs-indexer-sfn"
  assume_role_policy = data.aws_iam_policy_document.gitlab_efs_indexer_sfn_assume[0].json
  tags               = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-indexer-sfn" })
}

resource "aws_iam_policy" "gitlab_efs_indexer_sfn" {
  count  = local.gitlab_efs_indexer_enabled ? 1 : 0
  name   = "${local.name_prefix}-gitlab-efs-indexer-sfn"
  policy = data.aws_iam_policy_document.gitlab_efs_indexer_sfn_policy[0].json
  tags   = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-indexer-sfn" })
}

resource "aws_iam_role_policy_attachment" "gitlab_efs_indexer_sfn" {
  count      = local.gitlab_efs_indexer_enabled ? 1 : 0
  role       = aws_iam_role.gitlab_efs_indexer_sfn[0].name
  policy_arn = aws_iam_policy.gitlab_efs_indexer_sfn[0].arn
}

resource "aws_sfn_state_machine" "gitlab_efs_indexer" {
  count = local.gitlab_efs_indexer_enabled ? 1 : 0

  name       = "${local.name_prefix}-gitlab-efs-indexer"
  role_arn   = aws_iam_role.gitlab_efs_indexer_sfn[0].arn
  definition = local.gitlab_efs_indexer_state_machine_definition
  tags       = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-indexer" })
}
