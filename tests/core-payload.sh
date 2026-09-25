#!/usr/bin/env bash
set -euo pipefail


image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
name="ghostscript-printer-app-payload"
port="${PORT:-18010}"
state_dir="$(mktemp -d)"
sink_port="$((port + 1000))"
output_file="$(mktemp)"
pdf_output_file="$(mktemp)"
cookie_file="$(mktemp)"
sink_pid=""

cleanup() {
  podman rm -f "$name" >/dev/null 2>&1 || true
  if [[ -n "$sink_pid" ]]; then
    kill "$sink_pid" >/dev/null 2>&1 || true
    wait "$sink_pid" 2>/dev/null || true
  fi
  podman unshare rm -rf "$state_dir"
  rm -f "$output_file" "$pdf_output_file" "$cookie_file"
}
trap cleanup EXIT

just build

podman run --rm --entrypoint /usr/bin/bash "$image" -c '
  set -euo pipefail
  test -L /usr/lib/ghostscript-printer-app
  test "$(readlink /usr/lib/ghostscript-printer-app)" = /usr/lib/cups
  test -f /usr/share/ghostscript-printer-app/testpage.ps
  test -x /usr/bin/python3
  test -x /usr/bin/xz
  test -s /usr/share/cups/usb/org.cups.usb-quirks

  executables=(
    /usr/bin/ghostscript-printer-app
    /usr/bin/gs
    /usr/bin/python3
    /usr/bin/xz
    /usr/lib/cups/backend/dnssd
    /usr/lib/cups/backend/ipp
    /usr/lib/cups/backend/ipps
    /usr/lib/cups/backend/lpd
    /usr/lib/cups/backend/snmp
    /usr/lib/cups/backend/socket
    /usr/lib/cups/backend/usb
    /usr/lib/cups/filter/foomatic-rip
    /usr/lib/cups/filter/gstoraster
    /usr/lib/cups/filter/pdftops
    /usr/lib/cups/filter/rastertoepson
    /usr/lib/cups/filter/rastertohp
    /usr/lib/cups/filter/rastertolabel
    /usr/lib/cups/filter/rastertoescpx
    /usr/lib/cups/filter/rastertopclx
  )
  for executable in "${executables[@]}"; do
    test -x "$executable"
    dependencies="$(ldd "$executable")"
    [[ "$dependencies" != *"not found"* ]]
  done
  [[ "$(ldd /usr/lib/cups/backend/usb)" == *"libusb-1.0.so"* ]]

  devices="$(gs -h 2>&1)"
  [[ "$devices" == *"cups"* ]]
  [[ "$devices" == *"pxlcolor"* ]]

  archives=(cups-filters-ppds foomatic-ppds manufacturer-ppds)
  for archive_name in "${archives[@]}"; do
    archive="/usr/share/ppd/$archive_name"
    test -x "$archive"
    mapfile -t entries < <("$archive" list)
    ((${#entries[@]} > 0))
    uri="${entries[0]%% *}"
    uri="${uri#\"}"
    uri="${uri%\"}"
    ppd="$("$archive" cat "$uri")"
    [[ "$ppd" == *"*PPD-Adobe:"* ]]
  done

  /usr/share/ppd/foomatic-ppds cat \
    foomatic-ppds:0/Generic-PCL_6_PCL_XL_Printer-pxlcolor.ppd \
    > /tmp/foomatic.ppd
  if ! PPD=/tmp/foomatic.ppd /usr/lib/cups/filter/foomatic-rip \
    1 nonroot core-conversion 1 "" \
    /usr/share/ghostscript-printer-app/testpage.ps \
    > /tmp/foomatic-output.pcl 2>/tmp/foomatic.log; then
    cat /tmp/foomatic.log >&2
    exit 1
  fi
  test -s /tmp/foomatic-output.pcl

  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite \
    -sOutputFile=/tmp/pdf-filter-input.pdf \
    /usr/share/ghostscript-printer-app/testpage.ps
  test "$(stat -c %s /tmp/pdf-filter-input.pdf)" -gt 8192
  if ! PPD=/tmp/foomatic.ppd /usr/lib/cups/filter/gstoraster \
    1 nonroot pdf-regression 1 "" /tmp/pdf-filter-input.pdf \
    > /tmp/pdf-output.raster 2>/tmp/pdf-filter.log; then
    cat /tmp/pdf-filter.log >&2
    exit 1
  fi
  [[ "$(od -An -tx1 -N4 /tmp/pdf-output.raster)" == " 33 53 61 52" ]]
'
chmod 0777 "$state_dir"

python3 tests/socket-sink.py "$sink_port" "$output_file" &
sink_pid=$!

podman run -d \
  --name "$name" \
  --network host \
  -e PORT="$port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null

ready=0
for _ in $(seq 1 60); do
  http="$(curl --fail --silent --show-error "http://127.0.0.1:${port}/" 2>/dev/null || true)"
  https="$(curl --insecure --fail --silent --show-error "https://127.0.0.1:${port}/" 2>/dev/null || true)"
  if [[ "$http" == *'<title>Ghostscript Printer Application</title>'* && "$https" == *'<title>Ghostscript Printer Application</title>'* ]]; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  podman logs "$name" >&2
  printf 'FAIL: HTTP/HTTPS readiness was not reached\n' >&2
  exit 1
fi

system_uri="ipp://127.0.0.1:${port}/ipp/system"
printer_uri="ipp://127.0.0.1:${port}/ipp/print/core-test"
podman exec "$name" ghostscript-printer-app \
  -u "$system_uri" \
  -d core-test \
  -m generic--pcl-6-pcl-xl-printer--pxlcolor-recommended-en \
  -v "cups:socket://127.0.0.1:${sink_port}" \
  add
printer_page="$(curl --fail --silent --show-error \
  --cookie-jar "$cookie_file" \
  "http://127.0.0.1:${port}/core-test/")"
session="${printer_page#*name=\"session\" value=\"}"
session="${session%%\"*}"
[[ -n "$session" && "$session" != "$printer_page" ]]
curl --fail --silent --show-error \
  --cookie "$cookie_file" \
  --data-urlencode "session=$session" \
  --data 'action=print-test-page' \
  "http://127.0.0.1:${port}/core-test/" >/dev/null

for _ in $(seq 1 120); do
  [[ -s "$output_file" ]] && break
  sleep 0.5
done
if [[ ! -s "$output_file" ]]; then
  podman exec "$name" ghostscript-printer-app -u "$printer_uri" jobs >&2 || true
  podman exec "$name" cat /var/lib/ghostscript-printer-app/ghostscript-printer-app.log >&2 || true
  printf 'FAIL: print job produced no socket output\n' >&2
  exit 1
fi

wait "$sink_pid"
sink_pid=""
python3 -c 'import pathlib, sys; assert pathlib.Path(sys.argv[1]).read_bytes().startswith(b"\x1b%-12345X")' "$output_file"

jobs=""
for _ in $(seq 1 120); do
  jobs="$(podman exec "$name" ghostscript-printer-app -u "$printer_uri" jobs)"
  [[ "$jobs" == *"completed"* ]] && break
  sleep 0.5
done
[[ "$jobs" == *"completed"* ]]

# A PDF job must traverse libcupsfilters' page-count path before Ghostscript.
python3 tests/socket-sink.py "$sink_port" "$pdf_output_file" &
sink_pid=$!
podman cp tests/print-pdf.test "$name:/tmp/print-pdf.test"
podman exec "$name" /usr/bin/bash -c '
  gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite \
    -sOutputFile=/tmp/pdf-regression.pdf \
    /usr/share/ghostscript-printer-app/testpage.ps
  test "$(stat -c %s /tmp/pdf-regression.pdf)" -gt 8192
'
podman exec "$name" ipptool -f /tmp/pdf-regression.pdf "$printer_uri" /tmp/print-pdf.test
for _ in $(seq 1 120); do
  [[ -s "$pdf_output_file" ]] && break
  sleep 0.5
done
if [[ ! -s "$pdf_output_file" ]]; then
  podman exec "$name" cat /var/lib/ghostscript-printer-app/ghostscript-printer-app.log >&2 || true
  printf 'FAIL: PDF print job produced no socket output\n' >&2
  exit 1
fi
wait "$sink_pid"
sink_pid=""
python3 -c 'import pathlib, sys; assert pathlib.Path(sys.argv[1]).read_bytes().startswith(b"\x1b%-12345X")' "$pdf_output_file"
printf 'OK: core driver payload, HTTPS, and print conversion are available\n'
