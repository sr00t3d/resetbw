[![🇺🇸 English](https://img.shields.io/badge/lang-English-blue.svg)](README.md) [![🇧🇷 Português](https://img.shields.io/badge/lang-Português-green.svg)](README-ptbr.md) [![🇪🇸 Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README-es.md)

# resetbw

![resetbw cover](resetbw-cover.webp)

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/resetbw/releases/tag/v2.0.0)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-orange.svg)](#requisitos)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20cPanel%20%7C%20WHM-lightgrey.svg)](#requisitos)

**CLI Segura de Auditoría, Reinicio y Restauración de Ancho de Banda en cPanel/WHM (SQLite + Legacy).**

`resetbw.sh` audita el consumo de ancho de banda (`whmapi1 showbw` + `/var/cpanel/bandwidth_cache.sqlite`), crea respaldos `.tar.gz` (`chmod 600`) con snapshot JSON, reinicia contadores por mes (`--month YYYY-MM`) o completos y soporta restauración directa con `restore`.

> **Inspiración Histórica:** Reimplementación limpia en Bash + Python 3.6+ (`v2.0.0`) inspirada en `resetbw` (2011, v0.1, HostGator.com, LLC).

---

## Ejecución Directa

```bash
curl -fsSL https://raw.githubusercontent.com/sr00t3d/resetbw/main/resetbw.sh -o resetbw.sh
chmod +x resetbw.sh
sudo ./resetbw.sh audit --all
```

---

## Licencia

Licenciado bajo [Apache License 2.0](LICENSE).
