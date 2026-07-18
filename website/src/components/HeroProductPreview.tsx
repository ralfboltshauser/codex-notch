import { CheckIcon } from "../icons";
import { RELEASE } from "../data";

export function HeroProductPreview({ onExplore }: { onExplore: () => void }) {
  return (
    <figure
      className="hero-product"
      aria-labelledby="hero-product-caption"
      aria-describedby="hero-product-description"
    >
      <div className="hero-product-frame" aria-hidden="true">
        <div className="hero-product-menubar">
          <span><i />Codex Notch</span>
          <span>Fri 23:09</span>
        </div>

        <div className="hero-product-desktop">
          <div className="hero-context-window context-left">
            <div><i /><i /><i /><span>Codex</span></div>
            <strong>Improve the landing page</strong>
            <p>Compare the product story to what people can verify.</p>
            <span className="context-caret" />
          </div>
          <div className="hero-context-window context-right">
            <div><i /><i /><i /><span>Release</span></div>
            <small>v{RELEASE.version}</small>
            <strong>Signed · notarized · published</strong>
          </div>

          <div className="hero-notch-card">
            <div className="hero-notch-hardware"><span /></div>
            <header>
              <div className="preview-brand"><CheckIcon /><strong>Codex</strong></div>
              <div className="preview-usage"><span><b>5h</b> reached</span><span><b>7d</b> 54%</span></div>
              <div className="preview-attention"><i />2</div>
              <div className="preview-mode">Glance</div>
            </header>

            <div className="preview-section-label"><span>ACTIVE</span><span>2 ROOT TASKS</span></div>
            <div className="preview-task-row preview-task-primary">
              <span className="preview-number">1</span>
              <span className="preview-task-copy">
                <strong>Improve the Codex Notch landing page</strong>
                <small>codex-notch · codex/vibe-site-learnings · 2 subagents</small>
              </span>
              <span className="preview-status needs-input"><i />Needs input</span>
            </div>
            <div className="preview-task-row preview-task-secondary">
              <span className="preview-number">2</span>
              <span className="preview-task-copy">
                <strong>Verify remote delivery</strong>
                <small>Ubuntu home · main</small>
              </span>
              <span className="preview-status running"><i />Running</span>
            </div>

            <div className="preview-section-label preview-completed-label"><span>COMPLETED</span><span>LOCAL OUTCOME</span></div>
            <div className="preview-task-row preview-completed-row">
              <span className="preview-number preview-number-done"><CheckIcon /></span>
              <span className="preview-task-copy">
                <strong>Ship the attention workflow</strong>
                <small>Signed, notarized, and published.</small>
              </span>
              <span className="preview-time">Just now</span>
            </div>
          </div>

          <div className="hero-glance-pill"><span>2</span><small>inspectable signals</small></div>
        </div>
      </div>

      <figcaption>
        <span id="hero-product-caption"><i />Web simulation of the v{RELEASE.version} task surface</span>
        <button type="button" onClick={onExplore}>Explore the interactive demo <b>↓</b></button>
      </figcaption>
      <p className="sr-only" id="hero-product-description">
        The open notch shows a reached five-hour usage window, a 54 percent
        seven-day reading, two root tasks, one task needing input with project,
        branch, and two subagents, one running Ubuntu task, and one completed
        task with a bounded local outcome.
      </p>
    </figure>
  );
}
