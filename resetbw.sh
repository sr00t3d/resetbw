#!/usr/bin/env bash
# ==============================================================================
# resetbw.sh — Safe cPanel Bandwidth Auditor, Reset & Restore CLI (v2.0.0)
# ==============================================================================
# Clean-room Bash + Python 3.6+ reimplementation inspired by resetbw (2011, v0.1,
# HostGator.com, LLC).
#
# Eliminates dead Perl/CPAN dependencies (cPanel::PublicAPI, XML::Simple,
# Tie::File), deprecated /root/.accesshash, hardcoded /home/hgtransfer paths,
# and unsafe shell tar interpolation. Adds native support for modern cPanel
# SQLite bandwidth databases (/var/cpanel/bandwidth_cache.sqlite and
# /var/cpanel/bandwidth/<user>.sqlite), legacy flat files, whmapi1 showbw,
# read-only audit mode, --month granularity, chmod 600 tar.gz backups, and
# full restore capability.
#
# License: Apache-2.0
# Author:  Percio Castelo (https://perciocastelo.com.br)
# Repo:    https://github.com/sr00t3d/resetbw
# ==============================================================================

set -euo pipefail

readonly SCRIPT_NAME="resetbw.sh"
readonly SCRIPT_VERSION="2.0.0"

ACTION=""
TARGET=""
USER_FILE=""
ALL_USERS=0
MONTH_FILTER=""
ALL_MONTHS=0
BACKUP_DIR="/var/backups/resetbw"
BW_DIR="/var/cpanel/bandwidth"
BW_CACHE_DIR="/var/cpanel/bandwidth.cache"
CACHE_DB="/var/cpanel/bandwidth_cache.sqlite"
DO_UNSUSPEND=0
DO_WEBLOGS=0
DRY_RUN=0
EXIT_CODE_MODE=0
OUTPUT_FMT="table"
QUIET=0
NO_COLOR=0

C_RED=""
C_GREEN=""
C_YELLOW=""
C_CYAN=""
C_BOLD=""
C_RESET=""

init_colors() {
  if [[ "$NO_COLOR" -eq 0 && -t 1 && "$OUTPUT_FMT" == "table" ]]; then
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'
    C_CYAN=$'\033[0;36m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
  fi
}

usage() {
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — Safe cPanel Bandwidth Auditor, Reset & Restore CLI

Usage:
  ${SCRIPT_NAME} audit [user] [options]           Audit bandwidth usage & limits (read-only)
  ${SCRIPT_NAME} audit --all [options]            Audit all cPanel accounts
  ${SCRIPT_NAME} <user> [options]                 Shortcut for: audit <user>
  ${SCRIPT_NAME} reset <user> [options]           Backup & reset bandwidth counters for user
  ${SCRIPT_NAME} reset --file <list> [options]    Batch reset users listed in file (1 per line)
  ${SCRIPT_NAME} restore <backup.tar.gz> [opts]   Restore bandwidth state from backup archive

Options:
  --file <path>           File containing cPanel usernames (1 per line)
  --all                   Audit all cPanel accounts (audit mode)
  --month <YYYY-MM>       Target specific month (default: current month)
  --all-months            Reset all stored months instead of only the target month
  --backup-dir <dir>      Backup directory (default: /var/backups/resetbw)
  --bw-dir <dir>          Override /var/cpanel/bandwidth directory
  --cache-db <path>       Override /var/cpanel/bandwidth_cache.sqlite path
  --unsuspend             Also remove /var/cpanel/bwlimited/<user> if present
  --run-weblogs           Run /scripts/runweblogs <user> after resetting
  --dry-run               Preview all actions without modifying disk or databases
  --exit-code             In audit mode, exit 2 if any account is bwlimited or >= 90% quota
  -o, --output <fmt>      Output format: table (default), json, csv
  -q, --quiet             Minimal output
  --no-color              Disable ANSI colors
  -h, --help              Show this help
  -v, --version           Show version

Examples:
  ${SCRIPT_NAME} audit percio
  ${SCRIPT_NAME} audit --all --exit-code
  ${SCRIPT_NAME} reset percio --dry-run
  ${SCRIPT_NAME} reset percio --month 2026-11 --unsuspend
  ${SCRIPT_NAME} reset --file users.txt --run-weblogs
  ${SCRIPT_NAME} restore /var/backups/resetbw/20261122/percio-20261122T120000Z.tar.gz

Exit codes:
  0  Success
  1  Error (invalid arguments, missing account, I/O error)
  2  Bandwidth limit exceeded or >= 90% quota detected (audit --exit-code)
EOF
}

parse_args() {
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -v|--version) printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      --file)
        [[ $# -ge 2 ]] || { printf '[ERR] --file requires a path.\n' >&2; exit 1; }
        USER_FILE="$2"; shift 2 ;;
      --all) ALL_USERS=1; shift ;;
      --month)
        [[ $# -ge 2 ]] || { printf '[ERR] --month requires YYYY-MM.\n' >&2; exit 1; }
        MONTH_FILTER="$2"; shift 2 ;;
      --all-months) ALL_MONTHS=1; shift ;;
      --backup-dir)
        [[ $# -ge 2 ]] || { printf '[ERR] --backup-dir requires a path.\n' >&2; exit 1; }
        BACKUP_DIR="$2"; shift 2 ;;
      --bw-dir)
        [[ $# -ge 2 ]] || { printf '[ERR] --bw-dir requires a path.\n' >&2; exit 1; }
        BW_DIR="$2"; shift 2 ;;
      --cache-db)
        [[ $# -ge 2 ]] || { printf '[ERR] --cache-db requires a path.\n' >&2; exit 1; }
        CACHE_DB="$2"; shift 2 ;;
      --unsuspend) DO_UNSUSPEND=1; shift ;;
      --run-weblogs) DO_WEBLOGS=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --exit-code) EXIT_CODE_MODE=1; shift ;;
      -o|--output)
        [[ $# -ge 2 ]] || { printf '[ERR] --output requires table|json|csv.\n' >&2; exit 1; }
        OUTPUT_FMT="$2"; shift 2 ;;
      -q|--quiet) QUIET=1; shift ;;
      --no-color) NO_COLOR=1; shift ;;
      --) shift; while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done ;;
      -*)
        printf '[ERR] Unknown option: %s\n' "$1" >&2
        exit 1 ;;
      *)
        positional+=("$1"); shift ;;
    esac
  done

  if [[ ${#positional[@]} -eq 0 && -z "$USER_FILE" && "$ALL_USERS" -eq 0 ]]; then
    usage
    exit 0
  fi

  if [[ ${#positional[@]} -eq 0 ]]; then
    ACTION="audit"
  else
    case "${positional[0]}" in
      audit|show|status)
        ACTION="audit"
        TARGET="${positional[1]:-}"
        ;;
      reset)
        ACTION="reset"
        TARGET="${positional[1]:-}"
        ;;
      restore)
        ACTION="restore"
        TARGET="${positional[1]:-}"
        ;;
      *)
        # Backward-compatible read-only shortcut: resetbw.sh <user>
        ACTION="audit"
        TARGET="${positional[0]}"
        ;;
    esac
  fi

  case "$OUTPUT_FMT" in
    table|json|csv) ;;
    *) printf '[ERR] Invalid --output format: %s (expected table|json|csv)\n' "$OUTPUT_FMT" >&2; exit 1 ;;
  esac
}

main() {
  parse_args "$@"

  if ! command -v python3 >/dev/null 2>&1; then
    printf '[ERR] python3 is required.\n' >&2
    exit 1
  fi

  init_colors

  local ts_utc
  ts_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local py_script
  py_script="$(cat <<'PYEOF'
import csv
import io
import json
import os
import pwd
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import time

(
    action, target, user_file, all_users_s, month_filter, all_months_s,
    backup_dir, bw_dir, bw_cache_dir, cache_db,
    do_unsuspend_s, do_weblogs_s, dry_run_s, exit_code_s, fmt, quiet_s,
    script_name, script_version, ts_utc,
    c_red, c_green, c_yellow, c_cyan, c_bold, c_reset
) = sys.argv[1:26]

all_users = all_users_s == "1"
all_months = all_months_s == "1"
do_unsuspend = do_unsuspend_s == "1"
do_weblogs = do_weblogs_s == "1"
dry_run = dry_run_s == "1"
exit_code_mode = exit_code_s == "1"
quiet = quiet_s == "1"

USER_RE = re.compile(r'^[a-zA-Z0-9._-]{1,64}$')
MONTH_RE = re.compile(r'^([0-9]{4})-(0[1-9]|1[0-2])$')

now_tm = time.gmtime()
if month_filter:
    m_mo = MONTH_RE.match(month_filter)
    if not m_mo:
        print(f"[ERR] Invalid --month '{month_filter}' (expected YYYY-MM).", file=sys.stderr)
        sys.exit(1)
    target_year = int(m_mo.group(1))
    target_month = int(m_mo.group(2))
else:
    target_year = now_tm.tm_year
    target_month = now_tm.tm_mon


def human_bytes(num):
    if num is None:
        return "unlimited"
    n = float(num)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024.0:
            return f"{n:.2f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024.0
    return f"{n:.2f} PiB"


def run_cmd(cmd, timeout=60):
    try:
        p = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=timeout,
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def cpanel_user_exists(u):
    if not USER_RE.match(u):
        return False
    if os.path.isfile(f"/var/cpanel/users/{u}"):
        return True
    try:
        pwd.getpwnam(u)
        return os.path.isfile(os.path.join(bw_dir, f"{u}.sqlite"))
    except KeyError:
        return False


def get_all_cpanel_users():
    users = []
    udir = "/var/cpanel/users"
    if os.path.isdir(udir):
        for name in sorted(os.listdir(udir)):
            if name.startswith(".") or name in ("system", "root"):
                continue
            fp = os.path.join(udir, name)
            if os.path.isfile(fp) and USER_RE.match(name):
                users.append(name)
    return users


def resolve_user_list():
    users = []
    if all_users:
        users = get_all_cpanel_users()
    elif user_file:
        if not os.path.isfile(user_file):
            print(f"[ERR] User list file not found: {user_file}", file=sys.stderr)
            sys.exit(1)
        with open(user_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                u = line.split("#", 1)[0].strip()
                if u:
                    users.append(u)
    elif target:
        if os.path.isfile(target) and not cpanel_user_exists(target):
            with open(target, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    u = line.split("#", 1)[0].strip()
                    if u:
                        users.append(u)
        else:
            users.append(target)
    else:
        print(f"[ERR] Provide a cPanel username, --file <list>, or --all.", file=sys.stderr)
        sys.exit(1)

    dedup = []
    seen = set()
    for u in users:
        if u not in seen:
            seen.add(u)
            dedup.append(u)
    return dedup


def get_user_domains(user):
    domains = []
    if os.path.isfile("/etc/userdomains"):
        try:
            with open("/etc/userdomains", "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if ":" in line:
                        dom, owner = line.split(":", 1)
                        if owner.strip() == user:
                            d = dom.strip()
                            if d and d != "*":
                                domains.append(d)
        except Exception:
            pass
    return sorted(set(domains))


def query_whmapi_showbw(user=None):
    whm = shutil.which("whmapi1")
    if not whm:
        return {}
    cmd = [whm, "--output=json", "showbw", f"year={target_year}", f"month={target_month}"]
    if user:
        cmd.extend([f"search={user}", "searchtype=user"])
    rc, out, _ = run_cmd(cmd, timeout=30)
    if rc != 0 or not out:
        return {}
    try:
        data = json.loads(out)
        accts = data.get("data", {}).get("acct", [])
        res = {}
        for a in accts:
            u = a.get("user")
            if u:
                res[u] = a
        return res
    except Exception:
        return {}


def read_cache_db_rows(user, month_only=True):
    rows = []
    if not os.path.isfile(cache_db):
        return rows
    try:
        con = sqlite3.connect(cache_db)
        cur = con.cursor()
        if month_only:
            cur.execute(
                """
                SELECT m.year, m.month_num, u.name, d.name, m.bytes, m.user_id, m.domain_id
                FROM monthly_domain_data m
                JOIN users u ON u.id = m.user_id
                JOIN domains d ON d.id = m.domain_id
                WHERE u.name = ? AND m.year = ? AND m.month_num = ?
                """,
                (user, target_year, target_month),
            )
        else:
            cur.execute(
                """
                SELECT m.year, m.month_num, u.name, d.name, m.bytes, m.user_id, m.domain_id
                FROM monthly_domain_data m
                JOIN users u ON u.id = m.user_id
                JOIN domains d ON d.id = m.domain_id
                WHERE u.name = ?
                """,
                (user,),
            )
        for r in cur.fetchall():
            rows.append({
                "year": r[0],
                "month_num": r[1],
                "user": r[2],
                "domain": r[3],
                "bytes": r[4],
                "user_id": r[5],
                "domain_id": r[6],
            })
        con.close()
    except Exception:
        pass
    return rows


def find_user_bw_artifacts(user, domains):
    sqlite_path = os.path.join(bw_dir, f"{user}.sqlite")
    has_sqlite = os.path.isfile(sqlite_path)

    flat_files = []
    suffixes = ("", ".5min", ".hour", ".remainder")
    for base in list(domains) + [user]:
        for suf in suffixes:
            fp = os.path.join(bw_dir, f"{base}{suf}")
            if os.path.isfile(fp):
                flat_files.append(fp)

    cache_files = []
    for base in list(domains) + [user]:
        cf = os.path.join(bw_cache_dir, base)
        if os.path.isfile(cf):
            cache_files.append(cf)

    bwlimited_path = f"/var/cpanel/bwlimited/{user}"
    is_bwlimited_file = os.path.exists(bwlimited_path)

    return {
        "sqlite_file": sqlite_path if has_sqlite else None,
        "flat_files": sorted(set(flat_files)),
        "cache_files": sorted(set(cache_files)),
        "bwlimited_file": bwlimited_path if is_bwlimited_file else None,
    }


def emit_output(payload, columns, rows, header_title):
    if fmt == "json":
        print(json.dumps(payload, indent=2))
        return
    if fmt == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(columns)
        for r in rows:
            w.writerow(r)
        sys.stdout.write(buf.getvalue())
        return

    if not quiet:
        print("=" * 96)
        print(f" {c_bold}{script_name} v{script_version}{c_reset} | {header_title} | {ts_utc}")
        print("=" * 96)

    if not rows:
        print(f"{c_green}[CLEAN]{c_reset} No accounts/records to display.")
        return

    widths = [len(c) for c in columns]
    for r in rows:
        for idx, val in enumerate(r):
            plain = re.sub(r'\033\[[0-9;]*m', '', str(val))
            if len(plain) > widths[idx]:
                widths[idx] = min(len(plain), 60)

    hdr = "  ".join(c.ljust(widths[i]) for i, c in enumerate(columns))
    sep = "  ".join("-" * widths[i] for i in range(len(columns)))
    print(f"{c_bold}{hdr}{c_reset}")
    print(sep)
    for r in rows:
        cells = []
        for idx, val in enumerate(r):
            s = str(val)
            plain = re.sub(r'\033\[[0-9;]*m', '', s)
            pad = max(0, widths[idx] - len(plain))
            cells.append(s + (" " * pad))
        print("  ".join(cells))


# ==============================================================================
# AUDIT
# ==============================================================================
if action == "audit":
    users = resolve_user_list()
    whm_map = query_whmapi_showbw(None if (all_users or len(users) > 1) else users[0])
    records = []
    alert_found = False

    for u in users:
        if not cpanel_user_exists(u):
            print(f"[WARN] cPanel account not found: {u}", file=sys.stderr)
            continue
        domains = get_user_domains(u)
        art = find_user_bw_artifacts(u, domains)
        cache_rows = read_cache_db_rows(u, month_only=not all_months)
        cache_bytes = sum(r["bytes"] for r in cache_rows)

        whm_info = whm_map.get(u, {})
        total_bytes = int(whm_info.get("totalbytes", cache_bytes)) if whm_info else cache_bytes
        if cache_bytes > total_bytes:
            total_bytes = cache_bytes

        raw_limit = whm_info.get("limit", "unlimited")
        limit_bytes = None if str(raw_limit).lower() == "unlimited" else int(raw_limit)
        bwlimited = bool(whm_info.get("bwlimited", 0)) or bool(art["bwlimited_file"])

        pct = None
        if limit_bytes and limit_bytes > 0:
            pct = round((total_bytes / float(limit_bytes)) * 100.0, 1)

        if bwlimited or (pct is not None and pct >= 90.0):
            alert_found = True

        status = "LIMITED" if bwlimited else ("WARN" if (pct is not None and pct >= 90.0) else "OK")
        records.append({
            "user": u,
            "month": f"{target_year:04d}-{target_month:02d}" if not all_months else "ALL",
            "used_bytes": total_bytes,
            "used_human": human_bytes(total_bytes),
            "limit_bytes": limit_bytes,
            "limit_human": human_bytes(limit_bytes),
            "percent": pct,
            "bwlimited": bwlimited,
            "status": status,
            "sqlite_file": art["sqlite_file"],
            "cache_db_rows": len(cache_rows),
            "flat_files_count": len(art["flat_files"]),
            "cache_files_count": len(art["cache_files"]),
        })

    payload = {
        "tool": script_name,
        "version": script_version,
        "action": "audit",
        "timestamp_utc": ts_utc,
        "target_month": f"{target_year:04d}-{target_month:02d}",
        "count": len(records),
        "accounts": records,
    }
    rows = []
    for r in records:
        st = r["status"]
        if fmt == "table":
            if st == "LIMITED":
                st = f"{c_red}LIMITED{c_reset}"
            elif st == "WARN":
                st = f"{c_yellow}WARN{c_reset}"
            else:
                st = f"{c_green}OK{c_reset}"
        pct_s = f"{r['percent']}%" if r["percent"] is not None else "-"
        art_s = f"db:{r['cache_db_rows']} sql:{1 if r['sqlite_file'] else 0} flat:{r['flat_files_count']}"
        rows.append([r["user"], r["month"], r["used_human"], r["limit_human"], pct_s, st, art_s])

    emit_output(
        payload,
        ["USER", "PERIOD", "USED", "LIMIT", "PCT", "STATUS", "STORAGE"],
        rows,
        f"Bandwidth Audit ({target_year:04d}-{target_month:02d})",
    )
    if exit_code_mode and alert_found:
        sys.exit(2)
    sys.exit(0)

# ==============================================================================
# RESET
# ==============================================================================
elif action == "reset":
    users = resolve_user_list()
    results = []
    day_slug = time.strftime("%Y%m%d", time.gmtime())
    ts_slug = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())

    for u in users:
        if not cpanel_user_exists(u):
            print(f"[ERR] cPanel account not found: {u}", file=sys.stderr)
            sys.exit(1)

        domains = get_user_domains(u)
        art = find_user_bw_artifacts(u, domains)
        cache_rows = read_cache_db_rows(u, month_only=not all_months)
        before_bytes = sum(r["bytes"] for r in cache_rows)

        bdir = os.path.join(backup_dir, day_slug)
        backup_path = os.path.join(bdir, f"{u}-{ts_slug}.tar.gz")

        cache_rows_reset = 0
        sqlite_rows_reset = 0
        flat_files_reset = 0
        cache_files_removed = 0
        unsuspended = False
        weblogs_msg = "skipped"

        if not dry_run:
            os.makedirs(bdir, mode=0o700, exist_ok=True)
            os.chmod(bdir, 0o700)

            manifest = {
                "tool": script_name,
                "version": script_version,
                "created_utc": ts_utc,
                "user": u,
                "target_year": target_year,
                "target_month": target_month,
                "all_months": all_months,
                "cache_db": cache_db,
                "bw_dir": bw_dir,
                "cache_db_rows": cache_rows,
                "sqlite_file": art["sqlite_file"],
                "flat_files": art["flat_files"],
            }

            fd = os.open(backup_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as raw_f:
                with tarfile.open(fileobj=raw_f, mode="w:gz") as tar:
                    m_bytes = json.dumps(manifest, indent=2).encode("utf-8")
                    ti = tarfile.TarInfo(name="manifest.json")
                    ti.size = len(m_bytes)
                    ti.mtime = int(time.time())
                    ti.mode = 0o600
                    tar.addfile(ti, io.BytesIO(m_bytes))

                    if art["sqlite_file"]:
                        tar.add(art["sqlite_file"], arcname=f"bandwidth/{os.path.basename(art['sqlite_file'])}")
                    for fp in art["flat_files"]:
                        tar.add(fp, arcname=f"bandwidth/{os.path.basename(fp)}")

            # 1. Reset bandwidth_cache.sqlite rows atomically
            if os.path.isfile(cache_db) and cache_rows:
                con = sqlite3.connect(cache_db)
                try:
                    cur = con.cursor()
                    if all_months:
                        cur.execute(
                            """
                            UPDATE monthly_domain_data SET bytes = 0
                            WHERE user_id IN (SELECT id FROM users WHERE name = ?)
                            """,
                            (u,),
                        )
                    else:
                        cur.execute(
                            """
                            UPDATE monthly_domain_data SET bytes = 0
                            WHERE user_id IN (SELECT id FROM users WHERE name = ?)
                              AND year = ? AND month_num = ?
                            """,
                            (u, target_year, target_month),
                        )
                    cache_rows_reset = cur.rowcount
                    con.commit()
                finally:
                    con.close()

            # 2. Reset per-user <user>.sqlite if present
            if art["sqlite_file"]:
                con = sqlite3.connect(art["sqlite_file"])
                try:
                    cur = con.cursor()
                    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
                    tables = [r[0] for r in cur.fetchall()]
                    for tbl in tables:
                        if not re.match(r'^[A-Za-z0-9_]+$', tbl):
                            continue
                        cur.execute(f"PRAGMA table_info({tbl})")
                        cols = {c[1] for c in cur.fetchall()}
                        if "bytes" in cols:
                            if not all_months and "unixtime" in cols:
                                start_ts = int(time.mktime((target_year, target_month, 1, 0, 0, 0, 0, 0, 0)))
                                next_y = target_year + (1 if target_month == 12 else 0)
                                next_m = 1 if target_month == 12 else target_month + 1
                                end_ts = int(time.mktime((next_y, next_m, 1, 0, 0, 0, 0, 0, 0)))
                                cur.execute(
                                    f"UPDATE {tbl} SET bytes = 0 WHERE unixtime >= ? AND unixtime < ?",
                                    (start_ts, end_ts),
                                )
                            else:
                                cur.execute(f"UPDATE {tbl} SET bytes = 0")
                            sqlite_rows_reset += cur.rowcount
                    con.commit()
                finally:
                    con.close()

            # 3. Reset legacy flat files atomically
            for fp in art["flat_files"]:
                with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                updated = re.sub(r'=[0-9]+', '=0', content)
                tmp_fp = f"{fp}.resetbw.{os.getpid()}.tmp"
                st = os.stat(fp)
                fd2 = os.open(tmp_fp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, st.st_mode & 0o777)
                with os.fdopen(fd2, "w", encoding="utf-8") as tf:
                    tf.write(updated)
                os.replace(tmp_fp, fp)
                flat_files_reset += 1

            # 4. Remove stale bandwidth.cache files
            for cf in art["cache_files"]:
                try:
                    os.unlink(cf)
                    cache_files_removed += 1
                except Exception:
                    pass

            # 5. Optional unsuspend
            if do_unsuspend and art["bwlimited_file"]:
                try:
                    os.unlink(art["bwlimited_file"])
                    unsuspended = True
                except Exception:
                    pass

            # 6. Optional /scripts/runweblogs
            if do_weblogs and os.path.isfile("/scripts/runweblogs"):
                rc, out, err = run_cmd(["/scripts/runweblogs", u], timeout=120)
                weblogs_msg = "ok" if rc == 0 else f"failed ({err or out})"
        else:
            cache_rows_reset = len(cache_rows)
            flat_files_reset = len(art["flat_files"])
            cache_files_removed = len(art["cache_files"])

        results.append({
            "user": u,
            "period": "ALL" if all_months else f"{target_year:04d}-{target_month:02d}",
            "before_bytes": before_bytes,
            "before_human": human_bytes(before_bytes),
            "cache_rows_reset": cache_rows_reset,
            "sqlite_rows_reset": sqlite_rows_reset,
            "flat_files_reset": flat_files_reset,
            "cache_files_removed": cache_files_removed,
            "unsuspended": unsuspended,
            "weblogs": weblogs_msg,
            "backup_file": backup_path if not dry_run else f"[DRY-RUN] {backup_path}",
            "mode": "DRY-RUN" if dry_run else "RESET",
        })

    payload = {
        "tool": script_name,
        "version": script_version,
        "action": "reset",
        "dry_run": dry_run,
        "timestamp_utc": ts_utc,
        "results": results,
    }
    rows = []
    for r in results:
        tag = f"{c_yellow}DRY-RUN{c_reset}" if (dry_run and fmt == "table") else (f"{c_green}RESET{c_reset}" if fmt == "table" else r["mode"])
        rows.append([
            r["user"],
            r["period"],
            r["before_human"],
            str(r["cache_rows_reset"]),
            str(r["flat_files_reset"]),
            tag,
        ])
    emit_output(
        payload,
        ["USER", "PERIOD", "PREV_USED", "DB_ROWS", "FLAT_FILES", "STATUS"],
        rows,
        f"Bandwidth Reset [{'DRY-RUN' if dry_run else 'APPLIED'}]",
    )
    if fmt == "table" and not quiet:
        for r in results:
            print(f"\nBackup ({r['user']}): {r['backup_file']}")
    sys.exit(0)

# ==============================================================================
# RESTORE
# ==============================================================================
elif action == "restore":
    if not target or not os.path.isfile(target):
        print(f"[ERR] Backup archive not found: '{target}'", file=sys.stderr)
        sys.exit(1)

    with tarfile.open(target, "r:gz") as tar:
        names = tar.getnames()
        if "manifest.json" not in names:
            print("[ERR] Invalid resetbw backup archive (missing manifest.json).", file=sys.stderr)
            sys.exit(1)
        manifest = json.loads(tar.extractfile("manifest.json").read().decode("utf-8"))
        u = manifest["user"]
        orig_cache_db = cache_db if cache_db != "/var/cpanel/bandwidth_cache.sqlite" else manifest.get("cache_db", cache_db)
        orig_bw_dir = bw_dir if bw_dir != "/var/cpanel/bandwidth" else manifest.get("bw_dir", bw_dir)
        saved_rows = manifest.get("cache_db_rows", [])

        restored_files = 0
        restored_rows = 0

        if not dry_run:
            # Restore bandwidth files safely (prevent path traversal)
            for member in tar.getmembers():
                if not member.isfile() or not member.name.startswith("bandwidth/"):
                    continue
                base = os.path.basename(member.name)
                if not base or ".." in base or "/" in base:
                    continue
                dest = os.path.join(orig_bw_dir, base)
                tmp_dest = f"{dest}.restore.{os.getpid()}.tmp"
                data = tar.extractfile(member).read()
                fd = os.open(tmp_dest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "wb") as out_f:
                    out_f.write(data)
                os.replace(tmp_dest, dest)
                restored_files += 1

            # Restore bandwidth_cache.sqlite rows
            if saved_rows and os.path.isfile(orig_cache_db):
                con = sqlite3.connect(orig_cache_db)
                try:
                    cur = con.cursor()
                    for sr in saved_rows:
                        cur.execute(
                            """
                            UPDATE monthly_domain_data SET bytes = ?
                            WHERE year = ? AND month_num = ? AND user_id = ? AND domain_id = ?
                            """,
                            (sr["bytes"], sr["year"], sr["month_num"], sr["user_id"], sr["domain_id"]),
                        )
                        restored_rows += cur.rowcount
                    con.commit()
                finally:
                    con.close()
        else:
            restored_rows = len(saved_rows)
            restored_files = sum(1 for n in names if n.startswith("bandwidth/"))

    payload = {
        "tool": script_name,
        "version": script_version,
        "action": "restore",
        "dry_run": dry_run,
        "timestamp_utc": ts_utc,
        "archive": target,
        "user": u,
        "restored_db_rows": restored_rows,
        "restored_files": restored_files,
    }
    mode_tag = f"{c_yellow}DRY-RUN{c_reset}" if (dry_run and fmt == "table") else (f"{c_green}RESTORED{c_reset}" if fmt == "table" else ("DRY-RUN" if dry_run else "RESTORED"))
    emit_output(
        payload,
        ["USER", "DB_ROWS", "FILES", "STATUS"],
        [[u, str(restored_rows), str(restored_files), mode_tag]],
        f"Bandwidth Restore [{'DRY-RUN' if dry_run else 'APPLIED'}]",
    )
    sys.exit(0)
PYEOF
)"

  python3 -c "$py_script" \
    "$ACTION" "$TARGET" "$USER_FILE" "$ALL_USERS" "$MONTH_FILTER" "$ALL_MONTHS" \
    "$BACKUP_DIR" "$BW_DIR" "$BW_CACHE_DIR" "$CACHE_DB" \
    "$DO_UNSUSPEND" "$DO_WEBLOGS" "$DRY_RUN" "$EXIT_CODE_MODE" "$OUTPUT_FMT" "$QUIET" \
    "$SCRIPT_NAME" "$SCRIPT_VERSION" "$ts_utc" \
    "$C_RED" "$C_GREEN" "$C_YELLOW" "$C_CYAN" "$C_BOLD" "$C_RESET"
}

main "$@"
