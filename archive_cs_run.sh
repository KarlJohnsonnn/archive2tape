#!/usr/bin/env bash
set -euo pipefail

PROJECT=bb1262
SLURM_ACCOUNT="${SLURM_ACCOUNT:-$PROJECT}"
# export PACK_PARTITION=shared  # uncomment if compute rejects --account/partition pairing
CS_RUN="cs-eriswil__20260428_094815"
CS_RUNS_DIR="/work/bb1262/user/schimmel/cosmo-specs-torch/cosmo-specs-runs/RUN_ERISWILL_200x160x100/ensemble_output/"
ALLOW_HUGE=1
OVERWRITE=1
ARCHIVE_ROOT="/arch/${PROJECT}/cosmo-specs/ensemble_output/${CS_RUN}/"
# POSIX scratch is per login; Slurm --account must be an account you belong to (often same as PROJECT).
WORK_ROOT="/scratch/b/${USER}/archive2tape"
INCLUDE_PATTERNS="*.nc"
ALLOW_NON_SCRATCH_WORK=0
INCLUDE_HIDDEN=0

archive2tape put ${CS_RUNS_DIR}/${CS_RUN} $ARCHIVE_ROOT --project $PROJECT \
    --account "$SLURM_ACCOUNT" \
    --work "$WORK_ROOT" \
    --include ${INCLUDE_PATTERNS} \
    --allow-huge \
    --overwrite # --dry-run



