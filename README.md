# Alarm Clock

Adds a browser alarm clock page, backend API and alarm WAV playback support.

This repository is private while it is being checked and verified.

## Install

```bash
cd /home/pi/Stargate-Final_Patches
rm -rf Alarm-Clock
git clone https://github.com/matelv-x/Alarm-Clock.git
cd Alarm-Clock
chmod +x *.sh
sudo ./install.sh /home/pi/sg1_v4
sudo systemctl restart stargate.service
```

## Restore / uninstall

```bash
cd /home/pi/Stargate-Final_Patches/Alarm-Clock
chmod +x restore.sh
sudo ./restore.sh /home/pi/sg1_v4
sudo systemctl restart stargate.service
```

## What it changes

- Adds web/alarm_clock.htm and web/js/alarm_clock.js.
- Adds alarm manager classes, alarm config and alarm sound assets.
- Adds backend actions used by the browser alarm controls.

## Attribution and originality

Original base project: StargateProject SG1 software from the BuildAStargate/Jordan/Kristian/Jonnerd project lineage.

Additional source/idea credit: Feature idea by Marcin/Codex, built on Jordan/Kristian/Jonnerd StargateProject SG1 runtime and web UI.

How much is copied or changed: Medium patch. Some modified SG1 Python/web files are included as patch context, plus new alarm classes and sound assets.

The included `*.patch` file, when present, shows the exact text-level changes against the base software used while packaging.
