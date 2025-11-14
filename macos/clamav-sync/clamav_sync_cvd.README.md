# ClamAV CVD Sync – Final Working Setup

Generated: 2025-11-14 07:22:40 GMT

This documents the working configuration that updates ClamAV databases locally via cvdupdate and syncs to the QNAP over SSH, with reliable scheduling and logging.

## Components

- Main script: `/usr/local/sbin/clamav_sync_cvd.sh`
- LaunchDaemon: `/Library/LaunchDaemons/net.dpl.clamav-sync-cvd.plist`
- Service label: `net.dpl.clamav-sync-cvd`
- Unified log: `/var/log/net.dpl.clamav-sync-cvd.log`
- Login user inside script: `daniellarge`

## Schedule and triggers

- Weekly: Tuesday at `03:00`
- RunAtLoad: true
- KeepAlive.NetworkState: true

## How it runs

1. launchd (root) executes: `/bin/bash -x /usr/local/sbin/clamav_sync_cvd.sh`
2. Script runs cvd as `daniellarge`
   - DB dir: /Users/daniellarge/Library/Caches/clamav_defs
   - Log dir: /Users/daniellarge/Library/Logs/cvdupdate
3. It probes the NAS via SSH and copies only when MD5 differs
4. Stdout and stderr go to `/var/log/net.dpl.clamav-sync-cvd.log`

## Service management

    sudo launchctl bootout system/net.dpl.clamav-sync-cvd 2>/dev/null || true
    sudo launchctl bootstrap system /Library/LaunchDaemons/net.dpl.clamav-sync-cvd.plist
    sudo launchctl enable system/net.dpl.clamav-sync-cvd
    sudo launchctl kickstart -k system/net.dpl.clamav-sync-cvd
    sudo launchctl print system/net.dpl.clamav-sync-cvd | egrep 'state = |last exit code|pid ='

## Manual test (same environment)

    sudo -u daniellarge env HOME=/Users/daniellarge PATH="/usr/local/bin:/opt/homebrew/bin:/Users/daniellarge/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
      /bin/bash -x /usr/local/sbin/clamav_sync_cvd.sh

## Ownership and permissions

    sudo chown root:wheel /usr/local/sbin/clamav_sync_cvd.sh /Library/LaunchDaemons/net.dpl.clamav-sync-cvd.plist
    sudo chmod 755 /usr/local/sbin/clamav_sync_cvd.sh
    sudo chmod 644 /Library/LaunchDaemons/net.dpl.clamav-sync-cvd.plist
    sudo touch /var/log/net.dpl.clamav-sync-cvd.log && sudo chmod 644 /var/log/net.dpl.clamav-sync-cvd.log

## Current status snapshot

### launchd
	state = not running
	stdout path = /var/log/net.dpl.clamav-sync-cvd.log
	stderr path = /var/log/net.dpl.clamav-sync-cvd.log
	last exit code = 1
		state = active
		state = active

### Recent log
+ set -e -o pipefail
+ set +u
+ NAS_HOST=192.168.1.103
+ NAS_USER=admin
+ SSH_PORT_OPT=
+ USE_SUDO=
+ MAC_USER=daniellarge
+ MAC_HOME=/Users/daniellarge
+ export PATH=/usr/local/bin:/opt/homebrew/bin:/Users/daniellarge/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
+ PATH=/usr/local/bin:/opt/homebrew/bin:/Users/daniellarge/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
+ CVD_BIN=
+ for p in '"/usr/local/bin/cvd"' '"/opt/homebrew/bin/cvd"' '"${MAC_HOME}/.local/bin/cvd"'
+ '[' -x /usr/local/bin/cvd ']'
+ CVD_BIN=/usr/local/bin/cvd
+ break
+ '[' -z /usr/local/bin/cvd ']'
+ CACHE_DIR=/Users/daniellarge/Library/Caches/clamav_defs
+ LOG_DIR=/Users/daniellarge/Library/Logs/cvdupdate
++ id -u
+ '[' 0 -eq 0 ']'
+ '[' daniellarge '!=' root ']'
+ sudo install -d -m 755 -o daniellarge -g staff /Users/daniellarge/Library/Caches/clamav_defs /Users/daniellarge/Library/Logs/cvdupdate
+ as_user /usr/local/bin/cvd config set --dbdir /Users/daniellarge/Library/Caches/clamav_defs
++ id -u
+ '[' 0 -eq 0 ']'
+ '[' daniellarge '!=' root ']'
+ HOME=/Users/daniellarge
+ sudo -E -u daniellarge env HOME=/Users/daniellarge PATH=/usr/local/bin:/opt/homebrew/bin:/Users/daniellarge/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin /usr/local/bin/cvd config set --dbdir /Users/daniellarge/Library/Caches/clamav_defs
+ as_user /usr/local/bin/cvd config set --logdir /Users/daniellarge/Library/Logs/cvdupdate
++ id -u
+ '[' 0 -eq 0 ']'
+ '[' daniellarge '!=' root ']'
+ HOME=/Users/daniellarge
+ sudo -E -u daniellarge env HOME=/Users/daniellarge PATH=/usr/local/bin:/opt/homebrew/bin:/Users/daniellarge/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin /usr/local/bin/cvd config set --logdir /Users/daniellarge/Library/Logs/cvdupdate
+ as_user /usr/local/bin/cvd update
++ id -u
+ '[' 0 -eq 0 ']'
+ '[' daniellarge '!=' root ']'
+ HOME=/Users/daniellarge
+ sudo -E -u daniellarge env HOME=/Users/daniellarge PATH=/usr/local/bin:/opt/homebrew/bin:/Users/daniellarge/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin /usr/local/bin/cvd update
2025-11-14 07:18:16 AM - INFO:  Using system configured nameservers
2025-11-14 07:18:16 AM - INFO:  main.cvd is up-to-date. Version: 62
2025-11-14 07:18:16 AM - INFO:  daily.cvd is up-to-date. Version: 27821
2025-11-14 07:18:16 AM - INFO:  bytecode.cvd is up-to-date. Version: 339
++ date +%s
+ deadline=1763104756
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104699 -ge 1763104756 ']'
+ sleep 5
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104707 -ge 1763104756 ']'
+ sleep 5
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104715 -ge 1763104756 ']'
+ sleep 5
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104723 -ge 1763104756 ']'
+ sleep 5
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104732 -ge 1763104756 ']'
+ sleep 5
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104740 -ge 1763104756 ']'
+ sleep 5
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104748 -ge 1763104756 ']'
+ sleep 5
+ ssh -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 admin@192.168.1.103 'echo ok'
++ date +%s
+ '[' 1763104756 -ge 1763104756 ']'
+ echo 'SSH to admin@192.168.1.103 unavailable'
SSH to admin@192.168.1.103 unavailable
+ exit 1

### Plist (pretty)
{
  "KeepAlive" => {
    "NetworkState" => true
  }
  "Label" => "net.dpl.clamav-sync-cvd"
  "ProcessType" => "Background"
  "ProgramArguments" => [
    0 => "/bin/bash"
    1 => "-x"
    2 => "/usr/local/sbin/clamav_sync_cvd.sh"
  ]
  "RunAtLoad" => true
  "StandardErrorPath" => "/var/log/net.dpl.clamav-sync-cvd.log"
  "StandardOutPath" => "/var/log/net.dpl.clamav-sync-cvd.log"
  "StartCalendarInterval" => {
    "Hour" => 3
    "Minute" => 0
    "Weekday" => 3
  }
  "WorkingDirectory" => "/"
}

### cvdupdate
- Binary: `/usr/local/bin/cvd`
- Version:
unknown
