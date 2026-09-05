<p align="center">
  <img src="https://raw.githubusercontent.com/alextitov1/samba/main/assets/samba-logo.svg" alt="Samba logo" width="180">
</p>

# Samba Container

Share files over your network (Windows, Mac, Linux) using Docker.

## Quick start

```console
# <host-folder> is the folder you want to share over the network
docker run --rm -p 445:445 \
  -e 'SHARE1=data;/shares;yes;no;yes' \
  -v <host-folder>:/shares \
  4esnok/samba:latest
```

That creates a share named `data`, open to anyone on the network without a password, backed by the `<host-folder>` folder on your machine. Connect to it from your file browser at `\\<server-ip>\data` (Windows) or `smb://<server-ip>/data` (Mac/Linux).

Prefer Docker Compose? Save this as `compose.yaml` and run `docker compose up`:

```yaml
services:
  samba:
    image: 4esnok/samba:latest
    ports:
      - "445:445"
    environment:
      SHARE1: data;/shares;yes;no;yes
    volumes:
      - <host-folder>:/shares
```

> **Note**
> The container starts as root - that's needed to bind port 445 - but `smbd` writes files to shares as the `samba` user, UID/GID `1000` by default. Files placed in `<host-folder>` will be owned by that ID. Change it with the `SAMBA_UID` / `SAMBA_GID` environment variables if you need files to be owned by a different user on the host.


---

## License

Project code is MIT. Samba itself is GPL-3.0-or-later; its license is included in the built image.
