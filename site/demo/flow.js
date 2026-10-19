(() => {
  const canvas = document.querySelector('#flow');
  const button = document.querySelector('#motion-toggle');
  const context = canvas?.getContext('2d', { alpha: true });
  if (!context || !button) return;

  const drift = document.body.dataset.scene === 'drift';
  const colors = drift
    ? ['111,211,215', '173,166,235', '245,165,126', '230,236,255']
    : ['115,204,239', '248,184,120', '255,220,164', '236,226,205'];
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const pointer = { x: 0, y: 0, active: false, pulse: 0 };
  let width = 0;
  let height = 0;
  let particles = [];
  let frame = 0;
  let running = !reducedMotion.matches;
  let animationFrame = 0;
  let randomState = drift ? 84931 : 21017;

  function random() {
    randomState = (randomState * 1664525 + 1013904223) >>> 0;
    return randomState / 4294967296;
  }

  function particle() {
    return {
      x: random() * width,
      y: random() * height,
      life: 80 + random() * 240,
      color: colors[Math.floor(random() * colors.length)],
      weight: .8 + random() * 1.5
    };
  }

  function resize() {
    width = window.innerWidth;
    height = window.innerHeight;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    randomState = drift ? 84931 : 21017;
    particles = Array.from({ length: Math.min(1050, Math.max(480, Math.floor(width * height / 1100))) }, particle);
    frame = 0;
    context.clearRect(0, 0, width, height);
    for (let i = 0; i < 280; i++) draw(false);
  }

  function direction(x, y) {
    const time = frame * .003;
    if (drift) {
      const ribbon = Math.sin(x * .0044 + time) * .9 + Math.cos(y * .006 - time * .5) * .55;
      return -.25 + ribbon + Math.atan2(y - height * .47, x - width * .61) * .17;
    }
    const dx = x - width * .53;
    const dy = y - height * .43;
    const swirl = Math.atan2(dy, dx) + Math.PI * .5;
    return swirl + Math.sin(x * .006 + time) * .35 + Math.cos(y * .008 - time) * .27;
  }

  function draw(fade = true) {
    frame++;
    if (fade) {
      context.globalCompositeOperation = 'source-over';
      context.fillStyle = drift ? 'rgba(7,21,37,.012)' : 'rgba(7,21,37,.01)';
      context.fillRect(0, 0, width, height);
    }
    context.globalCompositeOperation = 'screen';
    for (let index = 0; index < particles.length; index++) {
      const point = particles[index];
      const angle = direction(point.x, point.y);
      const distance = Math.hypot(point.x - pointer.x, point.y - pointer.y);
      const influence = pointer.active ? Math.max(0, 1 - distance / Math.min(420, width * .38)) : 0;
      const bend = influence * (1.1 + pointer.pulse * .9);
      const speed = point.weight * (1.25 + influence * 2.3);
      const nextX = point.x + Math.cos(angle + bend) * speed;
      const nextY = point.y + Math.sin(angle + bend) * speed;
      context.strokeStyle = `rgba(${point.color},${.42 + influence * .38})`;
      context.lineWidth = point.weight;
      context.beginPath();
      context.moveTo(point.x, point.y);
      context.lineTo(nextX, nextY);
      context.stroke();
      if (index % 23 === 0 && frame % 3 === 0) {
        context.fillStyle = `rgba(${point.color},.7)`;
        context.beginPath();
        context.arc(nextX, nextY, point.weight * 1.25, 0, Math.PI * 2);
        context.fill();
      }
      point.x = nextX;
      point.y = nextY;
      point.life--;
      if (point.life <= 0 || point.x < -20 || point.x > width + 20 || point.y < -20 || point.y > height + 20) {
        particles[index] = particle();
      }
    }
    pointer.pulse *= .95;
  }

  function tick() {
    if (!running) return;
    draw();
    animationFrame = window.requestAnimationFrame(tick);
  }

  function setRunning(value) {
    if (running === value) return;
    running = value;
    button.textContent = value ? 'Pause' : 'Play';
    button.setAttribute('aria-label', value ? 'Pause animation' : 'Play animation');
    if (value) tick();
    else window.cancelAnimationFrame(animationFrame);
  }

  button.addEventListener('click', () => setRunning(!running));
  window.addEventListener('pointermove', event => {
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    pointer.active = true;
  });
  window.addEventListener('pointerdown', event => {
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    pointer.active = true;
    pointer.pulse = 1;
  });
  window.addEventListener('pointerleave', () => { pointer.active = false; });
  window.addEventListener('resize', resize);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) window.cancelAnimationFrame(animationFrame);
    else if (running) tick();
  });
  reducedMotion.addEventListener('change', event => setRunning(!event.matches));

  resize();
  if (!running) {
    button.textContent = 'Play';
    button.setAttribute('aria-label', 'Play animation');
  } else tick();
})();
