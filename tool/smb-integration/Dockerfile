FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends samba smbclient \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --no-create-home --shell /usr/sbin/nologin azusa \
    && printf 'azusa-integration-only\nazusa-integration-only\n' | smbpasswd -s -a azusa \
    && mkdir /srv/smb && chown azusa /srv/smb
COPY run.sh /usr/local/bin/run-samba-test
HEALTHCHECK --interval=2s --timeout=3s --start-period=5s \
    CMD smbclient //127.0.0.1/media -U 'azusa%azusa-integration-only' -c 'ls' >/dev/null
ENTRYPOINT ["/bin/sh", "/usr/local/bin/run-samba-test"]
