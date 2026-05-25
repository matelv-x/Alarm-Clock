import json
import os
import threading
import time

import simpleaudio as sa

from alarm_clock_wormhole import AlarmClockWormhole


class AlarmClockManager:
    def __init__(self, stargate):
        self.stargate = stargate
        self.log = stargate.log
        self.audio = stargate.audio
        self.schedule = stargate.schedule
        self.base_path = stargate.base_path

        self.config_path = os.path.join(self.base_path, "config", "alarm_clock.json")
        self.audio_dir = os.path.join(self.base_path, "soundfx", "alarm")
        self.clip_key = "alarm_clock_active"

        self._lock = threading.RLock()
        self._active = False
        self._stopping = False
        self._last_trigger_key = None
        self._active_file = None
        self._original_volume = self.audio.volume
        self._last_ramp_time = 0

        self._center_blink_thread = None
        self._center_blink_stop = threading.Event()

        self.start_volume = 35
        self.max_volume = 95
        self.ramp_step = 5
        self.ramp_interval_seconds = 8
        self.fade_steps = 14
        self.fade_delay = 0.16

        self.visual = AlarmClockWormhole(stargate)

        self.schedule.every(1).seconds.do(self.tick)
        self.log.log("AlarmClockManager initialized")

    def _default_data(self):
        return {
            "enabled": False,
            "hour": None,
            "minute": None,
            "meridiem": None,
            "audio_file": None
        }

    def read_config(self):
        data = self._default_data()
        if not os.path.exists(self.config_path):
            return data

        try:
            with open(self.config_path, "r", encoding="utf-8") as fh:
                loaded = json.load(fh)
            data["enabled"] = bool(loaded.get("enabled", False))
            data["hour"] = loaded.get("hour")
            data["minute"] = loaded.get("minute")
            data["meridiem"] = loaded.get("meridiem")
            data["audio_file"] = loaded.get("audio_file")
        except Exception as exc:
            self.log.log(f"Alarm read_config failed: {exc}")
        return data

    def write_config(self, data):
        os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
        with open(self.config_path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)

    def get_alarm_data(self):
        data = self.read_config()
        data["active"] = self.is_active()
        return data

    def list_audio_files(self):
        if not os.path.isdir(self.audio_dir):
            return []

        files = []
        for name in os.listdir(self.audio_dir):
            full_path = os.path.join(self.audio_dir, name)
            if os.path.isfile(full_path) and name.lower().endswith(".wav"):
                files.append(name)
        files.sort()
        return files

    def update_alarm(self, payload):
        files = self.list_audio_files()

        audio_file = payload.get("audio_file")
        if audio_file:
            audio_file = os.path.basename(str(audio_file))
            if audio_file not in files:
                raise ValueError(f"Audio file not found: {audio_file}")
        else:
            audio_file = None

        hour = payload.get("hour")
        minute = payload.get("minute")
        meridiem = payload.get("meridiem")
        enabled = bool(payload.get("enabled", True))

        if enabled:
            if hour is None or minute is None or meridiem not in ("AM", "PM") or not audio_file:
                raise ValueError("Select hour, minute, AM/PM, and WAV audio file")

            hour = int(hour)
            minute = int(minute)
            if hour < 1 or hour > 12:
                raise ValueError("Hour must be between 1 and 12")
            if minute < 0 or minute > 59:
                raise ValueError("Minute must be between 0 and 59")
        else:
            hour = int(hour) if hour is not None else None
            minute = int(minute) if minute is not None else None

        data = {
            "enabled": enabled,
            "hour": hour,
            "minute": minute,
            "meridiem": meridiem,
            "audio_file": audio_file
        }
        self.write_config(data)
        return data

    def is_active(self):
        with self._lock:
            return self._active or self._stopping

    def _get_audio_path(self, filename):
        return os.path.join(self.audio_dir, os.path.basename(filename))

    def _ensure_clip_loaded(self, filename):
        full_path = self._get_audio_path(filename)
        if not os.path.isfile(full_path):
            raise ValueError(f"Audio file not found: {filename}")

        self.audio.sounds[self.clip_key] = {
            "file": sa.WaveObject.from_wave_file(full_path)
        }

    def _clip_is_playing(self):
        try:
            if self.clip_key not in self.audio.sounds:
                return False
            clip = self.audio.sounds[self.clip_key]
            if 'obj' not in clip:
                return False
            return clip['obj'].is_playing()
        except Exception:
            return False

    def _get_dhd_hw(self):
        try:
            dialer = getattr(self.stargate, "dialer", None)
            hw = getattr(dialer, "hardware", None) if dialer else None
            dhd_type = getattr(dialer, "type", None) if dialer else None
            if hw is not None and dhd_type == "DHDv2":
                return hw
        except Exception:
            pass
        return None

    def _dhd_center_on_red(self):
        hw = self._get_dhd_hw()
        if hw is None:
            return False

        try:
            try:
                target_brightness = int(255 * 0.60)
                if hasattr(hw, "set_brightness_center"):
                    hw.set_brightness_center(target_brightness)
            except Exception:
                pass

            if hasattr(hw, "set_color_center"):
                hw.set_color_center((255, 0, 0))
            elif hasattr(hw, "set_pixel"):
                hw.set_pixel(0, 255, 0, 0)

            if hasattr(hw, "set_center_on"):
                hw.set_center_on()
            elif hasattr(hw, "center_on"):
                hw.center_on()

            if hasattr(hw, "latch"):
                hw.latch()

            return True
        except Exception as exc:
            self.log.log(f"Alarm DHD center ON failed: {exc}")
            return False

    def _dhd_center_off(self):
        hw = self._get_dhd_hw()
        if hw is None:
            return False

        try:
            if hasattr(hw, "clear_pixel"):
                hw.clear_pixel(0)
            elif hasattr(hw, "set_pixel"):
                hw.set_pixel(0, 0, 0, 0)
            elif hasattr(hw, "set_center_off"):
                hw.set_center_off()
            elif hasattr(hw, "center_off"):
                hw.center_off()

            if hasattr(hw, "latch"):
                hw.latch()

            return True
        except Exception as exc:
            self.log.log(f"Alarm DHD center OFF failed: {exc}")
            return False

    def _start_center_blink(self):
        self._stop_center_blink(wait=False)

        self._center_blink_stop.clear()

        def blink_loop():
            state_on = False
            try:
                while not self._center_blink_stop.is_set():
                    if state_on:
                        self._dhd_center_off()
                    else:
                        self._dhd_center_on_red()

                    state_on = not state_on

                    if self._center_blink_stop.wait(0.38):
                        break
            except Exception as exc:
                self.log.log(f"Alarm DHD blink loop failed: {exc}")
            finally:
                try:
                    self._dhd_center_off()
                except Exception:
                    pass

        self._center_blink_thread = threading.Thread(target=blink_loop, daemon=True)
        self._center_blink_thread.start()

    def _stop_center_blink(self, wait=True):
        self._center_blink_stop.set()

        thread = self._center_blink_thread
        if wait and thread and thread.is_alive():
            try:
                thread.join(timeout=1.0)
            except Exception:
                pass

        self._center_blink_thread = None

        try:
            self._dhd_center_off()
        except Exception:
            pass

    def _start_alarm_now(self, filename, reason):
        with self._lock:
            self._ensure_clip_loaded(filename)
            self._active_file = filename
            self._original_volume = self.audio.volume
            self._active = True
            self._stopping = False
            self._last_ramp_time = time.time()

            initial_volume = max(self.audio.volume, self.start_volume)
            if self.audio.volume != initial_volume:
                self.audio.set_volume(initial_volume)

            self.visual.start()
            self._start_center_blink()
            self.audio.sound_start(self.clip_key)
            self.log.log(f"Alarm started ({reason}) with file: {filename}")

    def test_alarm(self, filename=None):
        if not filename:
            filename = self.read_config().get("audio_file")

        if not filename:
            return {"success": False, "message": "No WAV file selected"}

        try:
            self._start_alarm_now(filename, "manual test")
            return {"success": True, "message": f"Alarm test started: {filename}"}
        except Exception as exc:
            self.log.log(f"Alarm test failed: {exc}")
            return {"success": False, "message": str(exc)}

    def stop_alarm(self):
        with self._lock:
            # 🔥 RESET ALARMU
            cleared = {
                "enabled": False,
                "hour": None,
                "minute": None,
                "meridiem": None,
                "audio_file": None
            }

            try:
                self.write_config(cleared)
            except Exception as exc:
                self.log.log(f"Alarm clear config failed: {exc}")

            if not self._active and not self._stopping:
                return {"success": True, "message": "Alarm stopped and cleared"}

            if self._stopping:
                return {"success": True, "message": "Alarm stop already in progress"}

            self._stopping = True

        threading.Thread(target=self._fade_out_and_stop, daemon=True).start()
        return {"success": True, "message": "Alarm stop requested and cleared"}

    def _fade_out_and_stop(self):
        try:
            start_volume = max(0, min(100, int(self.audio.volume)))
            for step in range(self.fade_steps):
                remaining = self.fade_steps - step - 1
                new_volume = int(start_volume * (remaining / max(self.fade_steps - 1, 1)))
                self.audio.set_volume(max(0, min(100, new_volume)))
                time.sleep(self.fade_delay)

            try:
                self.audio.sound_stop(self.clip_key)
            except Exception:
                pass

            self.visual.stop()
            self._stop_center_blink(wait=True)
            time.sleep(0.25)

            restore_volume = max(0, min(100, int(self._original_volume)))
            self.audio.set_volume(restore_volume)
            self.log.log("Alarm stopped")
        except Exception as exc:
            self.log.log(f"Alarm fade/stop failed: {exc}")
        finally:
            with self._lock:
                self._active = False
                self._stopping = False
                self._active_file = None

    def tick(self):
        try:
            with self._lock:
                if self._active:
                    if self._active_file and not self._clip_is_playing() and not self._stopping:
                        self.audio.sound_start(self.clip_key)

                    now_ts = time.time()
                    if (not self._stopping) and now_ts - self._last_ramp_time >= self.ramp_interval_seconds:
                        new_volume = min(self.max_volume, self.audio.volume + self.ramp_step)
                        if new_volume != self.audio.volume:
                            self.audio.set_volume(new_volume)
                        self._last_ramp_time = now_ts
                    return

            data = self.read_config()
            if not data.get("enabled", False):
                return

            hour = data.get("hour")
            minute = data.get("minute")
            meridiem = data.get("meridiem")
            audio_file = data.get("audio_file")
            if hour is None or minute is None or meridiem not in ("AM", "PM") or not audio_file:
                return

            now = time.localtime()
            hour_12 = now.tm_hour % 12
            if hour_12 == 0:
                hour_12 = 12
            now_meridiem = "AM" if now.tm_hour < 12 else "PM"

            trigger_key = f"{now.tm_year:04d}-{now.tm_mon:02d}-{now.tm_mday:02d}-{int(hour):02d}:{int(minute):02d}-{meridiem}"
            if hour_12 == int(hour) and now.tm_min == int(minute) and now_meridiem == meridiem:
                if self._last_trigger_key != trigger_key:
                    self._last_trigger_key = trigger_key
                    self._start_alarm_now(audio_file, "scheduled trigger")
        except Exception as exc:
            self.log.log(f"Alarm tick failed: {exc}")
