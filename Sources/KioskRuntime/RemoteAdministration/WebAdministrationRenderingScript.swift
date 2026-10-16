let webAdministrationRenderingScript = #"""
  const form = document.querySelector('#login-form');
  const message = document.querySelector('#message');
  const details = document.querySelector('#details');
  const password = document.querySelector('#password');
  const editor = document.querySelector('#editor');
  const exhibitionActions = document.querySelector('#exhibition-actions');
  const settingsForm = document.querySelector('#settings-form');
  const validation = document.querySelector('#validation');
  const pendingFields = new Map();
  let sessionToken = null;
  let currentState = null;
  let pendingMutation = Promise.resolve();
  let mutationFailed = false;
  let connectionLost = false;
  let saveOutcomeUnknown = false;

  function setText(id, value) {
    document.getElementById(id).textContent = value ?? '—';
  }
  function editing(field, input) {
    return document.activeElement === input || (pendingFields.get(field) ?? 0) > 0;
  }
  function setValue(id, field, value) {
    const input = document.querySelector(id);
    if (!editing(field, input)) input.value = value;
  }
  function setChecked(id, field, value) {
    const input = document.querySelector(id);
    if (!editing(field, input)) input.checked = value;
  }
  function yesNo(value) {
    return value ? document.body.dataset.yes : document.body.dataset.no;
  }
  function localValue(value) {
    if (!value) return null;
    const key = value.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`);
    return document.body.dataset[key.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())]
      ?? value;
  }
  function ruleAddress(rule) {
    const origin = rule.origin;
    const wildcard = rule.includeSubdomains ? '*.' : '';
    const host = origin.host.includes(':') ? `[${origin.host}]` : origin.host;
    const defaultPort = origin.scheme === 'https' ? 443 : 80;
    const port = origin.port === defaultPort ? '' : `:${origin.port}`;
    const scheme = origin.scheme === 'https' ? '' : `${origin.scheme}://`;
    return `${scheme}${wildcard}${host}${port}`;
  }
  function render(state) {
    currentState = state;
    const profile = state.savedProfile;
    details.hidden = false;
    form.hidden = true;
    setText('mode', localValue(state.mode));
    if (profile) {
      setText('start-url', profile.startURL);
      setText('navigation', localValue(profile.navigation.mode));
      setText('domains', (profile.navigation.rules || []).map(ruleAddress).join(', '));
      setText('http', yesNo(profile.navigation.allowsHTTP));
      setText('scroll', yesNo(profile.interaction.allowsScroll));
      setText('drag', yesNo(profile.interaction.allowsDrag));
      setText('idle', profile.idleTimeout);
      setText('reset', localValue(profile.resetMode));
      setText('destination', localValue(profile.exhibitionDestination ?? 'device'));
      const resolution = profile.externalDisplayMode;
      setText('resolution', resolution ? `${resolution.width} × ${resolution.height}` : null);
      setText('rotation', profile.externalDisplayRotation);
      setText('mac-output', localValue(profile.macOutput?.mode ?? 'fixedFullscreen'));
      const selectedDisplay = state.macDisplays?.find(item => item.id === profile.macOutput?.displayID);
      setText('mac-display', profile.macOutput?.displayID
        ? selectedDisplay?.name ?? document.body.dataset.disconnectedDisplay
        : document.body.dataset.automatic);
    }
    const macOutput = Array.isArray(state.macDisplays);
    const mobileOutput = state.mobileOutputAvailable;
    document.querySelector('#saved-destination').hidden = !mobileOutput;
    document.querySelector('#saved-resolution').hidden =
      !mobileOutput || profile?.exhibitionDestination !== 'externalDisplay';
    document.querySelector('#saved-rotation').hidden =
      !mobileOutput || profile?.exhibitionDestination !== 'externalDisplay';
    document.querySelector('#saved-mac-output').hidden = !macOutput;
    document.querySelector('#saved-mac-display').hidden =
      !macOutput || profile?.macOutput?.mode === 'projectionWindow';
    editor.hidden = !['administration', 'exhibiting', 'paused', 'safeHold']
      .includes(state.mode) || !state.draft;
    exhibitionActions.hidden = !profile;
    document.querySelector('#start-exhibition').hidden = state.mode !== 'administration';
    document.querySelector('#restart-exhibition').hidden =
      !['exhibiting', 'unlocking', 'enteringKiosk', 'leavingKiosk', 'safeHold']
        .includes(state.mode);
    document.querySelector('#stop-exhibition').hidden = state.mode !== 'exhibiting';
    document.querySelector('#resume-exhibition').hidden =
      !['paused', 'safeHold', 'unlocking'].includes(state.mode);
    if (!editor.hidden) {
      const draft = state.draft;
      setValue('#edit-start-url', 'startURL', draft.profile.startURL);
      setValue('#edit-navigation', 'navigationMode', draft.profile.navigation.mode);
      setChecked('#edit-http', 'allowsHTTP', draft.profile.navigation.allowsHTTP);
      setChecked('#edit-scroll', 'allowsScroll', draft.profile.interaction.allowsScroll);
      setChecked('#edit-drag', 'allowsDrag', draft.profile.interaction.allowsDrag);
      setValue('#edit-idle', 'idleTimeoutText', draft.idleTimeoutText);
      setValue('#edit-reset', 'resetMode', draft.profile.resetMode);
      renderRules(draft.rules || []);
      renderOutput(state, draft);
      validation.replaceChildren();
      const labels = {
        invalidNavigationRules: document.body.dataset.invalidNavigationRules,
        homeNotAllowed: document.body.dataset.homeNotAllowed,
        invalidIdleTimeout: document.body.dataset.invalidIdleTimeout,
        invalidDisplayMode: document.body.dataset.invalidDisplayMode,
        invalidRevision: document.body.dataset.invalidRevision
      };
      for (const issue of state.validationMessages || []) {
        const item = document.createElement('li');
        item.textContent = labels[issue.id] ?? issue.textKey;
        validation.append(item);
      }
      document.querySelector('#save-settings').disabled = !state.canSave;
      document.querySelector('#discard-settings').hidden = !state.hasUnsavedDraft;
    }
    if (state.webRestartFailed) message.textContent = document.body.dataset.restartFailed;
    else if (state.saveFailed) message.textContent = document.body.dataset.saveFailed;
  }
  function renderRules(rules) {
    const container = document.querySelector('#edit-rules');
    if (document.activeElement?.matches('#edit-rules input')
        || (pendingFields.get('originAddress') ?? 0) > 0) return;
    container.replaceChildren();
    for (const rule of rules) {
      const row = document.createElement('div');
      row.className = 'rule-row';
      const input = document.createElement('input');
      input.type = 'text';
      input.value = rule.address;
      input.setAttribute('aria-label', document.body.dataset.domain);
      input.addEventListener('change', () => enqueue('/api/draft/edit', {
        field: 'originAddress', id: rule.id, value: input.value
      }));
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'secondary';
      remove.textContent = '−';
      remove.setAttribute('aria-label', document.body.dataset.removeRule);
      remove.addEventListener('click', () => enqueue('/api/draft/rules/remove', { id: rule.id }));
      row.append(input, remove);
      container.append(row);
    }
  }
  function option(value, text, disabled = false) {
    const item = document.createElement('option');
    item.value = value;
    item.textContent = text;
    item.disabled = disabled;
    return item;
  }
  function resolutionID(mode) {
    return `${mode.width}x${mode.height}@${mode.pixelAspectRatio}`;
  }
  function renderOutput(state, draft) {
    const mac = document.querySelector('#mac-output-editor');
    mac.hidden = !Array.isArray(state.macDisplays);
    if (!mac.hidden) {
      const output = draft.profile.macOutput ?? { mode: 'fixedFullscreen' };
      setValue('#edit-mac-output', 'macOutputMode', output.mode);
      document.querySelector('#mac-display-row').hidden =
        document.querySelector('#edit-mac-output').value !== 'fixedFullscreen';
      const display = document.querySelector('#edit-mac-display');
      const displayValue = editing('macDisplayID', display) ? display.value : output.displayID ?? '';
      display.replaceChildren(option('', document.body.dataset.automatic));
      for (const item of state.macDisplays) display.append(option(item.id, item.name));
      if (output.displayID && !state.macDisplays.some(item => item.id === output.displayID)) {
        display.append(option(output.displayID, document.body.dataset.disconnectedDisplay, true));
      }
      display.value = displayValue;
    }
    const mobile = document.querySelector('#mobile-output-editor');
    mobile.hidden = !state.mobileOutputAvailable;
    if (!mobile.hidden) {
      const destination = draft.profile.exhibitionDestination ?? 'device';
      setValue('#edit-destination', 'exhibitionDestination', destination);
      document.querySelector('#edit-destination option[value="externalDisplay"]').disabled =
        !state.supportsExternalDisplay;
      document.querySelector('#external-options').hidden =
        document.querySelector('#edit-destination').value !== 'externalDisplay';
      setValue('#edit-rotation', 'externalDisplayRotation',
        String(draft.profile.externalDisplayRotation ?? 0));
      const resolution = document.querySelector('#edit-resolution');
      const saved = draft.profile.externalDisplayMode;
      const resolutionValue = editing('externalDisplayMode', resolution)
        ? resolution.value : saved ? resolutionID(saved) : '';
      resolution.replaceChildren(option('', document.body.dataset.automatic));
      for (const mode of state.externalDisplayModes) {
        resolution.append(option(resolutionID(mode), `${mode.width} × ${mode.height}`));
      }
      if (saved && !state.externalDisplayModes.some(mode => resolutionID(mode) === resolutionID(saved))) {
        resolution.append(option(resolutionID(saved),
          `${saved.width} × ${saved.height} ${document.body.dataset.disconnectedDisplay}`, true));
      }
      resolution.value = resolutionValue;
      document.querySelector('#external-preparation').hidden =
        document.querySelector('#edit-destination').value !== 'externalDisplay'
        || !state.showsExhibitionWindowPreparation;
    }
  }
  """#
