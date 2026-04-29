#!/usr/bin/env python3
"""Provide a working CUBRID install at --target, using a pluggable backend.

Backends (selected by env var CUBRID_BUILD_BACKEND, default `pod`):

  pod
      Build CUBRID inside a Kubernetes build pod, tar, kubectl-cp out, extract
      locally. Requires `kubectl` on PATH and `CUBRID_BUILD_POD` set to the
      target pod name. The build inside the pod uses devtoolset-8 + ninja.

  url
      Download a prebuilt CUBRID tarball from `CUBRID_BUILD_URL` and extract.
      The portable, deployment-friendly path; no kubectl required.

Default --target resolution:
  $CUBRID_INSTALL  ->  ./CUBRID  (current working directory)

The script is idempotent: if --target already contains a cubrid_rel whose
short SHA matches --commit, the build is skipped (override with --force).
"""
from __future__ import annotations
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import urllib.request


def log(msg: str) -> None:
    print(f"[build_cubrid] {msg}", flush=True)


def get_local_short_sha(target: str) -> str | None:
    rel = os.path.join(target, "bin", "cubrid_rel")
    if not os.path.isfile(rel):
        return None
    try:
        out = subprocess.check_output([rel], text=True, stderr=subprocess.STDOUT)
    except Exception:
        return None
    # e.g. "CUBRID 11.3 (11.3.5.1275-0e31336) (64bit ...)"
    m = re.search(r"-([0-9a-f]{7,40})\)", out)
    return m.group(1) if m else None


def install_tar(tar_path: str, target: str) -> None:
    if os.path.isdir(target):
        log(f"removing existing {target}")
        shutil.rmtree(target)
    parent = os.path.dirname(os.path.abspath(target))
    os.makedirs(parent, exist_ok=True)
    subprocess.run(["tar", "xzf", tar_path, "-C", parent], check=True)
    log(f"installed at {target}")


POD_BUILD_SCRIPT = textwrap.dedent("""\
    set -e
    cd /home/cubrid
    git fetch origin "{branch}"
    git checkout "{branch}"
    git pull origin "{branch}" || true
    {checkout_commit}
    git submodule sync --recursive
    git submodule foreach --recursive 'git reset --hard'
    git submodule foreach --recursive 'git clean -fdx'
    git submodule update --init --force --recursive
    if [ -f /opt/rh/devtoolset-8/enable ]; then source /opt/rh/devtoolset-8/enable; fi
    rm -rf build_x86_64_release
    ./build.sh -p /home/CUBRID -g ninja build
    tar czf /tmp/CUBRID.tar.gz -C /home CUBRID
""")


def build_via_pod(branch: str, commit: str | None, pod: str, target: str) -> None:
    if not shutil.which("kubectl"):
        sys.exit(
            "[build_cubrid] kubectl not found in PATH. The `pod` backend "
            "requires it. Either install kubectl, or switch to the portable "
            "`url` backend: set CUBRID_BUILD_BACKEND=url and CUBRID_BUILD_URL."
        )
    log(f"backend=pod pod={pod} branch={branch} commit={commit or '(branch tip)'}")
    checkout_commit = f"git checkout {commit}" if commit else ""
    sh = POD_BUILD_SCRIPT.format(branch=branch, checkout_commit=checkout_commit)
    subprocess.run(["kubectl", "exec", pod, "--", "bash", "-c", sh], check=True)
    with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as t:
        local_tar = t.name
    subprocess.run(["kubectl", "cp", f"{pod}:/tmp/CUBRID.tar.gz", local_tar], check=True)
    install_tar(local_tar, target)


def build_via_url(url: str, target: str) -> None:
    log(f"backend=url url={url}")
    with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as t:
        local_tar = t.name
    urllib.request.urlretrieve(url, local_tar)
    install_tar(local_tar, target)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--branch", required=True)
    ap.add_argument("--commit", default=None,
                    help="optional explicit commit; if omitted, build from branch tip")
    ap.add_argument(
        "--target",
        default=os.environ.get("CUBRID_INSTALL")
        or os.path.join(os.getcwd(), "CUBRID"),
        help="local install dir (default: $CUBRID_INSTALL or ./CUBRID)",
    )
    ap.add_argument("--force", action="store_true",
                    help="rebuild even if local install matches commit")
    args = ap.parse_args()

    if not args.force and args.commit:
        local_sha = get_local_short_sha(args.target)
        if local_sha and args.commit.lower().startswith(local_sha.lower()):
            log(f"skip — local install already at {local_sha} (matches --commit {args.commit})")
            return

    backend = os.environ.get("CUBRID_BUILD_BACKEND", "pod").lower()
    if backend == "url":
        url = os.environ.get("CUBRID_BUILD_URL")
        if not url:
            sys.exit("[build_cubrid] CUBRID_BUILD_BACKEND=url requires CUBRID_BUILD_URL")
        build_via_url(url, args.target)
    elif backend == "pod":
        pod = os.environ.get("CUBRID_BUILD_POD")
        if not pod:
            sys.exit(
                "[build_cubrid] CUBRID_BUILD_BACKEND=pod requires CUBRID_BUILD_POD "
                "to be set to the build pod name. For deployments without a pod, "
                "use CUBRID_BUILD_BACKEND=url + CUBRID_BUILD_URL instead."
            )
        build_via_pod(args.branch, args.commit, pod, args.target)
    else:
        sys.exit(f"[build_cubrid] unknown CUBRID_BUILD_BACKEND={backend!r}")


if __name__ == "__main__":
    main()
