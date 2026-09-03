# AlmaLinux Samba Container

A minimal standalone SMB3 file server built from verified upstream Samba source on AlmaLinux 10 with an AlmaLinux 10 Micro runtime.

## Scope

The image provides `smbd` on TCP port 445, guest or local-user authentication, mounted `smb.conf` support, and `amd64`/`arm64` builds. It intentionally excludes NetBIOS discovery, SMB1/SMB2, printing, Active Directory roles, LDAP integration, and the broad configuration interface of `dperson/samba`.

## Build and test

Docker is the only local prerequisite.

- `make build` builds `samba-container:test`.
- `make test` builds the image and runs isolated client/server integration tests in Docker.
- `make config` validates the bundled configuration.

## Run

Prepare a named volume for the default runtime UID/GID, then start the server with an environment-defined guest-writable `data` share:

```console
docker volume create samba-data
docker run --rm --entrypoint chown \
  -v samba-data:/shares \
  ghcr.io/OWNER/REPOSITORY:latest \
  1000:1000 /shares
docker run --rm -p 445:445 \
  -e 'SHARE1=data;/shares;yes;no;yes' \
  -v samba-data:/shares \
  ghcr.io/OWNER/REPOSITORY:latest
```

The bundled `smb.conf` contains global settings but no shares. Define shares with `SHARE<n>` variables or mount a reviewed configuration over `/etc/samba/smb.conf`. Mount persistent storage at every configured share path. The image-layer `/shares` directory is root-owned with mode `0755`, so everyone can read and traverse it, but mounted storage must be prepared separately for writes.

### Service identity

The entrypoint creates the filesystem service user and group named `samba` at startup. Their numeric IDs are configurable:

- `SAMBA_UID` defaults to `1000`.
- `SAMBA_GID` defaults to `1000`.

Both values must be positive integers. The names remain fixed because the bundled configuration uses `force user = samba` and `force group = samba`. These variables configure the identity used for share file operations; they are separate from authenticated accounts created by `USER<n>`.

Startup does not change ownership of `/shares`, generated share paths, or existing files. Prepare bind mounts or volumes for the selected numeric IDs before starting the server. Overriding the image entrypoint bypasses creation of the named account, so preparatory commands should use numeric IDs rather than `samba:samba`.

The runtime permits a requested ID already assigned to another image account. In that case both account names share the same Unix permission identity; avoid duplicate IDs unless that behavior is intentional.

### Environment users and shares

Numbered environment variables create local Samba users and generate shares at startup:

- `USER<n>=username;password[;UID;group;GID]`
- `SHARE<n>=name;path[;browsable;readonly;guest;users;admins;writelist;comment]`

The three share booleans default to `yes` when empty or omitted. User lists are comma-separated. Use `all` or an empty value for unrestricted `users`, and `none` or an empty value for no `admins` or `writelist`. Variables are processed in numeric order by the environment loader and appended to `/run/samba/shares.conf`. The entrypoint recreates this aggregate generated configuration on every startup before running its configuration loaders, and the bundled `smb.conf` includes it.

```console
docker run --rm -p 445:445 \
  -e 'USER1=alex;change-me' \
  -e 'SHARE1=mediaserver;/mediaserver;yes;yes;yes' \
  -e 'SHARE2=admin;/mediaserver;yes;no;no;alex' \
  -v samba-media:/mediaserver \
  ghcr.io/OWNER/REPOSITORY:latest
```

The equivalent Kubernetes container environment is:

```yaml
env:
  - name: USER1
    value: alex;change-me
  - name: SHARE1
    value: mediaserver;/mediaserver;yes;yes;yes
  - name: SHARE2
    value: admin;/mediaserver;yes;no;no;alex
```

Missing share directories are created, but startup does not recursively alter ownership or permissions. Ensure mounted paths are writable by the identity selected by `force user` and `force group` in `smb.conf` (the bundled configuration defaults to UID/GID 1000 through `SAMBA_UID` and `SAMBA_GID`).

> **Security warning:** `USER<n>` contains the password directly. Environment values can be exposed through container inspection, workload specifications, process environments, logs, and deployment systems. Restrict access to these systems and prefer a separately managed configuration/state approach when that exposure is unacceptable.

## Configuration and storage

- Configuration: `/etc/samba/smb.conf`
- Generated startup configuration: `/run/samba/shares.conf`
- Shared data: `/shares`
- Persistent Samba state: `/var/lib/samba`
- Runtime state: `/run/samba`
- Cache: `/var/cache/samba`

The startup script runs its configuration loaders and then validates the combined configuration with `testparm`. Set `SAMBA_CONFIG_FILE` when using a non-default primary configuration. To use environment-generated shares with a custom primary configuration, include `/run/samba/shares.conf` from that file. `SAMBA_SHARES_CONFIG_FILE` may override the generated file path when the primary configuration includes the same path.

On SELinux hosts, label bind mounts appropriately for container access. Align host ownership and permissions with `SAMBA_UID` and `SAMBA_GID` before startup. Changing these values does not migrate ownership of existing data.

## Security model

- SMB3 only; NetBIOS and printing are disabled.
- Build tools are absent from the runtime stage.
- Runtime packages are assembled in an AlmaLinux 10 Minimal stage and copied into the package-manager-free AlmaLinux 10 Micro image.
- Upstream archives are verified by SHA-512 and Samba's detached signature.
- Local integration tests exercise a real SMB client/server exchange with `make test`.

The daemon starts as root because binding port 445 and Samba account setup require privileges. Share operations are forced to the unprivileged `samba` identity by the default configuration. Arbitrary rootless execution is not currently supported.

## Releases and maintenance

- Full tags, such as `4.24.6`, identify a Samba release.
- Minor-line tags, such as `4.24`, follow the latest accepted patch in that line.
- `latest` points to the most recently validated stable release.
- Image digests are the immutable deployment reference.

Dependabot proposes base-image digest and GitHub Action updates. Push a `vX.Y.Z` Git tag to build and publish a `linux/amd64` and `linux/arm64` image to GHCR. The workflow publishes full-version and minor-line tags together with `latest`.

Only explicitly published release lines are supported. Security fixes are delivered by updating Samba or rebuilding from an updated AlmaLinux digest. AlmaLinux major-version changes require a separately reviewed migration.

## Migration from `dperson/samba`

The numbered `USER<n>` and `SHARE<n>` formats retain the corresponding legacy field order and defaults. Other legacy environment controls and command flags are not supported; move those settings into a reviewed mounted `smb.conf`. Migrate one share at a time, preserve a backup of data and Samba state, test client access, and retain the previous image digest for rollback.

## License

Project-owned scripts and configuration use the MIT license. Samba is distributed under GPL-3.0-or-later; its license is included in the built image. The exact upstream source URL is recorded in the image metadata and `Dockerfile`.
