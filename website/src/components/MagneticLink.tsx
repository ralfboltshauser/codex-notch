import { useEffect, useRef, type AnchorHTMLAttributes, type PointerEvent } from "react";
import { createSpring2D, type Spring2DController } from "../spring";

interface MagneticLinkProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  strength?: number;
}

export function MagneticLink({
  children,
  className = "",
  strength = 0.16,
  onPointerMove,
  onPointerLeave,
  ...props
}: MagneticLinkProps) {
  const linkRef = useRef<HTMLAnchorElement>(null);
  const springRef = useRef<Spring2DController | null>(null);

  useEffect(() => {
    const link = linkRef.current;
    if (!link) return;
    springRef.current = createSpring2D((x, y) => {
      link.style.transform = `translate3d(${x}px, ${y}px, 0)`;
    });
    return () => springRef.current?.stop();
  }, []);

  const handleMove = (event: PointerEvent<HTMLAnchorElement>) => {
    if (
      window.matchMedia("(hover: hover) and (pointer: fine)").matches &&
      !window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      const rect = event.currentTarget.getBoundingClientRect();
      const x = (event.clientX - rect.left - rect.width / 2) * strength;
      const y = (event.clientY - rect.top - rect.height / 2) * strength;
      springRef.current?.moveTo(x, y);
    }
    onPointerMove?.(event);
  };

  const handleLeave = (event: PointerEvent<HTMLAnchorElement>) => {
    springRef.current?.moveTo(0, 0);
    onPointerLeave?.(event);
  };

  return (
    <a
      ref={linkRef}
      className={`magnetic-link ${className}`}
      onPointerMove={handleMove}
      onPointerLeave={handleLeave}
      {...props}
    >
      {children}
    </a>
  );
}
