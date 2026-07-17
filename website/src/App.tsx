import { useCallback, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type PointerEvent } from "react";
import { CHAPTERS, RELEASE, THEMES, type NotchTheme, type StoryScene } from "./data";
import {
  useFinePointer,
  useHeaderCollisionLayout,
  useNarrowLayout,
  useReducedMotion,
  useStoryPosition,
} from "./hooks";
import {
  ArrowDownIcon,
  ArrowUpRightIcon,
  CheckIcon,
  GithubIcon,
  LockIcon,
} from "./icons";
import { MagneticLink } from "./components/MagneticLink";
import { NotchDemo, type NotchMode } from "./components/NotchDemo";
import { VisualStage } from "./components/VisualStage";
import { createSpring2D, type Spring2DController } from "./spring";

const baseModeForScene: Record<string, NotchMode> = {
  hero: "collapsed",
  delegate: "collapsed",
  signal: "compact",
  return: "compact",
  machines: "collapsed",
  usage: "collapsed",
  trust: "compact",
  personal: "collapsed",
  final: "collapsed",
};

const SCROLL_NOTCH_DWELL_MS = 3200;

const TOUCH_CHAPTER_COPY: Partial<
  Record<StoryScene, { body: string; note: string }>
> = {
  return: {
    body:
      "Tap the compact signal to return to the validated Codex thread. Tap the notch at the top whenever you want the current task list.",
    note: "Try the compact row above.",
  },
  personal: {
    body:
      "Preview authored palettes on the real open notch, choose a completion tone, hide active tasks, or turn on Do Not Disturb without changing macOS Focus.",
    note: "Tap a palette below to preview it live.",
  },
};

function App() {
  const { scene, progress, pageProgress } = useStoryPosition();
  const reduceMotion = useReducedMotion();
  const finePointer = useFinePointer();
  const narrowLayout = useNarrowLayout();
  const headerCollisionLayout = useHeaderCollisionLayout();
  const pointerLightRef = useRef<HTMLDivElement>(null);
  const headerRef = useRef<HTMLElement>(null);
  const pointerSpringRef = useRef<Spring2DController | null>(null);
  const taskTimer = useRef<number | undefined>(undefined);
  const taskReleaseFrame = useRef<number | undefined>(undefined);
  const instantTimer = useRef<number | undefined>(undefined);
  const dismissedAutoOpenScene = useRef<string | null>(null);
  const [theme, setTheme] = useState<NotchTheme>(THEMES[0]);
  const [hoverOpen, setHoverOpen] = useState(false);
  const [pinned, setPinned] = useState(false);
  const [autoOpen, setAutoOpen] = useState(false);
  const [threadOpening, setThreadOpening] = useState(false);
  const [instantInteraction, setInstantInteraction] = useState(false);
  const [notchFocusWithin, setNotchFocusWithin] = useState(false);
  const [keyboardTaskInteraction, setKeyboardTaskInteraction] = useState(false);

  const markInteractionInstant = useCallback(() => {
    setInstantInteraction(true);
    if (instantTimer.current) window.clearTimeout(instantTimer.current);
    instantTimer.current = window.setTimeout(() => {
      setInstantInteraction(false);
    }, 120);
  }, []);

  useEffect(() => {
    const light = pointerLightRef.current;
    pointerSpringRef.current?.stop();
    pointerSpringRef.current = null;
    if (!light || !finePointer || reduceMotion) return;
    const initialX = window.innerWidth / 2 - 310;
    const initialY = window.innerHeight * 0.42 - 310;
    pointerSpringRef.current = createSpring2D(
      (x, y) => {
        light.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      },
      { x: initialX, y: initialY },
      { stiffness: 145, damping: 21, precision: 0.05 },
    );
    return () => pointerSpringRef.current?.stop();
  }, [finePointer, reduceMotion]);

  useEffect(() => {
    if (dismissedAutoOpenScene.current === scene) {
      setAutoOpen(false);
      return;
    }
    if (notchFocusWithin) {
      setAutoOpen(true);
      return;
    }
    if (scene === "hero" || scene === "final" || narrowLayout) {
      setAutoOpen(false);
      return;
    }
    setAutoOpen(true);
    const timer = window.setTimeout(
      () => setAutoOpen(false),
      SCROLL_NOTCH_DWELL_MS,
    );
    return () => window.clearTimeout(timer);
  }, [narrowLayout, notchFocusWithin, progress, scene]);

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        markInteractionInstant();
        dismissedAutoOpenScene.current = scene;
        document.getElementById("web-notch-trigger")?.focus({ preventScroll: true });
        setPinned(false);
        setHoverOpen(false);
        setAutoOpen(false);
      }
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [markInteractionInstant, scene]);

  useEffect(
    () => () => {
      if (taskTimer.current) window.clearTimeout(taskTimer.current);
      if (taskReleaseFrame.current) window.cancelAnimationFrame(taskReleaseFrame.current);
      if (instantTimer.current) window.clearTimeout(instantTimer.current);
      pointerSpringRef.current?.stop();
    },
    [],
  );

  const baseMode = baseModeForScene[scene] ?? "collapsed";
  const notchMode: NotchMode =
    pinned || hoverOpen || autoOpen ? "full" : baseMode;
  const headerObscured =
    (notchMode === "full" && headerCollisionLayout) ||
    (notchMode === "compact" && narrowLayout);

  useLayoutEffect(() => {
    if (
      headerObscured &&
      headerRef.current?.contains(document.activeElement)
    ) {
      document.getElementById("web-notch-trigger")?.focus({ preventScroll: true });
    }
  }, [headerObscured]);

  const navigate = (target: StoryScene, immediate = false) => {
    if (immediate) {
      dismissedAutoOpenScene.current = target;
      markInteractionInstant();
      setAutoOpen(false);
    } else {
      dismissedAutoOpenScene.current = null;
      setAutoOpen(true);
    }
    document.getElementById(target)?.scrollIntoView({
      behavior: immediate || reduceMotion ? "auto" : "smooth",
      block: "center",
    });
  };

  const openTask = (immediate = false) => {
    if (immediate) markInteractionInstant();
    setKeyboardTaskInteraction(immediate);
    setThreadOpening(true);
    if (scene !== "return") navigate("return", immediate);
    if (taskTimer.current) window.clearTimeout(taskTimer.current);
    if (taskReleaseFrame.current) window.cancelAnimationFrame(taskReleaseFrame.current);
    taskTimer.current = window.setTimeout(() => {
      setThreadOpening(false);
      if (immediate) {
        taskReleaseFrame.current = window.requestAnimationFrame(() => {
          setKeyboardTaskInteraction(false);
        });
      }
    }, 2200);
  };

  const changeTheme = (nextTheme: NotchTheme, immediate = false) => {
    if (immediate) markInteractionInstant();
    setTheme(nextTheme);
  };

  const handlePointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!finePointer || reduceMotion) return;
    pointerSpringRef.current?.moveTo(event.clientX - 310, event.clientY - 310);
  };

  const themeStyle = {
    "--accent": theme.accent,
    "--accent-secondary": theme.secondary,
    "--notch-top": theme.top,
    "--notch-bottom": theme.bottom,
    "--page-progress": pageProgress,
  } as CSSProperties;

  return (
    <div
      className={`site scene-${scene}${instantInteraction ? " is-input-instant" : ""}${keyboardTaskInteraction ? " is-keyboard-task" : ""}${headerObscured ? " is-header-obscured" : ""}`}
      style={themeStyle}
      onPointerMove={handlePointerMove}
    >
      <a className="skip-link" href="#main-content">Skip to content</a>
      <div className="pointer-light" ref={pointerLightRef} aria-hidden="true" />
      <div className="film-grain" aria-hidden="true" />

      <NotchDemo
        mode={notchMode}
        scene={scene}
        sceneProgress={progress}
        theme={theme}
        pinned={pinned}
        onHoverOpenChange={setHoverOpen}
        onTogglePinned={(immediate) => {
          if (immediate) markInteractionInstant();
          if (pinned) {
            dismissedAutoOpenScene.current = scene;
            document.getElementById("web-notch-trigger")?.focus({ preventScroll: true });
            setNotchFocusWithin(false);
            setAutoOpen(false);
            setHoverOpen(false);
          }
          setPinned((value) => !value);
        }}
        onNavigate={navigate}
        onOpenTask={openTask}
        onThemeChange={changeTheme}
        onFocusWithinChange={(focused, keyboardExit) => {
          setNotchFocusWithin(focused);
          if (!focused && keyboardExit) {
            dismissedAutoOpenScene.current = scene;
            markInteractionInstant();
            setAutoOpen(false);
          }
        }}
      />

      <div className="page-progress" aria-hidden="true"><i /></div>

      <header
        className="site-header"
        ref={headerRef}
        aria-hidden={headerObscured || undefined}
        inert={headerObscured}
      >
        <a className="wordmark" href="#hero" aria-label="Codex Notch home">
          <span className="wordmark-mark"><i /></span>
          <span>Codex Notch</span>
        </a>
        <div className="header-actions">
          <a href={RELEASE.repository} target="_blank" rel="noreferrer">
            <GithubIcon />Source
          </a>
          <a className="header-download" href={RELEASE.download}>
            Download <ArrowDownIcon />
          </a>
        </div>
      </header>

      <main id="main-content">
        <section className="hero" id="hero" aria-labelledby="hero-title">
          <div className="hero-ambient" aria-hidden="true">
            <div className="hero-orbit orbit-one"><span>Running</span><i /></div>
            <div className="hero-orbit orbit-two"><span>Needs input</span><i /></div>
            <div className="hero-orbit orbit-three"><CheckIcon /><span>Finished</span></div>
            <div className="hero-horizon" />
          </div>

          <div className="hero-content">
            <div className="hero-eyebrow reveal-item">
              <span className="eyebrow-dot" />
              Native macOS HUD for Codex
            </div>
            <h1 id="hero-title">
              <span className="hero-line">Codex is working.</span>
              <span className="hero-line hero-line-muted">You don’t have to watch.</span>
            </h1>
            <p className="hero-lede">
              See what’s running, know when Codex needs you, and return the
              moment a turn finishes, from this Mac or your Ubuntu machines.
            </p>
            <div className="hero-cta-row">
              <MagneticLink
                className="primary-cta"
                href={RELEASE.download}
                aria-label={`Download Codex Notch version ${RELEASE.version} for Apple silicon`}
              >
                <span className="cta-icon"><ArrowDownIcon /></span>
                <span><strong>Download for Apple silicon</strong><small>v{RELEASE.version} · {RELEASE.macos}</small></span>
              </MagneticLink>
              <MagneticLink
                className="secondary-cta"
                href={RELEASE.repository}
                target="_blank"
                rel="noreferrer"
              >
                <GithubIcon /> View on GitHub <ArrowUpRightIcon />
              </MagneticLink>
            </div>
            <div className="hero-proof">
              <span><CheckIcon /> No Codex Notch account</span>
              <span><LockIcon /> Local by default</span>
              <span><CheckIcon /> Exact thread handoff</span>
            </div>
          </div>

          {finePointer ? (
            <div className={`top-intent-cue ${notchMode === "collapsed" ? "is-visible" : ""}`} aria-hidden="true">
              <span>Move to the top</span><i />
            </div>
          ) : (
            <button
              className="touch-notch-cue"
              type="button"
              onClick={(event) => {
                if (event.detail === 0) markInteractionInstant();
                document.getElementById("web-notch-trigger")?.focus({ preventScroll: true });
                setPinned(true);
              }}
            >
              Tap the notch to try it
            </button>
          )}

          <a className="scroll-cue" href="#delegate" aria-label="Scroll to the product story">
            <span>Experience the signal</span>
            <i><ArrowDownIcon /></i>
          </a>
        </section>

        <section className="story" aria-label="How Codex Notch works">
          <div className="story-wash" aria-hidden="true" />
          <div className="story-layout">
            <div className="sticky-stage-column">
              <div className="stage-label">
                <span><i />INTERACTIVE WEB DEMO</span>
                <small>{finePointer ? "Move your cursor over the screen" : "Scroll to drive the demo"}</small>
              </div>
              <VisualStage
                scene={scene}
                progress={progress}
                theme={theme}
                threadOpening={threadOpening}
                motionEnabled={finePointer && !reduceMotion}
              />
              <p className="demo-disclaimer">Web simulation · the native app opens real Codex threads.</p>
            </div>

            <div className="chapter-column">
              {CHAPTERS.map((chapter) => (
                <section
                  className={`chapter ${scene === chapter.id ? "is-active" : ""}`}
                  id={chapter.id}
                  key={chapter.id}
                  aria-labelledby={`${chapter.id}-title`}
                >
                  <div className="chapter-content">
                    <div className="chapter-meta">
                      <span>{chapter.number}</span><i />{chapter.eyebrow}
                    </div>
                    <h2 id={`${chapter.id}-title`}>{chapter.title}</h2>
                    <p>{!finePointer && TOUCH_CHAPTER_COPY[chapter.id]
                      ? TOUCH_CHAPTER_COPY[chapter.id]?.body
                      : chapter.body}</p>
                    <div className="chapter-note"><span /><strong>
                      {!finePointer && TOUCH_CHAPTER_COPY[chapter.id]
                        ? TOUCH_CHAPTER_COPY[chapter.id]?.note
                        : chapter.note}
                    </strong></div>

                    {chapter.id === "machines" ? (
                      <div className="machine-facts">
                        <span>MAC <strong>local</strong></span>
                        <i>+</i>
                        <span>UBUNTU <strong>publisher</strong></span>
                        <i>→</i>
                        <span>TAILSCALE <strong>private</strong></span>
                      </div>
                    ) : null}

                    {chapter.id === "trust" ? (
                      <div className="privacy-facts">
                        <span>task title</span><span>thread + turn IDs</span><span>source + state</span><span>timestamp</span>
                      </div>
                    ) : null}

                    {chapter.id === "personal" ? (
                      <div className="theme-scrubber" role="group" aria-label="Preview notch themes">
                        {THEMES.map((item) => (
                          <button
                            type="button"
                            key={item.id}
                            className={item.id === theme.id ? "is-selected" : ""}
                            onPointerEnter={() => {
                              if (finePointer) changeTheme(item);
                            }}
                            onFocus={(event) => {
                              changeTheme(item, event.currentTarget.matches(":focus-visible"));
                            }}
                            onClick={(event) => changeTheme(item, event.detail === 0)}
                            aria-label={`Preview ${item.name}: ${item.mood}`}
                            aria-pressed={item.id === theme.id}
                          >
                            <i style={{ background: item.accent }} />
                            <span>{item.name}</span>
                          </button>
                        ))}
                      </div>
                    ) : null}
                  </div>
                </section>
              ))}
            </div>
          </div>
        </section>

        <section className="final-cta" id="download" aria-labelledby="download-title">
          <div className="final-glow" aria-hidden="true" />
          <div className="final-notch-mark" aria-hidden="true"><i /></div>
          <div className="final-content">
            <div className="final-eyebrow"><span />READY WHEN YOU ARE</div>
            <h2 id="download-title">Give Codex a place<br />to find you.</h2>
            <p>
              Leave the window. Keep the signal. Come back at the moment that matters.
            </p>
            <MagneticLink
              className="final-download"
              href={RELEASE.download}
              strength={0.1}
            >
              <span className="final-download-icon"><ArrowDownIcon /></span>
              <span><strong>Download Codex Notch</strong><small>v{RELEASE.version} · {RELEASE.architecture} · {RELEASE.macos}</small></span>
              <i className="download-arrow">↘</i>
            </MagneticLink>
            <div className="final-requirements">
              <span><CheckIcon /> Native macOS app</span>
              <span><CheckIcon /> Codex CLI required</span>
              <span><CheckIcon /> Tailscale optional</span>
            </div>
          </div>

          <div className="install-path" aria-label="Installation steps">
            <div><span>1</span><p><strong>Install the app</strong>Unzip · move to Applications · open</p></div>
            <i />
            <div><span>2</span><p><strong>Finish setup</strong>Add the bundled local hook</p></div>
            <i />
            <div><span>3</span><p><strong>Approve once</strong>Review it in Codex</p></div>
          </div>

          <footer className="site-footer">
            <a className="footer-brand" href="#hero"><span className="wordmark-mark"><i /></span>Codex Notch</a>
            <p>Built for the space your Mac already has.</p>
            <div>
              <a href={RELEASE.release} target="_blank" rel="noreferrer">Release notes <ArrowUpRightIcon /></a>
              <a href={RELEASE.repository} target="_blank" rel="noreferrer">Source <GithubIcon /></a>
            </div>
          </footer>
        </section>
      </main>

      <div
        className={`thread-handoff-toast ${threadOpening ? "is-visible" : ""}`}
        aria-hidden={!threadOpening}
      >
        <span><CheckIcon /></span>
        <div><strong>Opening the exact Codex thread</strong><small>Simulated on the web</small></div>
        <i>↗</i>
      </div>
      <div className="sr-only" role="status" aria-live="polite">
        {threadOpening ? "Opening the exact Codex thread. Simulated on the web." : ""}
      </div>
    </div>
  );
}

export default App;
