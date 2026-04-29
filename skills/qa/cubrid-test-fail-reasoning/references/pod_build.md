# Build backend

`scripts/build_cubrid.py` is pluggable so the skill works in both today's
kubectl-pod environment and a future HTTP-tarball world. The choice is
controlled by `CUBRID_BUILD_BACKEND`.

## pod backend (default)

```
CUBRID_BUILD_BACKEND=pod
CUBRID_BUILD_POD=<your build pod name>             # required — no built-in default
```

Steps run inside the pod:

1. `git fetch origin <branch>` + checkout + pull.
2. Optionally `git checkout <commit>` if `--commit` is supplied.
3. Full submodule reset:
   ```
   git submodule sync --recursive
   git submodule foreach --recursive 'git reset --hard'
   git submodule foreach --recursive 'git clean -fdx'
   git submodule update --init --force --recursive
   ```
   This is required — submodule drift has bitten 11.3 builds repeatedly.
4. `source /opt/rh/devtoolset-8/enable` if available. The cent6_9 image's
   default `gcc` lacks a working `g++`; the SCL toolchain provides it.
5. `rm -rf build_x86_64_release && ./build.sh -p /home/CUBRID -g ninja build`.
   Note `build` (not `all`) — packaging adds 5+ minutes for no benefit when
   we only need the install tree.
6. `tar czf /tmp/CUBRID.tar.gz -C /home CUBRID`.
7. `kubectl cp <pod>:/tmp/CUBRID.tar.gz <local>` and extract to `--target`
   (default: `$CUBRID_INSTALL` or `./CUBRID` in the current working directory).

## url backend (future)

Once builds are served via HTTP:

```
CUBRID_BUILD_BACKEND=url
CUBRID_BUILD_URL=https://artifacts.example.com/cubrid/<branch>/<sha>/CUBRID.tar.gz
```

The script downloads with `urllib.request.urlretrieve` and extracts the same
way. No other changes — the rest of the pipeline (run_tc.py,
generate_report.py) is build-backend-agnostic.

## Idempotency

`get_local_short_sha()` reads `<target>/bin/cubrid_rel`'s output and parses
the trailing short SHA from the version string (e.g.
`CUBRID 11.3 (11.3.5.1275-0e31336)`). If it matches `--commit`, the build is
skipped. Pass `--force` to override.

## Cleanup before tests

After a fresh install, leftover `cub_master`/`cub_broker`/`cub_cas` processes
from a previous CUBRID at the same path will reference now-deleted binaries
(`/proc/<pid>/exe → ...(deleted)`). They cling to shared-memory keys and
break the next test's master start. `run_tc.py` calls `cleanup_stale_cubrid()`
at the start of each TC, which:

1. Issues `cubrid service stop` for graceful shutdown.
2. `pkill -f 'cub_master|cub_broker|cub_cas|query_editor'` to nuke orphans
   that ignored the graceful stop.

If you swap backends or update the toolchain, run a single TC manually first
to make sure cleanup is sufficient on the new configuration.
