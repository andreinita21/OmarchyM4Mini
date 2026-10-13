# SPDX-License-Identifier: MIT
# Build environment for the J773g (M4 Mac mini) bring-up: kernel, DTBs,
# busybox initramfs and m1n1. Runs natively on arm64 (Docker Desktop on the
# mini itself, or any arm64 Linux host). Driven by tools/j773g-build.sh.
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        bc bison build-essential busybox-static ca-certificates clang cpio \
        device-tree-compiler file flex git kmod libelf-dev libssl-dev lld \
        llvm python3 python3-dev python3-pip python3-venv rsync swig xz-utils \
        yamllint zstd \
    && rm -rf /var/lib/apt/lists/*

# dt-schema for "make dtbs_check" (kept in a venv; Debian's Python is
# externally managed).
RUN python3 -m venv /opt/dtschema \
    && /opt/dtschema/bin/pip install --no-cache-dir dtschema yamllint
ENV PATH=/opt/dtschema/bin:$PATH

WORKDIR /work
