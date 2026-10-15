/// DOM input for an independently rendered external Web viewport.
/// Each document owns its transient input state; replacing a Web surface discards it.
enum ExternalWebInputScript {
  static let control = #"""
    const key = '__plinthExternalInput';
    const state = window[key] ||= {hover: null, down: null, drag: null, x: 0, y: 0, lastX: 0.5, lastY: 0.5};
    if (action === 'scroll' || action === 'cancel') { x = state.lastX; y = state.lastY; }
    else { state.lastX = x; state.lastY = y; }
    const px = Math.min(innerWidth - 1, Math.max(0, (x || 0) * innerWidth));
    const py = Math.min(innerHeight - 1, Math.max(0, (y || 0) * innerHeight));
    const target = document.elementFromPoint(px, py);
    const mouse = (node, type, buttons, extra = {}) => node?.dispatchEvent(new MouseEvent(type, {
      bubbles: true, cancelable: true, clientX: px, clientY: py, button: 0, buttons, ...extra
    }));
    const pointer = (node, type, buttons) => node?.dispatchEvent(new PointerEvent(type, {
      bubbles: true, cancelable: true, clientX: px, clientY: py, button: 0, buttons,
      pointerType: 'mouse', pointerId: 2147483646, isPrimary: true
    }));
    // Only the virtual pointer uses this capture; native pointer IDs retain the browser implementation.
    if (!state.captureInstalled) {
      state.captureInstalled = true;
      const proto = Element.prototype;
      const nativeSet = proto.setPointerCapture, nativeRelease = proto.releasePointerCapture, nativeHas = proto.hasPointerCapture;
      proto.setPointerCapture = function(id) {
        if (id !== 2147483646) return nativeSet.call(this, id);
        if (!state.down) throw new DOMException('No active pointer', 'NotFoundError');
        state.capture = this;
        pointer(this, 'gotpointercapture', 1);
      };
      proto.releasePointerCapture = function(id) {
        if (id !== 2147483646) return nativeRelease.call(this, id);
        if (state.capture === this) { state.capture = null; pointer(this, 'lostpointercapture', 0); }
      };
      proto.hasPointerCapture = function(id) { return id === 2147483646 ? state.capture === this : nativeHas.call(this, id); };
    }
    const drag = (node, type) => node?.dispatchEvent(new DragEvent(type, {
      bubbles: true, cancelable: true, clientX: px, clientY: py, dataTransfer: state.transfer
    }));
    // Match the page's hover selectors without editing its original stylesheet.
    // The same attribute specificity as :hover preserves selector precedence.
    if (!state.style) {
      state.style = document.createElement('style');
      state.style.dataset.plinthInput = '';
      document.documentElement.append(state.style);
      state.sheets = new WeakSet();
    }
    const rules = list => [...list].map(rule => {
      if (rule.selectorText?.includes(':hover')) {
        return rule.selectorText.replaceAll(':hover', '[data-plinth-hover]') + '{' + rule.style.cssText + '}';
      }
      if (rule.cssRules) {
        const inner = rules(rule.cssRules);
        return inner ? rule.cssText.slice(0, rule.cssText.indexOf('{') + 1) + inner + '}' : '';
      }
      return '';
    }).join('');
    for (const sheet of document.styleSheets) {
      if (sheet.ownerNode === state.style || state.sheets.has(sheet)) continue;
      try { state.style.textContent += rules(sheet.cssRules); state.sheets.add(sheet); } catch {}
    }
    if (state.hover !== target) {
      pointer(state.hover, 'pointerout', state.down ? 1 : 0);
      mouse(state.hover, 'mouseout', state.down ? 1 : 0, {relatedTarget: target});
      for (let node = state.hover; node && !node.contains(target); node = node.parentElement) {
        node.dispatchEvent(new MouseEvent('mouseleave', {clientX: px, clientY: py, relatedTarget: target}));
        node.dispatchEvent(new PointerEvent('pointerleave', {clientX: px, clientY: py, pointerId: 2147483646, pointerType: 'mouse'}));
      }
      for (const node of document.querySelectorAll('[data-plinth-hover]')) node.removeAttribute('data-plinth-hover');
      for (let node = target; node; node = node.parentElement) node.setAttribute('data-plinth-hover', '');
      mouse(target, 'mouseover', state.down ? 1 : 0, {relatedTarget: state.hover});
      pointer(target, 'pointerover', state.down ? 1 : 0);
      for (let node = target; node && !node.contains(state.hover); node = node.parentElement) {
        node.dispatchEvent(new MouseEvent('mouseenter', {clientX: px, clientY: py}));
        node.dispatchEvent(new PointerEvent('pointerenter', {clientX: px, clientY: py, pointerId: 2147483646, pointerType: 'mouse'}));
      }
      state.hover = target;
    }
    if (action === 'scroll') {
      let node = state.hover;
      while (node && node !== document.documentElement) {
        const style = getComputedStyle(node);
        if (/(auto|scroll)/.test(style.overflow + style.overflowX + style.overflowY)
          && (node.scrollHeight > node.clientHeight || node.scrollWidth > node.clientWidth)) {
          node.scrollBy({left: dx, top: dy, behavior: 'instant'});
          return;
        }
        node = node.parentElement;
      }
      window.scrollBy({left: dx, top: dy, behavior: 'instant'});
      return;
    }
    if (action === 'cancel') {
      pointer(state.capture || state.down, 'pointercancel', 0);
      mouse(state.down, 'mouseup', 0);
      if (state.drag) drag(state.drag, 'dragend');
      if (state.capture) { const captured = state.capture; state.capture = null; pointer(captured, 'lostpointercapture', 0); }
      state.down = null; state.drag = null; state.drop = null; state.transfer = null;
      return;
    }
    if (!target) return;
    if (action === 'activate') {
      const control = target.closest('a,button,input,select,textarea,[role="button"]') || target;
      if (control.matches('input,select,textarea')) control.focus();
      control.click();
    } else if (action === 'press') {
      state.down = target; state.x = px; state.y = py; state.drag = null;
      pointer(target, 'pointerdown', 1); mouse(target, 'mousedown', 1);
      if (target.matches('input,select,textarea')) target.focus();
    } else if (action === 'move') {
      pointer(state.capture || target, 'pointermove', state.down ? 1 : 0);
      mouse(state.down || target, 'mousemove', state.down ? 1 : 0);
      if (state.down && Math.hypot(px - state.x, py - state.y) > 3) {
        const source = state.down.closest('[draggable="true"],a[href],img');
        if (!state.drag && source) {
          state.transfer = new DataTransfer();
          state.transfer.setData('text/plain', source.href || source.src || source.textContent);
          state.drag = source;
          if (!drag(source, 'dragstart')) state.drag = null;
        }
        if (state.drag) {
          drag(state.drag, 'drag');
          if (state.drop !== target) {
            drag(state.drop, 'dragleave'); drag(target, 'dragenter'); state.drop = target;
          }
          state.acceptsDrop = !drag(target, 'dragover');
        }
      }
    } else if (action === 'release') {
      pointer(state.capture || target, 'pointerup', 0); mouse(state.down || target, 'mouseup', 0);
      if (state.drag) {
        if (state.acceptsDrop) drag(target, 'drop');
        drag(state.drag, 'dragend');
      } else if (state.down && Math.hypot(px - state.x, py - state.y) <= 3) {
        const control = state.down.closest('a,button,input,select,textarea,[role="button"]') || state.down;
        control.click();
      }
      if (state.capture) { const captured = state.capture; state.capture = null; pointer(captured, 'lostpointercapture', 0); }
      state.down = null; state.drag = null; state.drop = null; state.transfer = null;
    }
    """#
}
