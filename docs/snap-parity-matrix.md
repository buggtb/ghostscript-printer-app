# Driver and behavior parity vs. the OpenPrinting Snap

This matrix tracks the FSDK OCI appliance's driver payload against the
upstream OpenPrinting `ghostscript-printer-app` Snap, using the Snap's own
build manifest (`snap/snapcraft.yaml`, still carried in this repository) as
the source of truth for Snap component versions. It exists so that a
version, architecture, or driver-family regression against the Snap is
visible without requiring Ghostscript itself to track the Snap version —
Ghostscript follows the reviewed FreeDesktop SDK (FSDK) pin instead, per
[ADR 0001](adr/0001-use-a-self-contained-fsdk-oci-appliance.md).

## How this stays true

- The complete advertised driver inventory is
  [`README.md#contained-printer-drivers`](../README.md#contained-printer-drivers),
  not a sample.
- `tests/appliance-parity.sh` (run by `just verify`) fails the build if any
  advertised backend, filter, driver command, or PPD-provider family named
  below is missing from the built OCI image, or if any README-advertised
  Ghostscript/Foomatic driver has no device or PPD entry. A regression in a
  named family therefore fails the full image parity gate, not just this
  document.
- Snap source versions below come from `snap/snapcraft.yaml`'s `source-tag`
  fields, still committed in this repository. FSDK source versions come from
  each `elements/printer-app/*.bst` junction's `ref:`/`track:`. Where a
  component is inherited from the pinned `freedesktop-sdk.bst` junction
  rather than pinned by an element in this repository, its exact upstream
  version is **unknown** here and is recorded as such rather than guessed.
- The Snap Store's currently published revision, architectures, and OCI
  image digest are **unknown** in this document: they are not committed
  artifacts of this repository and must be read from the Snap Store listing
  and this repository's own release evidence at verification time, not
  hard-coded here where they would silently go stale.

## Version and architecture matrix

| Property | This FSDK OCI appliance | OpenPrinting Snap |
| --- | --- | --- |
| Application version | `VERSION` file, currently `10.07.1-1` (checked into this repo) | `snap/snapcraft.yaml` `version:`, currently `10.08.0-1` (checked into this repo); Snap Store listing revision is unknown here |
| Build architectures | `amd64`, `arm64` (see `tests/appliance-parity.sh` architecture cases) | `amd64`, `arm64`, `armhf`, `riscv64` (`snap/snapcraft.yaml` `architectures:`) — `armhf`/`riscv64` are not produced by this repository |
| FreeDesktop SDK pin | `freedesktop-sdk-26.08rc.1` (`elements/freedesktop-sdk.bst`) | Not applicable; Snap does not use FSDK |
| OCI image digest | Produced per build; see release evidence and `org.opencontainers.image.*` labels asserted by `tests/appliance-parity.sh` | Not applicable; Snap has no OCI digest |
| Uncompressed size ceiling | 500 MiB (524,288,000 bytes), enforced by `tests/appliance-parity.sh` | Not tracked here; unknown |

## Driver/component matrix

Legend: **match** = same upstream ref; **differs** = pinned to a different
upstream version, fork, or revision; **inherited** = this repository does
not pin the component directly, it comes from the `freedesktop-sdk.bst`
junction, so its exact version is unknown without inspecting that pinned
FSDK release.

| Component | FSDK source ref | Snap source ref (`snap/snapcraft.yaml`) | Status |
| --- | --- | --- | --- |
| PAPPL | `elements/printer-app/pappl.bst`: `v1.4.12` | `pappl` part: `v1.4.12` | match |
| pappl-retrofit | `elements/printer-app/pappl-retrofit.bst`: commit `1626b338` (tracks `master`) | `pappl-retrofit` part: unpinned `master` (no `source-tag`) | unknown — both track upstream `master`; exact commits cannot be compared without re-resolving the Snap build at a point in time |
| Ghostscript (`gs` binary) | Inherited from `freedesktop-sdk.bst:components/ghostscript.bst` (FSDK `26.08rc.1`); `elements/printer-app/ijs.bst` separately pins `ghostpdl-10.07.1` for the IJS driver only | `ghostscript` part: `ghostpdl-10.08.0` | differs — the Snap's Ghostscript is one minor version ahead (`10.08.0` vs. this repo's IJS-only pin of `10.07.1`); the application's own `gs` binary version is unknown here and depends on the FSDK `26.08rc.1` payload, consistent with the "no requirement to match Snap version when FSDK lags" outcome of this issue |
| CUPS (libcups, backends, `rastertoepson`/`rastertohp`/`rastertolabel`) | Inherited from `freedesktop-sdk.bst:components/cups.bst`, plus local patches under `patches/cups` | `cups` part: `v2.4.19` | inherited — exact FSDK-provided CUPS version unknown here |
| libcupsfilters | Inherited from FSDK, plus local patches under `patches/libcupsfilters` | `libcupsfilters` part: `2.2.1` | inherited — exact FSDK-provided version unknown here |
| libppd | Inherited from `freedesktop-sdk.bst:components/cups-filters.bst` family | `libppd` part: `2.1.1` | inherited — exact FSDK-provided version unknown here |
| cups-filters (foomatic-rip, gstoraster, pdftops, rastertoescpx, rastertopclx) | Inherited from FSDK, plus local patches under `patches/cups-filters` | `cups-filters` part: `2.0.1` | inherited — exact FSDK-provided version unknown here |
| foomatic-db (PPD/manufacturer data) | Inherited from `freedesktop-sdk.bst:components/foomatic-db.bst` (used by `elements/printer-app/core-payload.bst`) | `foomatic-db` part: `20240504` | inherited — exact FSDK-provided snapshot date unknown here |
| foomatic-db-engine (`foomatic-compiledb`) | `elements/printer-app/foomatic-db-engine.bst`: commit `e4e7b9cd` (tracks `master`) | Debian package `foomatic-db-engine` via `build-packages:`, no pinned source | unknown — different packaging model, versions not directly comparable |
| brlaser | `elements/printer-app/brlaser.bst`: `pdewacht/brlaser` `v6` | `brlaser` part: `Owl-Maintain/brlaser` `v6.2.8` | **differs** — the Snap has moved to a different upstream fork (`Owl-Maintain`) at a newer tag; this repository still tracks the original `pdewacht/brlaser` `v6` |
| SpliX | `elements/printer-app/splix.bst`: `debian/2.0.1-1` | `splix` part: `debian/2.0.1-2` | **differs** — Snap is one Debian packaging revision ahead |
| c2esp | `elements/printer-app/c2esp.bst`: `debian/27-11` | `c2esp` part: `debian/27-11` | match |
| foo2zjs | `elements/printer-app/foo2zjs.bst`: `debian/20200505dfsg0-5` | `foo2zjs` part: `debian/20200505dfsg0-5` | match |
| fxlinuxprint | `elements/printer-app/fxlinuxprint.bst`: `debian/1.1.0+ds-4` | `fxlinuxprint` part: `debian/1.1.0+ds-4` | match |
| HPIJS (from hplip.v2) | `elements/printer-app/hpijs.bst`: `debian/3.26.4+dfsg0-3` | `hplip` part: `debian/3.26.4+dfsg0-3` | match |
| m2300w | `elements/printer-app/m2300w.bst`: `debian/0.51-15` | `m2300w` part: `debian/0.51-15` | match |
| pnm2ppa | `elements/printer-app/pnm2ppa.bst`: `debian/1.13-14` | `pnm2ppa` part: `debian/1.13-14` | match |
| printer-driver-oki | `elements/printer-app/printer-driver-oki.bst`: `1.0.2` | `printer-driver-oki` part: `1.0.2` | match |
| ptouch-driver | `elements/printer-app/ptouch-driver.bst`: `debian/1.7-1` | `ptouch-driver` part: `debian/1.7-1` | match |
| pxljr | `elements/printer-app/pxljr.bst`: `debian/1.4+repack0-6` | `pxljr` part: `debian/1.4+repack0-6` | match |
| c2050 | `elements/printer-app/c2050.bst`: `debian/0.3-7` | `c2050` part: `debian/0.3-7` | match |
| cjet | `elements/printer-app/cjet.bst`: `debian/0.8.9-11` | `cjet` part: `debian/0.8.9-11` | match |
| min12xxw | `elements/printer-app/min12xxw.bst`: `debian/0.0.9-11` | `min12xxw` part: `debian/0.0.9-11` | match |
| Dymo (dymo-cups-drivers) | `elements/printer-app/dymo-cups-drivers.bst`: `debian/1.4.0-12` | `dymo-cups-drivers` part: `debian/1.4.0-12` | match |
| rastertosag-gdi | `elements/printer-app/rastertosag-gdi.bst`: `debian/0.1-8` | `rastertosag-gdi` part: `debian/0.1-8` | match |
| pyppd | `elements/printer-app/pyppd.bst`: `release-1-1-0` | `pyppd` part: `release-1-1-0` | match |
| qpdf | Not pinned separately; PDF handling comes through the inherited FSDK `cups-filters`/`libppd`/`poppler` stack | `qpdf` part: `v11.10.1` | unknown — this repository's architecture does not carry a standalone `qpdf` build, so there is no directly comparable pin |

## Reading this matrix

- Every driver family in this table corresponds to a family enforced by
  `tests/appliance-parity.sh`'s backend, filter, command, and PPD-provider
  checks. If a family here is renamed or dropped from the image, that gate
  fails the build before this document could go stale silently.
- "Differs" rows (Ghostscript/ghostpdl, brlaser, SpliX) are known,
  intentional or currently-unreconciled version gaps against the Snap, not
  missing drivers: the driver family itself is present and gated in both
  distributions, only the pinned upstream revision differs.
- "Inherited"/"unknown" rows are components this repository does not pin
  directly; they come from the reviewed `freedesktop-sdk.bst` release.
  Resolving their exact upstream version requires inspecting that pinned
  FSDK release's own component manifest, which is out of scope for this
  document and does not block the Ghostscript-driver parity gate.
- This document does not assert physical print output parity. See
  [`docs/oci-physical-validation.md`](oci-physical-validation.md) for what
  remains unverified without hardware.
