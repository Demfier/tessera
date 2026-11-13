// A small working model of Tessera on two displays. Geometry is in percent of the stage.
(() => {
  "use strict";

  const stage = document.getElementById("stage");
  const pointer = document.getElementById("pointer");
  const caption = document.getElementById("caption");
  const buttons = new Map([...document.querySelectorAll(".controls button")].map((b) => [b.dataset.action, b]));
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const MOVE_MS = reducedMotion ? 0 : 440;
  const MENU_BAR = 0.07; // share of a display's height
  const GAP = 0.45;      // inset around each window, in stage percent

  // The laptop on the left, a larger external display to its right; two Spaces each.
  const displays = [
    { x: 3, y: 20, w: 37, h: 64, space: 0 },
    { x: 45, y: 4, w: 52, h: 80, space: 0 },
  ];
  const windows = [
    { color: "aqua", display: 0, space: 0, rect: [0.05, 0.6, 0.07, 0.72] },
    { color: "rose", display: 0, space: 0, rect: [0.38, 0.95, 0.3, 0.95] },
    { color: "amber", display: 1, space: 0, rect: [0.14, 0.74, 0.1, 0.86] },
    { color: "rose", display: 0, space: 1, rect: [0.08, 0.92, 0.08, 0.92] },
    { color: "aqua", display: 1, space: 1, rect: [0.1, 0.9, 0.1, 0.9] },
  ];
  let focused = windows[2];
  let pointerDisplay = 1;
  let pointerAt = null; // explicit pointer position; null = middle of the focused window
  let busy = false;
  let topZ = windows.length;

  windows.forEach((w, i) => {
    w.full = false;
    w.z = i + 1;
    w.el = document.createElement("div");
    w.el.className = `win ${w.color}`;
    stage.insertBefore(w.el, pointer);
  });
  stage.querySelectorAll(".display").forEach((el, i) => place(el, displays[i]));
  stage.querySelectorAll(".spaces").forEach((el, i) => {
    const d = displays[i];
    Object.assign(el.style, { left: `${d.x}%`, width: `${d.w}%`, top: `${d.y + d.h + 4}%` });
    el.innerHTML = "<span></span><span></span>";
  });

  function place(el, r) {
    Object.assign(el.style, { left: `${r.x}%`, top: `${r.y}%`, width: `${r.w}%`, height: `${r.h}%` });
  }

  function frameOf(w) {
    const d = displays[w.display];
    if (w.full) return { x: d.x, y: d.y, w: d.w, h: d.h };
    const top = d.y + d.h * MENU_BAR, height = d.h * (1 - MENU_BAR);
    const [x0, x1, y0, y1] = w.rect;
    return {
      x: d.x + d.w * x0 + GAP, y: top + height * y0 + GAP,
      w: d.w * (x1 - x0) - 2 * GAP, h: height * (y1 - y0) - 2 * GAP,
    };
  }

  const visible = (w) => displays[w.display].space === w.space;
  const frontmostOn = (display) =>
    windows.filter((w) => w.display === display && visible(w)).sort((a, b) => b.z - a.z)[0] ?? null;

  function render() {
    for (const w of windows) {
      place(w.el, frameOf(w));
      w.el.style.zIndex = w.z;
      w.el.style.visibility = visible(w) ? "visible" : "hidden";
      w.el.classList.toggle("full", w.full);
      w.el.classList.toggle("focused", w === focused);
    }
    stage.querySelectorAll(".spaces").forEach((el, i) =>
      el.querySelectorAll("span").forEach((s, n) => s.classList.toggle("on", n === displays[i].space)));
    const at = pointerAt ?? (focused ? centre(frameOf(focused)) : centre(displays[pointerDisplay]));
    pointer.style.left = `${at.x}%`;
    pointer.style.top = `${at.y}%`;
  }
  const centre = (r) => ({ x: r.x + r.w / 2, y: r.y + r.h / 2 });
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  function focus(w) {
    focused = w;
    if (w) w.z = ++topZ;
  }

  /** Apply a layout; a full-screen window leaves full screen first, as in the app. */
  async function snap(rect) {
    if (focused.full) {
      focused.full = false;
      render();
      await wait(MOVE_MS);
    }
    focused.rect = rect;
    render();
  }

  const actions = {
    leftHalf: { text: "Window moved to the left half.", run: () => snap([0, 0.5, 0, 1]) },
    rightHalf: { text: "Window moved to the right half.", run: () => snap([0.5, 1, 0, 1]) },
    maximize: { text: "Window maximized.", run: () => snap([0, 1, 0, 1]) },
    fullscreen: {
      text: () => (focused.full ? "Window entered full screen." : "Window left full screen."),
      run: () => { focused.full = !focused.full; render(); },
    },
    moveDisplay: {
      text: (wasFull) => wasFull
        ? "Window left full screen, moved to the other display, and entered full screen again."
        : "Window moved to the other display with the same layout.",
      run: async () => {
        const target = 1 - focused.display;
        const wasFull = focused.full;
        if (wasFull) { focused.full = false; render(); await wait(MOVE_MS + 60); }
        focused.display = target;
        focused.space = displays[target].space;
        pointerAt = null;
        render();
        if (wasFull) { await wait(MOVE_MS + 60); focused.full = true; render(); }
        return wasFull;
      },
    },
    focusDisplay: {
      text: (found) => found ? "Focus and pointer moved to the front window on the other display." : "Pointer moved to the other display. It has no windows to focus.",
      needsWindow: false,
      run: () => {
        const target = 1 - (focused ? focused.display : pointerDisplay);
        const w = frontmostOn(target);
        pointerDisplay = target;
        pointerAt = null;
        if (w) focus(w); else { focused = null; pointerAt = centre(displays[target]); }
        render();
        return Boolean(w);
      },
    },
    nextSpace: {
      text: "Switched to the next Space on the display under the pointer, without animation.",
      needsWindow: false,
      run: async () => {
        const d = displays[pointerDisplay];
        d.space = (d.space + 1) % 2;
        // macOS focuses a window on the Space you arrive at.
        if (!focused || !visible(focused) || focused.display !== pointerDisplay) focus(frontmostOn(pointerDisplay));
        if (focused) pointerAt = null;
        stage.classList.add("instant");
        render();
        await wait(30);
        stage.classList.remove("instant");
      },
    },
  };

  async function perform(name) {
    const action = actions[name];
    if (!action || busy) return;
    if (action.needsWindow !== false && !focused) {
      caption.textContent = "No window is focused. Use Focus other display first.";
      return;
    }
    const button = buttons.get(name);
    button?.classList.add("pressed");
    setTimeout(() => button?.classList.remove("pressed"), 220);
    busy = true;
    try {
      const result = await action.run();
      // Captions are worded after the fact, from the action's result or the new state.
      const text = typeof action.text === "function" ? action.text(result) : action.text;
      caption.textContent = `${button.querySelector(".keys").textContent || "Green button"}: ${text}`;
    } finally {
      busy = false;
    }
  }

  // Plays the shortcuts once when the model first comes into view. Any click or key press stops it.
  let autoplay = !reducedMotion;
  const script = ["leftHalf", "moveDisplay", "fullscreen", "moveDisplay", "focusDisplay", "nextSpace", "nextSpace"];
  async function runScript() {
    await wait(700);
    for (const step of script) {
      if (!autoplay) return;
      await perform(step);
      await wait(1500);
    }
    if (autoplay) caption.textContent = "Click a shortcut, or press it on your keyboard.";
  }
  const stopAutoplay = () => { autoplay = false; };

  buttons.forEach((button, name) => button.addEventListener("click", () => { stopAutoplay(); perform(name); }));

  // The real shortcuts work too, unless a window manager on the Mac handles them first.
  document.addEventListener("keydown", (e) => {
    if (!e.ctrlKey || !e.altKey) return;
    let name = null;
    const arrow = e.key === "ArrowLeft" || e.key === "ArrowRight";
    if (arrow && e.shiftKey && e.metaKey) name = "focusDisplay";
    else if (arrow && e.metaKey) name = "moveDisplay";
    else if (arrow && e.shiftKey) name = "nextSpace";
    else if (e.key === "ArrowLeft") name = "leftHalf";
    else if (e.key === "ArrowRight") name = "rightHalf";
    else if (e.key === "Enter") name = "maximize";
    if (!name) return;
    e.preventDefault();
    stopAutoplay();
    perform(name);
  });

  stage.classList.add("instant");
  render();
  requestAnimationFrame(() => stage.classList.remove("instant"));

  if (autoplay && "IntersectionObserver" in window) {
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        observer.disconnect();
        runScript();
      }
    }, { threshold: 0.6 });
    observer.observe(stage);
  }

  // Copy the install command.
  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      const text = document.getElementById(button.dataset.copy).textContent;
      try {
        await navigator.clipboard.writeText(text);
        button.textContent = "Copied";
      } catch {
        const range = document.createRange();
        range.selectNodeContents(document.getElementById(button.dataset.copy));
        getSelection().removeAllRanges();
        getSelection().addRange(range);
        button.textContent = "Press ⌘C";
      }
      setTimeout(() => { button.textContent = "Copy"; }, 1800);
    });
  });

  // Show the repository's star count next to the Star button. The button works without it.
  const starCount = document.getElementById("star-count");
  fetch("https://api.github.com/repos/Demfier/tessera")
    .then((response) => (response.ok ? response.json() : Promise.reject(response.status)))
    .then(({ stargazers_count: stars }) => {
      if (typeof stars !== "number" || stars === 0) return;
      starCount.textContent = stars.toLocaleString("en");
      starCount.hidden = false;
      starCount.closest("a").setAttribute("aria-label", `Star on GitHub, ${stars} ${stars === 1 ? "star" : "stars"}`);
    })
    .catch(() => {});
})();
