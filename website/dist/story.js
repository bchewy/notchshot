// SPDX-License-Identifier: MIT
// Normal page scrolling drives one reversible capture. No wheel/touch interception.
(() => {
  const story = document.querySelector(".scroll-story");
  const scene = document.querySelector(".mac-scene");
  const appWindow = document.querySelector(".app-window");
  const buttons = [...document.querySelectorAll("[data-step]")];
  const media = window.matchMedia("(prefers-reduced-motion: reduce)");
  if (!story || !scene || !appWindow) return;

  const clamp = (value, min = 0, max = 1) =>
    Math.min(max, Math.max(min, value));
  const smooth = (value) => {
    const t = clamp(value);
    return t * t * (3 - 2 * t);
  };
  const range = (progress, start, end) =>
    smooth((progress - start) / (end - start));
  const mix = (from, to, progress) => from + (to - from) * progress;
  let geometry;
  let frame = 0;
  let activeStep = -1;

  function measure() {
    const width = scene.clientWidth;
    const height = scene.clientHeight;
    const shelfScale = Math.min(1, (width - 20) / 440, (height * 0.44) / 207);
    geometry = {
      width,
      height,
      shelfScale,
      x: appWindow.offsetLeft + appWindow.offsetWidth / 2,
      y: appWindow.offsetTop + appWindow.offsetHeight / 2,
      cardWidth: appWindow.offsetWidth,
      cardHeight: appWindow.offsetHeight,
      // The center of the thumbnail inside the fully opened shelf.
      targetX: width / 2 - (440 * shelfScale) / 2 + 70 * shelfScale,
      targetY: (36 + 28 + 25 + 15.5 + 28) * shelfScale,
      distance: Math.max(
        1,
        story.offsetHeight - story.querySelector(".story-sticky").offsetHeight,
      ),
    };
    render();
  }

  function setStep(step) {
    if (step === activeStep) return;
    activeStep = step;
    buttons.forEach((button, index) => {
      if (index === step && !media.matches)
        button.setAttribute("aria-current", "step");
      else button.removeAttribute("aria-current");
    });
  }

  function render() {
    frame = 0;
    if (!geometry) return;
    const g = geometry;
    const style = scene.style;
    style.setProperty("--shelf-scale", g.shelfScale);
    if (media.matches) {
      style.setProperty("--notch-width", `${440 * g.shelfScale}px`);
      style.setProperty("--notch-height", `${207 * g.shelfScale}px`);
      setStep(-1);
      return;
    }
    const p = clamp(-story.getBoundingClientRect().top / g.distance);
    const peel = range(p, 0.14, 0.4);
    const flight = range(p, 0.46, 0.84);
    const open = range(p, 0.45, 0.67);
    const arrival = range(p, 0.84, 0.97);
    const finalScale = Math.min(
      (94 * g.shelfScale) / g.cardWidth,
      (56 * g.shelfScale) / g.cardHeight,
    );
    const previewScale = g.width <= 600 ? 0.63 : 0.53;
    const scale = mix(mix(1, previewScale, peel), finalScale, flight);
    const previewX = g.width * 0.56;
    const previewY = g.height * 0.5;
    // One shallow arc, without rotation or spring overshoot while scrolling.
    const x =
      mix(mix(g.x, previewX, peel), g.targetX, flight) +
      Math.sin(flight * Math.PI) * g.width * 0.065;
    const y = mix(mix(g.y, previewY, peel), g.targetY, flight);
    appWindow.style.transform = `translate3d(${x - g.x}px, ${y - g.y}px, 0) scale(${scale})`;
    style.setProperty(
      "--notch-width",
      `${mix(g.width <= 600 ? 130 : 172, 440 * g.shelfScale, open)}px`,
    );
    style.setProperty(
      "--notch-height",
      `${mix(31, 207 * g.shelfScale, open)}px`,
    );
    style.setProperty("--shelf-opacity", range(p, 0.55, 0.7));
    style.setProperty("--window-opacity", 1);
    style.setProperty("--source-shadow", 1 - peel);
    style.setProperty("--hint-opacity", 1 - range(p, 0.08, 0.18));
    style.setProperty(
      "--capture-opacity",
      range(p, 0.12, 0.2) * (1 - range(p, 0.76, 0.86)),
    );
    // One soft capture exposure, restricted to the example window.
    style.setProperty(
      "--flash-opacity",
      Math.max(0, 1 - Math.abs(p - 0.155) / 0.035) * 0.3,
    );
    style.setProperty(
      "--context-opacity",
      range(p, 0.28, 0.4) * (1 - range(p, 0.54, 0.66)),
    );
    style.setProperty("--context-y", `${mix(10, 0, peel)}px`);
    style.setProperty("--arrival-opacity", arrival);
    style.setProperty("--arrival-y", `${mix(14, 0, arrival)}px`);
    setStep(p < 0.25 ? 0 : p < 0.65 ? 1 : 2);
  }

  function requestRender() {
    if (!frame) frame = window.requestAnimationFrame(render);
  }

  function configure() {
    document.documentElement.classList.toggle("motion-enabled", !media.matches);
    document.documentElement.classList.toggle("motion-disabled", media.matches);
    scene.removeAttribute("style");
    appWindow.style.removeProperty("transform");
    buttons.forEach((button) => {
      button.disabled = media.matches;
    });
    activeStep = -2;
    measure();
  }

  buttons.forEach((button, index) => {
    button.addEventListener("click", () => {
      if (media.matches || !geometry) return;
      const start = window.scrollY + story.getBoundingClientRect().top;
      window.scrollTo({
        top: start + [0, 0.43, 1][index] * geometry.distance,
        behavior: "smooth",
      });
    });
  });
  window.addEventListener("scroll", requestRender, { passive: true });
  window.addEventListener("resize", measure, { passive: true });
  media.addEventListener("change", configure);
  configure();
  // Font metrics and image loading can change the section's starting position.
  window.addEventListener("load", measure, { once: true });
})();
