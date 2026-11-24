[![🇺🇸 English](https://img.shields.io/badge/lang-English-blue.svg)](README.md) [![🇧🇷 Português](https://img.shields.io/badge/lang-Português-green.svg)](README-ptbr.md) [![🇪🇸 Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README-es.md)

# resetbw

![resetbw cover](resetbw-cover.webp)

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/resetbw/releases/tag/v2.0.0)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-orange.svg)](#requirements)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20cPanel%20%7C%20WHM-lightgrey.svg)](#requirements)

**Safe cPanel Bandwidth Auditor, Reset & Restore CLI (SQLite + Legacy Flat Files).**

`resetbw.sh` audits cPanel/WHM account bandwidth usage and quotas (`whmapi1 showbw` + `/var/cpanel/bandwidth_cache.sqlite`), creates `chmod 600` `.tar.gz` backups with JSON state snapshots before any modification, resets monthly or full-history counters cleanly across both modern SQLite databases and legacy flat files, optionally clears `/var/cpanel/bwlimited/<user>`, and supports one-command `restore` from any backup archive.

> **Historical Inspiration:** Clean-room Bash + Python 3.6+ `v2.0.0` reimplementation inspired by `resetbw` (2011, v0.1, HostGator.com, LLC). Eliminates dead Perl/CPAN dependencies (`cPanel::PublicAPI`, `XML::Simple`, `Tie::File`), deprecated `/root/.accesshash`, hardcoded `/home/hgtransfer` paths, and unsafe shell `tar` interpolation, while adding native modern cPanel SQLite support (`bandwidth_cache.sqlite` & `<user>.sqlite`), read-only `audit` mode, `--month` granularity, `--dry-run`, JSON/CSV outputs, and `restore`.

---

## Requirements

- Linux server running cPanel/WHM with Bash 4.0+ and Python 3.6+ (standard library `sqlite3` & `tarfile`)
- Root privileges required to read/update `/var/cpanel/bandwidth*` and call `whmapi1`

---

## Direct Execution

```bash
curl -fsSL https://raw.githubusercontent.com/sr00t3d/resetbw/main/resetbw.sh -o resetbw.sh
chmod +x resetbw.sh
sudo ./resetbw.sh audit --all
```

---

## Usage

```bash
# 1. Audit bandwidth usage for one account or all accounts (read-only)
sudo ./resetbw.sh audit percio
sudo ./resetbw.sh audit --all --exit-code

# 2. Preview a bandwidth reset without touching disk or SQLite (--dry-run)
sudo ./resetbw.sh reset percio --dry-run

# 3. Reset current month (or a specific --month YYYY-MM) with chmod 600 backup
sudo ./resetbw.sh reset percio --month 2026-11 --unsuspend

# 4. Batch reset accounts from a file and refresh weblogs
sudo ./resetbw.sh reset --file users.txt --run-weblogs

# 5. Restore exact previous bandwidth state from a backup archive
sudo ./resetbw.sh restore /var/backups/resetbw/20261122/percio-20261122T120000Z.tar.gz

# 6. Export audit report as JSON or CSV
sudo ./resetbw.sh audit --all -o json
```

---

## Real Output Example

```text
================================================================================================
 resetbw.sh v2.0.0 | Bandwidth Audit (2026-11) | 2026-11-22T11:25:54Z
================================================================================================
USER    PERIOD   USED        LIMIT      PCT  STATUS  STORAGE
------  -------  ----------  ---------  ---  ------  -----------------
percio  2026-11  512.00 MiB  unlimited  -    OK      db:1 sql:0 flat:1
```

---

## License

Licensed under the [Apache License 2.0](LICENSE).
