#!/usr/bin/env bash
# Example wrapper: run archive2tape put on one COSMO-SPECS ensemble_output run.
#
# PROJECT must equal the first segment after /arch/ in ARCHIVE_ROOT (see README).
# --account uses $USER; switch to your Slurm billing account if sbatch rejects this.
# Remaining paths are deployment-specific—adjust CS_* and WORK_ROOT before use.

set -euo pipefail

PROJECT=bb1262
CS_RUN="cs-eriswil__20260428_094815"
CS_RUNS_DIR="/work/bb1262/user/schimmel/cosmo-specs-torch/cosmo-specs-runs/RUN_ERISWILL_200x160x100/ensemble_output/"

DATA_ROOT="${CS_RUNS_DIR}/${CS_RUN}"
ARCHIVE_ROOT="/arch/${PROJECT}/cosmo-specs/ensemble_output/${CS_RUN}/"
WORK_ROOT="/scratch/b/${USER}/archive2tape"

archive2tape put "$DATA_ROOT" "$ARCHIVE_ROOT" --project "$PROJECT" \
    --account "${USER}" \
    --work "$WORK_ROOT" \
    --include '*.nc' \
    --allow-huge \
    --overwrite # --dry-run



