#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ARCHIVE2TAPE="$SCRIPT_DIR/archive2tape"

python3 - "$ARCHIVE2TAPE" <<'PY'
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

archive2tape = Path(sys.argv[1])
repo = archive2tape.parents[2]


def run(args, check=True, env=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    proc = subprocess.run(
        [str(archive2tape), *args],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=merged_env,
    )
    if check and proc.returncode != 0:
        raise SystemExit(
            f"FAILED {' '.join(args)}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    return proc


def write_executable(path: Path, content: str):
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


subprocess.run(["bash", "-n", str(archive2tape)], check=True)

with tempfile.TemporaryDirectory(prefix="a2t_fixture_") as tmp:
    root = Path(tmp)
    source = root / "model_output"
    source.mkdir()
    (source / "a.nc").write_text("nc")
    (source / ".hidden.nc").write_text("hidden")
    zarr = source / "Meteogram_run.zarr"
    zarr.mkdir()
    (zarr / "nested.nc").write_text("nested")

    config = root / "archive2tape.conf"
    config.write_text(
        "\n".join(
            [
                "PROJECT=ab1234",
                "ACCOUNT=ab1234_cpu",
                f"WORK_ROOT={root}/work_root",
                "ARCHIVE_ROOT=/arch/ab1234/$USER",
                "INCLUDE_PATTERNS=*.nc *.zarr",
                "ALLOW_NON_SCRATCH_WORK=1",
                "INCLUDE_HIDDEN=0",
                "",
            ]
        )
    )

    proc = run(["put", str(source), "my_run", "--config", str(config), "--dry-run"])
    assert "ARCHIVE_DIR=/arch/ab1234/" in proc.stdout, proc.stdout
    assert "ACCOUNT=ab1234_cpu" in proc.stdout, proc.stdout
    assert "SELECTED_ENTRIES=2" in proc.stdout, proc.stdout
    assert "COMPRESSED_DIR=" in proc.stdout, proc.stdout

    bad_config = root / "bad.conf"
    bad_config.write_text("PROJECT=$(echo bad)\n")
    proc = run(["put", str(source), "my_run", "--config", str(bad_config), "--dry-run"], check=False)
    assert proc.returncode != 0 and "command substitution" in proc.stderr, proc.stderr

    bad_config.write_text("WORK_ROOT=$HOME/archive2tape\nPROJECT=ab1234\n")
    proc = run(["put", str(source), "my_run", "--config", str(bad_config), "--dry-run"], check=False)
    assert proc.returncode != 0 and "only $USER is allowed" in proc.stderr, proc.stderr

    work = root / "work"
    (work / "compressed").mkdir(parents=True)
    proc = run(
        [
            "archive",
            str(work),
            "/arch/ab1234/user/my_run",
            "--project",
            "ab1234",
            "--allow-non-scratch-work",
            "--dry-run",
        ]
    )
    assert "packems" in proc.stdout and "PACKEMS_INDEX=/arch/ab1234/user/my_run/INDEX.txt" in proc.stdout, proc.stdout

print("local fixture checks passed")
PY

if command -v zstd >/dev/null 2>&1; then
    python3 - "$ARCHIVE2TAPE" <<'PY'
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

archive2tape = Path(sys.argv[1])
repo = archive2tape.parents[2]


def run(args, check=True, env=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    proc = subprocess.run(
        [str(archive2tape), *args],
        cwd=repo,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=merged_env,
    )
    if check and proc.returncode != 0:
        raise SystemExit(
            f"FAILED {' '.join(args)}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    return proc


def write_executable(path: Path, content: str):
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


with tempfile.TemporaryDirectory(prefix="a2t_pack_") as tmp:
    root = Path(tmp)
    source = root / "src"
    work = root / "work"
    output = root / "out"
    source.mkdir()
    (source / "a.nc").write_text("payload")
    nested = source / "nested"
    nested.mkdir()
    (nested / "b.grib2").write_text("nested payload")
    zarr = source / "store.zarr"
    zarr.mkdir()
    (zarr / "nested.nc").write_text("zarr payload")

    run(
        [
            "pack",
            str(source),
            str(work),
            "--project",
            "ab1234",
            "--account",
            "ab1234",
            "--allow-non-scratch-work",
            "--run-now",
        ]
    )
    run(["unpack", str(work), str(output)])
    assert (output / "a.nc").read_text() == "payload"
    assert (output / "nested" / "b.grib2").read_text() == "nested payload"
    assert (output / "store.zarr" / "nested.nc").read_text() == "zarr payload"

    bin_dir = root / "bin"
    bin_dir.mkdir()
    packems_log = root / "packems.log"
    write_executable(bin_dir / "tapeinit", "#!/usr/bin/env bash\nexit 0\n")
    write_executable(
        bin_dir / "packems",
        "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$PACKEMS_LOG\"\nexit 0\n",
    )
    write_executable(
        bin_dir / "unpackems",
        """#!/usr/bin/env bash
set -euo pipefail
dest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) dest="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$dest/compressed"
cp -R "$UNPACKEMS_SOURCE"/. "$dest/compressed"/
""",
    )
    env = {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "PACKEMS_LOG": str(packems_log),
        "UNPACKEMS_SOURCE": str(work / "compressed"),
    }
    run(
        [
            "archive",
            str(work),
            "/arch/ab1234/user/my_run",
            "--project",
            "ab1234",
            "--allow-non-scratch-work",
            "--run-now",
        ],
        env=env,
    )
    log = packems_log.read_text()
    assert "--no-archive compressed" in log, log
    assert "--archive-only compressed" in log, log

    retrieved_out = root / "retrieved_out"
    run(
        [
            "retrieve",
            "/arch/ab1234/user/my_run",
            str(work),
            "--project",
            "ab1234",
            "--allow-non-scratch-work",
            "--run-now",
        ],
        env=env,
    )
    run(["unpack", str(work), str(retrieved_out), "--overwrite"])
    assert (retrieved_out / "a.nc").read_text() == "payload"
    assert (retrieved_out / "store.zarr" / "nested.nc").read_text() == "zarr payload"

print("packems-backed smoke passed")
PY
else
    printf 'zstd not installed; skipped packems-backed smoke\n'
fi
