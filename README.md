# Archive2Tape

Self-contained Levante helper for packing selected model-output files to `tar.zst`,
archiving them to DKRZ HSM tape, retrieving them back to scratch, and unpacking them
while preserving the source directory tree.

This is the department-facing replacement for copying personal compression scripts.
The older `scripts/nc_compression` directory remains as legacy/reference code.

## Setup

Add this directory to your `PATH`:

```bash
export PATH="/path/to/polarcap_analysis/scripts/archive2tape:$PATH"
```

Before using tape commands on Levante:

```bash
module load slk
slk login
```

`slk login` creates a token in `~/.slk/config.json`. The token is valid for about
30 days.

Optional user defaults can live in a small config file:

```bash
# archive2tape.conf
PROJECT=ab1234
ACCOUNT=ab1234
WORK_ROOT=/scratch/b/ab1234/$USER/archive2tape
ARCHIVE_ROOT=/arch/ab1234/$USER
INCLUDE_PATTERNS=*.nc *.zarr *.grb *.grib *.grb2 *.grib2
ALLOW_NON_SCRATCH_WORK=0
INCLUDE_HIDDEN=0
```

Use it with `--config archive2tape.conf`. CLI flags override config values. The
config parser accepts only known `KEY=VALUE` lines and does not `source` the file,
so shell code in the config is rejected instead of executed.

## Beginner Workflow

Terminology: DKRZ documentation calls archive directories "namespaces". This tool
uses `ARCHIVE_DIR` in help and examples because it is easier to understand; it
means the same destination path, e.g. `/arch/<project>/<user>/<dataset>`.

Archive selected files from `model_output_dir`:

```bash
PROJECT=ab1234  # replace with your project
archive2tape put model_output_dir "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run"
```

Start retrieval and unpack later:

```bash
PROJECT=ab1234  # replace with your project
archive2tape get "/arch/$PROJECT/$USER/my_run" model_output_from_archive \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run"
```

The `get` command starts retrieval. Retrieval from tape is asynchronous; when the
complete `.tar.zst` files are present in the work directory, run the printed
`unpack` command. `get` does not wait for tape recall to finish.

## Stage Commands

Use stage commands when a job failed, when disk space is tight, or when integrating
with existing scripts:

```bash
PROJECT=ab1234  # replace with your project
archive2tape pack model_output_dir "$GRAVEYARD/my_run" --project "$PROJECT"
archive2tape archive "$GRAVEYARD/my_run" "/arch/$PROJECT/$USER/my_run" --project "$PROJECT"

archive2tape retrieve "/arch/$PROJECT/$USER/my_run" "$GRAVEYARD/my_run" --project "$PROJECT"
archive2tape unpack "$GRAVEYARD/my_run" model_output_from_archive
```

Meanings:

- `put`: `pack` plus `archive`
- `get`: starts `retrieve` plus prints the exact `unpack` command
- `pack`: selected files to local/graveyard `.tar.zst`
- `archive`: existing `.tar.zst` objects to tape
- `retrieve`: existing `.tar.zst` objects from tape to local/graveyard storage
- `unpack`: local `.tar.zst` objects into a target directory

## Selected Files

Default include patterns:

```bash
*.nc
*.zarr
*.grb
*.grib
*.grb2
*.grib2
```

Add more patterns with repeated `--include` flags:

```bash
PROJECT=ab1234  # replace with your project
archive2tape put model_output_dir "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run" \
  --include '*.txt'
```

Hidden paths are skipped by default so `.git`, `.ssh`, `.ipynb_checkpoints`, and
similar files are not archived accidentally. Use `--include-hidden` only when you
know you need those files. Zarr metadata inside a selected `.zarr` directory is
kept because the whole store is packed. If a selected directory such as
`Meteogram_run.zarr` matches, descendants inside it are not added separately to
the tar list.

## Safety Checks

The tool fails early when:

- `--project` is missing for Slurm/HSM commands
- `ARCHIVE_DIR` does not look like `/arch/<project>/...`
- `--project` does not match the project in the `/arch/...` path
- the work directory is outside `/scratch` without `--allow-non-scratch-work`
- no selected files are found
- a local tar object already exists without `--overwrite`
- multiple local `*.tar.zst` files exist without an `archive2tape_archive_objects.txt`
  manifest, unless `--all-objects` is passed explicitly

Use `--dry-run` before submitting jobs:

```bash
PROJECT=ab1234  # replace with your project
archive2tape put model_output_dir "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run" \
  --dry-run
```

The dry run prints selected entry count, total selected size, planned tar object,
manifests, work directory, `ARCHIVE_DIR`, and project.

Use one work directory per archive set when possible. If a work directory is reused,
the generated `archive2tape_archive_objects.txt` controls which tar object belongs
to the current archive/restore. Extra tarballs in the same directory are ignored
when a manifest is present.

## DKRZ HSM Notes

DKRZ recommends:

- run `slk archive` and retrieval jobs on `shared` or `interactive`, not login
  nodes, for more than a few GB
- allocate about 6 GB memory for `slk archive` and retrieval commands
- avoid archiving many files below 1 GB; pack small files together
- aim for archive objects around 10-200 GB when possible
- avoid more than about 3 TB in one archive call
- avoid too many parallel `slk archive` commands; this tool archives sequentially
  in one Slurm job by default

This first version creates one `.tar.zst` object per archive set. It warns when
the planned object is outside the ideal DKRZ size range and requires `--allow-huge`
above 3 TiB. It does not split a single huge model-output file because split
restore adds fragility.

## Output Files

In the work directory:

- `<dataset>_0001.tar.zst`: packed data
- `archive2tape_manifest.tsv`: selected entries with type, size, and relative path
- `archive2tape_tar_paths.txt`: paths passed to `tar`
- `archive2tape_metadata.env`: archive metadata and restore hints
- `archive2tape_archive_objects.txt`: files sent to HSM
- `.slurm/`: Slurm logs

The tarball stores relative paths from `model_output_dir`, so unpacking into
`model_output_from_archive` preserves the source tree below that target.

Keep the metadata and manifest files with the tar object. They are archived along
with the data and are used to avoid accidentally archiving or unpacking stale
tarballs from a reused work directory.

## Troubleshooting

If packing fails, inspect:

```bash
less "$GRAVEYARD/my_run/.slurm/pack_<jobid>.err"
```

If archiving fails, inspect:

```bash
less "$GRAVEYARD/my_run/.slurm/archive_<jobid>.err"
less ~/.slk/slk-cli.log
```

For failed HSM archival, DKRZ recommends rerunning the same archive command. Missing
or incomplete files are archived again; complete matching files are skipped.

If retrieval uses watchers, the command prints `WATCHER_DIR`. Check `recall.log`
and `retrieve.log` there.

For cold restores where local metadata is not available, retrieval falls back to
listing `.tar.zst` objects in the archive namespace. Prefer keeping the generated
metadata in the work directory when restarting a retrieve/unpack workflow.

## Local Checks

Run local syntax and fixture checks after editing the tool:

```bash
bash scripts/archive2tape/test_archive2tape.sh
```

The test covers config parsing, hidden-file exclusion, `.zarr` selection without
duplicate nested entries, stale tarball guards, manifest-scoped unpack dry-runs,
and a real pack/unpack smoke test when `zstd` is installed.

## Options

```bash
--config FILE                 Read defaults from archive2tape.conf-style KEY=VALUE file
--project PROJECT              Slurm/HSM project, must match /arch/<PROJECT>/...
--account ACCOUNT              Slurm account; defaults to PROJECT
--work WORK_DIR                Work dir for put/get; defaults to $GRAVEYARD/<dataset>
--include GLOB                 Add selected pattern
--include-hidden               Allow hidden paths during selection
--dry-run                      Print plan without submitting or unpacking
--run-now                      Run pack/archive/unpack worker in the current shell
--all-objects                  Without a manifest, archive/unpack all local *.tar.zst objects
--allow-non-scratch-work       Allow work dir outside /scratch
--allow-huge                   Allow archive object plan above 3 TiB
--overwrite                    Replace existing local tar object
--log-dir DIR                  Slurm log dir; default WORK_DIR/.slurm
```

Use `--run-now` only in an interactive/compute allocation for `pack` or `archive`.
It is intentionally rejected for `retrieve` and `get`; retrieval should use the
Slurm-backed `slk_helpers` workflow.
