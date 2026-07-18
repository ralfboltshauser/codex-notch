import { LATEST_RELEASE, RELEASE } from "../data";
import { FEATURE_FACTS, LANDING_FAQS, PROOF_POINTS } from "../landingContent";
import { ArrowUpRightIcon, CheckIcon } from "../icons";

export function ProofRail() {
  return (
    <nav className="proof-rail" aria-label="Explore Codex Notch outcomes">
      {PROOF_POINTS.map((point, index) => (
        <a href={point.target} key={point.label}>
          <span>{String(index + 1).padStart(2, "0")} · {point.label}</span>
          <strong>{point.value}</strong>
          <i>↘</i>
        </a>
      ))}
    </nav>
  );
}

export function ProductFacts() {
  return (
    <section className="product-facts" id="facts" aria-labelledby="facts-title">
      <div className="facts-heading">
        <div className="section-kicker"><span />WHAT EARNS ITS PLACE</div>
        <h2 id="facts-title">The signal stays small.<br />The model stays clear.</h2>
        <p>
          Codex Notch is deliberately narrower than an agent dashboard. Every
          visible detail should help you decide whether to stay, inspect, or return.
        </p>
      </div>
      <div className="fact-grid">
        {FEATURE_FACTS.map((fact) => (
          <article className={fact.accent ? "is-accent" : ""} key={fact.number}>
            <div><span>{fact.number}</span><small>{fact.eyebrow}</small></div>
            <h3>{fact.title}</h3>
            <p>{fact.body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

export function LatestRelease() {
  const visibleChanges = LATEST_RELEASE.changes.slice(0, 3);
  return (
    <section className="release-proof" aria-labelledby="release-proof-title">
      <div className="release-proof-heading">
        <span>NOW SHIPPING</span>
        <h2 id="release-proof-title">v{RELEASE.version} · {LATEST_RELEASE.title}</h2>
        <small>Build {RELEASE.build} · {LATEST_RELEASE.date}</small>
      </div>
      <ul>
        {visibleChanges.map((change) => <li key={change}><CheckIcon />{change}</li>)}
      </ul>
      <a href={RELEASE.release} target="_blank" rel="noreferrer">
        Read the release notes <ArrowUpRightIcon />
      </a>
    </section>
  );
}

export function FAQSection() {
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: LANDING_FAQS.map((item) => ({
      "@type": "Question",
      name: item.question,
      acceptedAnswer: { "@type": "Answer", text: item.answer },
    })),
  };

  return (
    <section className="faq-section" id="faq" aria-labelledby="faq-title">
      <script type="application/ld+json">{JSON.stringify(structuredData)}</script>
      <div className="faq-heading">
        <div className="section-kicker"><span />BEFORE YOU INSTALL</div>
        <h2 id="faq-title">The obvious questions,<br />answered plainly.</h2>
        <p>No feature-count theater. These answers are tied to the current implementation.</p>
      </div>
      <div className="faq-list">
        {LANDING_FAQS.map((item, index) => (
          <details key={item.question} name="codex-notch-faq">
            <summary>
              <span>{String(index + 1).padStart(2, "0")}</span>
              <strong>{item.question}</strong>
              <i aria-hidden="true" />
            </summary>
            <p>{item.answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
