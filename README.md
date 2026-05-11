# Stargate Alarm Clock Add-on

This repository contains an installable Alarm Clock add-on for Jordan's original
StargateProject software.

It is an independent add-on package. It is not a fork of the original project and
does not replace the full StargateProject installation.

## Project Relationship

This package is intended to be used with:

1. Original StargateProject software:
   <https://github.com/jonnerd154/StargateProject-software>

2. This Alarm Clock add-on:
   <https://github.com/matelv-x/Alarm-Clock>

The add-on targets the `SG1_v4` project structure, usually located at:

```text
/home/pi/sg1_v4
```

## What It Adds

- an independent web-based alarm clock
- alarm settings stored and handled through the Stargate web system
- wormhole-style alarm effect
- DHD center-button alarm stop support
- web-interface alarm stop support
- custom background support
- custom alarm sound support
- included sample alarm sounds

## Included Files

```text
install.sh
restore.sh
AlarmClock.zip
```

`AlarmClock.zip` contains the add-on files that the installer applies to the
target StargateProject installation.

## Installation Modes

During installation, the script asks which web UI/background mode to use:

1. `Kristian-background` - for a clean Kristian image
2. `PolkaDot-background` - for the PolkaDot retro UI
3. `Custom` - for a custom background image

## Installation

Copy or clone this repository to the Raspberry Pi, then run:

```bash
sudo systemctl stop stargate.service
cd /home/pi/Alarm-Clock
chmod +x install.sh restore.sh
./install.sh
```

The installer expects the StargateProject folder at:

```text
/home/pi/sg1_v4
```

It creates a backup before applying changes. The backup path is stored in:

```text
.last_backup_path
```

## Restore

To restore the previous installation from the latest backup:

```bash
cd /home/pi/Alarm-Clock
sudo ./restore.sh
sudo systemctl restart stargate.service
```

## Modified Areas

The installer adds or patches files under:

```text
/home/pi/sg1_v4/classes
/home/pi/sg1_v4/classes/StargateMilkyWay
/home/pi/sg1_v4/web
/home/pi/sg1_v4/web/js
/home/pi/sg1_v4/web/img
/home/pi/sg1_v4/web/retro/js
/home/pi/sg1_v4/soundfx/alarm
```

## Safety Notice

Use this add-on at your own risk. Always create a backup before installing it,
especially on a modified StargateProject system.

The installer creates an automatic backup, but a manual backup is still
recommended:

```bash
cp -r /home/pi/sg1_v4 /home/pi/sg1_v4_manual_backup
```

## Troubleshooting

Restart the service after installation if the UI does not refresh:

```bash
sudo systemctl restart stargate.service
```

Check logs with:

```bash
journalctl -u stargate -n 50
```

If custom sounds do not appear, verify that WAV files are present in:

```text
/home/pi/sg1_v4/soundfx/alarm
```
