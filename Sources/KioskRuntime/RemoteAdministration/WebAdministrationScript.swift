let webAdministrationScript =
  webAdministrationRenderingScript + #"""
    async function refresh() {
      const response = await fetchWithTimeout('/api/state', {
        headers: { authorization: `Bearer ${sessionToken}` }, cache: 'no-store'
      });
      if (response.status === 401) {
        sessionToken = null;
        details.hidden = true;
        form.hidden = false;
        throw new Error('unauthorized');
      }
      if (!response.ok) throw new Error('state');
      const state = await response.json();
      render(state);
      if (connectionLost) {
        connectionLost = false;
        if (saveOutcomeUnknown && state.saving) {
          message.textContent = document.body.dataset.saveUnknown;
        } else {
          saveOutcomeUnknown = false;
          message.textContent = state.saveFailed ? document.body.dataset.saveFailed : '';
        }
      }
      return state;
    }
    async function fetchWithTimeout(path, options) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 5000);
      try {
        return await fetch(path, { ...options, signal: controller.signal });
      } finally {
        clearTimeout(timer);
      }
    }
    async function post(path, body) {
      return fetchWithTimeout(path, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          ...(sessionToken ? { authorization: `Bearer ${sessionToken}` } : {})
        },
        body: JSON.stringify(body), cache: 'no-store'
      });
    }
    async function rejectionMessage(response, action = 'edit') {
      const { reason } = await response.json().catch(() => ({}));
      if (reason === 'unsavedDraft') return document.body.dataset.unsavedDraft;
      if (reason === 'unsupportedDisplays') return document.body.dataset.unsupportedDisplays;
      if (reason === 'invalidState') return action === 'restart'
        ? document.body.dataset.restartMode : document.body.dataset.editMode;
      return document.body.dataset.rejected;
    }
    function enqueue(path, body) {
      const field = path === '/api/draft/edit' ? body.field : null;
      if (field) pendingFields.set(field, (pendingFields.get(field) ?? 0) + 1);
      pendingMutation = pendingMutation.catch(() => {}).then(async () => {
        let released = false;
        function release() {
          if (released || !field) return;
          released = true;
          const remaining = (pendingFields.get(field) ?? 1) - 1;
          if (remaining) pendingFields.set(field, remaining);
          else pendingFields.delete(field);
        }
        try {
          const response = await post(path, body);
          if (response.status === 401) {
            mutationFailed = true;
            sessionToken = null;
            details.hidden = true;
            form.hidden = false;
            message.textContent = document.body.dataset.rejected;
          } else if (response.ok) {
            mutationFailed = false;
            const state = await response.json();
            release();
            render(state);
            message.textContent = '';
          } else {
            mutationFailed = true;
            message.textContent = await rejectionMessage(response);
          }
        } catch {
          mutationFailed = true;
          connectionLost = true;
          message.textContent = document.body.dataset.connection;
        } finally {
          release();
        }
      });
      return pendingMutation;
    }
    document.querySelectorAll('[data-field]').forEach(input => {
      input.addEventListener('change', () => {
        const field = input.dataset.field;
        let value = input.type === 'checkbox' ? input.checked : input.value;
        if (field === 'macDisplayID') value = value || null;
        if (field === 'externalDisplayRotation') value = Number(value);
        if (field === 'externalDisplayMode') value = value
          ? currentState.externalDisplayModes.find(mode => resolutionID(mode) === value) : null;
        enqueue('/api/draft/edit', { field, value });
      });
    });
    document.querySelector('#add-rule').addEventListener('click', () =>
      enqueue('/api/draft/rules/add', {}));
    document.querySelector('#discard-settings').addEventListener('click', () =>
      enqueue('/api/draft/discard', {}));
    settingsForm.addEventListener('submit', async event => {
      event.preventDefault();
      try {
        await pendingMutation;
        if (mutationFailed) return;
        const response = await post('/api/draft/save', {});
        if (response.status === 422) {
          await refresh();
          return;
        }
        if (!response.ok) {
          message.textContent = await rejectionMessage(response);
          return;
        }
        for (let attempt = 0; attempt < 100; attempt++) {
          await new Promise(resolve => setTimeout(resolve, 150));
          const state = await refresh();
          if (!state.saving) {
            message.textContent = state.saveFailed ? document.body.dataset.saveFailed : '';
            return;
          }
        }
        message.textContent = document.body.dataset.connection;
      } catch {
        connectionLost = true;
        saveOutcomeUnknown = true;
        message.textContent = document.body.dataset.saveUnknown;
      }
    });
    async function exhibitionAction(path, target) {
      try {
        await pendingMutation;
        const response = await post(path, {});
        if (!response.ok) {
          message.textContent = await rejectionMessage(response, 'restart');
          return;
        }
        for (let attempt = 0; attempt < 100; attempt++) {
          await new Promise(resolve => setTimeout(resolve, 150));
          const state = await refresh();
          if (state.webRestartFailed) {
            message.textContent = document.body.dataset.restartFailed;
            return;
          }
          if (state.mode === target) {
            message.textContent = '';
            return;
          }
        }
        message.textContent = document.body.dataset.connection;
      } catch {
        connectionLost = true;
        message.textContent = document.body.dataset.connection;
      }
    }
    document.querySelector('#start-exhibition').addEventListener('click', () =>
      exhibitionAction('/api/exhibition/start', 'exhibiting'));
    document.querySelector('#restart-exhibition').addEventListener('click', () =>
      exhibitionAction('/api/exhibition/restart', 'exhibiting'));
    document.querySelector('#stop-exhibition').addEventListener('click', () =>
      exhibitionAction('/api/exhibition/stop', 'paused'));
    document.querySelector('#resume-exhibition').addEventListener('click', () =>
      exhibitionAction('/api/exhibition/resume', 'exhibiting'));
    setInterval(async () => {
      if (!sessionToken || editor.contains(document.activeElement)) return;
      try { await refresh(); }
      catch {
        connectionLost = true;
        message.textContent = saveOutcomeUnknown
          ? document.body.dataset.saveUnknown : document.body.dataset.connection;
      }
    }, 5000);
    form.addEventListener('submit', async event => {
      event.preventDefault();
      message.textContent = document.body.dataset.wait;
      try {
        const response = await post('/api/login', { password: password.value });
        password.value = '';
        if (response.status === 429) {
          message.textContent = document.body.dataset.cooldown;
          return;
        }
        if (!response.ok) {
          message.textContent = document.body.dataset.failed;
          return;
        }
        const ticket = await response.json();
        for (let attempt = 0; attempt < 100; attempt++) {
          await new Promise(resolve => setTimeout(resolve, 150));
          const result = await post('/api/login/status', ticket);
          if (!result.ok) throw new Error('login');
          const status = (await result.json()).status;
          if (status === 'pending') continue;
          if (status === 'failed') {
            message.textContent = document.body.dataset.failed;
            return;
          }
          sessionToken = ticket.token;
          await refresh();
          message.textContent = '';
          return;
        }
        message.textContent = document.body.dataset.connection;
      } catch {
        message.textContent = document.body.dataset.connection;
      }
    });
    """#
