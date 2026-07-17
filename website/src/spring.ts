export interface Spring2DController {
  moveTo: (x: number, y: number) => void;
  stop: () => void;
}

interface Point {
  x: number;
  y: number;
}

interface SpringOptions {
  stiffness?: number;
  damping?: number;
  precision?: number;
}

/**
 * A tiny interruptible 2D spring for pointer-following decoration. Updating the
 * target preserves velocity instead of restarting a CSS easing curve.
 */
export function createSpring2D(
  write: (x: number, y: number) => void,
  initial: Point = { x: 0, y: 0 },
  options: SpringOptions = {},
): Spring2DController {
  const stiffness = options.stiffness ?? 170;
  const damping = options.damping ?? 22;
  const precision = options.precision ?? 0.015;
  let x = initial.x;
  let y = initial.y;
  let targetX = x;
  let targetY = y;
  let velocityX = 0;
  let velocityY = 0;
  let frame = 0;
  let previousTime = 0;

  const tick = (time: number) => {
    const delta = previousTime
      ? Math.min(0.032, Math.max(0.001, (time - previousTime) / 1000))
      : 1 / 60;
    previousTime = time;

    velocityX += (stiffness * (targetX - x) - damping * velocityX) * delta;
    velocityY += (stiffness * (targetY - y) - damping * velocityY) * delta;
    x += velocityX * delta;
    y += velocityY * delta;
    write(x, y);

    const resting =
      Math.abs(targetX - x) < precision &&
      Math.abs(targetY - y) < precision &&
      Math.abs(velocityX) < precision &&
      Math.abs(velocityY) < precision;

    if (resting) {
      x = targetX;
      y = targetY;
      velocityX = 0;
      velocityY = 0;
      frame = 0;
      previousTime = 0;
      write(x, y);
      return;
    }

    frame = window.requestAnimationFrame(tick);
  };

  return {
    moveTo(nextX, nextY) {
      targetX = nextX;
      targetY = nextY;
      if (!frame) frame = window.requestAnimationFrame(tick);
    },
    stop() {
      if (frame) window.cancelAnimationFrame(frame);
      frame = 0;
      previousTime = 0;
    },
  };
}
