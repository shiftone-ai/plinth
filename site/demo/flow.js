(() => {
  const canvas = document.querySelector('#flow');
  const button = document.querySelector('#motion-toggle');
  const context = canvas?.getContext('2d', { alpha: false });
  if (!context || !button) return;

  const drift = document.body.dataset.scene === 'drift';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const pointer = { x: 0, y: 0, targetX: 0, targetY: 0, active: false, strength: 0 };
  let width = 0;
  let height = 0;
  let time = 0;
  let previousFrame = 0;
  let running = !reducedMotion.matches;
  let manualChoice = null;
  let animationFrame = 0;
  let grain = null;
  let glow = null;

  function makeGlow() {
    const layer = document.createElement('canvas');
    layer.width = width;
    layer.height = height;
    const layerContext = layer.getContext('2d');
    const scale = Math.min(width, height);
    layerContext.filter = `blur(${Math.round(scale * .12)}px)`;
    layerContext.globalAlpha = drift ? .32 : .19;
    layerContext.fillStyle = drift ? '#db6849' : '#e29a6f';
    layerContext.beginPath();
    layerContext.ellipse(width * .57, height * .47, scale * .31, scale * .24, -.4, 0, Math.PI * 2);
    layerContext.fill();
    return layer;
  }

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
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    glow = makeGlow();
    grain = makeGrain();
    draw();
  }

  function repel(x, y) {
    if (pointer.strength < .01) return [x, y];
    const dx = x - pointer.x;
    const dy = y - pointer.y;
    const distance = Math.hypot(dx, dy);
    const reach = Math.min(width, height) * .34;
    if (distance >= reach || distance < 1) return [x, y];
    const force = 56 * pointer.strength * (1 - distance / reach) ** 2;
    return [x + dx / distance * force, y + dy / distance * force];
  }

  function drawFlux() {
    const scale = Math.min(width, height);
    const centerX = width * (width < 640 ? .52 : .60);
    const centerY = height * (width < 640 ? .43 : .51);
    const extent = scale * (width < 640 ? .43 : .59);
    const rings = width < 640 ? 48 : 72;
    for (let ring = rings - 1; ring >= 0; ring--) {
      const depth = ring / (rings - 1);
      const radius = extent * (.075 + .93 * depth);
      const phase = ring * .035 + time * .0004;
      context.beginPath();
      for (let step = 0; step <= 260; step++) {
        const angle = step / 260 * Math.PI * 2;
        const wave = (
          Math.sin(angle * 6 + phase) * 12 +
          Math.sin(angle * 11 - ring * .025 - time * .00027) * 5
        ) * (.25 + depth * .75);
        const distance = radius + wave;
        const x = centerX + Math.cos(angle) * distance * 1.08;
        const y = centerY + Math.sin(angle) * distance * .88;
        const [bentX, bentY] = repel(x, y);
        if (step === 0) context.moveTo(bentX, bentY);
        else context.lineTo(bentX, bentY);
      }
      context.closePath();
      context.strokeStyle = ring % 11 === 0 ? '#da593c' : '#172e43';
      context.lineWidth = ring % 11 === 0 ? 2.3 : 1.1;
      context.stroke();
    }
  }

  function drawDrift() {
    const lines = 78;
    const gap = height / (lines - 1);
    for (let line = 0; line < lines; line++) {
      const base = line * gap;
      context.beginPath();
      for (let x = -12; x <= width + 12; x += 8) {
        const focus = Math.exp(-(((x - width * .53) / (width * .37)) ** 2));
        const wave = Math.sin(x * .009 + line * .16 + time * .00048) * (10 + 50 * focus);
        const fold = Math.sin(line * .13 - time * .00017) * 28 * focus;
        const [bentX, bentY] = repel(x, base + wave + fold);
        if (x === -12) context.moveTo(bentX, bentY);
        else context.lineTo(bentX, bentY);
      }
      context.strokeStyle = line % 13 === 0 ? '#e46d51' : '#e7e2d9';
      context.lineWidth = line % 13 === 0 ? 2.1 : .95;
      context.stroke();
    }
  }

  function draw() {
    context.fillStyle = drift ? '#10293d' : '#f2efe7';
    context.fillRect(0, 0, width, height);
    context.drawImage(glow, 0, 0);
    if (drift) drawDrift();
    else drawFlux();
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

  function tick(timestamp) {
    animationFrame = 0;
    if (!running || document.hidden) return;
    if (previousFrame) time += Math.min(40, timestamp - previousFrame);
    previousFrame = timestamp;
    pointer.x += (pointer.targetX - pointer.x) * .075;
    pointer.y += (pointer.targetY - pointer.y) * .075;
    pointer.strength += ((pointer.active ? 1 : 0) - pointer.strength) * .08;
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
    pointer.targetX = event.clientX;
    pointer.targetY = event.clientY;
    if (!pointer.active) {
      pointer.x = pointer.targetX;
      pointer.y = pointer.targetY;
    }
    pointer.active = true;
  });
  window.addEventListener('pointerdown', event => {
    pointer.targetX = event.clientX;
    pointer.targetY = event.clientY;
    if (!pointer.active) {
      pointer.x = pointer.targetX;
      pointer.y = pointer.targetY;
    }
    pointer.active = true;
  });
  window.addEventListener('pointerleave', () => { pointer.active = false; });
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
