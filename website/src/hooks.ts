import { useEffect, useState } from "react";
import { STORY_SCENES, type PageScene, type StoryScene } from "./data";

interface StoryPosition {
  scene: PageScene;
  progress: number;
  pageProgress: number;
}

export function useStoryPosition(): StoryPosition {
  const [position, setPosition] = useState<StoryPosition>({
    scene: "hero",
    progress: 0,
    pageProgress: 0,
  });

  useEffect(() => {
    let frame = 0;
    let previousScene: PageScene = "hero";
    let previousProgress = -1;

    const measure = () => {
      frame = 0;
      const viewport = window.innerHeight;
      const hero = document.getElementById("hero");
      const final = document.getElementById("download");
      const pageHeight = Math.max(
        1,
        document.documentElement.scrollHeight - viewport,
      );
      const pageProgress = Math.min(1, Math.max(0, window.scrollY / pageHeight));

      let scene: PageScene = "hero";
      let progress = Math.min(1, Math.max(0, window.scrollY / viewport));

      if (final && final.getBoundingClientRect().top < viewport * 0.62) {
        scene = "final";
        const rect = final.getBoundingClientRect();
        progress = Math.min(1, Math.max(0, (viewport * 0.62 - rect.top) / rect.height));
      } else if (!hero || hero.getBoundingClientRect().bottom < viewport * 0.48) {
        let closest: { id: StoryScene; distance: number; rect: DOMRect } | null = null;
        STORY_SCENES.forEach((id) => {
          const element = document.getElementById(id);
          if (!element) return;
          const rect = element.getBoundingClientRect();
          const distance = Math.abs(rect.top + rect.height * 0.42 - viewport * 0.52);
          if (!closest || distance < closest.distance) {
            closest = { id, distance, rect };
          }
        });
        if (closest) {
          const current = closest as { id: StoryScene; distance: number; rect: DOMRect };
          scene = current.id;
          progress = Math.min(
            1,
            Math.max(0, (viewport * 0.7 - current.rect.top) / (current.rect.height + viewport * 0.25)),
          );
        }
      }

      if (scene !== previousScene || Math.abs(progress - previousProgress) > 0.008) {
        previousScene = scene;
        previousProgress = progress;
        setPosition({ scene, progress, pageProgress });
      }
    };

    const requestMeasure = () => {
      if (!frame) frame = window.requestAnimationFrame(measure);
    };

    measure();
    window.addEventListener("scroll", requestMeasure, { passive: true });
    window.addEventListener("resize", requestMeasure);
    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      window.removeEventListener("scroll", requestMeasure);
      window.removeEventListener("resize", requestMeasure);
    };
  }, []);

  return position;
}

function useMediaQuery(query: string) {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const media = window.matchMedia(query);
    const update = () => setMatches(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, [query]);

  return matches;
}

export function useReducedMotion() {
  return useMediaQuery("(prefers-reduced-motion: reduce)");
}

export function useFinePointer() {
  return useMediaQuery("(hover: hover) and (pointer: fine)");
}

export function useNarrowLayout() {
  return useMediaQuery("(max-width: 640px)");
}

export function useHeaderCollisionLayout() {
  return useMediaQuery("(max-width: 1320px)");
}
