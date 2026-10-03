# tailscale-derp

Container image for [derper](https://pkg.go.dev/tailscale.com/cmd/derper), the Tailscale DERP relay server.

## Features

- Follows upstream: Renovate tracks Tailscale releases and the image version matches upstream
- Fresh toolchain: the Go compiler and base images are bumped by Renovate
- Secure by default: **distroless**, **non-root (UID 65532)**, no shell, SBOM and signed build provenance
- Small: about 30 MB
- Multi-arch: `linux/amd64` and `linux/arm64`

## Usage

```yaml
services:
  derper:
    image: ghcr.io/channinghe/tailscale-derp:latest
    restart: unless-stopped
    # Replaces the default command, so keep -a and -c.
    command:
      - -a=:31478
      - -c=/var/lib/derper/derper.key
      - -stun-port=3478
      # - -verify-clients
    ports:
      # Plain HTTP, for the reverse proxy on this host only.
      # Use 31478:31478/tcp if the proxy runs on another machine.
      - 127.0.0.1:31478:31478/tcp
      # STUN must be reachable from clients directly.
      - 3478:3478/udp
    volumes:
      - ./data:/var/lib/derper  # optional, see "Key file"
      # - /var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock
    read_only: true
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
```

### Key file

`-c` is mandatory because the image runs as non-root. The file holds the server's private key and is created on first start if missing. Mounting it is optional unless `read_only: true` is set; without a mount the key changes when the container is recreated, which clients handle on reconnect.

To create one in advance:

```sh
mkdir -p data && \
  printf '{"PrivateKey":"privkey:%s"}\n' "$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')" \
    > data/derper.key && \
  chmod 600 data/derper.key && \
  sudo chown -R 65532:65532 data
```

### Reverse proxy

derper serves plain HTTP; TLS is handled by the proxy. Caddy obtains and renews the certificate on its own. Point a DNS record at the host and open `80/tcp`, `443/tcp` and `3478/udp`.

```
{
	email admin@example.com
}

derp.example.com {
	reverse_proxy 127.0.0.1:31478 {
		# Keep DERP connections open across Caddy config reloads.
		stream_close_delay 5m
	}
}

# Captive portal check used by clients when the DERP node sets CanPort80.
http://derp.example.com {
	handle /generate_204 {
		reverse_proxy 127.0.0.1:31478
	}
	handle {
		redir https://{host}{uri} permanent
	}
}
```

Other proxies work too if they forward `Upgrade: DERP` over HTTP/1.1 and do not time out idle connections after less than a few minutes. STUN cannot be proxied; `3478/udp` must reach the container directly.

Then add the node to the `derpMap` in your [tailnet policy file](https://tailscale.com/kb/1118/custom-derp-servers).

## Security

- Enable `-verify-clients` and mount the host's `tailscaled` socket, or use `-verify-client-url`. Without either, anyone can relay traffic through your server.
- Only the proxy should reach `31478/tcp`. Publish it as `127.0.0.1:31478:31478` or keep it on an internal network.
- Pin a version or commit tag in production instead of `latest`, and use `-debug` only while troubleshooting.

Run `derper -h` for all flags.

## Tags

Images are published to `ghcr.io/channinghe/tailscale-derp`.

| Tag | Points to |
| --- | --- |
| `1.102.5` | Upstream release |
| `1.102` | Latest build of that upstream minor |
| `a1b2c3d` | Commit of this repository |
| `latest` | Latest build from `main` |

Append `-debug` to any tag for a variant with a busybox shell, e.g. `1.102.5-debug`, `latest-debug`.

## License

MIT for the files in this repository. The published images contain derper (BSD-3-Clause) and its dependencies under their own licenses, included in `/usr/share/licenses/derper`.
