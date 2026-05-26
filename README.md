# Stargate Alarm Clock Add-on

Installable Alarm Clock add-on for StargateProject SG1 v4.

This repository is private while it is being checked and verified.

## Install

Clone or unzip this add-on into `/home/pi`, then run:

```bash
cd /home/pi
rm -rf Alarm-Clock
git clone https://github.com/matelv-x/Alarm-Clock.git
cd Alarm-Clock
chmod +x install.sh restore.sh
sudo systemctl stop stargate.service
sudo ./install.sh
sudo systemctl restart stargate.service
```

## Restore / uninstall

```bash
cd /home/pi/Alarm-Clock
sudo ./restore.sh
sudo systemctl restart stargate.service
```

## What it changes

- Adds web alarm-clock UI.
- Adds alarm backend/files and sample alarm sounds.
- Installer asks which background/UI mode to use.
- Shows Raspberry Pi system time/timezone in the Alarm Clock UI.
- Uses Raspberry Pi local system time for scheduled alarm triggers.

## Timezone note

Scheduled alarms run from the Raspberry Pi system clock, not from the browser clock. If an alarm triggers at the wrong time, check the Pi timezone first:

```bash
timedatectl
date
```

Set the correct timezone if needed, for example:

```bash
sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp true
sudo systemctl restart stargate.service
```

## Attribution and originality

Original base project: StargateProject SG1 software from the BuildAStargate/Jordan/Kristian/Jonnerd project lineage.

Additional source/idea credit: Feature idea by matelv-x/Codex over Jordan/Jonnerd StargateProject SG1 v4.

How much is copied or changed: Large add-on package with embedded ZIP payload and selected modified files.
