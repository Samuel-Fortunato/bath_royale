#!/usr/bin/env bash
# Database-component feasibility only; no Auth/API or managed migration claim.
set -euo pipefail
umask 077

command -v podman >/dev/null
test "$(podman info --format '{{.Host.Security.Rootless}}')" = true
test "$(podman info --format '{{.Host.Arch}}')" = amd64

# Official self-hosted/v0.8.5 database image; digest tested on x86_64 only.
image='docker.io/supabase/postgres@sha256:5a4314708484bec672de2c09653a5c01fb1c84a998564ac231b0325e2238ed5b'
scratch=$(mktemp -d /tmp/bath-royale-backend-smoke.XXXXXXXX)
container="bath-royale-smoke-${scratch##*.}"
created=false
cleanup() {
  if "$created"; then
    podman rm --force --volumes "$container" >/dev/null
  fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT

# Disposable credential, never printed or passed on the command line.
printf 'POSTGRES_PASSWORD=' > "$scratch/container.env"
head -c 32 /dev/urandom | base64 >> "$scratch/container.env"
podman run --detach --name "$container" --network none \
  --env-file "$scratch/container.env" "$image" > /dev/null
created=true

ready=false
for ((attempt = 0; attempt < 60; attempt++)); do
  if podman exec "$container" pg_isready -h 127.0.0.1 -U postgres -d postgres >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
"$ready" || { echo 'Database readiness failed.' >&2; exit 1; }

podman exec -i "$container" psql -X -U postgres -v ON_ERROR_STOP=1 -d postgres > /dev/null <<'SQL'
CREATE DATABASE smoke_source;
CREATE DATABASE smoke_restored;
SQL
podman exec -i "$container" psql -X -U postgres -v ON_ERROR_STOP=1 -d smoke_source > /dev/null <<'SQL'
CREATE TABLE fictional_bathrooms (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  fictional boolean NOT NULL CHECK (fictional)
);
INSERT INTO fictional_bathrooms VALUES
  ('00000000-0000-4000-8000-000000000001', 'Fictional smoke-test bathroom', true);
SQL
podman exec "$container" pg_dump -U postgres -d smoke_source --schema=public \
  --clean --if-exists --no-owner --no-acl > "$scratch/fictional.sql"
podman exec -i "$container" psql -X -U postgres -v ON_ERROR_STOP=1 \
  --single-transaction -d smoke_restored < "$scratch/fictional.sql" > /dev/null
result=$(podman exec "$container" psql -X -U postgres -At -d smoke_restored \
  -c "SELECT count(*) FROM fictional_bathrooms WHERE id = '00000000-0000-4000-8000-000000000001' AND name = 'Fictional smoke-test bathroom' AND fictional;")
test "$result" = 1
test "$(podman inspect "$container" --format '{{.HostConfig.NetworkMode}}')" = none
test -z "$(podman port "$container")"
echo 'PASS: isolated Supabase PostgreSQL access, fictional insert, SQL export and restore; no published ports.'
