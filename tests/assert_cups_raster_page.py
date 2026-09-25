#!/usr/bin/env python3
"""Validate that a CUPS raster file holds exactly one real, bounded page.

Used by the direct ``gstoraster`` PDF regression probe (see
tests/core-payload.sh). A bare sync-word check or a "file is non-empty"
check both pass on a truncated or blank page, which is exactly the shape
of failure the unpatched libcupsfilters PDF tempfile bug produced. This
parses the CUPS Raster page header (RFC "cups-raster" v2/v3 layout) to
assert real, bounded page geometry and non-blank pixel data.
"""
import struct
import sys

SYNC_WORDS = {
    b"RaSt": "be",  # v1, big-endian
    b"tSaR": "le",  # v1, little-endian
    b"RaS2": "be",  # v2, big-endian
    b"2SaR": "le",  # v2, little-endian
    b"RaS3": "be",  # v3, big-endian
    b"3SaR": "le",  # v3, little-endian
}

# Fixed-size cupsRasterHeader2 page header, immediately following the
# 4-byte sync word: 4 name strings (64 bytes each) + 15 legacy PostScript
# integer/geometry fields (unsigned ints, some arrays) + the cups-prefixed
# fields used here. Offsets below are counted from the start of the page
# header (i.e. file offset - 4).
_MEDIA_STRINGS_LEN = 64 * 4  # MediaClass, MediaColor, MediaType, OutputType
_LEGACY_FIELDS_LEN = 4 * (
    1  # AdvanceDistance
    + 1  # AdvanceMedia
    + 1  # Collate
    + 1  # CutMedia
    + 1  # Duplex
    + 2  # HWResolution[2]
    + 4  # ImagingBoundingBox[4]
    + 1  # InsertSheet
    + 1  # Jog
    + 1  # LeadingEdge
    + 2  # Margins[2]
    + 1  # ManualFeed
    + 1  # MediaPosition
    + 1  # MediaWeight
    + 1  # MirrorPrint
    + 1  # NegativePrint
    + 1  # NumCopies
    + 1  # Orientation
    + 1  # OutputFaceUp
    + 2  # PageSize[2]
    + 1  # Separations
    + 1  # TraySwitch
    + 1  # Tumble
)
_CUPS_WIDTH_OFFSET = _MEDIA_STRINGS_LEN + _LEGACY_FIELDS_LEN  # cupsWidth
_CUPS_INT_FIELDS = (
    "cupsWidth",
    "cupsHeight",
    "cupsMediaType",
    "cupsBitsPerColor",
    "cupsBitsPerPixel",
    "cupsBytesPerLine",
    "cupsColorOrder",
    "cupsColorSpace",
    "cupsCompression",
    "cupsRowCount",
    "cupsRowFeed",
    "cupsRowStep",
)
_CUPS_INT_FIELDS_LEN = 4 * len(_CUPS_INT_FIELDS)
PAGE_HEADER_LEN = 1796  # standard cupsRasterHeader2 size, sync word excluded


def _read_header(data: bytes, offset: int):
    sync = data[offset : offset + 4]
    if sync not in SYNC_WORDS:
        raise AssertionError(
            f"missing/unknown CUPS raster sync word at offset {offset}: {sync!r}"
        )
    endian = "<" if SYNC_WORDS[sync] == "le" else ">"
    header_start = offset + 4
    header = data[header_start : header_start + PAGE_HEADER_LEN]
    if len(header) < PAGE_HEADER_LEN:
        raise AssertionError("truncated CUPS raster page header")
    ints_start = _CUPS_WIDTH_OFFSET
    ints_blob = header[ints_start : ints_start + _CUPS_INT_FIELDS_LEN]
    values = struct.unpack(f"{endian}{len(_CUPS_INT_FIELDS)}I", ints_blob)
    fields = dict(zip(_CUPS_INT_FIELDS, values))
    fields["_header_end"] = header_start + PAGE_HEADER_LEN
    return fields


def main() -> int:
    path, max_bytes, min_width, max_width, min_height, max_height = sys.argv[1:7]
    max_bytes = int(max_bytes)
    min_width, max_width = int(min_width), int(max_width)
    min_height, max_height = int(min_height), int(max_height)

    data = open(path, "rb").read()
    if not data:
        print(f"FAIL: {path} is empty", file=sys.stderr)
        return 1
    if len(data) > max_bytes:
        print(
            f"FAIL: {path} is {len(data)} bytes; expected no more than {max_bytes}",
            file=sys.stderr,
        )
        return 1

    header = _read_header(data, 0)
    width, height = header["cupsWidth"], header["cupsHeight"]
    if not (min_width <= width <= max_width):
        print(f"FAIL: cupsWidth {width} outside [{min_width}, {max_width}]", file=sys.stderr)
        return 1
    if not (min_height <= height <= max_height):
        print(f"FAIL: cupsHeight {height} outside [{min_height}, {max_height}]", file=sys.stderr)
        return 1

    payload = data[header["_header_end"] :]
    if not payload:
        print("FAIL: raster page has no pixel data", file=sys.stderr)
        return 1
    if header["cupsCompression"] == 0:
        expected_bytes = header["cupsBytesPerLine"] * height
        if len(payload) < expected_bytes:
            print(
                f"FAIL: uncompressed page data is {len(payload)} bytes; "
                f"expected at least {expected_bytes} for {width}x{height}",
                file=sys.stderr,
            )
            return 1

    # A blank/white page is not proof the filter rendered real content; the
    # test page draws visible marks, so at least some payload bytes must be
    # non-zero and not-all-0xFF (both are common "nothing was drawn" fills).
    sample = payload[: min(len(payload), 1 << 20)]
    if len(set(sample)) <= 1:
        print("FAIL: raster page payload looks uniform/blank", file=sys.stderr)
        return 1

    # A second sync word anywhere after this page's data would mean the
    # filter emitted more than the single page this bounded probe expects.
    sync = data[0:4]
    if data.find(sync, header["_header_end"]) != -1:
        print("FAIL: raster output contains more than one page", file=sys.stderr)
        return 1

    print(
        f"OK: single {width}x{height} raster page, {len(data)} bytes, non-blank",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
