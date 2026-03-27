# Proxmox LXC Container Export Script

A standalone bash script to backup/export an existing LXC container on a Proxmox VE host using `vzdump`.

## Features

- **Single-command export** — one command to backup any LXC container
- **Snapshot mode** — live backup with no container downtime (default)
- **Configurable compression** — zstd (default), gzip, lzo, or none
- **Input validation** — checks root permissions, container existence, command availability
- **Logging** — timestamped entries to both stdout and a log file
- **Reproducible** — logs the exact `vzdump` command used

## Requirements

- **Proxmox VE** host (tested on PVE 7.x / 8.x)
- **Root access** (vzdump requires root)
- Commands available: `vzdump`, `pct` (part of standard PVE install)

## Installation

```bash
# Copy the script to your Proxmox host
scp proxmox-export.sh root@<proxmox-host>:/usr/local/bin/

# Make it executable
ssh root@<proxmox-host> "chmod +x /usr/local/bin/proxmox-export.sh"
```

Or directly on the Proxmox host:

```bash
curl -o /usr/local/bin/proxmox-export.sh <raw-url>
chmod +x /usr/local/bin/proxmox-export.sh
```

## Usage

```
Usage:
  proxmox-export.sh --id <CTID> [OPTIONS]

Required:
  -i, --id <CTID>          Container ID to export (e.g., 100)

Options:
  -d, --dumpdir <PATH>     Output directory (default: /var/lib/vz/dump)
  -c, --compress <TYPE>    Compression type: zstd, gzip, lzo, none (default: zstd)
  -m, --mode <MODE>        Backup mode: snapshot, suspend, stop (default: snapshot)
  -l, --logfile <PATH>     Log file path (default: /var/log/proxmox-export.log)
  -h, --help               Show help message
```

## Examples

### Basic export with defaults

```bash
# Snapshot mode, zstd compression, output to /var/lib/vz/dump
./proxmox-export.sh --id 100
```

### Export to custom directory with gzip

```bash
./proxmox-export.sh --id 100 --dumpdir /mnt/backups --compress gzip
```

### Stop container during backup (most consistent)

```bash
./proxmox-export.sh --id 100 --mode stop
```

### Full example with all options

```bash
./proxmox-export.sh \
  --id 100 \
  --dumpdir /mnt/nfs/proxmox-backups \
  --compress zstd \
  --mode snapshot \
  --logfile /var/log/ct100-export.log
```

## Backup Modes

| Mode | Downtime | Description |
|------|----------|-------------|
| `snapshot` | None | Live backup using LXC snapshots. Default and recommended. |
| `suspend` | Brief | Suspends the container briefly to ensure consistency. |
| `stop` | Full | Stops the container during backup. Most consistent but causes downtime. |

## Compression Types

| Type | Speed | Ratio | File Extension |
|------|-------|-------|----------------|
| `zstd` | Fast | Excellent | `.tar.zst` |
| `gzip` | Medium | Good | `.tar.gz` |
| `lzo` | Very fast | Lower | `.tar.lzo` |
| `none` | Fastest | None | `.tar` |

## Output

The script produces a vzdump backup file in the output directory:

```
/var/lib/vz/dump/vzdump-lxc-100-2026_03_23-19_45_00.tar.zst
```

After completion, a summary is displayed:

```
═══════════════════════════════════════════════════════
  Export Summary
═══════════════════════════════════════════════════════
  Container:    CT100
  Mode:         snapshot
  Compression:  zstd
  Output file:  /var/lib/vz/dump/vzdump-lxc-100-2026_03_23-19_45_00.tar.zst
  File size:    1.2G
  Duration:     2m 34s
  Log file:     /var/log/proxmox-export.log
═══════════════════════════════════════════════════════
```

## Restoring a Backup

To restore the exported container on any Proxmox host:

```bash
# Restore to a new container ID (e.g., 200)
pct restore 200 /var/lib/vz/dump/vzdump-lxc-100-2026_03_23-19_45_00.tar.zst \
  --storage local-lvm

# Restore with specific options
pct restore 200 /path/to/backup.tar.zst \
  --storage local-lvm \
  --memory 2048 \
  --cores 2 \
  --hostname restored-ct
```

## Scheduling with Cron

While the script doesn't include built-in scheduling, you can easily add a cron job:

```bash
# Edit root's crontab
crontab -e

# Daily export at 2:00 AM
0 2 * * * /usr/local/bin/proxmox-export.sh --id 100 --dumpdir /mnt/backups >> /var/log/proxmox-export-cron.log 2>&1

# Weekly export on Sundays at 3:00 AM
0 3 * * 0 /usr/local/bin/proxmox-export.sh --id 100 --mode stop --dumpdir /mnt/backups >> /var/log/proxmox-export-cron.log 2>&1
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `must be run as root` | Run with `sudo` or as the root user |
| `vzdump not found` | Ensure you're on a Proxmox VE host with `vzdump` installed |
| `container does not exist` | Verify the CTID with `pct list` |
| `snapshot mode fails` | Try `--mode suspend` or `--mode stop` instead |
| Backup file too large | Use `--compress zstd` for best compression ratio |

## License

MIT
