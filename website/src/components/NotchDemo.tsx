import { useEffect, useMemo, useRef, useState, type MouseEvent } from "react";
import {
  RELEASE,
  STORY_SCENES,
  THEMES,
  type NotchTheme,
  type PageScene,
  type StoryScene,
} from "../data";
import {
  BoltIcon,
  CheckIcon,
  CloseIcon,
  SettingsIcon,
} from "../icons";

export type NotchMode = "collapsed" | "compact" | "full";

interface NotchDemoProps {
  mode: NotchMode;
  scene: PageScene;
  sceneProgress: number;
  theme: NotchTheme;
  pinned: boolean;
  onHoverOpenChange: (open: boolean) => void;
  onTogglePinned: (immediate?: boolean) => void;
  onNavigate: (scene: StoryScene, immediate?: boolean) => void;
  onOpenTask: (immediate?: boolean) => void;
  onThemeChange: (theme: NotchTheme, immediate?: boolean) => void;
  onFocusWithinChange: (focused: boolean, keyboardExit?: boolean) => void;
}

const statusClass: Record<string, string> = {
  Running: "running",
  "Needs approval": "approval",
  "Needs input": "input",
  "Connection lost": "lost",
};

function sceneAsStory(scene: PageScene): StoryScene {
  return STORY_SCENES.includes(scene as StoryScene)
    ? (scene as StoryScene)
    : "delegate";
}

function isKeyboardActivation(event: MouseEvent<HTMLElement>) {
  return event.detail === 0;
}

function canHover() {
  return window.matchMedia("(hover: hover) and (pointer: fine)").matches;
}

export function NotchDemo({
  mode,
  scene,
  sceneProgress,
  theme,
  pinned,
  onHoverOpenChange,
  onTogglePinned,
  onNavigate,
  onOpenTask,
  onThemeChange,
  onFocusWithinChange,
}: NotchDemoProps) {
  const openTimer = useRef<number | undefined>(undefined);
  const closeTimer = useRef<number | undefined>(undefined);
  const focusWithinRef = useRef(false);
  const keyboardExitRef = useRef(false);
  const fullContentRef = useRef<HTMLDivElement>(null);
  const [usageHovered, setUsageHovered] = useState(false);
  const [hostHovered, setHostHovered] = useState(false);

  const activeStatus = useMemo(() => {
    if (scene !== "delegate") return "Running";
    if (sceneProgress < 0.36) return "Running";
    if (sceneProgress < 0.7) return "Needs approval";
    return "Needs input";
  }, [scene, sceneProgress]);

  const currentStoryScene = sceneAsStory(scene);
  const compactTitle =
    scene === "trust" ? "Return signal secured" : "Signed release published";
  const usageVisible = mode === "full" && (scene === "usage" || usageHovered);
  const hostVisible = mode === "full" && (scene === "machines" || hostHovered);

  const clearTimers = () => {
    if (openTimer.current) window.clearTimeout(openTimer.current);
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
  };

  const beginIntent = () => {
    if (!canHover()) return;
    clearTimers();
    openTimer.current = window.setTimeout(() => {
      onHoverOpenChange(true);
    }, 140);
  };

  const keepOpen = () => {
    if (!canHover()) return;
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
    if (mode !== "full") beginIntent();
  };

  const endIntent = () => {
    if (openTimer.current) window.clearTimeout(openTimer.current);
    closeTimer.current = window.setTimeout(() => {
      if (focusWithinRef.current) return;
      onHoverOpenChange(false);
      setUsageHovered(false);
      setHostHovered(false);
    }, 220);
  };

  useEffect(() => clearTimers, []);

  return (
    <aside
      className={`web-notch mode-${mode} scene-${scene}`}
      aria-label="Interactive web demonstration of Codex Notch"
      data-mode={mode}
      onFocusCapture={(event) => {
        const focusedInsidePanel = Boolean(
          fullContentRef.current?.contains(event.target),
        );
        focusWithinRef.current = focusedInsidePanel;
        onFocusWithinChange(focusedInsidePanel);
      }}
      onKeyDownCapture={(event) => {
        keyboardExitRef.current = event.key === "Tab";
      }}
      onPointerDownCapture={() => {
        keyboardExitRef.current = false;
      }}
      onBlurCapture={(event) => {
        if (event.currentTarget.contains(event.relatedTarget)) return;
        const keyboardExit = keyboardExitRef.current;
        keyboardExitRef.current = false;
        focusWithinRef.current = false;
        onFocusWithinChange(false, keyboardExit);
        if (keyboardExit) {
          clearTimers();
          onHoverOpenChange(false);
        } else {
          endIntent();
        }
      }}
    >
      <button
        id="web-notch-trigger"
        className="notch-hit-target"
        type="button"
        aria-expanded={mode === "full"}
        aria-label={
          pinned ? "Unpin and close the web notch" : "Pin the web notch open"
        }
        onPointerEnter={beginIntent}
        onPointerLeave={endIntent}
        onClick={(event) => onTogglePinned(isKeyboardActivation(event))}
      />

      <div
        className="notch-surface"
        onPointerEnter={keepOpen}
        onPointerLeave={endIntent}
      >
        <div className="notch-material" />
        <div className="notch-hardware" aria-hidden="true">
          <span className="notch-camera" />
        </div>

        <div
          className="notch-full-content"
          ref={fullContentRef}
          aria-hidden={mode !== "full"}
          inert={mode !== "full"}
        >
          <header className="notch-header">
            <div className="notch-header-side notch-header-left">
              <button
                type="button"
                className="notch-brand notch-pressable"
                onClick={(event) => onNavigate("delegate", isKeyboardActivation(event))}
                aria-label="Go to active tasks story"
              >
                <CheckIcon />
                <span>Codex</span>
              </button>
              <div className="notch-popover-anchor">
                <button
                  type="button"
                  className="notch-badge usage-badge notch-pressable"
                  onClick={(event) => onNavigate("usage", isKeyboardActivation(event))}
                  onPointerEnter={() => {
                    if (canHover()) setUsageHovered(true);
                  }}
                  onPointerLeave={() => setUsageHovered(false)}
                  aria-label="Five hour Codex limit reached; 54 percent of the seven day limit remaining"
                >
                  <span><i>5h</i><b>reached</b></span>
                  <span><i>7d</i><b>54%</b></span>
                </button>
                <div
                  className={`mini-popover usage-popover ${
                    usageVisible ? "is-visible" : ""
                  }`}
                  aria-hidden={!usageVisible}
                >
                  <strong>5h reached · 7d 54%</strong>
                  <span>Seven-day pace: lasts through reset</span>
                  <small>Account-wide · labeled by duration · click to refresh</small>
                </div>
              </div>
              <div className="notch-popover-anchor">
                <button
                  type="button"
                  className="notch-badge host-badge notch-pressable"
                  onClick={(event) => onNavigate("machines", isKeyboardActivation(event))}
                  onPointerEnter={() => {
                    if (canHover()) setHostHovered(true);
                  }}
                  onPointerLeave={() => setHostHovered(false)}
                  aria-label="Three connected hosts"
                >
                  <span className="host-dot" />3
                </button>
                <div
                  className={`mini-popover host-popover ${
                    hostVisible ? "is-visible" : ""
                  }`}
                  aria-hidden={!hostVisible}
                >
                  <span><i className="health-dot" />This Mac</span>
                  <span><i className="health-dot" />Ubuntu home</span>
                  <span><i className="health-dot" />Ubuntu server</span>
                </div>
              </div>
            </div>

            <div className="notch-header-gap" aria-hidden="true" />

            <div className="notch-header-side notch-header-right">
              <button
                type="button"
                className="notch-icon-button notch-pressable"
                onClick={(event) => onNavigate("personal", isKeyboardActivation(event))}
                aria-label="Go to personalization story"
              >
                <SettingsIcon />
              </button>
              <button
                type="button"
                className="notch-active-toggle notch-pressable"
                onClick={(event) => onNavigate("delegate", isKeyboardActivation(event))}
                aria-label="Active tasks are visible"
              >
                <BoltIcon />
                <span>⌃⇧R</span>
              </button>
              <button
                type="button"
                className="shortcut-badge notch-pressable"
                onClick={(event) => onTogglePinned(isKeyboardActivation(event))}
                aria-label="Toggle web notch"
              >
                {pinned ? <CloseIcon /> : "⌃⇧H"}
              </button>
            </div>
          </header>

          <div className="notch-task-list">
            <div className="notch-section-label">
              <span>ACTIVE</span>
              {scene === "delegate" && sceneProgress > 0.82 ? (
                <span className="frozen-label">· FROZEN</span>
              ) : null}
            </div>

            <button
              type="button"
              className="notch-task-row active-row notch-pressable"
              onClick={(event) => onNavigate("delegate", isKeyboardActivation(event))}
            >
              <span className="task-number">1</span>
              <span className="task-copy">
                <strong>Build the Codex Notch landing page</strong>
                <small>
                  {scene === "machines"
                    ? "Ubuntu server · codex-notch · 2 subagents"
                    : "This Mac · codex-notch · codex/vibe-site · 2 subagents"}
                </small>
              </span>
              <span className={`task-status ${statusClass[activeStatus]}`}>
                <i />{activeStatus}
              </span>
              <kbd>J</kbd>
            </button>

            <button
              type="button"
              className="notch-task-row active-row notch-pressable"
              onClick={(event) => onNavigate("machines", isKeyboardActivation(event))}
            >
              <span className="task-number">2</span>
              <span className="task-copy">
                <strong>Verify the signed release</strong>
                <small>{scene === "machines" ? "Ubuntu home · codex-notch · main" : "This Mac · codex-notch · main"}</small>
              </span>
              <span className="task-status running"><i />Running</span>
              <kbd>K</kbd>
            </button>

            <div className="notch-section-label completed-label">COMPLETED</div>

            <button
              type="button"
              className={`notch-task-row completed-row notch-pressable ${
                scene === "return" || scene === "signal" ? "is-highlighted" : ""
              }`}
              onClick={(event) => onOpenTask(isKeyboardActivation(event))}
            >
              <span className="task-number completed-number">3</span>
              <span className="task-copy">
                <strong>Ship Codex Notch {RELEASE.version}</strong>
                <small>Signed, notarized, and published.</small>
              </span>
              <span className="finished-mark"><CheckIcon /></span>
              <kbd>L</kbd>
            </button>

            <button
              type="button"
              className="notch-task-row completed-row notch-pressable"
              onClick={(event) => onNavigate("signal", isKeyboardActivation(event))}
            >
              <span className="task-number completed-number">4</span>
              <span className="task-copy">
                <strong>Study motion frame by frame</strong>
                <small>Motion tuned; reduced motion preserved.</small>
              </span>
              <span className="finished-mark"><CheckIcon /></span>
              <kbd>Ö</kbd>
            </button>
          </div>

          {scene === "personal" ? (
            <div className="notch-theme-preview" aria-label="Preview a notch theme">
              {THEMES.map((item) => (
                <button
                  type="button"
                  key={item.id}
                  className={item.id === theme.id ? "is-selected" : ""}
                  style={{ "--swatch": item.accent } as React.CSSProperties}
                  onPointerEnter={() => {
                    if (canHover()) onThemeChange(item);
                  }}
                  onFocus={(event) => {
                    onThemeChange(item, event.currentTarget.matches(":focus-visible"));
                  }}
                  onClick={(event) => onThemeChange(item, isKeyboardActivation(event))}
                  aria-label={`Preview ${item.name} theme`}
                  aria-pressed={item.id === theme.id}
                >
                  <span />
                </button>
              ))}
            </div>
          ) : null}

          <nav className="notch-story-nav" aria-label="Landing page chapters">
            {STORY_SCENES.map((id, index) => (
              <button
                type="button"
                key={id}
                className={id === currentStoryScene ? "is-active" : ""}
                onClick={(event) => onNavigate(id, isKeyboardActivation(event))}
                aria-label={`Go to chapter ${index + 1}: ${id}`}
                aria-current={id === currentStoryScene ? "step" : undefined}
              >
                <span>{String(index + 1).padStart(2, "0")}</span>
              </button>
            ))}
          </nav>
        </div>

        <button
          type="button"
          className="notch-compact-content notch-pressable"
          aria-hidden={mode !== "compact"}
          tabIndex={mode === "compact" ? 0 : -1}
          onClick={(event) => {
            const immediate = isKeyboardActivation(event);
            if (immediate) {
              document.getElementById("web-notch-trigger")?.focus({ preventScroll: true });
            }
            if (scene === "trust") onNavigate("trust", immediate);
            else onOpenTask(immediate);
          }}
        >
          <span className="compact-icon"><CheckIcon /></span>
          <span className="compact-copy">
            <strong>{compactTitle}</strong>
            <small>{scene === "trust" ? "Remote metadata only" : "Signed and notarized · Just now"}</small>
          </span>
          <span className="compact-hint">Open <span>↗</span></span>
        </button>
      </div>
    </aside>
  );
}
