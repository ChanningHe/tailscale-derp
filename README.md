# tailscale-derp

Container image for [derper](https://pkg.go.dev/tailscale.com/cmd/derper), the Tailscale DERP relay server, built to run behind a TLS-terminating reverse proxy.

## Features

- Built from upstream `tailscale.com/cmd/derper` releases, tracked by Renovate
- Distroless base, runs as UID 65532, no shell
- `-debug` variant with busybox for troubleshooting
- linux/amd64 and linux/arm64
- Plain HTTP on `31478/tcp`, STUN on `3478/udp`; no built-in certificate handling
- SBOM and build provenance attached; third-party licenses in `/usr/share/licenses/derper`

## Tags

Images are published to `ghcr.io/<owner>/tailscale-derp`.

| Tag | Points to |
| --- | --- |
| `1.102.5` | Upstream release |
| `1.102` | Latest build of that upstream minor |
| `a1b2c3d` | Commit of this repository |
| `latest` | Latest build from `main` |

Append `-debug` to any tag for the busybox variant, e.g. `1.102.5-debug`, `latest-debug`.

## Usage

```yaml
services:
  derper:
    image: ghcr.io/<owner>/tailscale-derp:latest
    restart: unless-stopped
    # Replaces the default command, so keep -a and -c.
    command:
      - -a=:31478
      - -c=/var/lib/derper/derper.key
      - -stun-port=3478
      - -verify-clients
    ports:
      - 127.0.0.1:31478:31478/tcp
      - 3478:3478/udp
    volumes:
      - ./data:/var/lib/derper  # optional, see "Key file"
      - /var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock
    read_only: true
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
```

### Key file

`-c` is required because the image runs as non-root; derper only falls back to a default key path when running as root. The file holds the server's private key, which identifies this DERP node. If it does not exist, derper creates it on startup.

Mounting it is optional. Without a volume, a recreated container gets a new key and clients pick it up on reconnect. With `read_only: true`, the path must be a writable mount.

To create a key in advance:

```sh
mkdir -p data && printf '{"PrivateKey":"privkey:%s"}\n' "$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')" > data/derper.key && chmod 600 data/derper.key && sudo chown -R 65532:65532 data
```

### Access and proxy

`-verify-clients` restricts the relay to nodes in the tailnet of the host's `tailscaled`. Without it, anyone can relay traffic through the server.

The reverse proxy must forward `Upgrade: DERP` over HTTP/1.1 and allow long-lived connections. With Caddy:

```
derp.example.com {
	reverse_proxy 127.0.0.1:31478
}
```

STUN cannot go through an HTTP proxy; expose `3478/udp` directly. Do not put the hostname behind a CDN.

Run `derper -h` for all flags.

## License

MIT for the files in this repository. The published images contain derper (BSD-3-Clause) and its dependencies under their own licenses.
