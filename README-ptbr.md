[![🇺🇸 English](https://img.shields.io/badge/lang-English-blue.svg)](README.md) [![🇧🇷 Português](https://img.shields.io/badge/lang-Português-green.svg)](README-ptbr.md) [![🇪🇸 Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README-es.md)

# resetbw

![resetbw cover](resetbw-cover.webp)

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/resetbw/releases/tag/v2.0.0)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-orange.svg)](#requisitos)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20cPanel%20%7C%20WHM-lightgrey.svg)](#requisitos)

**CLI Segura de Auditoria, Reset e Restauração de Banda do cPanel/WHM (SQLite + Legado).**

O `resetbw.sh` audita consumo e cotas de largura de banda no cPanel (`whmapi1 showbw` + `/var/cpanel/bandwidth_cache.sqlite`), gera backups `.tar.gz` (`chmod 600`) com snapshot JSON antes de qualquer alteração, zera contadores por mês (`--month YYYY-MM`) ou histórico completo tanto nas bases SQLite modernas quanto nos arquivos legados, remove bloqueio `/var/cpanel/bwlimited/<user>` com `--unsuspend` e permite restauração exata via `restore`.

> **Inspiração Histórica:** Reimplementação limpa em Bash + Python 3.6+ (`v2.0.0`) inspirada no clássico `resetbw` (2011, v0.1, HostGator.com, LLC).

---

## Requisitos

- Servidor Linux com cPanel/WHM, Bash 4.0+ e Python 3.6+
- Privilégios de root para ler/atualizar `/var/cpanel/bandwidth*` e executar `whmapi1`

---

## Execução Direta

```bash
curl -fsSL https://raw.githubusercontent.com/sr00t3d/resetbw/main/resetbw.sh -o resetbw.sh
chmod +x resetbw.sh
sudo ./resetbw.sh audit --all
```

---

## Exemplos de Uso

```bash
sudo ./resetbw.sh audit percio
sudo ./resetbw.sh audit --all --exit-code
sudo ./resetbw.sh reset percio --dry-run
sudo ./resetbw.sh reset percio --month 2026-11 --unsuspend
sudo ./resetbw.sh restore /var/backups/resetbw/20261122/percio-20261122T120000Z.tar.gz
```

---

## Licença

Distribuído sob a licença [Apache License 2.0](LICENSE).
