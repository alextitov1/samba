# syntax=docker/dockerfile:1.7
ARG ALMALINUX_BUILD_IMAGE=almalinux:9-minimal@sha256:e03fe7d942a94ad7a72b9fe5eb6af54388b05bc8357151c891f13c023817df98

FROM ${ALMALINUX_BUILD_IMAGE} AS builder

ARG SAMBA_VERSION=4.24.6
ARG SAMBA_SHA512=fb4e4602c0a36ab26ce04457e0ae259eda6f00411468f91227d234385b545e230103c1053820b17193e8f5a1967dc3bf637777e946c72ecbe1f2e82901af737f
WORKDIR /usr/src

RUN microdnf install -y --enablerepo=crb --setopt=install_weak_deps=0 \
        binutils bison ca-certificates curl-minimal diffutils findutils flex gcc gcc-c++ gnutls-devel \
    gnupg2 gzip libattr-devel libcap-devel libtirpc-devel lmdb-devel \
        make perl perl-Parse-Yapp pkgconf-pkg-config popt-devel python3 rpcgen \
        tar which zlib-devel \
    && microdnf clean all

RUN curl --fail --location --proto '=https' --tlsv1.2 \
        --output samba.tar.gz \
        "https://download.samba.org/pub/samba/stable/samba-${SAMBA_VERSION}.tar.gz" \
    && curl --fail --location --proto '=https' --tlsv1.2 \
        --output samba.tar.asc \
        "https://download.samba.org/pub/samba/stable/samba-${SAMBA_VERSION}.tar.asc" \
    && curl --fail --location --proto '=https' --tlsv1.2 \
        --output samba-pubkey.asc \
        "https://download.samba.org/pub/samba/samba-pubkey.asc" \
    && gpg2 --batch --import samba-pubkey.asc \
    && echo "${SAMBA_SHA512}  samba.tar.gz" | sha512sum --check --strict \
    && gzip --decompress samba.tar.gz \
    && gpg2 --batch --verify samba.tar.asc samba.tar \
    && tar --extract --file samba.tar \
    && cd "samba-${SAMBA_VERSION}" \
    && ./configure \
        --prefix=/opt/samba \
        --sysconfdir=/etc/samba \
        --localstatedir=/var \
        --with-statedir=/var/lib/samba \
        --with-privatedir=/var/lib/samba/private \
        --with-cachedir=/var/cache/samba \
        --with-lockdir=/run/samba \
        --with-piddir=/run/samba \
        --with-sockets-dir=/run/samba \
        --without-ad-dc \
        --without-ads \
        --disable-python \
        --disable-cups \
        --disable-iprint \
        --without-pam \
        --without-systemd \
        --without-ldap \
        --without-json \
        --without-winbind \
        --without-libarchive \
        --without-quotas \
        --without-utmp \
        --without-syslog \
        --without-automount \
        --without-regedit \
        --without-winexe \
        --without-fake-kaserver \
        --without-dmapi \
        --without-fam \
        --without-smb1-server \
        --without-systemd-userdb \
        --without-libunwind \
        --without-lttng \
        --disable-avahi \
        --disable-glusterfs \
        --disable-cephfs \
        --disable-spotlight \
        --disable-wsp \
        --without-iconv \
        --without-acl-support \
        --with-shared-modules='!DEFAULT,vfs_catia,vfs_fruit,vfs_streams_xattr' \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make install \
    && install -D -m 0644 COPYING /opt/samba/share/licenses/samba/COPYING \
    && rm -rf /opt/samba/include /opt/samba/lib/pkgconfig \
    && find /opt/samba -type f \( -name '*.so*' -o -perm -u+x \) \
        -exec sh -c 'strip --strip-unneeded "$@" 2>/dev/null || true' _ {} + \
    && /opt/samba/sbin/smbd --version

FROM ${ALMALINUX_BUILD_IMAGE} AS runtime-packages

RUN mkdir -p /runtime-root \
    && microdnf install -y --installroot=/runtime-root --releasever=9 \
        --config=/etc/dnf/dnf.conf --noplugins \
        --setopt=cachedir=/var/cache/dnf --setopt=reposdir=/etc/yum.repos.d \
        --setopt=varsdir=/etc/dnf/vars --setopt=install_weak_deps=0 --nodocs \
        coreutils-single gawk gnutls grep libattr libcap popt sed \
        shadow-utils zlib \
    && rm -rf /runtime-root/var/cache/dnf /runtime-root/var/lib/dnf \
        /runtime-root/var/log/*

FROM scratch AS runtime

ARG SAMBA_VERSION=4.24.6
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.title="AlmaLinux Samba" \
      org.opencontainers.image.description="Minimal standalone Samba file server built from verified upstream source" \
      org.opencontainers.image.version="${SAMBA_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.samba.source="https://download.samba.org/pub/samba/stable/samba-${SAMBA_VERSION}.tar.gz"

COPY --from=runtime-packages /runtime-root/ /

RUN install -d -m 0755 /etc/samba /run/samba /usr/local/libexec/samba /var/cache/samba /var/lib/samba/private \
    && install -m 0644 /dev/null /run/samba/shares.conf \
    && install -d -m 0755 /shares

COPY --from=builder /opt/samba /opt/samba
COPY config/smb.conf /etc/samba/smb.conf
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY scripts/load-env.sh /usr/local/libexec/samba/load-env

RUN chmod 0755 /usr/local/bin/entrypoint /usr/local/libexec/samba/load-env

ENV SAMBA_UID=1000 \
    SAMBA_GID=1000 \
    PATH="/opt/samba/bin:/opt/samba/sbin:${PATH}" \
    LD_LIBRARY_PATH="/opt/samba/lib64:/opt/samba/lib"

EXPOSE 445/tcp
VOLUME ["/shares", "/var/lib/samba"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD smbclient -L //127.0.0.1 -N -m SMB3 >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint"]
