#!/bin/sh
set -e

echo "[Solray] Waiting for database and syncing schema..."
# Creates/updates all tables to match the Prisma schema.
# Safe to run on every start (no-op when already in sync).
npx prisma db push --skip-generate

echo "[Solray] Starting application on port ${PORT:-3000}..."
exec yarn start
