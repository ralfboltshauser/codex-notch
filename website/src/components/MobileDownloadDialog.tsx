import { useEffect, useRef, useState } from "react";
import { RELEASE } from "../data";
import { ArrowDownIcon, ArrowUpRightIcon, CheckIcon, CloseIcon } from "../icons";

interface MobileDownloadDialogProps {
  open: boolean;
  onClose: () => void;
}

export function MobileDownloadDialog({ open, onClose }: MobileDownloadDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [feedback, setFeedback] = useState("");

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      setFeedback("");
      dialog.showModal();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const root = document.documentElement;
    const body = document.body;
    const previousRootOverflow = root.style.overflow;
    const previousBodyOverflow = body.style.overflow;
    root.style.overflow = "hidden";
    body.style.overflow = "hidden";
    return () => {
      root.style.overflow = previousRootOverflow;
      body.style.overflow = previousBodyOverflow;
    };
  }, [open]);

  const sharePage = async () => {
    const pageURL = window.location.href;
    try {
      if (navigator.share) {
        await navigator.share({ title: "Codex Notch", url: pageURL });
        setFeedback("Page shared.");
      } else {
        await navigator.clipboard.writeText(pageURL);
        setFeedback("Page link copied.");
      }
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
      setFeedback("Couldn’t share automatically. Open the release page instead.");
    }
  };

  return (
    <dialog
      className="mobile-download-dialog"
      ref={dialogRef}
      aria-labelledby="mobile-download-title"
      aria-describedby="mobile-download-description"
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) event.currentTarget.close();
      }}
    >
      <div className="mobile-download-sheet">
        <button className="download-sheet-close" type="button" onClick={() => dialogRef.current?.close()} aria-label="Close download options">
          <CloseIcon />
        </button>
        <div className="download-sheet-mark"><span><i /></span></div>
        <div className="download-sheet-copy">
          <small>MAC APP · APPLE SILICON</small>
          <h2 id="mobile-download-title">Codex Notch lives on your Mac.</h2>
          <p id="mobile-download-description">Share this page with your Mac, inspect the signed release, or keep downloading the ZIP here.</p>
        </div>
        <button className="download-sheet-share" type="button" onClick={sharePage} autoFocus>
          Share this page <span>↗</span>
        </button>
        <a className="download-sheet-release" href={RELEASE.release} target="_blank" rel="noreferrer">
          View GitHub release <ArrowUpRightIcon />
        </a>
        <a className="download-sheet-anyway" href={RELEASE.download}>
          <ArrowDownIcon /> Download anyway
        </a>
        <p className="download-sheet-feedback" role="status">
          {feedback ? <><CheckIcon />{feedback}</> : "No email. No tracking handoff."}
        </p>
      </div>
    </dialog>
  );
}
