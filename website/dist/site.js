// SPDX-License-Identifier: MIT
// Native scrolling drives everything. A spring smooths the story's progress so
// motion glides on any input device, without ever taking over the page's scroll.
(() => {
  window.__notchshotReady = true;
  const root = document.documentElement;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)");
  const $ = (selector, scope = document) => scope.querySelector(selector);
  const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];
  const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));
  const smooth = (value) => {
    const t = clamp(value);
    return t * t * (3 - 2 * t);
  };
  const range = (progress, start, end) => smooth((progress - start) / (end - start));
  const mix = (from, to, t) => from + (to - from) * t;
  const easeOut = (t) => 1 - Math.pow(1 - clamp(t), 3);
  const fixed = (value, digits = 3) => value.toFixed(digits);

  let motion = !reduced.matches;

  // ---------------------------------------------------------------- Aperture
  // The same six-blade geometry as the app's ApertureShape.
  const SHUTTER = {
    open: { opening: 0.72, turn: 0, inset: 0, dot: 0, press: 0, spark: 0, print: 0 },
    shut: { opening: 0, turn: 55, inset: 0.16, dot: 1, press: 1, spark: 1, print: 0 },
    half: { opening: 0.34, turn: 28, inset: 0.08, dot: 0.45, press: 0, spark: 0, print: 1 },
    reopening: { opening: 0.9, turn: -12, inset: -0.07, dot: 0, press: 0, spark: 0, print: 0 },
  };

  function aperturePaths(opening, turn) {
    const center = 16;
    const rim = 15;
    const hole = rim * (0.1 + 0.52 * clamp(opening));
    const start = ((turn - 90) * Math.PI) / 180;
    const vertices = Array.from({ length: 6 }, (_, index) => {
      const angle = start + (index * Math.PI) / 3;
      return [center + hole * Math.cos(angle), center + hole * Math.sin(angle)];
    });
    const point = ([x, y]) => `${fixed(x, 2)} ${fixed(y, 2)}`;
    const blades = `M1 16a15 15 0 1 0 30 0a15 15 0 1 0 -30 0ZM${vertices.map(point).join("L")}Z`;
    let seams = "";
    for (let index = 0; index < 6; index += 1) {
      const [ax, ay] = vertices[index];
      const [bx, by] = vertices[(index + 1) % 6];
      const length = Math.hypot(bx - ax, by - ay) || 1;
      const dx = (bx - ax) / length;
      const dy = (by - ay) / length;
      const ox = bx - center;
      const oy = by - center;
      const along = ox * dx + oy * dy;
      const reach = -along + Math.sqrt(Math.max(0, along * along - (ox * ox + oy * oy - rim * rim)));
      seams += `M${point([bx, by])}L${point([bx + dx * reach, by + dy * reach])}`;
    }
    return [blades, seams];
  }

  function brackets(inset) {
    const near = 3.4 + inset * 32;
    const far = 32 - near;
    const arm = (far - near) * 0.3;
    return [
      [near, near, 1, 1],
      [far, near, -1, 1],
      [near, far, 1, -1],
      [far, far, -1, -1],
    ]
      .map(([x, y, dx, dy]) => `M${fixed(x, 2)} ${fixed(y + dy * arm, 2)}L${fixed(x, 2)} ${fixed(y, 2)}L${fixed(x + dx * arm, 2)} ${fixed(y, 2)}`)
      .join("");
  }

  // ------------------------------------------------------------------- Chrome
  const header = $(".site-header");
  const progressBar = $(".scroll-progress i");
  let lastChromeY = window.scrollY;
  let storyPinned = false;

  function updateChrome() {
    const y = window.scrollY;
    const max = root.scrollHeight - window.innerHeight;
    progressBar.style.transform = `scaleX(${fixed(max > 0 ? clamp(y / max) : 0, 4)})`;
    header.classList.toggle("is-scrolled", y > 12);
    const delta = y - lastChromeY;
    const focused = header.contains(document.activeElement);
    if (!focused && (storyPinned || (delta > 4 && y > 420))) header.classList.add("is-hidden");
    else if (focused || delta < -4 || y < 420) header.classList.remove("is-hidden");
    lastChromeY = y;
  }

  // -------------------------------------------------------------------- Story
  const story = $(".story");
  const sticky = $(".story-sticky");
  const scene = $(".mac-scene");
  const sceneWrap = $(".scene-wrap");
  const appWindow = $(".app-window");
  const bladesPath = $(".aperture-blades");
  const seamsPath = $(".aperture-seams");
  const historyUi = $(".history-ui");
  const historyQuery = $(".history-query");
  const axLines = $$(".ax-lines li");
  const captions = $$(".caption");
  const railButtons = $$(".rail button");
  const chapters = [
    [0, 0.2],
    [0.2, 0.48],
    [0.48, 0.78],
    [0.78, 1],
  ];
  // Where each rail button lands: the key moment of its chapter.
  const chapterMoments = [0.13, 0.4, 0.74, 0.985];
  const shutterSegments = [
    [0.09, 0.12, "open", "shut"],
    [0.17, 0.27, "shut", "half"],
    [0.64, 0.71, "half", "reopening"],
    [0.74, 0.82, "reopening", "open"],
  ];
  let geometry = null;
  let current = 0;
  let activeChapter = -1;
  let lastAperture = "";
  let lastQuery = null;

  function measureStory() {
    if (!story) return;
    const width = scene.clientWidth;
    const height = scene.clientHeight;
    const shelfScale = Math.min(1, (width - 20) / 440, (height * 0.44) / 207);
    geometry = {
      width,
      height,
      portrait: width < height,
      shelfScale,
      x: appWindow.offsetLeft + appWindow.offsetWidth / 2,
      y: appWindow.offsetTop + appWindow.offsetHeight / 2,
      cardWidth: appWindow.offsetWidth,
      cardHeight: appWindow.offsetHeight,
      // The centre of the thumbnail inside the fully open shelf.
      targetX: width / 2 - (440 * shelfScale) / 2 + 70 * shelfScale,
      targetY: (36 + 28 + 25 + 15.5 + 28) * shelfScale,
      notchWidth: width < height ? 130 : 172,
      distance: Math.max(1, story.offsetHeight - sticky.offsetHeight),
    };
  }

  function shutterAt(progress) {
    let state = SHUTTER.open;
    for (const [start, end, from, to] of shutterSegments) {
      if (progress < start) break;
      const t = range(progress, start, end);
      state = {
        opening: mix(SHUTTER[from].opening, SHUTTER[to].opening, t),
        turn: mix(SHUTTER[from].turn, SHUTTER[to].turn, t),
      };
    }
    return state;
  }

  function setChapter(index) {
    if (index === activeChapter) return;
    activeChapter = index;
    captions.forEach((caption, i) => {
      caption.classList.toggle("is-active", i === index);
      caption.classList.toggle("is-past", i < index);
    });
    railButtons.forEach((button, i) => {
      if (i === index) button.setAttribute("aria-current", "step");
      else button.removeAttribute("aria-current");
    });
  }

  function renderStory(p, entry) {
    const g = geometry;
    const style = scene.style;
    const lift = easeOut(entry);
    sceneWrap.style.setProperty("--tilt", `${fixed(g.portrait ? 0 : mix(22, 0, lift), 2)}deg`);
    sceneWrap.style.setProperty("--lift", fixed(mix(g.portrait ? 0.96 : 0.88, 1, lift), 4));
    style.setProperty("--shelf-scale", g.shelfScale);

    // 01 · Capture: both Shift keys press, the aperture shuts, the window flashes.
    style.setProperty("--key-press", fixed(range(p, 0.065, 0.095) * (1 - range(p, 0.125, 0.15))));
    style.setProperty("--hint-opacity", fixed(1 - range(p, 0.15, 0.21)));
    style.setProperty("--flash-opacity", fixed(Math.max(0, 1 - Math.abs(p - 0.12) / 0.028) * 0.42));
    style.setProperty("--capture-opacity", fixed(range(p, 0.11, 0.14) * (1 - range(p, 0.52, 0.6))));
    const shutter = shutterAt(p);
    const apertureKey = `${fixed(shutter.opening)}|${fixed(shutter.turn, 1)}`;
    if (apertureKey !== lastAperture) {
      lastAperture = apertureKey;
      const [blades, seams] = aperturePaths(shutter.opening, shutter.turn);
      bladesPath.setAttribute("d", blades);
      seamsPath.setAttribute("d", seams);
    }

    // 02 · Context: the window becomes a card and its tree unfolds beside it.
    const peel = range(p, 0.16, 0.3);
    const flight = range(p, 0.5, 0.7);
    const previewScale = g.portrait ? 0.7 : 0.47;
    const previewX = g.portrait ? g.width * 0.5 : g.width * 0.315;
    const previewY = g.portrait ? g.height * 0.35 : g.height * 0.55;
    const finalScale = Math.min((94 * g.shelfScale) / g.cardWidth, (56 * g.shelfScale) / g.cardHeight);
    const scale = mix(mix(1, previewScale, peel), finalScale, flight);
    const arc = Math.sin(flight * Math.PI);
    const x = mix(mix(g.x, previewX, peel), g.targetX, flight) + arc * g.width * 0.06;
    const y = mix(mix(g.y, previewY, peel), g.targetY, flight) - arc * g.height * 0.05;
    appWindow.style.transform = `translate3d(${fixed(x - g.x, 2)}px, ${fixed(y - g.y, 2)}px, 0) rotate(${fixed(-arc * 4, 2)}deg) scale(${fixed(scale, 4)})`;
    style.setProperty("--source-shadow", fixed(1 - peel));
    const toHistory = range(p, 0.8, 0.85);
    style.setProperty("--window-opacity", fixed(1 - toHistory));

    const treeIn = range(p, 0.24, 0.33);
    const treeOut = range(p, 0.45, 0.51);
    style.setProperty("--ax-opacity", fixed(treeIn * (1 - treeOut)));
    style.setProperty("--ax-x", `${fixed(mix(-g.width * 0.03, 0, treeIn) - treeOut * g.width * 0.05, 1)}px`);
    style.setProperty("--ax-scale", fixed(1 - 0.06 * treeOut));
    axLines.forEach((line, index) => {
      const t = range(p, 0.27 + index * 0.016, 0.31 + index * 0.016);
      line.style.setProperty("--o", fixed(t));
      line.style.setProperty("--x", `${fixed((1 - t) * 10, 1)}px`);
    });

    // 03 · Notch: the notch opens into the shelf and the count ticks to one.
    const open = range(p, 0.5, 0.62);
    style.setProperty("--notch-width", `${fixed(mix(g.notchWidth, 440 * g.shelfScale, open), 1)}px`);
    style.setProperty("--notch-height", `${fixed(mix(31, 207 * g.shelfScale, open), 1)}px`);
    style.setProperty("--shelf-opacity", fixed(range(p, 0.58, 0.66) * (1 - toHistory)));
    style.setProperty("--count-opacity", p >= 0.7 ? 1 : 0);
    style.setProperty("--count-scale", fixed(1 + 0.5 * Math.max(0, 1 - Math.abs(p - 0.712) / 0.02)));

    // 04 · History: search types "coffee" and finds the shot.
    style.setProperty("--history-opacity", fixed(toHistory));
    const query = "coffee".slice(0, Math.floor(clamp((p - 0.86) / 0.055) * 6.999));
    if (query !== lastQuery) {
      lastQuery = query;
      historyQuery.textContent = query;
      historyUi.classList.toggle("has-query", query.length > 0);
    }
    historyUi.classList.toggle("is-filtered", p >= 0.925);
    const arrival = range(p, 0.95, 0.995);
    style.setProperty("--arrival-opacity", fixed(arrival));
    style.setProperty("--arrival-y", `${fixed(mix(16, 0, arrival), 1)}px`);

    setChapter(p >= 1 ? 3 : chapters.findIndex(([, end]) => p < end));
    railButtons.forEach((button, index) => {
      const [start, end] = chapters[index];
      button.style.setProperty("--fill", fixed(clamp((p - start) / (end - start))));
    });
  }

  function renderStaticStory() {
    if (!geometry) return;
    const style = scene.style;
    style.setProperty("--shelf-scale", geometry.shelfScale);
    style.setProperty("--notch-width", `${440 * geometry.shelfScale}px`);
    style.setProperty("--notch-height", `${207 * geometry.shelfScale}px`);
    setChapter(-1);
  }

  // Returns true while the spring is still catching up with the scroll.
  function updateStory(dt) {
    if (!story || !geometry || !motion) return false;
    const rect = story.getBoundingClientRect();
    const visible = rect.bottom > 0 && rect.top < window.innerHeight;
    const target = clamp(-rect.top / geometry.distance);
    storyPinned = rect.top <= 1 && rect.bottom >= window.innerHeight - 1;
    if (!visible) {
      current = target;
      return false;
    }
    current += (target - current) * (1 - Math.exp(-dt * 9));
    if (Math.abs(target - current) < 0.0004) current = target;
    renderStory(current, clamp(1 - rect.top / window.innerHeight));
    return current !== target;
  }

  railButtons.forEach((button, index) => {
    button.addEventListener("click", () => {
      if (!motion || !geometry) return;
      const top = window.scrollY + story.getBoundingClientRect().top;
      window.scrollTo({ top: top + chapterMoments[index] * geometry.distance, behavior: "smooth" });
    });
  });

  // ------------------------------------------------------------------ Marquee
  const marqueeTrack = $(".marquee-track");
  const marqueeRow = marqueeTrack && $(".marquee-row", marqueeTrack);
  let marqueeClone = null;
  let marqueeWidth = 0;
  let marqueeX = 0;
  let marqueeVisible = false;
  let marqueeBoost = 0;
  let marqueeDirection = -1;

  function setupMarquee() {
    if (!marqueeTrack) return;
    if (motion && !marqueeClone) {
      marqueeClone = marqueeRow.cloneNode(true);
      marqueeTrack.append(marqueeClone);
    } else if (!motion && marqueeClone) {
      marqueeClone.remove();
      marqueeClone = null;
      marqueeTrack.style.transform = "";
    }
    marqueeWidth = marqueeRow.getBoundingClientRect().width;
  }

  function updateMarquee(dt, scrollDelta) {
    if (!marqueeTrack || !marqueeVisible || !motion || !marqueeWidth) return false;
    if (scrollDelta) marqueeDirection = scrollDelta > 0 ? -1 : 1;
    const wanted = clamp((Math.abs(scrollDelta) / Math.max(dt, 0.001)) * 0.35, 0, 900);
    marqueeBoost += (wanted - marqueeBoost) * (1 - Math.exp(-dt * (wanted > marqueeBoost ? 10 : 2.5)));
    marqueeX += marqueeDirection * (60 + marqueeBoost) * dt;
    if (marqueeX <= -marqueeWidth) marqueeX += marqueeWidth;
    if (marqueeX > 0) marqueeX -= marqueeWidth;
    marqueeTrack.style.transform = `translate3d(${fixed(marqueeX, 2)}px, 0, 0)`;
    return true;
  }

  // --------------------------------------------------------------------- Film
  const film = $(".film");
  const filmScale = $(".film-scale");
  const video = $(".film video");
  const play = $(".film-play");

  function updateFilm() {
    if (!film) return;
    if (!motion) {
      filmScale.style.removeProperty("--film-scale");
      filmScale.style.removeProperty("--film-radius");
      return;
    }
    const t = easeOut(clamp((window.innerHeight - film.getBoundingClientRect().top) / (window.innerHeight * 0.95)));
    filmScale.style.setProperty("--film-scale", fixed(mix(0.86, 1, t), 4));
    filmScale.style.setProperty("--film-radius", `${fixed(mix(44, 22, t), 1)}px`);
  }

  if (play && video) {
    play.addEventListener("click", () => {
      film.classList.add("is-playing");
      video.play().catch(() => film.classList.remove("is-playing"));
      video.focus({ preventScroll: true });
    });
    video.addEventListener("play", () => film.classList.add("is-playing"));
    video.addEventListener("ended", () => film.classList.remove("is-playing"));
  }

  // ------------------------------------------------------------- Frame loop
  let frame = 0;
  let lastTime = 0;
  let lastFrameY = window.scrollY;
  let chromeDirty = true;

  function tick(now) {
    frame = 0;
    const dt = lastTime ? Math.min(0.064, (now - lastTime) / 1000) : 1 / 60;
    lastTime = now;
    const y = window.scrollY;
    const scrollDelta = y - lastFrameY;
    lastFrameY = y;
    const storyMoving = updateStory(dt);
    if (chromeDirty) {
      updateChrome();
      updateFilm();
      chromeDirty = false;
    }
    const marqueeMoving = updateMarquee(dt, scrollDelta);
    if (storyMoving || marqueeMoving) schedule();
    else lastTime = 0;
  }

  function schedule() {
    if (!frame) frame = window.requestAnimationFrame(tick);
  }

  window.addEventListener(
    "scroll",
    () => {
      chromeDirty = true;
      schedule();
    },
    { passive: true },
  );
  window.addEventListener(
    "resize",
    () => {
      measureStory();
      setupMarquee();
      if (!motion) renderStaticStory();
      chromeDirty = true;
      schedule();
    },
    { passive: true },
  );

  // ------------------------------------------------------------------ Reveals
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.16, rootMargin: "0px 0px -6% 0px" },
  );
  $$(".bento .card").forEach((card, index) => card.style.setProperty("--d", `${fixed((index % 3) * 0.08, 2)}s`));
  $$(".reveal, .closing").forEach((element) => observer.observe(element));
  // Wide or long-running elements count as visible once any part is on screen;
  // a ratio threshold could never be met by the marquee's very wide track.
  const visibility = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.target === marqueeTrack) {
        marqueeVisible = entry.isIntersecting;
        if (marqueeVisible) schedule();
      } else if (entry.target === miniHistory) {
        setMiniHistory(entry.isIntersecting);
      }
    });
  });
  if (marqueeTrack) visibility.observe(marqueeTrack);

  // --------------------------------------------------- Pointer: tilt, magnets
  if (finePointer.matches) {
    $$(".card").forEach((card) => {
      card.addEventListener("pointermove", (event) => {
        const rect = card.getBoundingClientRect();
        const px = (event.clientX - rect.left) / rect.width;
        const py = (event.clientY - rect.top) / rect.height;
        card.style.setProperty("--px", `${fixed(px * 100, 1)}%`);
        card.style.setProperty("--py", `${fixed(py * 100, 1)}%`);
        card.style.setProperty("--spot", "1");
        if (!motion) return;
        const strength = card.classList.contains("card-custom") ? 2 : 4;
        card.style.setProperty("--rx", `${fixed((0.5 - py) * strength, 2)}deg`);
        card.style.setProperty("--ry", `${fixed((px - 0.5) * strength * 1.2, 2)}deg`);
      });
      card.addEventListener("pointerleave", () => {
        card.style.setProperty("--rx", "0deg");
        card.style.setProperty("--ry", "0deg");
        card.style.setProperty("--spot", "0");
      });
    });
    $$(".magnetic").forEach((element) => {
      element.addEventListener("pointermove", (event) => {
        if (!motion) return;
        const rect = element.getBoundingClientRect();
        element.classList.add("is-magnetized");
        element.style.setProperty("--mx", `${fixed((event.clientX - rect.left - rect.width / 2) * 0.22, 1)}px`);
        element.style.setProperty("--my", `${fixed((event.clientY - rect.top - rect.height / 2) * 0.32, 1)}px`);
      });
      element.addEventListener("pointerleave", () => {
        element.classList.remove("is-magnetized");
        element.style.setProperty("--mx", "0px");
        element.style.setProperty("--my", "0px");
      });
    });
    const hero = $(".hero");
    const glow = $(".hero-glow");
    hero?.addEventListener("pointermove", (event) => {
      if (!motion) return;
      const rect = hero.getBoundingClientRect();
      glow.style.setProperty("--gx", `${fixed(((event.clientX - rect.left) / rect.width - 0.5) * 140, 1)}px`);
      glow.style.setProperty("--gy", `${fixed(((event.clientY - rect.top) / rect.height - 0.5) * 90, 1)}px`);
    });
  }

  // ------------------------------------------------- Make-it-yours notch demo
  const THEMES = {
    mint: ["#8ae8c4", "#b3fad9"],
    sky: ["#8cc9ff", "#c2e6ff"],
    lavender: ["#c2abff", "#e0d1ff"],
    rose: ["#ffa3c4", "#ffd1e3"],
    peach: ["#ffba8c", "#ffdebf"],
    gold: ["#fad67a", "#ffedba"],
  };
  const demoNotch = $(".demo-notch");
  const demoMark = $(".demo-mark");
  const demoCount = $(".demo-count");
  const apertureStops = $$("#aperture-fill stop");
  let demoKind = "aperture";
  let demoShots = 2;
  let demoAnimation = 0;

  function markMarkup(kind) {
    const gradient =
      '<defs><linearGradient id="demo-fill" x1="0" y1="0" x2="1" y2="1">' +
      '<stop offset="0" style="stop-color: var(--accent-2)"/><stop offset="1" style="stop-color: var(--accent)"/></linearGradient></defs>';
    if (kind === "viewfinder") {
      return `<svg viewBox="0 0 32 32">${gradient}<path class="d-brackets" fill="none" stroke="url(#demo-fill)" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle class="d-dot" cx="16" cy="16" r="3.6" style="fill: var(--accent)"/></svg>`;
    }
    if (kind === "camera") {
      return (
        `<svg viewBox="0 0 32 32">${gradient}<rect class="d-print" x="10.5" y="17" width="11" height="9" rx="1.2" fill="#f4f7f3"/>` +
        '<path class="d-camera" fill="url(#demo-fill)" fill-rule="evenodd" d="M4 11a3 3 0 0 1 3-3h4l2-3h6l2 3h4a3 3 0 0 1 3 3v12a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3ZM16 11.2a5.6 5.6 0 1 0 0 11.2a5.6 5.6 0 1 0 0-11.2ZM16 13.6a3.2 3.2 0 1 1 0 6.4a3.2 3.2 0 1 1 0-6.4Z"/>' +
        '<path class="d-spark" d="M27 0.5l1.4 3.3 3.3 1.4-3.3 1.4L27 9.9l-1.4-3.3-3.3-1.4 3.3-1.4Z" fill="#fff"/></svg>'
      );
    }
    return `<svg viewBox="0 0 32 32">${gradient}<path class="d-blades" fill="url(#demo-fill)" fill-rule="evenodd"/><path class="d-seams" fill="none" stroke="#000" stroke-opacity="0.62" stroke-width="1.5" stroke-linecap="round"/></svg>`;
  }

  function renderDemo(state) {
    if (demoKind === "aperture") {
      const [blades, seams] = aperturePaths(state.opening, state.turn);
      $(".d-blades", demoMark).setAttribute("d", blades);
      $(".d-seams", demoMark).setAttribute("d", seams);
    } else if (demoKind === "viewfinder") {
      $(".d-brackets", demoMark).setAttribute("d", brackets(state.inset));
      const dot = $(".d-dot", demoMark);
      dot.setAttribute("opacity", fixed(state.dot));
      dot.setAttribute("r", fixed(1.6 + state.dot * 2.2, 2));
    } else {
      $(".d-camera", demoMark).setAttribute("transform", `translate(16 16) scale(${fixed(1 - state.press * 0.12)}) translate(-16 -16)`);
      const spark = $(".d-spark", demoMark);
      spark.setAttribute("opacity", fixed(state.spark));
      spark.setAttribute("transform", `translate(27 5) scale(${fixed(0.3 + state.spark * 0.7)}) translate(-27 -5)`);
      const print = $(".d-print", demoMark);
      print.setAttribute("opacity", fixed(state.print));
      print.setAttribute("transform", `translate(0 ${fixed(state.print * 5.5, 2)})`);
    }
  }

  function setDemoKind(kind) {
    demoKind = kind;
    demoMark.innerHTML = markMarkup(kind);
    renderDemo(SHUTTER.open);
    $$(".mark-picker button").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.mark === kind)));
  }

  function setTheme(name) {
    const [accent, highlight] = THEMES[name];
    demoNotch.style.setProperty("--accent", accent);
    demoNotch.style.setProperty("--accent-2", highlight);
    // The whole page follows the chosen color, like the app's theme setting.
    root.style.setProperty("--mint", accent);
    root.style.setProperty("--mint-2", highlight);
    if (apertureStops.length === 2) {
      apertureStops[0].setAttribute("stop-color", highlight);
      apertureStops[1].setAttribute("stop-color", accent);
    }
    $$(".swatches button").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.theme === name)));
  }

  const shotTimeline = [
    [0, "open"],
    [140, "shut"],
    [520, "half"],
    [1050, "reopening"],
    [1450, "open"],
  ];

  function interpolate(from, to, t) {
    const state = {};
    for (const key of Object.keys(from)) state[key] = mix(from[key], to[key], t);
    return state;
  }

  function takeShot() {
    cancelAnimationFrame(demoAnimation);
    const start = performance.now();
    let counted = false;
    demoNotch.classList.add("is-flash");
    const step = (now) => {
      const elapsed = now - start;
      let state = SHUTTER.open;
      for (let index = 1; index < shotTimeline.length; index += 1) {
        const [at, name] = shotTimeline[index];
        const [previousAt, previousName] = shotTimeline[index - 1];
        if (elapsed < at) {
          state = interpolate(SHUTTER[previousName], SHUTTER[name], easeOut((elapsed - previousAt) / (at - previousAt)));
          break;
        }
        state = SHUTTER[name];
      }
      renderDemo(state);
      if (!counted && elapsed >= 520) {
        counted = true;
        demoShots += 1;
        demoCount.textContent = String(demoShots);
        demoCount.classList.add("is-bump");
        setTimeout(() => demoCount.classList.remove("is-bump"), 260);
      }
      if (elapsed >= 600) demoNotch.classList.remove("is-flash");
      if (elapsed < shotTimeline[shotTimeline.length - 1][0]) demoAnimation = requestAnimationFrame(step);
    };
    if (motion) demoAnimation = requestAnimationFrame(step);
    else {
      demoShots += 1;
      demoCount.textContent = String(demoShots);
      demoNotch.classList.remove("is-flash");
    }
  }

  if (demoNotch) {
    setDemoKind("aperture");
    $$(".mark-picker button").forEach((button) =>
      button.addEventListener("click", () => {
        setDemoKind(button.dataset.mark);
        takeShot();
      }),
    );
    $$(".swatches button").forEach((button) => button.addEventListener("click", () => setTheme(button.dataset.theme)));
    $(".try-capture")?.addEventListener("click", takeShot);
  }

  // --------------------------------------------------- History card typing
  const miniHistory = $(".mini-history");
  const miniQuery = $(".mini-query");
  const miniRows = $$(".mini-history li");
  const miniQueries = ["coffee", "release", "invoice", "notch"];
  let miniTimer = 0;
  let miniIndex = 0;

  function filterMini(query) {
    miniRows.forEach((row) => {
      const hit = query.length > 0 && row.dataset.words.includes(query);
      row.classList.toggle("is-match", hit);
      row.classList.toggle("is-hidden", query.length > 0 && !hit);
    });
  }

  function runMini(phase = "type", length = 0) {
    const word = miniQueries[miniIndex % miniQueries.length];
    if (phase === "type") {
      miniQuery.textContent = word.slice(0, length);
      if (length < word.length) miniTimer = setTimeout(() => runMini("type", length + 1), 90);
      else {
        filterMini(word);
        miniTimer = setTimeout(() => runMini("erase", word.length), 1700);
      }
    } else {
      if (length === word.length) filterMini("");
      miniQuery.textContent = word.slice(0, length);
      if (length > 0) miniTimer = setTimeout(() => runMini("erase", length - 1), 38);
      else {
        miniIndex += 1;
        miniTimer = setTimeout(() => runMini("type", 0), 500);
      }
    }
  }

  function setMiniHistory(visible) {
    clearTimeout(miniTimer);
    if (!motion) {
      miniQuery.textContent = "coffee";
      filterMini("coffee");
      return;
    }
    if (visible) runMini("type", 0);
    else {
      miniQuery.textContent = "";
      filterMini("");
    }
  }
  if (miniHistory) visibility.observe(miniHistory);

  // -------------------------------------------------------------- Lifecycle
  function applyMode() {
    motion = !reduced.matches;
    root.classList.toggle("motion-enabled", motion);
    root.classList.toggle("motion-disabled", !motion);
    if (scene) {
      scene.removeAttribute("style");
      appWindow.style.removeProperty("transform");
      sceneWrap.style.removeProperty("--tilt");
      sceneWrap.style.removeProperty("--lift");
    }
    activeChapter = -1;
    lastAperture = "";
    lastQuery = null;
    storyPinned = false;
    measureStory();
    setupMarquee();
    if (!motion) {
      renderStaticStory();
      if (miniHistory) setMiniHistory(false);
    } else {
      current = geometry ? clamp(-story.getBoundingClientRect().top / geometry.distance) : 0;
    }
    chromeDirty = true;
    schedule();
  }

  reduced.addEventListener("change", applyMode);
  applyMode();
  // Layout can shift once images and fonts settle.
  window.addEventListener("load", () => {
    measureStory();
    setupMarquee();
    schedule();
  });
  requestAnimationFrame(() => requestAnimationFrame(() => root.classList.add("is-ready")));
})();
