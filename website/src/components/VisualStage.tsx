import { useEffect, useRef, type CSSProperties, type PointerEvent } from "react";
import type { NotchTheme, PageScene } from "../data";
import { createSpring2D, type Spring2DController } from "../spring";
import {
  CheckIcon,
  LaptopIcon,
  LockIcon,
  ServerIcon,
  ShieldIcon,
} from "../icons";

interface VisualStageProps {
  scene: PageScene;
  progress: number;
  theme: NotchTheme;
  threadOpening: boolean;
  motionEnabled: boolean;
}

function isActive(scene: PageScene, target: PageScene) {
  return scene === target ? "is-active" : "";
}

export function VisualStage({
  scene,
  progress,
  theme,
  threadOpening,
  motionEnabled,
}: VisualStageProps) {
  const frameRef = useRef<HTMLDivElement>(null);
  const frameSpringRef = useRef<Spring2DController | null>(null);
  const storyScene = scene === "hero" || scene === "final" ? "delegate" : scene;
  const activeStatus =
    storyScene !== "delegate" || progress < 0.36
      ? "Running"
      : progress < 0.7
        ? "Needs approval"
        : "Needs input";

  useEffect(() => {
    const frame = frameRef.current;
    frameSpringRef.current?.stop();
    frameSpringRef.current = null;
    if (!frame || !motionEnabled) {
      if (frame) frame.style.transform = "rotateX(0deg) rotateY(0deg) translate3d(0, 0, 0)";
      return;
    }
    frameSpringRef.current = createSpring2D(
      (x, y) => {
        frame.style.transform = `rotateX(${y}deg) rotateY(${x}deg) translate3d(0, 0, 0)`;
      },
      { x: 0, y: 0 },
      { stiffness: 150, damping: 21 },
    );
    return () => frameSpringRef.current?.stop();
  }, [motionEnabled]);

  const handlePointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!motionEnabled) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    frameSpringRef.current?.moveTo(x * 1.7, y * -1.4);
  };

  const handlePointerLeave = () => {
    frameSpringRef.current?.moveTo(0, 0);
  };

  return (
    <div
      className={`visual-stage visual-${storyScene}`}
      style={
        {
          "--stage-progress": progress,
          "--stage-accent": theme.accent,
          "--stage-secondary": theme.secondary,
        } as CSSProperties
      }
      onPointerMove={handlePointerMove}
      onPointerLeave={handlePointerLeave}
      aria-hidden="true"
    >
      <div className="stage-shadow" />
      <div className="desktop-frame" ref={frameRef}>
        <div className="desktop-glare" />
        <header className="desktop-toolbar">
          <div className="traffic-lights"><i /><i /><i /></div>
          <span className="desktop-path">codex / active workspace</span>
          <span className="desktop-live"><i />LIVE WEB DEMO</span>
        </header>

        <div className="scene-stack">
          <section className={`stage-panel delegate-panel ${isActive(storyScene, "delegate")}`}>
            <div className="editor-window">
              <div className="editor-tabs">
                <span className="is-active">App.tsx</span><span>styles.css</span>
              </div>
              <div className="editor-code">
                <span style={{ "--line": "88%" } as CSSProperties} />
                <span style={{ "--line": "64%" } as CSSProperties} />
                <span style={{ "--line": "76%" } as CSSProperties} />
                <span className="accent-line" style={{ "--line": "52%" } as CSSProperties} />
                <span style={{ "--line": "81%" } as CSSProperties} />
                <span style={{ "--line": "44%" } as CSSProperties} />
              </div>
              <div className="editor-caret" />
            </div>
            <div className="stage-task-card">
              <div className="stage-task-top">
                <span className="task-orb"><i /></span>
                <small>CODEX TASK · THIS MAC</small>
              </div>
              <strong>Build the Codex Notch landing page</strong>
              <div className={`large-status status-${activeStatus.toLowerCase().replace(" ", "-")}`}>
                <i />{activeStatus}
              </div>
              <p>Runtime state from Codex App Server</p>
            </div>
            <div className="delegate-caption">You keep moving. The task keeps working.</div>
          </section>

          <section className={`stage-panel signal-panel ${isActive(storyScene, "signal")}`}>
            <div className="completion-radar">
              <span className="radar-ring ring-one" />
              <span className="radar-ring ring-two" />
              <span className="radar-ring ring-three" />
              <span className="completion-core"><CheckIcon /></span>
            </div>
            <div className="signal-copy">
              <small>TURN COMPLETED · 18:42</small>
              <strong>The useful interruption.</strong>
              <p>One compact signal. Your current window keeps focus.</p>
            </div>
            <div className="focus-token"><span>Keyboard focus</span><strong>stays here</strong></div>
          </section>

          <section className={`stage-panel return-panel ${isActive(storyScene, "return")}`}>
            <div className={`codex-thread-window ${threadOpening ? "is-opening" : ""}`}>
              <div className="thread-sidebar">
                <span className="thread-brand">CODEX</span>
                <i className="thread-item is-active" />
                <i className="thread-item" />
                <i className="thread-item short" />
              </div>
              <div className="thread-content">
                <small>CODEX NOTCH LANDING PAGE</small>
                <h3>Build a motion-led product story</h3>
                <div className="thread-message user-message">Make the product itself the demo.</div>
                <div className="thread-message agent-message">
                  <span><i /> Codex</span>
                  <p>The interactive top edge is now working end to end.</p>
                </div>
                <div className="thread-status"><CheckIcon /> Turn completed</div>
              </div>
            </div>
            <div className={`handoff-line ${threadOpening ? "is-active" : ""}`}>
              <span />
              <em>validated thread handoff</em>
            </div>
          </section>

          <section className={`stage-panel machines-panel ${isActive(storyScene, "machines")}`}>
            <svg className="network-lines" viewBox="0 0 700 410" preserveAspectRatio="none">
              <path d="M125 95 C260 95 245 205 350 205" />
              <path d="M125 315 C260 315 245 205 350 205" />
              <path d="M350 205 C470 205 470 120 585 120" />
              <path d="M350 205 C470 205 470 290 585 290" />
            </svg>
            <div className="network-packets">
              <span className="network-packet packet-one"><i /></span>
              <span className="network-packet packet-two"><i /></span>
              <span className="network-packet packet-three"><i /></span>
              <span className="network-packet packet-four"><i /></span>
            </div>
            <div className="network-node mac-node">
              <LaptopIcon /><span>This Mac</span><small>local</small><i />
            </div>
            <div className="network-node home-node">
              <ServerIcon /><span>Ubuntu home</span><small>Tailscale</small><i />
            </div>
            <div className="network-hub">
              <LockIcon /><strong>Private<br />tailnet</strong>
            </div>
            <div className="network-node notch-node">
              <span className="mini-notch-shape" /><span>Codex Notch</span><small>one calm view</small><i />
            </div>
            <div className="network-node server-node">
              <ServerIcon /><span>Ubuntu server</span><small>Tailscale</small><i />
            </div>
            <div className="network-proof"><ShieldIcon /> authenticated · acknowledged · retried</div>
          </section>

          <section className={`stage-panel usage-panel ${isActive(storyScene, "usage")}`}>
            <div className="usage-dial">
              <div className="usage-ring"><span><strong>68%</strong><small>remaining</small></span></div>
              <p>ACCOUNT-WIDE · SEVEN DAYS</p>
            </div>
            <div className="usage-forecast">
              <small>LOCAL PACE</small>
              <strong>Lasts through reset</strong>
              <div className="usage-chart">
                {[38, 44, 43, 52, 58, 62, 68, 71, 76, 81, 86, 90].map((height, index) => (
                  <i key={index} style={{ "--bar": `${height}%` } as CSSProperties} />
                ))}
                <span className="reset-marker">Tue 08:00</span>
              </div>
              <div className="usage-facts">
                <span><i /> Recent change <b>12% / 18h</b></span>
                <span><i /> Precision <b>whole percent</b></span>
              </div>
            </div>
          </section>

          <section className={`stage-panel trust-panel ${isActive(storyScene, "trust")}`}>
            <div className="privacy-orbit">
              <span className="rejected-data rejected-one">prompt <i>×</i></span>
              <span className="rejected-data rejected-two">transcript <i>×</i></span>
              <span className="rejected-data rejected-three">Codex credentials <i>×</i></span>
              <span className="rejected-data rejected-four">model output <i>×</i></span>
              <div className="signal-packet">
                <ShieldIcon />
                <small>RETURN SIGNAL</small>
                <strong>Landing page finished</strong>
                <div className="packet-fields">
                  <span>thread ID</span><span>turn ID</span><span>source</span><span>state</span><span>timestamp</span>
                </div>
              </div>
            </div>
            <p className="privacy-caption">Task metadata only · authenticated by a per-host pairing token.</p>
          </section>

          <section className={`stage-panel personal-panel ${isActive(storyScene, "personal")}`}>
            <div className="theme-aura">
              <span className="theme-aura-ring" />
              <span className="theme-aura-core"><i /></span>
              <strong>{theme.name}</strong>
              <small>{theme.mood}</small>
            </div>
            <div className="preference-stack">
              <div className="preference-row"><span>Completion sound</span><strong>Glass Drop <i className="waveform" /></strong></div>
              <div className="preference-row"><span>Do Not Disturb</span><strong className="toggle is-on"><i /></strong></div>
              <div className="preference-row"><span>Show active tasks</span><strong className="toggle is-on"><i /></strong></div>
              <div className="preference-row"><span>Reduce Motion</span><strong>Supported</strong></div>
            </div>
          </section>
        </div>

        <div className="desktop-footer">
          <span>SCENE {String(Math.max(1, ["delegate", "signal", "return", "machines", "usage", "trust", "personal"].indexOf(storyScene) + 1)).padStart(2, "0")}</span>
          <div><i style={{ transform: `scaleX(${Math.max(0.04, progress)})` }} /></div>
          <span>SCROLL TO DRIVE</span>
        </div>
      </div>
    </div>
  );
}
