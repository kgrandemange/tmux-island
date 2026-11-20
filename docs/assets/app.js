/* TmuxIsland — page de présentation : langue FR/EN, île animée, apparition au défilement, copie de code. */
(() => {
  const root = document.documentElement;

  /* ---------- Langue (FR par défaut dans le HTML, EN via data-en) ---------- */
  const nodes = [...document.querySelectorAll("[data-en]")];
  nodes.forEach((n) => (n.dataset.fr = n.innerHTML));
  const attrNodes = [...document.querySelectorAll("[data-en-alt],[data-en-label]")];
  attrNodes.forEach((n) => {
    if (n.dataset.enAlt !== undefined) n.dataset.frAlt = n.getAttribute("alt");
    if (n.dataset.enLabel !== undefined) n.dataset.frLabel = n.getAttribute("aria-label");
  });
  const meta = {
    fr: { title: "TmuxIsland — La Dynamic Island de ton tmux", desc: "Sache quel agent IA a fini ou attend ta validation, et va sur le bon pane tmux en un clic. Une île autour de la notch de ton Mac, couplée à tmux." },
    en: { title: "TmuxIsland — The Dynamic Island for your tmux", desc: "Know which AI agent finished or needs your approval, and jump to the right tmux pane in one click. An island around your Mac's notch, built on tmux." },
  };
  const buttons = [...document.querySelectorAll(".lang button")];

  function setLang(lang) {
    root.lang = lang;
    nodes.forEach((n) => (n.innerHTML = lang === "en" ? n.dataset.en : n.dataset.fr));
    attrNodes.forEach((n) => {
      if (n.dataset.enAlt !== undefined) n.setAttribute("alt", lang === "en" ? n.dataset.enAlt : n.dataset.frAlt);
      if (n.dataset.enLabel !== undefined) n.setAttribute("aria-label", lang === "en" ? n.dataset.enLabel : n.dataset.frLabel);
    });
    setVideoLang(lang);
    document.title = meta[lang].title;
    document.querySelector('meta[name="description"]')?.setAttribute("content", meta[lang].desc);
    buttons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
    try { localStorage.setItem("lang", lang); } catch (_) {}
  }
  let saved = null;
  try { saved = localStorage.getItem("lang"); } catch (_) {}
  /* ---------- Vidéo de démonstration (version FR / EN) ---------- */
  const video = document.getElementById("hero-video");
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  function setVideoLang(lang) {
    if (!video) return;
    const base = "assets/tmuxisland-" + lang;
    const wasPlaying = !video.paused;
    video.poster = "assets/poster-" + lang + ".jpg";
    video.innerHTML = '<source src="' + base + '.webm" type="video/webm; codecs=vp9"><source src="' + base + '.mp4" type="video/mp4">';
    video.load();
    if (!reduceMotion && (wasPlaying || video.dataset.started !== "1")) { video.dataset.started = "1"; video.play().catch(() => {}); }
  }

  const browserFr = (navigator.language || "fr").toLowerCase().startsWith("fr");
  setLang(saved === "fr" || saved === "en" ? saved : browserFr ? "fr" : "en");
  buttons.forEach((b) => b.addEventListener("click", () => setLang(b.dataset.lang)));

  /* ---------- Île animée : compact → toast → déplié ---------- */
  const island = document.getElementById("island");
  const stage = document.getElementById("stage");
  if (island && stage) {
    const states = [
      { s: "compact", ms: 2600 },
      { s: "toast", ms: 2800 },
      { s: "expanded", ms: 7000 },
    ];
    const pips = [...stage.querySelectorAll(".steps i")];
    let i = 0, timer = null, paused = false;
    const show = (k) => {
      i = k;
      island.dataset.state = states[k].s;
      pips.forEach((p, n) => p.classList.toggle("on", n === k));
    };
    const loop = () => {
      clearTimeout(timer);
      if (paused) return;
      timer = setTimeout(() => { show((i + 1) % states.length); loop(); }, states[i].ms);
    };
    show(0);
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      show(2);
    } else {
      loop();
      stage.addEventListener("mouseenter", () => { paused = true; clearTimeout(timer); show(2); });
      stage.addEventListener("mouseleave", () => { paused = false; show(0); loop(); });
    }
  }

  /* ---------- Apparition au défilement ---------- */
  const rev = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((es) => es.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    }), { threshold: 0.12 });
    rev.forEach((r) => io.observe(r));
  } else {
    rev.forEach((r) => r.classList.add("in"));
  }

  /* ---------- Copier le code ---------- */
  document.querySelectorAll(".copy button").forEach((b) => {
    b.addEventListener("click", async () => {
      const txt = b.closest(".codebox").querySelector("pre").innerText.replace(/^\$ /gm, "");
      try { await navigator.clipboard.writeText(txt); } catch (_) { return; }
      const old = b.textContent;
      b.textContent = root.lang === "en" ? "Copied" : "Copié";
      setTimeout(() => (b.textContent = old), 1400);
    });
  });
})();
