import math
import threading
import time


class AlarmClockWormhole:
    def __init__(self, stargate):
        self.stargate = stargate
        self.log = stargate.log
        self._lock = threading.RLock()
        self._active = False
        self._thread = None

    def is_active(self):
        with self._lock:
            return self._active

    def start(self):
        with self._lock:
            if self._active:
                return
            self._active = True
            self._thread = threading.Thread(target=self._run, daemon=True)
            self._thread.start()
        self.log.log("Alarm wormhole visual started")

    def stop(self):
        with self._lock:
            self._active = False
        self.log.log("Alarm wormhole visual stop requested")

    def _build_pattern(self, red_level):
        tot_leds = self.stargate.wh_manager.tot_leds
        pattern = []
        for index in range(tot_leds):
            if index % 5 == 0:
                pattern.append((red_level, red_level // 6, 0))
            elif index % 2 == 0:
                pattern.append((max(red_level - 35, 0), 0, 0))
            else:
                pattern.append((max(red_level - 15, 0), 0, 0))
        return pattern

    def _run(self):
        phase = 0.0
        try:
            while self.is_active():
                # Do not fight with the real wormhole renderer if a real wormhole is active.
                if getattr(self.stargate, 'wormhole_active', False):
                    time.sleep(0.1)
                    continue

                red_level = int(35 + ((math.sin(phase) + 1.0) / 2.0) * 220)
                pattern = self._build_pattern(red_level)
                self.stargate.wh_manager.animation_manager.set_wormhole_pattern(pattern)
                time.sleep(0.05)
                phase += 0.18
        except Exception as exc:
            self.log.log(f"Alarm wormhole visual failed: {exc}")
        finally:
            try:
                if not getattr(self.stargate, 'wormhole_active', False):
                    self.stargate.wh_manager.animation_manager.clear_wormhole()
            except Exception as exc:
                self.log.log(f"Alarm wormhole clear failed: {exc}")
