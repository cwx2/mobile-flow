// MobileFlow Agent Dashboard — Run Configuration logic
// Manages run configurations: CRUD, execution, output polling via xterm.js

// ── State ──
let configs = [];
let selectedId = null;
let states = {};
let saveTimer = null;
let outputPollTimer = null;
let lastOutputIndex = 0;
const DEBOUNCE_MS = 600;
const OUTPUT_POLL_MS = 800;

// ── xterm.js terminal for run config output ──
let _rcTerm = null;
let _rcFit = null;
let _rcTermInitialized = false;

function initRunConfigTerminal() {
  if (_rcTermInitialized) return;
  _rcTermInitialized = true;
  const container = document.getElementById('terminal-container');
  if (!container || typeof Terminal === 'undefined') return;
  _rcTerm = new Terminal({
    theme: { background: '#0d0e17', foreground: '#c8d3f5', cursor: '#43e6c3' },
    fontSize: 13,
    fontFamily: "'JetBrains Mono', 'Consolas', 'Courier New', monospace",
    cursorBlink: false,
    disableStdin: true,
    scrollback: 5000,
    convertEol: true,
  });
  _rcFit = new FitAddon.FitAddon();
  _rcTerm.loadAddon(_rcFit);
  _rcTerm.open(container);
  _rcFit.fit();
  _rcTerm.writeln('\x1b[90m— Select a configuration and click Run —\x1b[0m');
  window.addEventListener('resize', () => { if (_rcFit) _rcFit.fit(); });
}

// ── API helpers ──
async function rcApi(path) { return (await fetch(path)).json(); }

// ── Load configs ──
async function loadConfigs() {
  const data = await rcApi('/api/run-config/list');
  configs = data.configurations || [];
  selectedId = selectedId || data.selected_id;
  renderList();
  if (selectedId) showEditor(selectedId);
}

// ── Poll status ──
async function pollStatus() {
  const data = await rcApi('/api/run-config/status');
  states = data.states || {};
  renderList();
  updateActions();
}

// ── Poll output ──
async function pollOutput() {
  if (!selectedId || !_rcTerm) return;
  try {
    const data = await rcApi(`/api/run-config/output?id=${selectedId}&since=${lastOutputIndex}`);
    const lines = data.lines || [];
    for (const line of lines) {
      if (line.stream === 'stderr') {
        _rcTerm.writeln(`\x1b[33m${line.text}\x1b[0m`);
      } else {
        _rcTerm.writeln(line.text);
      }
      lastOutputIndex = line.index + 1;
    }
  } catch (e) { /* ignore polling errors */ }
}

function startOutputPoll() {
  stopOutputPoll();
  outputPollTimer = setInterval(pollOutput, OUTPUT_POLL_MS);
}
function stopOutputPoll() {
  if (outputPollTimer) { clearInterval(outputPollTimer); outputPollTimer = null; }
}

// ── Render config list ──
function renderList() {
  const el = document.getElementById('config-list');
  if (!configs.length) {
    el.innerHTML = '<div class="text-center text-xs text-gray-500 py-8">No configurations. Click + to create.</div>';
    return;
  }
  el.innerHTML = configs.map(c => {
    const state = states[c.id] || 'idle';
    const active = c.id === selectedId ? 'active' : '';
    const icon = { preview:'&#127760;', script:'&#9000;', test:'&#10003;', custom:'&#9881;' }[c.type] || '&#9881;';
    const statusDot = (state === 'running' || state === 'starting' || state === 'before_run')
      ? `<span class="status-dot ${state === 'running' ? 'running' : 'starting'}"></span>` : '';
    return `<div class="config-item flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer border border-transparent hover:bg-white/5 transition-colors ${active}" data-id="${c.id}">
      <span class="text-sm">${icon}</span>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium text-gray-200 truncate">${rcEsc(c.name)}</div>
        <div class="text-xs text-gray-500">${c.type}${state !== 'idle' ? ' · '+state : ''}</div>
      </div>
      ${statusDot}
    </div>`;
  }).join('');
  el.querySelectorAll('.config-item').forEach(item => {
    item.onclick = () => { selectedId = item.dataset.id; renderList(); showEditor(selectedId); switchOutput(); };
  });
}

function rcEsc(s) { const d = document.createElement('div'); d.textContent = s||''; return d.innerHTML; }

// ── Show editor ──
function showEditor(id) {
  const c = configs.find(x => x.id === id);
  if (!c) return;
  document.getElementById('editor-empty').classList.add('hidden');
  document.getElementById('editor-form').classList.remove('hidden');
  document.getElementById('f-name').value = c.name || '';
  document.getElementById('f-command').value = c.command || '';
  document.getElementById('f-workdir').value = c.working_directory || '';
  const isPreview = c.type === 'preview';
  document.getElementById('field-url').classList.toggle('hidden', !isPreview);
  document.getElementById('field-host').classList.toggle('hidden', !isPreview);
  document.getElementById('row-autorefresh').classList.toggle('hidden', !isPreview);
  if (isPreview && c.preview) {
    document.getElementById('f-url').value = c.preview.url || '';
    document.getElementById('f-host').value = c.preview.host_header || '';
    document.getElementById('t-autorefresh').checked = c.preview.auto_refresh !== false;
  }
  document.getElementById('t-parallel').checked = c.allow_parallel === true;
  renderEnvVars(c.environment_variables || {});
  renderTasks(c.before_run_tasks || []);
  updateActions();
}

// ── Switch output to selected config ──
function switchOutput() {
  if (!_rcTerm) return;
  _rcTerm.clear();
  lastOutputIndex = 0;
  pollOutput();
  startOutputPoll();
}

// ── Update action buttons ──
function updateActions() {
  const state = states[selectedId] || 'idle';
  const active = ['running','starting','before_run','stopping'].includes(state);
  document.getElementById('btn-run').classList.toggle('hidden', active);
  document.getElementById('btn-stop').classList.toggle('hidden', !active);
  const statusEl = document.getElementById('output-status');
  if (state !== 'idle') {
    statusEl.classList.remove('hidden');
    statusEl.textContent = `Status: ${state}`;
    statusEl.className = `px-4 py-2 border-t border-border text-xs ${state === 'running' ? 'text-green-400' : state === 'stopped' ? 'text-gray-500' : 'text-yellow-400'}`;
  } else {
    statusEl.classList.add('hidden');
  }
}

// ── Env vars ──
function renderEnvVars(vars) {
  const el = document.getElementById('env-list');
  const entries = Object.entries(vars);
  el.innerHTML = entries.map(([k,v],i) => `<div class="flex gap-1 items-center">
    <input class="flex-1 px-2 py-1 bg-surface-dark border border-border rounded text-xs font-mono text-gray-200" value="${rcEsc(k)}" placeholder="KEY" data-ek="${i}">
    <input class="flex-1 px-2 py-1 bg-surface-dark border border-border rounded text-xs font-mono text-gray-200" value="${rcEsc(v)}" placeholder="value" data-ev="${i}">
    <button class="text-red-400 bg-transparent border-none cursor-pointer text-sm px-1" data-er="${i}">&#215;</button>
  </div>`).join('');
  el.querySelectorAll('[data-er]').forEach(b => b.onclick = () => {
    const c = configs.find(x=>x.id===selectedId); if(!c) return;
    const keys = Object.keys(c.environment_variables||{});
    delete c.environment_variables[keys[parseInt(b.dataset.er)]];
    renderEnvVars(c.environment_variables);
    scheduleSave('environment_variables', JSON.stringify(c.environment_variables));
  });
  el.querySelectorAll('input').forEach(inp => inp.onblur = saveEnvVars);
}
function saveEnvVars() {
  const rows = document.querySelectorAll('#env-list > div');
  const vars = {};
  rows.forEach(r => { const k=r.querySelector('[data-ek]').value.trim(), v=r.querySelector('[data-ev]').value; if(k) vars[k]=v; });
  const c = configs.find(x=>x.id===selectedId); if(c) c.environment_variables=vars;
  scheduleSave('environment_variables', JSON.stringify(vars));
}

// ── Tasks ──
function renderTasks(tasks) {
  const el = document.getElementById('task-list');
  el.innerHTML = tasks.map((t,i) => `<div class="flex items-center gap-2 bg-surface-dark rounded px-2 py-1">
    <input type="checkbox" class="checkbox checkbox-xs checkbox-primary" ${t.enabled!==false?'checked':''} data-tt="${i}">
    <span class="flex-1 text-xs font-mono truncate text-gray-400">${rcEsc(t.command)}</span>
    <button class="text-red-400 bg-transparent border-none cursor-pointer text-sm px-1" data-tr="${i}">&#215;</button>
  </div>`).join('');
  el.querySelectorAll('[data-tt]').forEach(cb => cb.onchange = () => {
    const c=configs.find(x=>x.id===selectedId); if(c&&c.before_run_tasks[parseInt(cb.dataset.tt)]) {
      c.before_run_tasks[parseInt(cb.dataset.tt)].enabled=cb.checked;
      scheduleSave('before_run_tasks',JSON.stringify(c.before_run_tasks));
    }
  });
  el.querySelectorAll('[data-tr]').forEach(b => b.onclick = () => {
    const c=configs.find(x=>x.id===selectedId); if(!c) return;
    c.before_run_tasks.splice(parseInt(b.dataset.tr),1);
    renderTasks(c.before_run_tasks);
    scheduleSave('before_run_tasks',JSON.stringify(c.before_run_tasks));
  });
}

// ── Auto-save ──
function scheduleSave(field, value) {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    if (!selectedId) return;
    rcApi(`/api/run-config/update?id=${selectedId}&field=${field}&value=${encodeURIComponent(value)}`);
  }, DEBOUNCE_MS);
}

// ── Init Run Config tab ──
function initRunConfig() {
  // Event bindings for form fields
  ['f-name','f-command','f-workdir','f-url','f-host'].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.onblur = function() {
      if (!selectedId) return;
      const map = {'f-name':'name','f-command':'command','f-workdir':'working_directory','f-url':'preview.url','f-host':'preview.host_header'};
      scheduleSave(map[id], this.value);
    };
  });

  const parallelEl = document.getElementById('t-parallel');
  if (parallelEl) parallelEl.onchange = function() { scheduleSave('allow_parallel', this.checked?'true':'false'); };

  const autorefreshEl = document.getElementById('t-autorefresh');
  if (autorefreshEl) autorefreshEl.onchange = function() { scheduleSave('preview.auto_refresh', this.checked?'true':'false'); };

  const addEnvBtn = document.getElementById('btn-add-env');
  if (addEnvBtn) addEnvBtn.onclick = () => {
    const c=configs.find(x=>x.id===selectedId); if(!c) return;
    if(!c.environment_variables) c.environment_variables={};
    c.environment_variables['']='';
    renderEnvVars(c.environment_variables);
  };

  const addTaskBtn = document.getElementById('btn-add-task');
  if (addTaskBtn) addTaskBtn.onclick = () => {
    const cmd = prompt('Enter before-run command:'); if(!cmd) return;
    const c=configs.find(x=>x.id===selectedId); if(!c) return;
    if(!c.before_run_tasks) c.before_run_tasks=[];
    c.before_run_tasks.push({command:cmd,enabled:true});
    renderTasks(c.before_run_tasks);
    scheduleSave('before_run_tasks',JSON.stringify(c.before_run_tasks));
  };

  const runBtn = document.getElementById('btn-run');
  if (runBtn) runBtn.onclick = async () => {
    if(!selectedId || !_rcTerm) return;
    _rcTerm.clear(); lastOutputIndex=0;
    _rcTerm.writeln('\x1b[90m— Starting...\x1b[0m');
    await rcApi(`/api/run-config/start?id=${selectedId}`);
    startOutputPoll();
    pollStatus();
  };

  const stopBtn = document.getElementById('btn-stop');
  if (stopBtn) stopBtn.onclick = async () => {
    if(!selectedId) return;
    await rcApi(`/api/run-config/stop?id=${selectedId}`);
    pollStatus();
  };

  const clearBtn = document.getElementById('btn-clear');
  if (clearBtn) clearBtn.onclick = async () => {
    if(!selectedId || !_rcTerm) return;
    _rcTerm.clear(); lastOutputIndex=0;
    await rcApi(`/api/run-config/clear-output?id=${selectedId}`);
  };

  const deleteBtn = document.getElementById('btn-delete');
  if (deleteBtn) deleteBtn.onclick = async () => {
    if(!selectedId||!confirm('Delete this configuration?')) return;
    await rcApi(`/api/run-config/delete?id=${selectedId}`);
    selectedId=null;
    document.getElementById('editor-form').classList.add('hidden');
    document.getElementById('editor-empty').classList.remove('hidden');
    if (_rcTerm) _rcTerm.clear();
    await loadConfigs();
  };

  const addBtn = document.getElementById('btn-add');
  if (addBtn) addBtn.onclick = () => document.getElementById('type-dialog').showModal();

  document.querySelectorAll('#type-options button').forEach(opt => {
    opt.onclick = async () => {
      document.getElementById('type-dialog').close();
      const data = await rcApi(`/api/run-config/create?type=${opt.dataset.type}`);
      if(data.success&&data.configuration) { configs.push(data.configuration); selectedId=data.configuration.id; renderList(); showEditor(selectedId); switchOutput(); }
    };
  });

  // Resize handle drag logic
  const resizeHandle = document.getElementById('resize-handle');
  const outputPanel = document.getElementById('output-panel');
  let isResizing = false;

  if (resizeHandle && outputPanel) {
    resizeHandle.addEventListener('mousedown', (e) => {
      isResizing = true;
      document.body.style.cursor = 'col-resize';
      document.body.style.userSelect = 'none';
      e.preventDefault();
    });

    document.addEventListener('mousemove', (e) => {
      if (!isResizing) return;
      const containerRight = document.body.clientWidth;
      const newWidth = containerRight - e.clientX;
      if (newWidth >= 200 && newWidth <= 800) {
        outputPanel.style.width = newWidth + 'px';
        if (_rcFit) _rcFit.fit();
      }
    });

    document.addEventListener('mouseup', () => {
      if (isResizing) {
        isResizing = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
        if (_rcFit) _rcFit.fit();
      }
    });
  }
}

// ── Activate when Run Config tab is opened ──
document.querySelector('.nav-tab[data-tab="runconfig"]').addEventListener('click', () => {
  initRunConfigTerminal();
  if (!configs.length) loadConfigs();
  startOutputPoll();
});

// Initialize event bindings immediately (DOM is ready since script is at bottom)
initRunConfig();

// Status polling for run configs (only when tab is visible)
setInterval(() => {
  const rcTab = document.getElementById('tab-runconfig');
  if (rcTab && !rcTab.classList.contains('hidden')) {
    pollStatus();
  }
}, 3000);
