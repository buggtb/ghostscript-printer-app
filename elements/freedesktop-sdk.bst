kind: junction

sources:
  - kind: git_repo
    url: gitlab:freedesktop-sdk/freedesktop-sdk.git
    track: freedesktop-sdk-26.08*
    ref: freedesktop-sdk-26.08.1-0-gb02b59ffe19a49a402f357fd5fcb1d552ebc50d7
  - kind: local
    path: patches/cups
    directory: patches/ghostscript-printer-app/cups
  - kind: local
    path: patches/libcupsfilters
    directory: patches/ghostscript-printer-app/libcupsfilters
  - kind: local
    path: patches/cups-filters
    directory: patches/ghostscript-printer-app/cups-filters
  - kind: patch_queue
    path: patches/freedesktop-sdk

config:
  options:
    target_arch: "%{arch}"
    (?):
      - arch == "x86_64":
          bootstrap_build_arch: "x86_64"
      - arch == "aarch64":
          bootstrap_build_arch: "aarch64"
