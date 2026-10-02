/*
  Football PA Match Centre: save guard
  ------------------------------------
  Problem it fixes: if a goal, card, sub or clock change failed to save
  (for example, poor signal at the ground), Match Centre still showed it,
  gave no warning, and about 5 seconds later reloaded from the database
  and the change vanished.

  What this does instead:
  - Keeps the change on screen, marked "NOT SAVED".
  - Shows a red banner with a Retry button.
  - Stops the 5-second reload from wiping unsaved changes.
  - Retries automatically every 10 seconds and when the phone comes back online.
  - Blocks switching match or resetting the match while anything is unsaved.
  - Warns before the page is closed with unsaved changes.

  Loaded by match-centre.html after its main script. It wraps the existing
  save functions; it does not change how successful saves work.
*/
(function () {
  if (typeof persistMatchEvent !== 'function' || typeof requestSave !== 'function') return;

  const pending = [];        // [{ key, run }]
  let runtimeFailed = false; // clock / phase / lineup save failed
  let retrying = false;

  const orig = {
    persistMatchEvent: persistMatchEvent,
    persistSubstitutions: persistSubstitutions,
    deletePersistedEvent: deletePersistedEvent,
    deletePersistedSubstitution: deletePersistedSubstitution,
    requestSave: requestSave,
    syncRemoteState: syncRemoteState,
    loadMatch: loadMatch,
    saveLineupPositions: saveLineupPositions,
    render: render
  };

  function hasUnsaved() { return pending.length > 0 || runtimeFailed; }

  function addPending(key, run) {
    const i = pending.findIndex(p => p.key === key);
    if (i >= 0) pending[i] = { key, run }; else pending.push({ key, run });
  }

  function bannerEl() {
    let el = document.getElementById('unsavedBanner');
    if (!el) {
      el = document.createElement('div');
      el.id = 'unsavedBanner';
      el.className = 'card status bad hidden';
      el.style.cssText = 'position:sticky;top:0;z-index:25;font-size:14px;font-weight:800;display:flex;gap:10px;align-items:center;justify-content:space-between';
      const app = document.getElementById('app');
      if (app && app.parentNode) app.parentNode.insertBefore(el, app);
    }
    return el;
  }

  function showBanner(message) {
    const el = bannerEl();
    const n = pending.length + (runtimeFailed ? 1 : 0);
    if (!n) { el.classList.add('hidden'); el.innerHTML = ''; return; }
    el.classList.remove('hidden');
    const status = $('status');
    if (status && status.classList.contains('bad')) status.classList.add('hidden'); // the banner replaces raw error text
    el.innerHTML =
      '<span>⚠ ' + n + ' change' + (n === 1 ? '' : 's') + ' NOT SAVED yet' +
      (message ? ' (' + esc(message) + ')' : '') +
      '. Keep this page open. Retrying automatically…</span>' +
      '<button type="button" class="btn primary" id="retryUnsavedBtn">Retry now</button>';
    document.getElementById('retryUnsavedBtn').onclick = () => retryAll();
  }

  // Turn browser network errors into plain English
  function errorText(err) {
    const msg = (err && err.message) ? String(err.message) : '';
    if (!msg || /load failed|failed to fetch|networkerror|network request failed|fetch failed|timeout/i.test(msg)) return 'no signal';
    return msg;
  }

  // Once everything has saved, clear any old red error message
  function clearOldErrors() {
    const status = $('status');
    if (status && status.classList.contains('bad')) {
      status.classList.add('hidden');
      status.classList.remove('bad');
      status.textContent = '';
    }
    const saveState = $('saveState');
    if (saveState) saveState.textContent = 'Saved · ' + new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  async function retryAll() {
    if (retrying || !hasUnsaved()) { showBanner(); return; }
    retrying = true;
    let lastError = '';
    try {
      for (const item of pending.slice()) {
        try {
          await item.run();
          const i = pending.indexOf(item);
          if (i >= 0) pending.splice(i, 1);
        } catch (err) { lastError = errorText(err); break; }
      }
      if (!lastError && !pending.length && runtimeFailed) {
        try { await orig.requestSave(); runtimeFailed = false; }
        catch (err) { lastError = errorText(err); }
      }
    } finally {
      retrying = false;
      showBanner(lastError);
      render();
      if (!hasUnsaved()) clearOldErrors();
    }
  }

  // Goals, cards and edits
  window.persistMatchEvent = async function (ev) {
    try {
      const result = await orig.persistMatchEvent(ev);
      ev.unsaved = false;
      return result;
    } catch (err) {
      ev.unsaved = true;
      addPending('event:' + ev.id, () => orig.persistMatchEvent(ev).then(r => { ev.unsaved = false; return r; }));
      showBanner(errorText(err));
      render();
      return null;
    }
  };

  // Substitutions
  window.persistSubstitutions = async function (subs) {
    const markEvents = (flag) => {
      const ids = (subs || []).map(s => s.id).filter(Boolean);
      (state?.events || []).forEach(e => { if (ids.includes(e.id)) e.unsaved = flag; });
    };
    try {
      const result = await orig.persistSubstitutions(subs);
      markEvents(false);
      return result;
    } catch (err) {
      markEvents(true);
      const key = 'subs:' + (subs || []).map(s => s.id).join(',');
      addPending(key, () => orig.persistSubstitutions(subs).then(r => { markEvents(false); return r; }));
      showBanner(errorText(err));
      render();
      return null;
    }
  };

  // Shirt positions on the lineup pitch
  window.saveLineupPositions = async function () {
    try { return await orig.saveLineupPositions(); }
    catch (err) {
      addPending('positions', () => orig.saveLineupPositions());
      $('saveState').textContent = 'Positions not saved yet';
      showBanner(errorText(err));
      return null;
    }
  };

  // Clock, phase and lineup
  window.requestSave = function () {
    return orig.requestSave().then(
      r => { if (runtimeFailed) { runtimeFailed = false; showBanner(); } return r; },
      err => { runtimeFailed = true; showBanner(errorText(err)); $('saveState').textContent = 'Not saved yet'; throw err; }
    );
  };

  // Deletes: put the score back if the delete did not reach the server
  window.deletePersistedEvent = async function (ev) {
    try { return await orig.deletePersistedEvent(ev); }
    catch (err) {
      eventGoalDelta(ev, +1);
      render();
      $('status').textContent = 'That delete did not save (' + errorText(err) + '). Check signal and try again.';
      $('status').classList.remove('hidden');
      $('status').classList.add('bad');
      throw err;
    }
  };
  window.deletePersistedSubstitution = async function (sub) {
    try { return await orig.deletePersistedSubstitution(sub); }
    catch (err) {
      render();
      $('status').textContent = 'That delete did not save (' + errorText(err) + '). Check signal and try again.';
      $('status').classList.remove('hidden');
      $('status').classList.add('bad');
      throw err;
    }
  };

  // Never reload from the database over unsaved changes
  window.syncRemoteState = async function () {
    if (hasUnsaved() || retrying) return;
    return orig.syncRemoteState();
  };
  window.loadMatch = async function () {
    if (hasUnsaved()) return;
    return orig.loadMatch.apply(this, arguments);
  };

  // Mark unsaved rows in the event feed
  window.render = function () {
    orig.render.apply(this, arguments);
    try {
      (state?.events || []).forEach((e, i) => {
        if (!e.unsaved) return;
        const btn = document.querySelector('[data-edit-event="' + i + '"]');
        const row = btn && btn.closest('.event');
        if (!row || row.querySelector('.unsavedTag')) return;
        row.style.background = '#fdeceb';
        const label = row.children[1];
        if (label) label.insertAdjacentHTML('beforeend', ' <span class="unsavedTag" style="color:#b42318;font-size:11px;font-weight:900">· NOT SAVED</span>');
      });
    } catch (_) {}
  };

  // Block switching match or resetting while anything is unsaved
  function guardControl(id) {
    const el = $(id);
    if (!el || typeof el.onchange !== 'function' && typeof el.onclick !== 'function') return;
    const prop = el.tagName === 'SELECT' ? 'onchange' : 'onclick';
    const original = el[prop];
    el[prop] = function (e) {
      if (hasUnsaved()) {
        alert('Some match changes have not saved yet. Wait for them to save (or tap Retry now) before doing this.');
        if (prop === 'onchange' && fixture) el.value = fixture.id;
        return;
      }
      return original.call(this, e);
    };
  }
  guardControl('fixtureSelect');
  guardControl('resetBtn');

  // Retry every 10 seconds, and as soon as the phone is back online
  setInterval(() => { if (hasUnsaved()) retryAll(); }, 10000);
  window.addEventListener('online', () => { if (hasUnsaved()) retryAll(); });

  // Warn before closing the page with unsaved changes
  window.addEventListener('beforeunload', e => {
    if (!hasUnsaved()) return;
    e.preventDefault();
    e.returnValue = '';
  });
})();
