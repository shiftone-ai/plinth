(() => {
  const canvas = document.querySelector('#flow');
  const button = document.querySelector('#motion-toggle');
  const context = canvas?.getContext('2d', { alpha: false });
  if (!context || !button) return;

  const drift = document.body.dataset.scene === 'drift';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const pointer = { x: 0, y: 0, active: false };
  const bodies = Array.from({ length: 2 }, () => ({ x: 0, y: 0, vx: 0, vy: 0 }));
  const ripples = [];
  let width = 0;
  let height = 0;
  let time = 0;
  let previousFrame = 0;
  let running = !reducedMotion.matches;
  let manualChoice = null;
  let animationFrame = 0;
  let grain = null;
  let rippleBand = 0;
  let fluxSamples = [];

  function makeGrain() {
    const tile = document.createElement('canvas');
    tile.width = 160;
    tile.height = 160;
    const tileContext = tile.getContext('2d');
    const image = tileContext.createImageData(tile.width, tile.height);
    let seed = 17721;
    for (let index = 0; index < image.data.length; index += 4) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      const value = drift ? 255 : 20;
      image.data[index] = value;
      image.data[index + 1] = value;
      image.data[index + 2] = value;
      image.data[index + 3] = 12 + seed % 44;
    }
    tileContext.putImageData(image, 0, 0);
    return context.createPattern(tile, 'repeat');
  }

  function resize() {
    width = window.innerWidth;
    height = window.innerHeight;
    rippleBand = Math.min(width, height) * .105;
    const sampleCount = width < 640 ? 320 : 440;
    fluxSamples = Array.from({ length: sampleCount + 1 }, (_, step) => {
      const angle = step / sampleCount * Math.PI * 2;
      const cos = Math.cos(angle);
      const sin = Math.sin(angle);
      return {
        cos, sin,
        squareX: Math.sign(cos) * Math.sqrt(Math.abs(cos)),
        squareY: Math.sign(sin) * Math.sqrt(Math.abs(sin)),
        sin3: Math.sin(angle * 3),
        cos3: Math.cos(angle * 3),
      };
    });
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    grain = makeGrain();
    draw();
  }

  function displace(x, y) {
    if (!ripples.length) return [x, y];
    let offsetX = 0;
    let offsetY = 0;
    for (const ripple of ripples) {
      const rippleX = x - ripple.x;
      const rippleY = y - ripple.y;
      const squaredDistance = rippleX * rippleX + rippleY * rippleY;
      if (squaredDistance < ripple.innerSquared || squaredDistance > ripple.outerSquared) continue;
      const rippleDistance = Math.sqrt(squaredDistance);
      if (rippleDistance < 1) continue;
      const position = (rippleDistance - ripple.radius) / rippleBand;
      const envelope = 1 - position * position;
      const force = -ripple.strength * position * envelope * envelope;
      offsetX += rippleX / rippleDistance * force;
      offsetY += rippleY / rippleDistance * force;
    }
    return [x + offsetX, y + offsetY];
  }

  function addRipple(x, y, amplitude) {
    const adjusted = drift ? amplitude : amplitude * .55;
    ripples.push({
      x, y, age: 0, amplitude: adjusted, strength: adjusted,
      radius: 0, innerSquared: 0, outerSquared: rippleBand * rippleBand,
    });
    if (ripples.length > 3) ripples.shift();
  }

  function drawFlux() {
    const scale = Math.min(width, height);
    const centerX = width * (width < 640 ? .52 : .60);
    const centerY = height * (width < 640 ? .5 : .51);
    const extent = scale * (width < 640 ? .53 : .54);
    const rings = width < 640 ? 50 : 74;
    const echo = ripples.reduce((sum, ripple) =>
      sum + ripple.strength * Math.sin(ripple.age * .006) * .008, 0);
    for (let layer = 0; layer < 2; layer++) {
      context.globalAlpha = layer ? .53 : 1;
      const layerX = centerX + bodies[layer].x;
      const layerY = centerY + bodies[layer].y;
      for (let ring = rings - 1; ring >= 0; ring--) {
        const depth = ring / (rings - 1);
        const radius = extent * (.055 + .96 * depth);
        const morph = depth;
        const turn = depth * (layer ? -.19 : .13) + time * .00008 * (layer ? -1 : 1) +
          (layer ? .06 + echo : 0);
        const cosTurn = Math.cos(turn);
        const sinTurn = Math.sin(turn);
        const wavePhase = ring * (layer ? -.085 : .068) + time * .0002;
        const cosWave = Math.cos(wavePhase);
        const sinWave = Math.sin(wavePhase);
        context.beginPath();
        for (let step = 0; step < fluxSamples.length; step++) {
          const sample = fluxSamples[step];
          const wave = (sample.sin3 * cosWave + sample.cos3 * sinWave) * (2 + depth * 8);
          const distance = radius + wave;
          const localX = ((1 - morph) * sample.cos + morph * sample.squareX) * distance;
          const localY = ((1 - morph) * sample.sin + morph * sample.squareY) * distance;
          const x = layerX + localX * cosTurn - localY * sinTurn;
          const y = layerY + localX * sinTurn + localY * cosTurn;
          const [bentX, bentY] = displace(x, y);
          if (step === 0) context.moveTo(bentX, bentY);
          else context.lineTo(bentX, bentY);
        }
        context.closePath();
        context.strokeStyle = layer ? '#2f4860' : ring % 10 === 0 ? '#da593c' : '#172e43';
        context.lineWidth = layer ? .75 : ring % 10 === 0 ? 1.7 : .95;
        context.shadowColor = !layer && ring % 10 === 0 ? 'rgba(218, 89, 60, .3)' : 'transparent';
        context.shadowBlur = !layer && ring % 10 === 0 ? 10 : 0;
        context.stroke();
      }
    }
    context.globalAlpha = 1;
  }

  function drawDrift() {
    // Keep moving layers and click ripples inside an oversized field so their ends stay offscreen.
    const overscan = 192;
    for (let layer = 0; layer < 2; layer++) {
      const lines = layer ? 58 : 78;
      const gap = height / (lines - 1);
      const extraLines = Math.ceil(overscan / gap);
      const shiftX = bodies[layer].x;
      const shiftY = bodies[layer].y;
      context.globalAlpha = layer ? .32 : 1;
      for (let line = -extraLines; line < lines + extraLines; line++) {
        const base = line * gap;
        context.beginPath();
        for (let x = -overscan; x <= width + overscan; x += 8) {
          const focus = Math.exp(-(((x - width * .53) / (width * .37)) ** 2));
          const wave = Math.sin(x * (layer ? .0085 : .009) + line * (layer ? -.17 : .16) +
            time * (layer ? -.0004 : .00048)) * (10 + 50 * focus);
          const fold = Math.sin(line * (layer ? -.11 : .13) - time * .00017) * 28 * focus;
          const [bentX, bentY] = displace(x + shiftX, base + shiftY + wave + fold);
          if (x === -overscan) context.moveTo(bentX, bentY);
          else context.lineTo(bentX, bentY);
        }
        context.strokeStyle = layer ? '#8db7bd' : line % 13 === 0 ? '#e46d51' : '#e7e2d9';
        context.lineWidth = layer ? .7 : line % 13 === 0 ? 2.1 : .95;
        context.shadowColor = !layer && line % 13 === 0 ? 'rgba(228, 109, 81, .5)' : 'transparent';
        context.shadowBlur = !layer && line % 13 === 0 ? 14 : 0;
        context.stroke();
      }
    }
    context.globalAlpha = 1;
  }

  function draw() {
    context.fillStyle = drift ? '#10293d' : '#f2efe7';
    context.fillRect(0, 0, width, height);
    if (drift) drawDrift();
    else drawFlux();
    context.shadowBlur = 0;
    context.shadowColor = 'transparent';
    context.save();
    context.globalAlpha = .48;
    context.fillStyle = grain;
    context.fillRect(0, 0, width, height);
    context.restore();
  }

  function scheduleFrame() {
    if (running && !document.hidden && !animationFrame) {
      animationFrame = window.requestAnimationFrame(tick);
    }
  }

  function moveBodies(elapsed) {
    const seconds = elapsed / 1000;
    const centerX = drift ? width * .5 : width * (width < 640 ? .52 : .60);
    const centerY = drift ? height * .5 : height * (width < 640 ? .5 : .51);
    for (let layer = 0; layer < bodies.length; layer++) {
      const body = bodies[layer];
      let accelerationX = -3.6 * body.x - 2.5 * body.vx;
      let accelerationY = -3.6 * body.y - 2.5 * body.vy;
      if (pointer.active) {
        const towardX = pointer.x - centerX - body.x;
        const towardY = pointer.y - centerY - body.y;
        const distance = Math.hypot(towardX, towardY);
        if (distance > 1) {
          const direction = layer ? -1 : 1;
          const force = 240 * Math.min(1, distance / 260);
          accelerationX += direction * force * towardX / distance;
          accelerationY += direction * force * towardY / distance;
        }
      }
      body.vx += accelerationX * seconds;
      body.vy += accelerationY * seconds;
      body.x += body.vx * seconds;
      body.y += body.vy * seconds;
    }
  }

  function tick(timestamp) {
    animationFrame = 0;
    if (!running || document.hidden) return;
    const elapsed = previousFrame ? Math.min(40, timestamp - previousFrame) : 16.7;
    time += elapsed;
    previousFrame = timestamp;
    moveBodies(elapsed);
    for (let index = ripples.length - 1; index >= 0; index--) {
      ripples[index].age += elapsed;
      ripples[index].strength = ripples[index].amplitude * Math.exp(-ripples[index].age / 850);
      const radius = ripples[index].age * .28;
      ripples[index].radius = radius;
      ripples[index].innerSquared = Math.max(0, radius - rippleBand) ** 2;
      ripples[index].outerSquared = (radius + rippleBand) ** 2;
      const beyondScreen = radius > Math.hypot(width, height) + rippleBand;
      if (ripples[index].strength < .12 || beyondScreen) ripples.splice(index, 1);
    }
    draw();
    scheduleFrame();
  }

  function setRunning(value) {
    if (running === value) return;
    running = value;
    button.textContent = value ? 'Pause' : 'Play';
    button.setAttribute('aria-label', value ? 'Pause animation' : 'Play animation');
    if (value) scheduleFrame();
    else {
      window.cancelAnimationFrame(animationFrame);
      animationFrame = 0;
      previousFrame = 0;
    }
  }

  button.addEventListener('click', () => {
    manualChoice = !running;
    setRunning(manualChoice);
  });
  window.addEventListener('pointermove', event => {
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    pointer.active = true;
  });
  window.addEventListener('pointerdown', event => {
    if (event.target instanceof Element && event.target.closest('button, a')) return;
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    addRipple(event.clientX, event.clientY, 55);
    pointer.active = true;
  });
  document.documentElement.addEventListener('pointerleave', () => { pointer.active = false; });
  window.addEventListener('resize', resize);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      window.cancelAnimationFrame(animationFrame);
      animationFrame = 0;
      previousFrame = 0;
    } else scheduleFrame();
  });
  reducedMotion.addEventListener('change', event => {
    if (manualChoice === null) setRunning(!event.matches);
  });

  resize();
  if (!running) {
    button.textContent = 'Play';
    button.setAttribute('aria-label', 'Play animation');
  } else scheduleFrame();
})();
