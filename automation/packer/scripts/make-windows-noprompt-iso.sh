#!/usr/bin/env bash
# =============================================================================
# make-windows-noprompt-iso.sh — Remove "Press any key to boot from CD or DVD"
#
# Windows ISOs pause for a keypress before starting setup, which breaks
# unattended Packer builds (the prompt window is too short to catch
# reliably). Every Windows ISO ships alternative NO-PROMPT boot loaders
# inside itself — this script swaps them in and rebuilds the ISO:
#     efi/microsoft/boot/efisys_noprompt.bin  -> efisys.bin
#     efi/microsoft/boot/cdboot_noprompt.efi  -> cdboot.efi
#
# Community-verified approach (Proxmox forum, ntlite.com). Run it ONCE per
# Windows ISO, upload the result to Proxmox, and point win_iso_file at it.
#
# Usage:
#   ./make-windows-noprompt-iso.sh <input.iso> <output.iso>
#
# Example (on the Proxmox host, where the ISOs already live):
#   ./make-windows-noprompt-iso.sh \
#     /mnt/pve/NFS-10GB-PROXMOX-1/template/iso/Windows-Server-2025.ISO \
#     /mnt/pve/NFS-10GB-PROXMOX-1/template/iso/Windows-Server-2025-noprompt.ISO
#
# Requirements: xorriso (no root, no mounts — pure file extraction), and
# free disk space of ~2x the ISO size in $TMPDIR (or alongside the output).
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              05-07-2026
# =============================================================================

echo "[$(basename "${BASH_SOURCE[0]:-$0}")] starting as $(id -un 2>/dev/null || echo '?') in $(pwd)"
set -euo pipefail
trap 's=$?; echo "[$(basename "${BASH_SOURCE[0]:-$0}")] FATAL exit=$s at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

IN="${1:-}"; OUT="${2:-}"
[[ -n "${IN}" && -n "${OUT}" ]] || fail "Usage: $0 <input.iso> <output.iso>"
[[ -f "${IN}" ]] || fail "Input not found: ${IN}"
[[ -e "${OUT}" ]] && fail "Output already exists: ${OUT}"
command -v xorriso &>/dev/null || fail "xorriso not found (apt-get install -y xorriso)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/noprompt.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

log "Extracting ${IN} (no mount needed — xorriso osirrox)..."
xorriso -osirrox on -indev "${IN}" -extract / "${WORK}/iso" >/dev/null 2>&1
chmod -R u+w "${WORK}/iso"

# Locate the boot dir case-insensitively (Joliet/UDF differ between ISOs)
BOOTDIR=$(find "${WORK}/iso" -ipath '*efi/microsoft/boot' -type d | head -1)
[[ -n "${BOOTDIR}" ]] || fail "efi/microsoft/boot not found — is this a Windows ISO?"
NOPROMPT_BIN=$(find "${BOOTDIR}" -maxdepth 1 -iname 'efisys_noprompt.bin' | head -1)
NOPROMPT_EFI=$(find "${BOOTDIR}" -maxdepth 1 -iname 'cdboot_noprompt.efi' | head -1)
EFISYS=$(find "${BOOTDIR}" -maxdepth 1 -iname 'efisys.bin' | head -1)
CDBOOT=$(find "${BOOTDIR}" -maxdepth 1 -iname 'cdboot.efi' | head -1)
[[ -n "${NOPROMPT_BIN}" && -n "${EFISYS}" ]] || fail "efisys_noprompt.bin not found in the ISO"

log "Swapping in the no-prompt boot loaders..."
cp -f "${NOPROMPT_BIN}" "${EFISYS}"
[[ -n "${NOPROMPT_EFI}" && -n "${CDBOOT}" ]] && cp -f "${NOPROMPT_EFI}" "${CDBOOT}"

ETFSBOOT=$(find "${WORK}/iso" -ipath '*boot/etfsboot.com' | head -1)
[[ -n "${ETFSBOOT}" ]] || fail "boot/etfsboot.com not found — cannot rebuild BIOS boot record"
ETFSBOOT_REL="${ETFSBOOT#"${WORK}/iso/"}"
EFISYS_REL="${EFISYS#"${WORK}/iso/"}"

log "Rebuilding ISO (this takes a few minutes for a full Windows image)..."
xorriso -as mkisofs \
    -iso-level 3 \
    -volid "WINSETUP_NOPROMPT" \
    -eltorito-boot "${ETFSBOOT_REL}" \
      -eltorito-catalog boot/boot.cat \
      -no-emul-boot \
      -boot-load-size 8 \
      -boot-info-table \
    -eltorito-alt-boot \
      -e "${EFISYS_REL}" \
      -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "${OUT}" \
    "${WORK}/iso" 2>&1 | tail -3

[[ -f "${OUT}" ]] || fail "ISO rebuild produced no output"
log "Done: ${OUT} ($(du -h "${OUT}" | cut -f1))"
log "Upload it to Proxmox ISO storage (or it's already there if you wrote to the storage path),"
log "then set win_iso_file to its volid — the build boots straight into setup, no keypress."
