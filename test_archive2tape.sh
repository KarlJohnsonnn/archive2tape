#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ARCHIVE2TAPE="$SCRIPT_DIR/archive2tape"

python3 - "$ARCHIVE2TAPE" <<'PY'
import subprocess
import sys
import tempfile
from pathlib import Path

archive2tape = Path(sys.argv[1])
repo = archive2tape.parents[2]


def run(args, check=True):
    proc = subprocess.run(
        [str(archive2tape), *args],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and proc.returncode != 0:
        raise SystemExit(
            f"FAILED {' '.join(args)}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    return proc


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

    bad_config = root / "bad.conf"
    bad_config.write_text("PROJECT=$(echo bad)\n")
    proc = run(["put", str(source), "my_run", "--config", str(bad_config), "--dry-run"], check=False)
    assert proc.returncode != 0 and "command substitution" in proc.stderr, proc.stderr

    bad_config.write_text("WORK_ROOT=$HOME/archive2tape\nPROJECT=ab1234\n")
    proc = run(["put", str(source), "my_run", "--config", str(bad_config), "--dry-run"], check=False)
    assert proc.returncode != 0 and "only $USER is allowed" in proc.stderr, proc.stderr

    work = root / "work"
    work.mkdir()
    (work / "one.tar.zst").write_text("fake")
    (work / "two.tar.zst").write_text("fake")
    proc = run(
        [
            "archive",
            str(work),
            "/arch/ab1234/user/my_run",
            "--project",
            "ab1234",
            "--allow-non-scratch-work",
            "--dry-run",
        ],
        check=False,
    )
    assert proc.returncode != 0 and "Multiple .tar.zst files" in proc.stderr, proc.stderr

    manifest = work / "archive2tape_archive_objects.txt"
    manifest.write_text(str(work / "one.tar.zst") + "\n")
    proc = run(["unpack", str(work), str(root / "out"), "--dry-run"])
    assert str(work / "one.tar.zst") in proc.stdout, proc.stdout
    assert str(work / "two.tar.zst") not in proc.stdout, proc.stdout

print("local fixture checks passed")
PY

if command -v zstd >/dev/null 2>&1; then
    python3 - "$ARCHIVE2TAPE" <<'PY'
import subprocess
import sys
import tempfile
from pathlib import Path

archive2tape = Path(sys.argv[1])
repo = archive2tape.parents[2]

with tempfile.TemporaryDirectory(prefix="a2t_pack_") as tmp:
    root = Path(tmp)
    source = root / "src"
    work = root / "work"
    output = root / "out"
    source.mkdir()
    (source / "a.nc").write_text("payload")
    zarr = source / "store.zarr"
    zarr.mkdir()
    (zarr / "nested.nc").write_text("nested")

    subprocess.run(
        [
            str(archive2tape),
            "pack",
            str(source),
            str(work),
            "--project",
            "ab1234",
            "--account",
            "ab1234",
            "--allow-non-scratch-work",
            "--run-now",
        ],
        cwd=repo,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    subprocess.run(
        [str(archive2tape), "unpack", str(work), str(output)],
        cwd=repo,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert (output / "a.nc").read_text() == "payload"
    assert (output / "store.zarr" / "nested.nc").read_text() == "nested"

print("pack/unpack smoke passed")
PY
else
    printf 'zstd not installed; skipped pack/unpack smoke\n'
fi
