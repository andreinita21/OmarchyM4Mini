#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the Omarchy image for the M4 Mac mini (J773g) inside the Arch Linux
# ARM container (tools/j773g-image.sh runs this as root, --privileged).
#
# A trimmed, unsigned relative of omacom/omarchy-mac-installer's
# image-builder/bin/build-mac-image (MIT): the same order of operations and the
# same on-disk contract (btrfs @ @home @log @pkg + sealed @factory, ext4 /boot,
# FAT ESP with m1n1 stage 2 and Limine), with the J773g packages from
# packaging/j773g/ in place of linux-aurora / m1n1-aurora / uboot-asahi, and
# no candidate-set signing. Plan: docs/j773g-phase3-plan.md §4.
#
#   image-build.sh --pkgs DIR --cache DIR --out DIR [--channel edge] [--keep-going]
set -euo pipefail
umask 022

HERE=$(cd "$(dirname "$0")" && pwd)
CHANNEL=edge
PLATFORM=aarch64-apple
PLATFORM_COMPATIBLE=apple,arm-platform   # what the chroot's device tree says; the manifest decides the platform
KERNEL=linux-gravity-m4
J773G_PACKAGES=(linux-gravity-m4 m1n1-gravity uboot-gravity omarchy-j773g)
PLATFORM_PACKAGES=(mkinitcpio limine limine-snapper-sync limine-mkinitcpio-hook asahi-scripts asahi-fwextract)
APPLE_AUDIO=(alsa-ucm-conf-asahi asahi-audio)
BOOTSTRAP=(base sudo btrfs-progs dosfstools e2fsprogs archlinuxarm-keyring asahi-alarm-keyring omarchy-keyring)
RUNTIME=omarchy-dev            # the edge runtime with the aarch64-apple platform (basecamp/omarchy master)
SETTINGS=omarchy-settings-dev

OMARCHY_SERVER='https://pkgs.omarchy.org/edge/$arch'
ASAHI_SERVER='https://github.com/asahi-alarm/asahi-alarm/releases/download/aarch64'
ALARM_SERVER='https://arm-mirror.omarchy.org/$arch/$repo'
OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
ASAHI_KEY=12CE6799A94A3F1B5DDFFE88F576553597FB8FEB

# Fixed identities, as the official image has them (the installer template
# and fstab name them). Different from Omarchy's own so the two never collide.
ROOT_UUID=4a373733-4752-4f4f-5400-000000000001
BOOT_UUID=4a373733-424f-4f54-0000-000000000001
ESP_VOLUME_ID=0x4a373733
ESP_SIZE=524288000          # 500 MB, Gravity's and Omarchy's size
BOOT_SIZE=2147483648        # 2 GiB
ROOT_SIZE=34359738368       # 32 GiB template size; the file is shrunk to content, growfs expands

pkgs="" cache="" out="" keep_going=0
while (($#)); do
  case $1 in
    --pkgs) pkgs=$2; shift ;;
    --cache) cache=$2; shift ;;
    --out) out=$2; shift ;;
    --channel) CHANNEL=$2; shift ;;
    --keep-going) keep_going=1 ;;
    *) echo "unknown option $1" >&2; exit 64 ;;
  esac
  shift
done
[[ -d $pkgs && -d $cache && -d $out ]] || { echo "usage: $0 --pkgs DIR --cache DIR --out DIR" >&2; exit 64; }
(( EUID == 0 )) || { echo "run as root (privileged container)" >&2; exit 1; }

work=/work/image
logs=$out/logs
target=$work/target
top=$work/top
mkdir -p "$work" "$logs" "$target" "$top" "$cache/pkg"
: >"$logs/build.log"

say() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$logs/build.log"; }
fail() { say "FAILED: $*"; exit 1; }

# ---------------------------------------------------------------- cleanup ---
api_mounts=()
cleanup() {
  local status=$?
  set +e
  unmount_api
  for m in "$target/var/cache/pacman/pkg" "$target/boot/efi" "$target/boot" "$target/var/log" "$target/home" "$target"; do
    findmnt -n "$m" >/dev/null 2>&1 && umount -R "$m" 2>/dev/null
  done
  findmnt -n "$top" >/dev/null 2>&1 && umount "$top"
  losetup -D 2>/dev/null
  ((status == 0)) || say "build stopped with status $status; logs in $logs"
}
trap cleanup EXIT

# -------------------------------------------------- build host keyring/pacman --
# The container trusts Arch Linux ARM; add the Asahi ALARM and Omarchy keys by
# installing their keyring packages here, then check the fingerprints.
prepare_host_trust() {
  say "host trust: Asahi ALARM and Omarchy keyrings"
  cat >"$work/bootstrap.conf" <<EOF
[options]
Architecture = aarch64
SigLevel = Never
DisableSandbox
[omarchy]
Server = $OMARCHY_SERVER
[asahi-alarm]
Server = $ASAHI_SERVER
EOF
  local kr
  pacman --config "$work/bootstrap.conf" -Sy --noconfirm >>"$logs/host-trust.log" 2>&1 || fail "cannot sync the Omarchy/Asahi databases"
  pacman --config "$work/bootstrap.conf" -Sw --noconfirm --cachedir "$cache/pkg" omarchy-keyring asahi-alarm-keyring >>"$logs/host-trust.log" 2>&1 ||
    fail "cannot download the keyring packages"
  for kr in omarchy-keyring asahi-alarm-keyring; do
    pacman -U --noconfirm --config <(sed 's/^LocalFileSigLevel.*/LocalFileSigLevel = Never/' /etc/pacman.conf) \
      "$(ls -t "$cache"/pkg/$kr-*.pkg.tar.* | head -1)" >>"$logs/host-trust.log" 2>&1 || fail "cannot install $kr on the build host"
  done
  pacman-key --populate archlinuxarm asahi-alarm omarchy >>"$logs/host-trust.log" 2>&1 || fail "pacman-key --populate failed"
  pacman-key --finger "$OMARCHY_KEY" >/dev/null 2>&1 || fail "the Omarchy keyring does not hold $OMARCHY_KEY"
  pacman-key --finger "$ASAHI_KEY" >/dev/null 2>&1 || fail "the Asahi ALARM keyring does not hold $ASAHI_KEY"
}

# The build's pacman configuration: Omarchy's Apple Silicon order ([omarchy],
# [asahi-alarm], Arch Linux ARM) plus a local, unsigned [j773g] file repository
# for packaging/j773g's packages. Signed packages are still verified.
write_build_pacman_config() {
  say "build pacman.conf with the local [j773g] repository"
  rm -rf "$work/j773g-repo" && mkdir -p "$work/j773g-repo"
  local n=0 f
  for f in "$pkgs"/*.pkg.tar.*; do
    [[ -f $f && $f != *.sig ]] || continue
    ln -f "$f" "$work/j773g-repo/" 2>/dev/null || cp "$f" "$work/j773g-repo/"
    n=$((n + 1))
  done
  ((n >= 4)) || fail "fewer than 4 packages in $pkgs (need ${J773G_PACKAGES[*]})"
  repo-add -q "$work/j773g-repo/j773g.db.tar.gz" "$work"/j773g-repo/*.pkg.tar.* >>"$logs/build.log" 2>&1 || fail "repo-add failed"
  cat >"$work/build.conf" <<EOF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
CacheDir = $cache/pkg
DisableSandbox
ParallelDownloads = 5

[j773g]
SigLevel = Never
Server = file://$work/j773g-repo

[omarchy]
Server = $OMARCHY_SERVER

[asahi-alarm]
Server = $ASAHI_SERVER

[core]
Server = $ALARM_SERVER
[extra]
Server = $ALARM_SERVER
[alarm]
Server = $ALARM_SERVER
[aur]
Server = $ALARM_SERVER
EOF
}

# ------------------------------------------------------------- the images ---
make_filesystems() {
  say "filesystems: btrfs root ($ROOT_UUID), ext4 boot, FAT ESP"
  rm -f "$work"/{root,boot,esp}-build.img
  truncate -s 20G "$work/root-build.img"
  truncate -s "$BOOT_SIZE" "$work/boot-build.img"
  truncate -s "$ESP_SIZE" "$work/esp-build.img"
  mkfs.btrfs -q -f -L OMARCHY_ROOT -U "$ROOT_UUID" "$work/root-build.img"
  mkfs.ext4 -q -F -L OMARCHY_BOOT -U "$BOOT_UUID" "$work/boot-build.img"
  mkfs.vfat -F 32 -n OMARCHYESP -i "${ESP_VOLUME_ID#0x}" "$work/esp-build.img" >/dev/null
  root_loop=$(losetup -f --show "$work/root-build.img")
  mount -o compress=zstd "$root_loop" "$top"
  local s
  for s in @ @home @log @pkg; do btrfs subvolume create "$top/$s" >/dev/null; done
  mount -o subvol=@,compress=zstd "$root_loop" "$target"
  mkdir -p "$target/home" "$target/var/log" "$target/var/cache/pacman/pkg" "$target/boot"
  mount -o subvol=@home,compress=zstd "$root_loop" "$target/home"
  mount -o subvol=@log,compress=zstd "$root_loop" "$target/var/log"
  mount -o subvol=@pkg,compress=zstd "$root_loop" "$target/var/cache/pacman/pkg"
  mount -o loop "$work/boot-build.img" "$target/boot"
  mkdir -p "$target/boot/efi"
  mount -o loop "$work/esp-build.img" "$target/boot/efi"
  # asahi-scripts' builder marker keeps update-m1n1 on this ESP.
  mkdir -p "$target/boot/efi/m1n1" "$target/boot/efi/omarchy" "$target/boot/omarchy"
  : >"$target/boot/efi/.builder"
  ESP_UUID=$(blkid -s UUID -o value "$work/esp-build.img")
}

# --------------------------------------------------- isolated chroot (API) ---
# The chroot never sees the build host's hardware: a device tree naming the
# image's platform, UEFI without EFI variables, no PCI/USB/input/DMI.
mount_api() {
  local root=$target node point
  mkdir -m 0755 -p "$root/dev" "$root/run" "$root/sys" "$root/proc" "$root/etc/pacman.d"
  mkdir -m 1777 -p "$root/tmp"
  _m() { local p=$1; shift; findmnt -n "$p" >/dev/null 2>&1 && return 0; mount "$@" "$p" || fail "cannot mount ${p#"$root"}"; api_mounts=("$p" "${api_mounts[@]}"); }
  _m "$root/proc" -t proc -o nosuid,noexec,nodev proc
  _m "$root/sys" -t sysfs -o nosuid,noexec,nodev,ro sysfs
  _m "$root/sys/firmware" -t tmpfs -o mode=0755,nosuid,noexec,nodev,size=1m tmpfs
  mkdir -p "$root/sys/firmware/devicetree/base" "$root/sys/firmware/efi/efivars"
  printf '%s\0' "$PLATFORM_COMPATIBLE" >"$root/sys/firmware/devicetree/base/compatible"
  printf 'Omarchy image (%s)\0' "$PLATFORM" >"$root/sys/firmware/devicetree/base/model"
  mount -o remount,ro,bind "$root/sys/firmware" 2>/dev/null || true
  for point in "$root/sys/class/dmi" "$root/sys/devices/virtual/dmi" "$root/sys/bus/pci" "$root/sys/bus/usb" "$root/sys/class/input"; do
    [[ -d $point ]] || continue
    _m "$point" -t tmpfs -o mode=0755,nosuid,noexec,nodev,size=64k tmpfs
    [[ $point != */sys/bus/* ]] || mkdir -p "$point/devices" "$point/drivers"
  done
  _m "$root/dev" -t tmpfs -o mode=0755,nosuid tmpfs
  mkdir -p "$root/dev/pts" "$root/dev/shm" "$root/dev/disk/by-uuid"
  _m "$root/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec devpts
  _m "$root/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev tmpfs
  for node in null zero random urandom tty; do
    touch "$root/dev/$node"; _m "$root/dev/$node" --bind "/dev/$node"
  done
  # This build's loop devices, for the tools that name the root by UUID.
  while read -r name file; do
    [[ $file == "$work"/* ]] || continue
    node=${name##*/}; touch "$root/dev/$node"; _m "$root/dev/$node" --bind "$name"
    case $file in
      */root-build.img) ln -sfn "/dev/$node" "$root/dev/disk/by-uuid/$ROOT_UUID" ;;
      */boot-build.img) ln -sfn "/dev/$node" "$root/dev/disk/by-uuid/$BOOT_UUID" ;;
      */esp-build.img) ln -sfn "/dev/$node" "$root/dev/disk/by-uuid/$ESP_UUID" ;;
    esac
  done < <(losetup -n -O NAME,BACK-FILE --list 2>/dev/null || true)
  [[ -L $root/dev/fd ]] || ln -s /proc/self/fd "$root/dev/fd"
  [[ -L $root/dev/stdin ]] || ln -s /proc/self/fd/0 "$root/dev/stdin"
  [[ -L $root/dev/stdout ]] || ln -s /proc/self/fd/1 "$root/dev/stdout"
  [[ -L $root/dev/stderr ]] || ln -s /proc/self/fd/2 "$root/dev/stderr"
  _m "$root/run" -t tmpfs -o mode=0755,nosuid,noexec tmpfs
  mkdir -m 0755 -p "$root/run/lock"
  _m "$root/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid tmpfs
}
unmount_api() {
  local p
  for p in "${api_mounts[@]}"; do umount -l "$p" 2>/dev/null || true; done
  api_mounts=()
}
in_target() {
  chroot "$target" env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root TERM=dumb LANG=C.UTF-8 \
    OMARCHY_PATH=/usr/share/omarchy "$@"
}
target_pacman() {
  pacman --config "$work/build.conf" --root "$target" --dbpath "$target/var/lib/pacman" \
    --hookdir "$target/etc/pacman.d/hooks" --gpgdir /etc/pacman.d/gnupg --noconfirm "$@"
}

# ------------------------------------------------------------ installation ---
install_bootstrap() {
  say "install: base + $SETTINGS (alone, so its platform guard is resident first)"
  mkdir -m 0755 -p "$target/var/lib/pacman" "$target/etc/pacman.d/hooks"
  mount_api
  target_pacman -Sy >>"$logs/install.log" 2>&1 || fail "pacman -Sy (logs/install.log)"
  target_pacman -S "${BOOTSTRAP[@]}" "$SETTINGS" >>"$logs/install.log" 2>&1 || fail "bootstrap install (logs/install.log)"
  unmount_api
}

write_image_target() {
  say "image-target manifest: platform=$PLATFORM"
  install -d -m 0755 "$target/var/lib/omarchy" "$target/var/lib/omarchy/image"
  printf 'format=1\nplatform=%s\nbuilder=OmarchyM4Mini tools/j773g/image-build.sh\nbuilder_commit=%s\nimage_profile=lab\n' \
    "$PLATFORM" "${BUILDER_COMMIT:-unknown}" >"$target/var/lib/omarchy/image/target"
  chmod 0644 "$target/var/lib/omarchy/image/target"
}

# Names from a runtime package list, dropping comments; packages the pinned
# repositories lack are recorded as unavailable instead of stopping the build.
list_names() { awk 'NF && $1 !~ /^#/ { print $1 }' "$1"; }
available() {
  local name out
  : >"$work/unavailable"
  for name in "$@"; do
    if out=$(target_pacman -Sp --print-format x "$name" 2>&1); then
      printf '%s\n' "$name"
    elif grep -Fq "target not found: $name" <<<"$out"; then
      printf '%s\n' "$name" >>"$work/unavailable"
    else
      fail "cannot resolve $name: $out"
    fi
  done
}

install_runtime() {
  say "install: $RUNTIME, then the base + aarch64 package lists"
  mount_api
  target_pacman -S "$RUNTIME" >>"$logs/install.log" 2>&1 || fail "runtime install (logs/install.log)"
  local lists=$target/usr/share/omarchy/install base=() excluded=()
  [[ -f $lists/omarchy-base.packages ]] || fail "the runtime ships no omarchy-base.packages"
  mapfile -t excluded < <([[ -f $lists/omarchy-x86_64-only.packages ]] && list_names "$lists/omarchy-x86_64-only.packages")
  mapfile -t base < <( { list_names "$lists/omarchy-base.packages"; [[ -f $lists/omarchy-aarch64.packages ]] && list_names "$lists/omarchy-aarch64.packages"; } |
    grep -vxF -f <(printf '%s\n' "${excluded[@]}" x) )
  mapfile -t base < <(available "${base[@]}")
  [[ ! -s $work/unavailable ]] || say "unavailable on aarch64, left out: $(paste -sd' ' "$work/unavailable")"
  cp "$work/unavailable" "$out/unavailable" 2>/dev/null || true
  target_pacman -S "${base[@]}" >>"$logs/install.log" 2>&1 || fail "base package install (logs/install.log)"
  unmount_api
}

install_apple_set() {
  say "install: Apple set (omarchy-mac, omarchy-mac-boot...), the J773g packages, platform and audio packages"
  local lists=$target/usr/share/omarchy/install apple=()
  [[ -f $lists/omarchy-aarch64-apple.packages ]] || fail "the runtime ships no omarchy-aarch64-apple.packages"
  mapfile -t apple < <(list_names "$lists/omarchy-aarch64-apple.packages")
  mount_api
  # Arch Linux ARM's rootfs kernel must not stay beside ours.
  target_pacman -Rdd linux-aarch64 >>"$logs/install.log" 2>&1 || true
  target_pacman -S "${apple[@]}" "${J773G_PACKAGES[@]}" "${PLATFORM_PACKAGES[@]}" "${APPLE_AUDIO[@]}" >>"$logs/install.log" 2>&1 ||
    fail "Apple set install (logs/install.log)"
  unmount_api
  local installed
  installed=$(pacman --dbpath "$target/var/lib/pacman" -Q)
  grep -q "^$KERNEL " <<<"$installed" || fail "$KERNEL is not installed"
  ! grep -Eq '^linux-(asahi|aurora|aarch64) ' <<<"$installed" || fail "another kernel is installed beside $KERNEL"
  [[ -s $target/usr/lib/modules/*-ARCH/dtbs/t8132-j773g.dtb ]] || fail "the kernel package ships no t8132-j773g.dtb"
}

# --------------------------------------------------------------- configure ---
write_fstab() {
  cat >"$target/etc/fstab" <<EOF
# /etc/fstab — generated by the OmarchyM4Mini image builder
UUID=$ROOT_UUID  /                      btrfs  noatime,compress=zstd,x-systemd.growfs,subvol=@       0 0
UUID=$ROOT_UUID  /home                  btrfs  noatime,compress=zstd,subvol=@home   0 0
UUID=$ROOT_UUID  /var/log               btrfs  noatime,compress=zstd,subvol=@log    0 0
UUID=$ROOT_UUID  /var/cache/pacman/pkg  btrfs  noatime,compress=zstd,subvol=@pkg    0 0
UUID=$BOOT_UUID  /boot                  ext4   defaults,noatime       0 2
UUID=$ESP_UUID   /boot/efi              vfat   umask=0077              0 2
EOF
}

finalize_root() {
  bash "$HERE/finalize-root" --root "$target" >>"$logs/finalize.log" 2>&1 || fail "finalize-root (logs/finalize.log)"
  # The J773g boot line from the ladder (PLAN.md §5); keep Omarchy's quiet
  # defaults in GRUB_CMDLINE_LINUX_DEFAULT, add the hardware options here.
  if [[ -n ${J773G_CMDLINE:-} ]]; then
    sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 $J773G_CMDLINE\"|" "$target/etc/default/grub"
  fi
}

prepare_target_keyring() {
  say "image keyring (archlinuxarm, asahi-alarm, omarchy)"
  rm -rf "$target/etc/pacman.d/gnupg"
  mount_api
  in_target pacman-key --init >>"$logs/keyring.log" 2>&1 || fail "pacman-key --init in the image (logs/keyring.log)"
  in_target pacman-key --populate archlinuxarm asahi-alarm omarchy >>"$logs/keyring.log" 2>&1 || fail "pacman-key --populate in the image"
  unmount_api
}

# The image's own pacman.conf while the runtime sets it up: the same
# repositories as the build (with [j773g] for our packages), then the
# runtime's Apple Silicon template once setup is done.
run_system_setup() {
  say "omarchy-apply-system --defer-provisioning --first-install (long)"
  install -m 0644 "$work/build.conf" "$target/etc/pacman.conf"
  mkdir -p "$target$work/j773g-repo" && mount --bind -o ro "$work/j773g-repo" "$target$work/j773g-repo"
  mkdir -p "$target$cache/pkg" && mount --bind "$cache/pkg" "$target$cache/pkg"
  mount_api
  rm -f "$target/etc/resolv.conf"; cp /etc/resolv.conf "$target/etc/resolv.conf"
  in_target env OMARCHY_MAC_IMAGE_BUILD=1 /usr/bin/omarchy-apply-system --defer-provisioning --first-install >>"$logs/system-setup.log" 2>&1 ||
    { cp "$target/var/log/omarchy-install.log" "$logs/" 2>/dev/null || true
      ((keep_going)) || fail "omarchy-apply-system stopped (logs/system-setup.log, logs/omarchy-install.log)"
      say "omarchy-apply-system stopped; --keep-going continues"; }
  cp "$target/var/log/omarchy-install.log" "$logs/" 2>/dev/null || true
  unmount_api
  rm -f "$target/etc/resolv.conf"
  umount "$target$work/j773g-repo" "$target$cache/pkg"; rmdir -p "$target$work/j773g-repo" "$target$cache/pkg" 2>/dev/null || true
  if [[ -x $target/usr/bin/omarchy-provision-hardware ]]; then
    [[ -f $target/var/lib/omarchy/image/deferred-steps ]] || say "WARNING: the runtime defers hardware setup but queued nothing"
  fi
}

apply_presets() {
  say "presets"
  local preset units=() name
  for preset in "$target"/usr/lib/systemd/system-preset/80-omarchy-mac*.preset "$target"/usr/lib/systemd/system-preset/79-omarchy-j773g.preset; do
    [[ -f $preset ]] || continue
    mapfile -t -O "${#units[@]}" units < <(awk '$1 == "enable" { print $2 }' "$preset")
  done
  ((${#units[@]})) || fail "no Apple Silicon preset in the image"
  mapfile -t units < <(printf '%s\n' "${units[@]}" | grep -vx omarchy-first-boot.service | sort -u)
  systemctl --root="$target" preset "${units[@]}" >>"$logs/presets.log" 2>&1 || fail "presets (logs/presets.log)"
  systemctl --root="$target" enable omarchy-mac-first-boot.service >>"$logs/presets.log" 2>&1 || fail "enable omarchy-mac-first-boot"
}

write_installed_config() {
  say "installed pacman.conf: the runtime's $PLATFORM template, $CHANNEL"
  local t=$target/usr/share/omarchy/default/pacman/$PLATFORM
  [[ -f $t/pacman-$CHANNEL.conf && -f $t/mirrorlist-$CHANNEL ]] || fail "the runtime ships no $PLATFORM $CHANNEL pacman template"
  install -m 0644 "$t/pacman-$CHANNEL.conf" "$target/etc/pacman.conf"
  install -D -m 0644 "$t/mirrorlist-$CHANNEL" "$target/etc/pacman.d/mirrorlist"
  # The J773g packages are local: hold them so a pacman -Syu never replaces
  # them with linux-aurora & co. through the omarchy-mac dependency chain.
  sed -i "/^\[options\]/a # OmarchyM4Mini: local J773g boot packages (packaging/j773g)\nIgnorePkg = ${J773G_PACKAGES[*]} linux-gravity-m4-headers" "$target/etc/pacman.conf"
}

stage_owner_provisioning() {
  say "owner provisioning: Node.js pin, pending marker"
  local unit=$target/usr/share/omarchy/install/provisioning/omarchy-provision-owner.service version url size sha file
  [[ -f $unit && -x $target/usr/bin/omarchy-provision-owner ]] || fail "the runtime ships no owner provisioning"
  version=$(sed -n 's/^version=//p' "$HERE/node.pin"); url=$(sed -n 's/^url=//p' "$HERE/node.pin")
  size=$(sed -n 's/^size=//p' "$HERE/node.pin"); sha=$(sed -n 's/^sha256=//p' "$HERE/node.pin")
  file=node-v$version-linux-arm64.tar.gz
  if [[ ! -f $cache/$file || $(sha256sum "$cache/$file" | cut -d' ' -f1) != "$sha" ]]; then
    curl -fsSL --retry 3 -o "$cache/$file.part" "$url" && mv "$cache/$file.part" "$cache/$file"
  fi
  [[ $(stat -c %s "$cache/$file") == "$size" && $(sha256sum "$cache/$file" | cut -d' ' -f1) == "$sha" ]] || fail "Node.js download mismatch"
  install -d -m 0755 "$target/var/lib/omarchy/provisioning/packages"
  install -m 0444 "$cache/$file" "$target/var/lib/omarchy/provisioning/packages/$file"
  : >"$target/var/lib/omarchy/provisioning/pending"; chmod 0644 "$target/var/lib/omarchy/provisioning/pending"
  install -d -m 0755 "$target/etc/systemd/system/multi-user.target.wants"
  cp -p "$unit" "$target/etc/systemd/system/omarchy-provision-owner.service"
  ln -sfn /etc/systemd/system/omarchy-provision-owner.service "$target/etc/systemd/system/multi-user.target.wants/omarchy-provision-owner.service"
}

build_boot() {
  say "mkinitcpio -P, update-m1n1 (LC_ALL=C), Limine activation"
  mount_api
  in_target mkinitcpio -P >"$logs/mkinitcpio.log" 2>&1 || fail "mkinitcpio (logs/mkinitcpio.log)"
  [[ -s $target/boot/vmlinuz-$KERNEL && -s $target/boot/initramfs-$KERNEL.img ]] || fail "/boot has no $KERNEL kernel and initramfs"
  in_target env LC_ALL=C update-m1n1 >"$logs/update-m1n1.log" 2>&1 || fail "update-m1n1 (logs/update-m1n1.log)"
  [[ -s $target/boot/efi/m1n1/boot.bin ]] || fail "no m1n1/boot.bin on the ESP"
  : >"$logs/limine-boot.log"
  [[ ! -e $target/var/lib/omarchy/limine.enabled ]] || fail "the Limine gate is set before the boot setup ran"
  local resolved
  resolved=$(in_target /usr/bin/omarchy-lifecycle-dispatch --resolve setup-boot 2>>"$logs/limine-boot.log") || fail "the dispatcher has no setup-boot"
  [[ $resolved == /usr/lib/omarchy/mac-boot/setup-boot ]] || fail "setup-boot resolves to $resolved"
  in_target env BOOT_PART=/boot EFI_PART=/boot/efi /bin/bash -euo pipefail -c '
    /usr/bin/omarchy-lifecycle-dispatch setup-boot
    install -Dm644 /dev/null /var/lib/omarchy/limine.enabled
    /usr/bin/omarchy-lifecycle-dispatch setup-boot' >>"$logs/limine-boot.log" 2>&1 || fail "Limine activation (logs/limine-boot.log)"
  unmount_api
  [[ -s $target/boot/efi/limine.conf ]] || fail "no Limine menu"
  [[ -s $target/boot/efi/EFI/Linux/omarchy_$KERNEL.efi ]] || fail "no $KERNEL UKI"
  cmp -s "$target/usr/share/limine/BOOTAA64.EFI" "$target/boot/efi/EFI/BOOT/BOOTAA64.EFI" || fail "the U-Boot slot does not carry Limine"
  : >"$target/etc/machine-id"
  local identity
  while read -r identity; do
    [[ -n $identity ]] || continue
    rm -rf "${target:?}/boot/efi/$identity"
  done < <(grep -o 'machine-id=[0-9a-f]\{32\}' "$target/boot/efi/limine.conf" | cut -d= -f2 | sort -u)
  sed -i '/^comment: machine-id=/d' "$target/boot/efi/limine.conf"
  # The ESP property for Omarchy's hooks is written by omarchy-j773g on the
  # first boot from the Gravity stage-1 property; nothing to do here.
}

arm_first_boot() {
  local fb=$target/usr/lib/omarchy/mac-first-boot/omarchy-mac-first-boot
  [[ -x $fb ]] || fail "omarchy-mac-boot ships no first boot"
  bash "$fb" arm "$target" || fail "could not arm first boot"
}

seal_factory() {
  say "sealing @factory"
  local new=$top/@factory.new
  btrfs subvolume snapshot "$top/@" "$new" >>"$logs/build.log" 2>&1 || fail "snapshot @"
  rm -rf -- "$new/var/lib/omarchy/first-boot" "$new/var/lib/omarchy/mac-first-boot" \
    "$new/var/lib/omarchy/provisioning/pending" "$new/etc/pacman.d/gnupg" "$new/var/lib/omarchy/backups" \
    "$new/etc/NetworkManager/system-connections/"* "$new/var/lib/NetworkManager/"* "$new/var/lib/iwd"
  install -d -m 0755 "$new/var/lib/omarchy"
  printf 'format=2\nbuilder=OmarchyM4Mini\nbuilder_commit=%s\n' "${BUILDER_COMMIT:-unknown}" >"$new/var/lib/omarchy/factory-sealed"
  btrfs property set -ts "$new" ro true || fail "seal @factory"
  sync; mv -T "$new" "$top/@factory"; sync
}

seal_images() {
  say "writing root.img (shrunk to content), boot.img, esp/"
  local used=0 bytes s size
  umount -R "$target/boot/efi" "$target/boot" "$target/var/cache/pacman/pkg" "$target/var/log" "$target/home" "$target" 2>/dev/null || true
  for s in @ @home @log @pkg; do bytes=$(du -s --apparent-size -B1 "$top/$s" | cut -f1); used=$((used + bytes)); done
  size=$(( (used + used / 4 + 2 * 1024 * 1024 * 1024 + 1048575) / 1048576 * 1048576 ))
  ((size <= ROOT_SIZE)) || fail "the root needs $size bytes, more than the $ROOT_SIZE-byte template"
  btrfs filesystem sync "$top"
  btrfs filesystem resize "$size" "$top" >>"$logs/build.log" 2>&1 || fail "cannot shrink the root filesystem to $size"
  umount "$top"; losetup -d "$root_loop"
  truncate -s "$size" "$work/root-build.img"
  btrfs check --readonly "$work/root-build.img" >>"$logs/btrfs-check.log" 2>&1 || fail "btrfs check (logs/btrfs-check.log)"
  mkdir -p "$out/esp"
  rm -rf "$out/esp"/*
  mcopy -i "$work/esp-build.img" -s -p -Q ::/ "$out/esp/" >>"$logs/build.log" 2>&1 || {
    mount -o loop,ro "$work/esp-build.img" "$top" && cp -a "$top"/. "$out/esp/" && umount "$top"; }
  rm -f "$out/esp/.builder" "$out/esp/m1n1/boot.bin.old"
  mv -f "$work/root-build.img" "$out/root.img"
  mv -f "$work/boot-build.img" "$out/boot.img"
  rm -f "$work/esp-build.img"
  ROOT_IMG_SIZE=$size
}

write_installer_data() {
  # For the Gravity installer served locally (docs/j773g-phase3-plan.md §5b);
  # mirrors Gravity's own template with our images.
  cat >"$out/installer_data.json" <<EOF
{
  "os_list": [
    {
      "name": "Omarchy M4 mini (J773g, lab image $(date -u +%Y%m%d))",
      "default_os_name": "Omarchy",
      "boot_object": "m1n1.bin",
      "next_object": "m1n1/boot.bin",
      "package": "omarchy-j773g-$(date -u +%Y%m%d).zip",
      "supported_fw": ["26.6.2"],
      "extras": [],
      "partitions": [
        {"name": "EFI", "type": "EFI", "size": "${ESP_SIZE}B", "format": "fat", "volume_id": "$ESP_VOLUME_ID",
         "copy_firmware": true, "copy_installer_data": true, "source": "esp"},
        {"name": "Boot", "type": "Linux", "size": "${BOOT_SIZE}B", "image": "boot.img"},
        {"name": "Root", "type": "Linux", "size": "${ROOT_SIZE}B", "expand": true, "image": "root.img"}
      ]
    }
  ]
}
EOF
}

# ------------------------------------------------------------------- main ---
say "J773g Omarchy image build: channel=$CHANNEL kernel=$KERNEL"
prepare_host_trust
write_build_pacman_config
make_filesystems
install_bootstrap
write_image_target
install_runtime
install_apple_set
write_fstab
finalize_root
[[ -s $target/boot/vmlinuz-$KERNEL && -s $target/boot/initramfs-$KERNEL.img ]] || say "WARNING: no initramfs after the Apple set (mkinitcpio runs again below)"
prepare_target_keyring
run_system_setup
finalize_root
apply_presets
write_installed_config
stage_owner_provisioning
rm -rf "$target/etc/pacman.d/gnupg"
build_boot
arm_first_boot
rm -f "$target/boot/efi/.builder"
find "$target/var/cache/pacman/pkg" -mindepth 1 -delete
pacman --dbpath "$target/var/lib/pacman" -Q >"$out/packages.txt"
seal_factory
seal_images
write_installer_data
say "done: $out/root.img ($ROOT_IMG_SIZE bytes), boot.img, esp/, installer_data.json, packages.txt"
