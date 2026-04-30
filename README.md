# Archive2Tape

Levante helper for compressing selected model-output files, then using Packems to
pack, index, archive, retrieve, and unpack them through DKRZ HSM tape.

`archive2tape` keeps a beginner-friendly interface around the maintained
ESM tools:

- local stage: select paths and compress them into `WORK_DIR/compressed`
- tape stage: `packems` creates tar objects, archives them, and writes `INDEX.txt`
- restore stage: `unpackems` retrieves the compressed staging tree, then
  `archive2tape unpack` decompresses it into the target tree

## Setup

Add this directory to your `PATH`:

```bash
export PATH="/path/to/archive2tape/:$PATH"
```

Before running `archive2tape` commands on Levante:

```bash
module load packems
tapeinit
```

`tapeinit` checks or renews the StrongLink token used by Packems.

Optional user defaults can live in a config file:

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
config parser accepts only known `KEY=VALUE` lines and rejects shell code.

## Beginner Workflow

Archive selected files from `model_output_dir`:

```bash
PROJECT=ab1234
archive2tape put model_output_dir "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run"
```

Start retrieval later:

```bash
PROJECT=ab1234
archive2tape get "/arch/$PROJECT/$USER/my_run" model_output_from_archive \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run"
```

`get` runs `unpackems` to restore the compressed staging tree from the Packems
`INDEX.txt`. When retrieval is complete, run the printed `archive2tape unpack`
command to decompress into `model_output_from_archive`. Note that the path 
`GRAVEYARD` is points to `/scratch/`, where data gets deleted 14 days after 
the last file access. 


## Stage Commands

Use stage commands when debugging, restarting, or integrating with scripts:

```bash
PROJECT=ab1234
archive2tape pack model_output_dir "$GRAVEYARD/my_run" --project "$PROJECT"
archive2tape archive "$GRAVEYARD/my_run" "/arch/$PROJECT/$USER/my_run" --project "$PROJECT"

archive2tape retrieve "/arch/$PROJECT/$USER/my_run" "$GRAVEYARD/my_run" --project "$PROJECT"
archive2tape unpack "$GRAVEYARD/my_run" model_output_from_archive
```

Meanings:

- `put`: `pack` plus Packems archive
- `get`: `retrieve` plus printed `unpack` command
- `pack`: select source paths and compress them into `WORK_DIR/compressed`
- `archive`: use Packems on `WORK_DIR/compressed`
- `retrieve`: use `unpackems` and Packems `INDEX.txt`
- `unpack`: decompress restored staging files into a target directory

## Data Layout

In `WORK_DIR/compressed`:

- regular files become relative-path-preserving `*.zst` files
- selected directories, such as `.zarr` stores, become `relative/path.tar.zst`
- `archive2tape_manifest.tsv` records type, original size, source relative path,
  and compressed relative path
- `archive2tape_metadata.env` records project, source, archive, and include info

Packems then packs and archives the `compressed` directory. The archive namespace
contains Packems tar objects and `INDEX.txt`, so `listems`/`unpackems` can inspect
and restore the contents without local `.slurm` logs.

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
archive2tape put model_output_dir "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run" \
  --include '*.txt'
```

Hidden paths are skipped by default so `.git`, `.ssh`, `.ipynb_checkpoints`, and
similar files are not archived accidentally. Use `--include-hidden` only when
needed. If a selected directory such as `Meteogram_run.zarr` matches, descendants
inside it are not selected separately.

## Packems Choices

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

## Safety Checks

The tool fails early when:

- `--project` is missing for Slurm/HSM commands
- `ARCHIVE_DIR` does not look like `/arch/<project>/...`
- `--project` does not match the project in the `/arch/...` path
- the work directory is outside `/scratch` without `--allow-non-scratch-work`
- no selected files are found
- compressed outputs or decompressed targets already exist without `--overwrite`

Use `--dry-run` before submitting jobs:

```bash
archive2tape put model_output_dir "/arch/$PROJECT/$USER/my_run" \
  --project "$PROJECT" \
  --work "$GRAVEYARD/my_run" \
  --dry-run
```

## Legacy Archives

Archives created by earlier `archive2tape` versions as plain `.tar.zst` blobs are
not Packems-indexed. Restore those with the old workflow or manual
`slk_helpers` retrieval. New Packems-backed archives should use `get`/`retrieve`
plus `unpack`.

Complete legacy restore example:

```bash
PROJECT=ab1234
ACCOUNT="$PROJECT"
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

## Local Checks

Run local syntax, config, stubbed Packems, and compression round-trip checks:

```bash
bash share/archive2tape/test_archive2tape.sh
```

The Packems tests use local stub binaries, so they do not require Levante or HSM
access.

## Options

```bash
--config FILE                 Read defaults from archive2tape.conf-style KEY=VALUE file
--project PROJECT              Slurm/HSM project, must match /arch/<PROJECT>/...
--account ACCOUNT              Slurm account; defaults to PROJECT
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

Use `--run-now` only in an interactive/compute allocation for real Packems
archive/retrieve commands.
