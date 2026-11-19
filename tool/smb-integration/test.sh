#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
image=azusa-smb-integration
container=''
cleanup() {
  if [ -n "$container" ]; then docker stop "$container" >/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker build -t "$image" tool/smb-integration
for dialect in SMB2_10 SMB3_11; do
  container=$(docker run --rm -d -p 127.0.0.1:445:445 "$image" "$dialect")
  attempts=0
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$container")" = healthy ]; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 20 ]; then docker logs "$container"; exit 1; fi
    sleep 1
  done
  printf '\nTesting Samba with %s and mandatory signing\n' "$dialect"
  AZU_SMB_INTEGRATION=1 flutter test test/live_smb_test.dart
  cleanup
  container=''
done
