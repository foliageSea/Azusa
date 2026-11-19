#!/bin/sh
set -eu
# This container is for local integration tests, not production.
protocol=${1:-SMB3_11}
case "$protocol" in
  SMB2_10|SMB3_11) ;;
  *) printf '%s\n' 'Expected SMB2_10 or SMB3_11' >&2; exit 2 ;;
esac
cat >/etc/samba/smb.conf <<EOF
[global]
  server role = standalone server
  server min protocol = $protocol
  server max protocol = $protocol
  server signing = mandatory
  smb ports = 445
  disable netbios = yes
  map to guest = Never
  wide links = no
  follow symlinks = no
  log file = /dev/stdout

[media]
  path = /srv/smb
  valid users = azusa
  read only = no

[readonly]
  path = /srv/smb
  valid users = azusa
  read only = yes
EOF
# Force QUERY_DIRECTORY to exceed a single SMB response in the integration test.
mkdir /srv/smb/pagination
for i in $(seq 1 1400); do
  touch "/srv/smb/pagination/page-$(printf '%04d' "$i")-abcdefghijklmnopqrstuvwxyz0123456789.txt"
done
chown -R azusa /srv/smb/pagination
exec smbd --foreground --no-process-group
