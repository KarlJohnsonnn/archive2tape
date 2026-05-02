# Archive2Tape

`archive2tape` prepares selected model-output files on DKRZ Levante and sends
them to the DKRZ HSM tape system through Packems.

It exists to make archive and restore workflows less manual: files are selected,
compressed, indexed, archived, retrieved, and unpacked with the same command
structure. This should help teams archive ICON, COSMO, and similar numerical
weather model output reproducibly.

## Contents

- [Install](#install)
- [Test run](#test-run)
- [my_run: dry run with own data](#my_run-dry-run-with-own-data)
- [Configuration](#configuration)
  - [Config file](#config-file)
  - [Data layout](#data-layout)
  - [Selected files](#selected-files)
  - [Packems choices](#packems-choices)
- [Reference](#reference)
  - [Typical workflow (`put` / `get`)](#typical-workflow-put--get)
  - [Step-by-step commands (`pack`, `archive`, `retrieve`, `unpack`)](#step-by-step-commands-pack-archive-retrieve-unpack)
  - [Safety checks](#safety-checks)
  - [Legacy archives](#legacy-archives)
  - [Options](#options)

## Install

Add this repository to your `PATH`:

```bash
export PATH="/path/to/archive2tape/:$PATH"
```

On DKRZ Levante, initialize the Packems environment before running tape-facing
commands:

```bash
module load packems
tapeinit
```

`tapeinit` checks or renews the StrongLink token used by Packems.

## Test run

Run the local compression round-trip checks:

```bash
bash share/archive2tape/test_archive2tape.sh
```

The test script replaces Packems commands with local test commands. It checks
the archive command flow without submitting jobs on Levante and without
connecting to the HSM tape system.

## my_run: dry run with own data

Use `--dry-run` before submitting archive or retrieval work:

```bash
PROJECT=bb1234
archive2tape put /path/to/model_output "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run" \
  --dry-run
```

Omitting `--account` uses `PROJECT` as the Slurm `--account` value (override when your site requires a different billing account).

If the plan looks right, remove `--dry-run` to archive selected files. Retrieve
later from the same archive namespace:

```bash
archive2tape get "/arch/$PROJECT/$USER/my_run" model_output_from_archive \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run"
```

`get` runs `unpackems` to restore the compressed work tree from the Packems
`INDEX.txt`. When retrieval is complete, run the printed `archive2tape unpack`
command to decompress into `model_output_from_archive`.

## Configuration

### Config file

Optional site or user defaults can live in a config file. Use `--config FILE`;
CLI flags override config values. The parser accepts only known `KEY=VALUE`
lines and rejects shell code.

```bash
# archive2tape.conf
PROJECT=bb1234
ACCOUNT=b123456
WORK_ROOT=/scratch/b/$PROJECT/$USER/archive2tape
ARCHIVE_ROOT=/arch/$PROJECT/$USER
INCLUDE_PATTERNS=*.nc *.zarr *.grb *.grib *.grb2 *.grib2
ALLOW_NON_SCRATCH_WORK=0
INCLUDE_HIDDEN=0
```

`PROJECT` must match the first path segment after `/arch/` for any archive namespace you pass or resolve through `ARCHIVE_ROOT`. `ACCOUNT` is the Slurm `--account` value for submitted jobs and defaults to `PROJECT` when omitted; on Levante it often differs from `PROJECT`.

### Data layout

In `WORK_DIR/compressed`:

- regular files become relative-path-preserving `*.zst` files
- selected directories, such as `.zarr` stores, become `relative/path.tar.zst`
- `archive2tape_manifest.tsv` records type, original size, source relative path,
  and compressed relative path
- `archive2tape_metadata.env` records project, source, archive, and include info

Packems then packs and archives the `compressed` directory. The archive namespace
contains Packems tar objects and `INDEX.txt`, so `listems` and `unpackems` can
inspect and restore the contents without local `.slurm` logs.

### Selected files

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
archive2tape put /path/to/model_output "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run" \
  --include '*.txt'
```

Hidden paths are skipped by default so `.git`, `.ssh`, `.ipynb_checkpoints`, and
similar files are not archived accidentally. Use `--include-hidden` only when
needed. If a selected directory such as `Meteogram_run.zarr` matches, descendants
inside it are not selected separately.

### Packems choices

`archive2tape archive` runs Packems in two phases:

```bash
packems ... --no-archive compressed
packems ... --archive-only compressed
```

This keeps compression separate from HSM upload and uses Packems restart/index
behavior for the tape-facing work. Defaults follow DKRZ guidance:

- target tar object size: `PACKEMS_TARGET_GB=100`
- hard max object size: `PACKEMS_MAX_GB=200`
- parallel jobs: `PACKEMS_JOBS=4`

Override these through environment variables if needed.

## Reference

### Typical workflow (`put` / `get`)

Archive selected files from a model-output directory:

```bash
PROJECT=bb1234
ACCOUNT=b123456
archive2tape put /path/to/model_output "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --account "$ACCOUNT" \
  --work "$GRAVEYARD/my_run"
```

Start retrieval later from the same archive namespace:

```bash
PROJECT=bb1234
ACCOUNT=b123456
archive2tape get "/arch/$PROJECT/$USER/my_run" model_output_from_archive \
  --project "$PROJECT" \
  --account "$ACCOUNT" \
  --work "$GRAVEYARD/my_run"
```

`get` runs `unpackems` to restore the compressed work-directory tree from the Packems
`INDEX.txt`. When retrieval is complete, run the printed `archive2tape unpack`
command to decompress into `model_output_from_archive`. On Levante, `$GRAVEYARD`
points to scratch storage, where files are removed automatically after the
site-defined retention period.

### Step-by-step commands (`pack`, `archive`, `retrieve`, `unpack`)

The shortcuts `put` and `get` chain these steps. Run the individual subcommands
when you need to pause between phases, retry one phase, or call them from other
scripts:

```bash
PROJECT=bb1234
ACCOUNT=b123456
archive2tape pack /path/to/model_output "$GRAVEYARD/my_run" --project "$PROJECT" --account "$ACCOUNT"
archive2tape archive "$GRAVEYARD/my_run" "/arch/$PROJECT/$USER/my_run" --project "$PROJECT" --account "$ACCOUNT"

archive2tape retrieve "/arch/$PROJECT/$USER/my_run" "$GRAVEYARD/my_run" --project "$PROJECT" --account "$ACCOUNT"
archive2tape unpack "$GRAVEYARD/my_run" model_output_from_archive
```

Meanings:

- `put`: `pack` plus Packems archive
- `get`: `retrieve` plus printed `unpack` command
- `pack`: select source paths and compress them into `WORK_DIR/compressed`
- `archive`: use Packems on `WORK_DIR/compressed`
- `retrieve`: use `unpackems` and Packems `INDEX.txt`
- `unpack`: decompress the retrieved compressed tree into a target directory (runs locally; Slurm `--account` does not apply)

### Safety checks

The tool fails early when:

- `--project` is missing for Slurm/HSM commands
- `ARCHIVE_DIR` does not look like `/arch/<project>/...`
- `--project` does not match the first segment `<project>` of `ARCHIVE_DIR` after `/arch/`
- the work directory is outside `/scratch` without `--allow-non-scratch-work`
- no selected files are found
- compressed outputs or decompressed targets already exist without `--overwrite`

Use `--dry-run` before submitting jobs (see **my_run** above).

### Legacy archives

Archives created by earlier `archive2tape` versions as plain `.tar.zst` blobs are
not Packems-indexed. Restore those with the old workflow or manual
`slk_helpers` retrieval. New Packems-backed archives should use `get` or
`retrieve` plus `unpack`.

Complete legacy restore example:

```bash
PROJECT=bb1234
ACCOUNT=b123456
ARCHIVE_DIR="/arch/$PROJECT/$USER/my_old_run"
WORK_DIR="$GRAVEYARD/my_old_run_legacy_restore"
TARGET_DIR="$PWD/my_old_run_restored"

module load slk
slk login

mkdir -p "$WORK_DIR" "$TARGET_DIR"

# Inspect the old archive namespace and choose the archived tar.zst object.
slk list "$ARCHIVE_DIR"
LEGACY_OBJECT="$ARCHIVE_DIR/my_old_run_0001.tar.zst"

# Start recall/retrieval to local scratch. This submits Slurm retrieval work.
slk_helpers recall "$LEGACY_OBJECT" -d "$WORK_DIR"
slk_helpers retrieve "$LEGACY_OBJECT" -d "$WORK_DIR" -v --slurm "$ACCOUNT"

# After the retrieval job has finished and the tarball exists locally, unpack it.
zstd -dc "$WORK_DIR/$(basename "$LEGACY_OBJECT")" | tar -xf - -C "$TARGET_DIR"
```

If the old namespace contains several `.tar.zst` objects, repeat the
`slk_helpers` and `zstd | tar` commands for each object.

### Options

```bash
--config FILE                 Read defaults from archive2tape.conf-style KEY=VALUE file
--project PROJECT              Must equal first segment after /arch/ in ARCHIVE_DIR
--account ACCOUNT              Slurm #SBATCH --account; defaults to PROJECT if omitted
--work WORK_DIR                Work dir for put/get; defaults to $GRAVEYARD/<dataset>
--include GLOB                 Add selected pattern
--include-hidden               Allow hidden paths during selection
--dry-run                      Print plan without submitting or decompressing
--run-now                      Run stage worker in the current shell
--allow-non-scratch-work       Allow work dir outside /scratch
--allow-huge                   Allow selected source plan above 3 TiB
--overwrite                    Replace existing local compressed/decompressed files
--log-dir DIR                  Slurm log dir; default WORK_DIR/.slurm
```

Use `--run-now` only in an interactive or compute allocation for real Packems
archive/retrieve commands.
