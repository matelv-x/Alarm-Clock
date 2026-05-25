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

## Attribution and originality

Original base project: StargateProject SG1 software from the BuildAStargate/Jordan/Kristian/Jonnerd project lineage.

Additional source/idea credit: Feature idea by Marcin/Codex over Jordan/Jonnerd StargateProject SG1 v4.

How much is copied or changed: Large add-on package with embedded ZIP payload and selected modified files.
