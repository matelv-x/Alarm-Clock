(function () {
  "use strict";

  const svgNS = "http://www.w3.org/2000/svg";
  const VIEWBOX_SIZE = 1000;
  const CX = VIEWBOX_SIZE / 2;
  const CY = VIEWBOX_SIZE / 2;

  const ENDPOINTS = {
    alarmConfigUrl: ["/stargate/get/alarm_clock", "stargate/get/alarm_clock", "/get/alarm_clock", "get/alarm_clock"],
    alarmUpdateUrl: ["/stargate/update/alarm_clock", "stargate/update/alarm_clock", "/update/alarm_clock", "update/alarm_clock"],
    alarmAudioFilesUrl: ["/stargate/get/alarm_audio_files", "stargate/get/alarm_audio_files", "/get/alarm_audio_files", "get/alarm_audio_files"],
    testAlarmUrl: ["/stargate/do/test_alarm_clock", "stargate/do/test_alarm_clock", "/do/test_alarm_clock", "do/test_alarm_clock"],
    stopAlarmUrl: ["/stargate/do/stop_alarm_clock", "stargate/do/stop_alarm_clock", "/do/stop_alarm_clock", "do/stop_alarm_clock"]
  };

  const CONFIG = {
    hours: 12,
    minutes: 60,
    minuteLabelEvery: 5,
    hourGapDeg: 1.8,
    minuteGapDeg: 0.55
  };

  const GEOMETRY = {
    bodyRadius: 0.36,
    ring1Radius: 0.332,
    ring2Radius: 0.287,
    ring3Radius: 0.210,
    minuteOuter: 0.323,
    minuteInner: 0.248,
    minuteLabelRadius: 0.286,
    hourOuter: 0.244,
    hourInner: 0.150,
    hourLabelRadius: 0.196,
    centerOuter: 0.112,
    centerInner: 0.092,
    centerButton: 0.072,
    orbitDotRadius: 0.341
  };

  const state = {
    selectedHour: null,
    selectedMinute: null,
    selectedMeridiem: null,
    selectedAudioFile: null,
    availableAudioFiles: [],
    currentHour: null,
    currentMinute: null,
    currentSecond: null,
    currentMeridiem: null,
    centerBlinkInterval: null,
    centerButtonCircle: null,
    testMode: false,
    lastKnownActive: null,
    audioPickerOverlay: null,
    audioHoverCloseTimer: null
  };

  const els = {
    clockBase: document.getElementById("clockBase"),
    minuteRing: document.getElementById("minuteRing"),
    hourRing: document.getElementById("hourRing"),
    centerGroup: document.getElementById("centerGroup"),
    alarmTime: document.getElementById("alarmTime"),
    statusLine: document.getElementById("statusLine"),
    amBtn: document.getElementById("amBtn"),
    pmBtn: document.getElementById("pmBtn"),
    confirmBtn: document.getElementById("confirmBtn"),
    testBtn: document.getElementById("testBtn"),
    audioSelectBtn: document.getElementById("audioSelectBtn"),
    audioDisplay: document.getElementById("audioDisplay")
  };

  function updateStatus(message) {
    els.statusLine.textContent = message;
  }

  function updateDisplay() {
    const hh = state.selectedHour === null ? "--" : String(state.selectedHour).padStart(2, "0");
    const mm = state.selectedMinute === null ? "--" : String(state.selectedMinute).padStart(2, "0");
    const ap = state.selectedMeridiem || "--";
    els.alarmTime.textContent = `${hh}:${mm} ${ap}`;
    els.audioDisplay.textContent = state.selectedAudioFile || "No file selected";
  }

  function r(value) {
    return VIEWBOX_SIZE * value;
  }

  function polar(cx, cy, radius, angleDeg) {
    const rad = (angleDeg - 90) * Math.PI / 180;
    return {
      x: cx + radius * Math.cos(rad),
      y: cy + radius * Math.sin(rad)
    };
  }

  function ringSegmentPath(cx, cy, innerR, outerR, startDeg, endDeg) {
    const p1 = polar(cx, cy, outerR, startDeg);
    const p2 = polar(cx, cy, outerR, endDeg);
    const p3 = polar(cx, cy, innerR, endDeg);
    const p4 = polar(cx, cy, innerR, startDeg);
    const largeArc = (endDeg - startDeg) > 180 ? 1 : 0;

    return [
      `M ${p1.x} ${p1.y}`,
      `A ${outerR} ${outerR} 0 ${largeArc} 1 ${p2.x} ${p2.y}`,
      `L ${p3.x} ${p3.y}`,
      `A ${innerR} ${innerR} 0 ${largeArc} 0 ${p4.x} ${p4.y}`,
      "Z"
    ].join(" ");
  }

  function createSvg(tag, attrs = {}) {
    const el = document.createElementNS(svgNS, tag);
    Object.entries(attrs).forEach(([key, value]) => el.setAttribute(key, value));
    return el;
  }

  async function requestJson(endpointKey, options = {}) {
    let lastError = null;

    for (const url of ENDPOINTS[endpointKey]) {
      try {
        const response = await fetch(url, options);
        if (!response.ok) {
          throw new Error(`HTTP ${response.status} for ${url}`);
        }
        return await response.json().catch(() => ({}));
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError || new Error(`Request failed for ${endpointKey}`);
  }

  function buildBase() {
    els.clockBase.innerHTML = "";

    els.clockBase.appendChild(createSvg("circle", {
      cx: CX,
      cy: CY,
      r: r(GEOMETRY.bodyRadius),
      fill: "url(#bodyFill)"
    }));

    els.clockBase.appendChild(createSvg("circle", {
      cx: CX,
      cy: CY,
      r: r(GEOMETRY.bodyRadius),
      fill: "url(#bodyHighlight)",
      opacity: "0.45"
    }));

    els.clockBase.appendChild(createSvg("circle", {
      cx: CX,
      cy: CY,
      r: r(GEOMETRY.bodyRadius),
      fill: "#ffffff",
      filter: "url(#metalNoise)",
      opacity: "0.95"
    }));

    [GEOMETRY.bodyRadius, GEOMETRY.ring1Radius, GEOMETRY.ring2Radius, GEOMETRY.ring3Radius].forEach((radius) => {
      els.clockBase.appendChild(createSvg("circle", {
        cx: CX,
        cy: CY,
        r: r(radius),
        fill: "none",
        stroke: "rgba(255,255,255,0.05)",
        "stroke-width": radius === GEOMETRY.bodyRadius ? 1.8 : 2
      }));
    });
  }

  function makeSegment(pathD, labelText, labelX, labelY, className, datasetName, datasetValue, clickHandler, fontSize) {
    const g = createSvg("g", { class: `seg ${className}` });
    g.dataset[datasetName] = datasetValue;

    g.appendChild(createSvg("path", {
      class: "seg-shape",
      d: pathD,
      filter: "url(#innerShadow)"
    }));

    if (labelText !== null) {
      const text = createSvg("text", {
        class: "label",
        x: labelX,
        y: labelY,
        "font-size": fontSize
      });
      text.textContent = labelText;
      g.appendChild(text);
    }

    g.addEventListener("click", clickHandler);
    return g;
  }

  function buildMinuteRing() {
    els.minuteRing.innerHTML = "";
    const step = 360 / CONFIG.minutes;

    for (let i = 0; i < CONFIG.minutes; i += 1) {
      const start = -step / 2 + i * step + CONFIG.minuteGapDeg;
      const end = -step / 2 + (i + 1) * step - CONFIG.minuteGapDeg;

      const d = ringSegmentPath(
        CX,
        CY,
        r(GEOMETRY.minuteInner),
        r(GEOMETRY.minuteOuter),
        start,
        end
      );

      const mid = (start + end) / 2;
      const tp = polar(CX, CY, r(GEOMETRY.minuteLabelRadius), mid);

      const label = i % CONFIG.minuteLabelEvery === 0 ? String(i).padStart(2, "0") : null;
      const className = i % CONFIG.minuteLabelEvery === 0 ? "minute-major" : "minute-minor";

      const seg = makeSegment(
        d,
        label,
        tp.x,
        tp.y + 0.5,
        className,
        "minute",
        i,
        () => {
          document.querySelectorAll("[data-minute]").forEach((el) => el.classList.remove("active"));
          seg.classList.add("active");
          state.selectedMinute = i;
          updateDisplay();
          applyClockHighlights();
          updateStatus(`Minute selected: ${String(i).padStart(2, "0")}`);
        },
        VIEWBOX_SIZE * 0.011
      );

      els.minuteRing.appendChild(seg);
    }
  }

  function buildHourRing() {
    els.hourRing.innerHTML = "";
    const step = 360 / CONFIG.hours;

    for (let i = 0; i < CONFIG.hours; i += 1) {
      const start = -step / 2 + i * step + CONFIG.hourGapDeg;
      const end = -step / 2 + (i + 1) * step - CONFIG.hourGapDeg;
      const hour = i === 0 ? 12 : i;

      const d = ringSegmentPath(
        CX,
        CY,
        r(GEOMETRY.hourInner),
        r(GEOMETRY.hourOuter),
        start,
        end
      );

      const mid = (start + end) / 2;
      const tp = polar(CX, CY, r(GEOMETRY.hourLabelRadius), mid);

      const seg = makeSegment(
        d,
        String(hour),
        tp.x,
        tp.y + 1,
        "hour-seg",
        "hour",
        hour,
        () => {
          document.querySelectorAll("[data-hour]").forEach((el) => el.classList.remove("active"));
          seg.classList.add("active");
          state.selectedHour = hour;
          updateDisplay();
          applyClockHighlights();
          updateStatus(`Hour selected: ${String(hour).padStart(2, "0")}`);
        },
        VIEWBOX_SIZE * 0.021
      );

      els.hourRing.appendChild(seg);
    }
  }

  function startCenterBlink() {
    stopCenterBlink();

    if (!state.centerButtonCircle) {
      return;
    }

    let blinkOn = false;

    state.centerBlinkInterval = setInterval(() => {
      blinkOn = !blinkOn;
      if (blinkOn) {
        state.centerButtonCircle.setAttribute("fill", "#ff2a2a");
        state.centerButtonCircle.setAttribute("opacity", "1");
      } else {
        state.centerButtonCircle.setAttribute("fill", "url(#centerFill)");
        state.centerButtonCircle.setAttribute("opacity", "0.82");
      }
    }, 380);
  }

  function stopCenterBlink() {
    if (state.centerBlinkInterval) {
      clearInterval(state.centerBlinkInterval);
      state.centerBlinkInterval = null;
    }

    if (state.centerButtonCircle) {
      state.centerButtonCircle.setAttribute("fill", "url(#centerFill)");
      state.centerButtonCircle.setAttribute("opacity", "1");
    }
  }

  function buildCenter() {
    els.centerGroup.innerHTML = "";

    els.centerGroup.appendChild(createSvg("circle", {
      cx: CX,
      cy: CY,
      r: r(GEOMETRY.centerOuter),
      fill: "#2a2f36",
      stroke: "rgba(255,255,255,0.08)",
      "stroke-width": 2
    }));

    els.centerGroup.appendChild(createSvg("circle", {
      cx: CX,
      cy: CY,
      r: r(GEOMETRY.centerOuter),
      fill: "#ffffff",
      filter: "url(#metalNoise)",
      opacity: "0.28"
    }));

    els.centerGroup.appendChild(createSvg("circle", {
      cx: CX,
      cy: CY,
      r: r(GEOMETRY.centerInner),
      fill: "#181d22",
      stroke: "rgba(255,255,255,0.06)",
      "stroke-width": 2
    }));

    const buttonGroup = createSvg("g", { class: "center-button", id: "centerButton" });
    const buttonCircle = createSvg("circle", {
      cx: CX,
      cy: CY,
      r: r(GEOMETRY.centerButton),
      fill: "url(#centerFill)",
      stroke: "rgba(255,255,255,0.14)",
      "stroke-width": 3,
      opacity: "1"
    });

    state.centerButtonCircle = buttonCircle;

    buttonGroup.appendChild(buttonCircle);
    buttonGroup.addEventListener("click", stopAlarm);
    els.centerGroup.appendChild(buttonGroup);
  }

  function renderClockFace() {
    buildBase();
    buildMinuteRing();
    buildHourRing();
    buildCenter();
    updateDisplay();
    applyClockHighlights();
  }

  function setMeridiem(value) {
    state.selectedMeridiem = value;
    els.amBtn.classList.toggle("active", value === "AM");
    els.pmBtn.classList.toggle("active", value === "PM");
    updateDisplay();
    updateStatus(`${value} selected`);
  }

  function getAlarmPayload(enabledValue = true) {
    return {
      enabled: enabledValue,
      hour: state.selectedHour,
      minute: state.selectedMinute,
      meridiem: state.selectedMeridiem,
      audio_file: state.selectedAudioFile
    };
  }

  function clearTimeHighlights() {
    document.querySelectorAll("[data-hour]").forEach((el) => {
      el.classList.remove("current-time", "alarm-time");
    });

    document.querySelectorAll("[data-minute]").forEach((el) => {
      el.classList.remove("current-time", "alarm-time");
    });

    const dot = document.getElementById("minuteOrbitDot");
    if (dot) {
      dot.remove();
    }
  }

  function drawMinuteOrbitDot() {
    const existing = document.getElementById("minuteOrbitDot");
    if (existing) {
      existing.remove();
    }

    if (state.currentSecond === null) {
      return;
    }

    const step = 360 / 60;
    const angle = state.currentSecond * step;
    const point = polar(CX, CY, r(GEOMETRY.orbitDotRadius), angle);

    const dot = createSvg("circle", {
      id: "minuteOrbitDot",
      cx: point.x,
      cy: point.y,
      r: VIEWBOX_SIZE * 0.008,
      fill: "#ffd86a",
      stroke: "rgba(55, 32, 0, 0.82)",
      "stroke-width": 1.4
    });

    dot.style.filter =
      "drop-shadow(0 0 5px rgba(255,216,106,0.50)) drop-shadow(0 0 14px rgba(255,170,60,0.26))";
    els.minuteRing.appendChild(dot);
  }

  function applyClockHighlights() {
    clearTimeHighlights();

    if (state.selectedHour !== null) {
      const alarmHourEl = document.querySelector(`[data-hour="${state.selectedHour}"]`);
      if (alarmHourEl) {
        alarmHourEl.classList.add("alarm-time");
      }
    }

    if (state.selectedMinute !== null) {
      const alarmMinuteEl = document.querySelector(`[data-minute="${state.selectedMinute}"]`);
      if (alarmMinuteEl) {
        alarmMinuteEl.classList.add("alarm-time");
      }
    }

    if (state.currentHour !== null) {
      const currentHourEl = document.querySelector(`[data-hour="${state.currentHour}"]`);
      if (currentHourEl) {
        currentHourEl.classList.add("current-time");
      }
    }

    if (state.currentMinute !== null) {
      const currentMinuteEl = document.querySelector(`[data-minute="${state.currentMinute}"]`);
      if (currentMinuteEl) {
        currentMinuteEl.classList.add("current-time");
      }
    }

    drawMinuteOrbitDot();
  }

  function updateLiveClockState() {
    const now = new Date();

    let hour = now.getHours();
    const minute = now.getMinutes();
    const second = now.getSeconds();

    const meridiem = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour === 0) {
      hour = 12;
    }

    state.currentHour = hour;
    state.currentMinute = minute;
    state.currentSecond = second;
    state.currentMeridiem = meridiem;

    applyClockHighlights();
  }

  function startLiveClock() {
    updateLiveClockState();
    setInterval(updateLiveClockState, 1000);
  }

  function resetSegmentVisualState() {
    document.querySelectorAll(".seg").forEach((seg) => {
      seg.classList.remove("active", "alarm-time");
    });

    document.querySelectorAll(".seg .seg-shape").forEach((shape) => {
      shape.style.opacity = "";
      shape.style.filter = "";
    });

    document.querySelectorAll(".seg .label").forEach((label) => {
      label.style.opacity = "";
      label.style.filter = "";
    });
  }

  function clearAlarmUi() {
    state.testMode = false;
    stopCenterBlink();

    state.selectedHour = null;
    state.selectedMinute = null;
    state.selectedMeridiem = null;
    state.selectedAudioFile = null;

    document.querySelectorAll("[data-hour]").forEach((el) => {
      el.classList.remove("active", "alarm-time", "current-time");
    });

    document.querySelectorAll("[data-minute]").forEach((el) => {
      el.classList.remove("active", "alarm-time", "current-time");
    });

    els.amBtn.classList.remove("active");
    els.pmBtn.classList.remove("active");

    resetSegmentVisualState();
    updateDisplay();
    applyClockHighlights();
  }

  async function loadAudioFiles() {
    try {
      const data = await requestJson("alarmAudioFilesUrl", {
        method: "GET",
        headers: { "Accept": "application/json" }
      });

      state.availableAudioFiles = Array.isArray(data.files) ? data.files : [];

      if (!state.selectedAudioFile && state.availableAudioFiles.length > 0) {
        state.selectedAudioFile = state.availableAudioFiles[0];
      }

      updateDisplay();
      updateStatus(
        state.availableAudioFiles.length > 0
          ? `Loaded ${state.availableAudioFiles.length} WAV file(s)`
          : "No WAV files found in /home/pi/sg1_v4/soundfx/alarm"
      );
    } catch (error) {
      console.warn("[alarm_clock.js] loadAudioFiles failed:", error);
      updateStatus("Failed to load audio files");
    }
  }

  function closeAudioPicker() {
    if (state.audioPickerOverlay) {
      state.audioPickerOverlay.remove();
      state.audioPickerOverlay = null;
    }
  }

  function clearAudioHoverCloseTimer() {
    if (state.audioHoverCloseTimer) {
      clearTimeout(state.audioHoverCloseTimer);
      state.audioHoverCloseTimer = null;
    }
  }

  function delayedCloseAudioPicker() {
    clearAudioHoverCloseTimer();
    state.audioHoverCloseTimer = setTimeout(() => {
      closeAudioPicker();
    }, 220);
  }

  function openAudioPicker() {
    if (!state.availableAudioFiles || state.availableAudioFiles.length === 0) {
      updateStatus("No WAV files found in /home/pi/sg1_v4/soundfx/alarm");
      return;
    }

    closeAudioPicker();
    clearAudioHoverCloseTimer();

    const buttonRect = els.audioSelectBtn.getBoundingClientRect();

    const overlay = document.createElement("div");
    overlay.style.position = "fixed";
    overlay.style.left = `${buttonRect.left}px`;
    overlay.style.top = `${buttonRect.bottom + 6}px`;
    overlay.style.width = `${Math.max(buttonRect.width, 220)}px`;
    overlay.style.maxHeight = "280px";
    overlay.style.overflowY = "auto";
    overlay.style.background = "rgba(18,24,30,0.96)";
    overlay.style.border = "1px solid rgba(55,191,222,0.35)";
    overlay.style.borderRadius = "10px";
    overlay.style.padding = "8px";
    overlay.style.boxShadow = "0 0 24px rgba(0,0,0,0.45)";
    overlay.style.zIndex = "9999";

    overlay.addEventListener("mouseenter", clearAudioHoverCloseTimer);
    overlay.addEventListener("mouseleave", delayedCloseAudioPicker);

    state.availableAudioFiles.forEach((file) => {
      const item = document.createElement("button");
      item.type = "button";
      item.textContent = file;
      item.style.display = "block";
      item.style.width = "100%";
      item.style.textAlign = "left";
      item.style.padding = "10px 12px";
      item.style.marginBottom = "6px";
      item.style.borderRadius = "8px";
      item.style.border = file === state.selectedAudioFile
        ? "1px solid rgba(108,239,255,0.85)"
        : "1px solid rgba(55,191,222,0.28)";
      item.style.background = file === state.selectedAudioFile
        ? "rgba(52, 78, 105, 0.72)"
        : "rgba(36, 43, 50, 0.72)";
      item.style.color = "#eef3f7";
      item.style.cursor = "pointer";
      item.style.fontSize = "14px";

      const choose = () => {
        state.selectedAudioFile = file;
        updateDisplay();
        updateStatus(`Audio selected: ${state.selectedAudioFile}`);
        closeAudioPicker();
      };

      item.addEventListener("click", choose);
      item.addEventListener("touchend", (ev) => {
        ev.preventDefault();
        choose();
      }, { passive: false });

      overlay.appendChild(item);
    });

    document.body.appendChild(overlay);
    state.audioPickerOverlay = overlay;
  }

  async function loadAlarmSettings() {
    try {
      const data = await requestJson("alarmConfigUrl", {
        method: "GET",
        headers: { "Accept": "application/json" }
      });

      if (typeof data.hour === "number") {
        state.selectedHour = data.hour;
      }
      if (typeof data.minute === "number") {
        state.selectedMinute = data.minute;
      }
      if (typeof data.meridiem === "string") {
        state.selectedMeridiem = data.meridiem;
      }
      if (typeof data.audio_file === "string" && data.audio_file.trim() !== "") {
        state.selectedAudioFile = data.audio_file;
      }

      renderClockFace();

      if (state.selectedHour !== null) {
        const hourEl = document.querySelector(`[data-hour="${state.selectedHour}"]`);
        if (hourEl) {
          hourEl.classList.add("active");
        }
      }

      if (state.selectedMinute !== null) {
        const minuteEl = document.querySelector(`[data-minute="${state.selectedMinute}"]`);
        if (minuteEl) {
          minuteEl.classList.add("active");
        }
      }

      els.amBtn.classList.toggle("active", state.selectedMeridiem === "AM");
      els.pmBtn.classList.toggle("active", state.selectedMeridiem === "PM");

      updateDisplay();
      applyClockHighlights();

      const isActive = !!(data && data.active);
      state.lastKnownActive = isActive;

      if (isActive) {
        startCenterBlink();
      } else {
        stopCenterBlink();
      }

      updateStatus("Alarm settings loaded");
    } catch (error) {
      console.warn("[alarm_clock.js] loadAlarmSettings failed:", error);
      updateStatus("Failed to load alarm settings");
    }
  }

  async function syncAlarmActiveState() {
    try {
      const data = await requestJson("alarmConfigUrl", {
        method: "GET",
        headers: { "Accept": "application/json" }
      });

      const isActive = !!(data && data.active);

      if (isActive) {
        startCenterBlink();
      } else {
        stopCenterBlink();
      }

      if (state.lastKnownActive === true && isActive === false) {
        clearAlarmUi();
        updateStatus("Alarm stopped");
      }

      state.lastKnownActive = isActive;
    } catch (error) {
      console.warn("[alarm_clock.js] syncAlarmActiveState failed:", error);
    }
  }

  async function resolveAudioFileForTest() {
    if (state.selectedAudioFile) {
      return state.selectedAudioFile;
    }

    try {
      const config = await requestJson("alarmConfigUrl", {
        method: "GET",
        headers: { "Accept": "application/json" }
      });

      if (config && typeof config.audio_file === "string" && config.audio_file.trim() !== "") {
        state.selectedAudioFile = config.audio_file;
        updateDisplay();
        return config.audio_file;
      }
    } catch (error) {
      console.warn("[alarm_clock.js] resolveAudioFileForTest config failed:", error);
    }

    if (!state.availableAudioFiles || state.availableAudioFiles.length === 0) {
      try {
        await loadAudioFiles();
      } catch (error) {
        console.warn("[alarm_clock.js] resolveAudioFileForTest reload files failed:", error);
      }
    }

    if (state.availableAudioFiles && state.availableAudioFiles.length > 0) {
      state.selectedAudioFile = state.availableAudioFiles[0];
      updateDisplay();
      return state.selectedAudioFile;
    }

    return null;
  }

  async function confirmAlarm() {
    if (state.selectedHour === null || state.selectedMinute === null || !state.selectedMeridiem) {
      updateStatus("Select hour, minute, and AM/PM");
      return;
    }

    if (!state.selectedAudioFile) {
      updateStatus("Select WAV file");
      return;
    }

    try {
      await requestJson("alarmUpdateUrl", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(getAlarmPayload(true))
      });

      updateStatus(`${String(state.selectedHour).padStart(2, "0")}:${String(state.selectedMinute).padStart(2, "0")} ${state.selectedMeridiem} armed`);
      applyClockHighlights();
    } catch (error) {
      console.warn("[alarm_clock.js] confirmAlarm failed:", error);
      updateStatus("Failed to save alarm");
    }
  }

  async function toggleTestAlarm() {
    try {
      if (state.lastKnownActive === true || state.testMode) {
        await stopAlarm();
        return;
      }

      const audioFile = await resolveAudioFileForTest();

      if (!audioFile) {
        updateStatus("No WAV file available for test");
        return;
      }

      state.testMode = true;
      startCenterBlink();

      const result = await requestJson("testAlarmUrl", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ audio_file: audioFile })
      });

      state.lastKnownActive = true;
      updateStatus(result.message || "Alarm test started");
    } catch (error) {
      console.warn("[alarm_clock.js] toggleTestAlarm failed:", error);
      updateStatus("Alarm test failed");
    }
  }

  async function stopAlarm() {
    try {
      const result = await requestJson("stopAlarmUrl", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({})
      });

      clearAlarmUi();
      state.lastKnownActive = false;
      updateStatus(result.message || "Alarm stopped and cleared");
    } catch (error) {
      console.warn("[alarm_clock.js] stopAlarm failed:", error);
      updateStatus("Alarm stop failed");
    }
  }

  function pulseActiveSegments() {
    const active = document.querySelectorAll(".seg.active .seg-shape");
    active.forEach((el, index) => {
      const t = Date.now() / 520 + index;
      const glow = 0.78 + Math.sin(t) * 0.22;
      el.style.opacity = glow.toFixed(2);
    });

    document.querySelectorAll(".seg:not(.active) .seg-shape").forEach((el) => {
      if (el.style.opacity) {
        el.style.opacity = "";
      }
    });

    requestAnimationFrame(pulseActiveSegments);
  }

  function bindEventHandlers() {
    els.amBtn.addEventListener("click", () => setMeridiem("AM"));
    els.pmBtn.addEventListener("click", () => setMeridiem("PM"));
    els.confirmBtn.addEventListener("click", confirmAlarm);
    els.testBtn.addEventListener("click", toggleTestAlarm);

    els.audioSelectBtn.addEventListener("mouseenter", openAudioPicker);
    els.audioSelectBtn.addEventListener("mouseleave", delayedCloseAudioPicker);
    els.audioSelectBtn.addEventListener("click", openAudioPicker);

    els.audioDisplay.addEventListener("mouseenter", openAudioPicker);
    els.audioDisplay.addEventListener("mouseleave", delayedCloseAudioPicker);
    els.audioDisplay.addEventListener("click", openAudioPicker);
    els.audioDisplay.addEventListener("touchend", (ev) => {
      ev.preventDefault();
      openAudioPicker();
    }, { passive: false });

    els.audioDisplay.style.cursor = "pointer";
    els.audioSelectBtn.style.cursor = "pointer";
  }

  async function init() {
    bindEventHandlers();
    renderClockFace();
    pulseActiveSegments();
    startLiveClock();
    await loadAudioFiles();
    await loadAlarmSettings();
    await syncAlarmActiveState();
    setInterval(syncAlarmActiveState, 1000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();