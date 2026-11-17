# ufdbGuard backup cleanup

Retains the three most recent `blacklists.bak.YYYY-MM-DD-HHMMSS` directories under `/var/lib/ufdbguard`. Protects the active `blacklists` directory. Designed for a Linux host using Squid and ufdbGuard.

## Install

```bash
sudo install -o root -g root -m 0750 ufdbguard-backup-cleanup.sh /usr/local/sbin/ufdbguard-backup-cleanup.sh
sudo install -o root -g root -m 0644 ufdbguard-backup-cleanup.service /etc/systemd/system/
sudo install -o root -g root -m 0644 ufdbguard-backup-cleanup.timer /etc/systemd/system/
sudo bash -n /usr/local/sbin/ufdbguard-backup-cleanup.sh
sudo /usr/local/sbin/ufdbguard-backup-cleanup.sh --dry-run
```

Inspect the simulated deletion list before the first real run. Then:

```bash
sudo /usr/local/sbin/ufdbguard-backup-cleanup.sh
sudo systemctl daemon-reload
sudo systemctl enable --now ufdbguard-backup-cleanup.timer
sudo systemctl list-timers --all | grep ufdbguard-backup-cleanup
sudo journalctl -u ufdbguard-backup-cleanup.service -n 100 --no-pager
df -h /var
```

## Operational limitations

- Cleanup is destructive and historical backups cannot be recovered without separate backups.
- The updater process check is best-effort only. **Implement a shared lock in the updater before relying on race-free automation.**
- The script expects the ufdbGuard data directory to reside on the `/var` mount; change the mount assertion for other layouts.
- `Persistent=true` may trigger a missed timer run immediately when enabled.
- No Squid or ufdbGuard restart is performed.
- Review the `systemd` timer separately if updater duration can exceed 04:30.

## Files

- `ufdbguard-backup-cleanup.sh`: cleanup and dry-run.
- `ufdbguard-backup-cleanup.service`: systemd oneshot.
- `ufdbguard-backup-cleanup.timer`: daily at 04:30.
