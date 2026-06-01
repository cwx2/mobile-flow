// MobileFlow Agent Dashboard — Client-side logic

// ── Tab navigation ──

document.querySelectorAll('.nav-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    // Update tab active state (Tailwind classes)
    document.querySelectorAll('.nav-tab').forEach(t => {
      t.classList.remove('bg-brand/10', 'text-brand');
      t.classList.add('bg-transparent', 'text-gray-400');
    });
    tab.classList.remove('bg-transparent', 'text-gray-400');
    tab.classList.add('bg-brand/10', 'text-brand');
    // Show/hide tab content
    document.querySelectorAll('.tab-panel').forEach(c => c.classList.add('hidden'));
    const target = document.getElementById('tab-' + tab.dataset.tab);
    if (target) target.classList.remove('hidden');
  });
});

// ── Data loading ──

async function fetchJSON(url) {
  const res = await fetch(url);
  return res.json();
}

async function loadStatus() {
  try {
    const data = await fetchJSON('/api/status');
    const el = document.getElementById('info-status');
    if (data.connected_clients > 0) {
      el.innerHTML = `<span class="badge badge-success">${t('home.statusConnected', data.connected_clients)}</span>`;
    } else {
      el.innerHTML = `<span class="badge badge-warning">${t('home.statusWaiting')}</span>`;
    }
    document.getElementById('setting-version').textContent = data.version || '--';
    document.getElementById('setting-port').textContent = data.port || '--';
    document.getElementById('setting-cwd').textContent = data.work_dir || '--';
    // Home page project info
    const projName = document.getElementById('home-project-name');
    const projPath = document.getElementById('home-project-path');
    const defCli = document.getElementById('home-default-cli');
    if (projName) projName.textContent = data.project_name || '--';
    if (projPath) projPath.textContent = data.work_dir || '--';
    if (defCli) defCli.textContent = data.default_cli || '--';
  } catch (e) {
    console.error('Failed to load status:', e);
  }
}

async function loadConnectInfo() {
  try {
    const data = await fetchJSON('/api/connect');
    document.getElementById('info-host').textContent = data.host || '--';
    document.getElementById('info-port').textContent = data.port || '--';
    document.getElementById('info-password').textContent = data.password || '--';

    // Generate QR code (if library loaded)
    const qrData = `mobileflow://connect?host=${data.host}&port=${data.port}&token=${data.password}`;
    const container = document.getElementById('qr-container');
    container.innerHTML = '';
    if (typeof QRCode !== 'undefined') {
      new QRCode(container, {
        text: qrData,
        width: 128,
        height: 128,
        colorDark: '#0A0F1C',
        colorLight: '#FFFFFF',
      });
    } else {
      container.innerHTML = `<div style="color:#6F7D96;font-size:11px;text-align:center;padding:40px 10px;">${t('home.qrNotLoaded')}</div>`;
    }
  } catch (e) {
    console.error('Failed to load connect info:', e);
  }
}

async function loadCliList() {
  try {
    const data = await fetchJSON('/api/cli/list');
    renderCliList(data.adapters || []);
    renderHomeCliStatus(data.adapters || []);
  } catch (e) {
    console.error('Failed to load CLI list:', e);
    document.getElementById('cli-list').innerHTML = '<p style="color:#ff6b7a;font-size:13px;">Failed to load</p>';
  }
}

function renderHomeCliStatus(adapters) {
  const el = document.getElementById('home-cli-status');
  if (!el) return;
  const installed = adapters.filter(a => a.installed);
  if (installed.length === 0) {
    el.innerHTML = '<span style="color:#6F7D96;font-size:13px;">No AI Agent installed</span>';
    return;
  }
  el.innerHTML = installed.map(cli => `
    <div style="display:flex;align-items:center;gap:8px;">
      <span style="width:8px;height:8px;border-radius:50%;background:#3ddb8c;flex-shrink:0;"></span>
      <span style="font-size:13px;color:#e0e0e0;">${escapeHtml(cli.display_name)}</span>
      <span style="font-size:11px;color:#6F7D96;font-family:monospace;">${escapeHtml(cli.name)}</span>
    </div>
  `).join('');
}

function renderCliList(adapters) {
  const container = document.getElementById('cli-list');

  if (adapters.length === 0) {
    container.innerHTML = `<p style="color:#6F7D96;font-size:14px;">${t('agent.noAgent')}</p>`;
    return;
  }

  const installed = adapters.filter(a => a.installed);
  const available = adapters.filter(a => !a.installed);

  let html = '';

  if (installed.length > 0) {
    html += `<div style="font-size:11px;color:#6F7D96;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:8px;">${t('agent.installed')}</div>`;
    installed.forEach(cli => {
      html += `<div style="display:flex;align-items:center;gap:12px;padding:10px 12px;background:#0f1019;border-radius:8px;margin-bottom:6px;">
        <span class="cli-status installed"></span>
        <div style="flex:1;min-width:0;">
          <div style="font-size:13px;font-weight:500;color:#e0e0e0;">${escapeHtml(cli.display_name)}</div>
          <div style="font-size:11px;color:#6F7D96;font-family:monospace;">${escapeHtml(cli.name)}</div>
        </div>
        <button onclick="testCli('${cli.name}')" style="font-size:11px;color:#6F7D96;background:none;border:1px solid #2a2b3e;border-radius:4px;padding:4px 10px;cursor:pointer;">${t('agent.test')}</button>
      </div>`;
    });
  }

  if (available.length > 0) {
    html += `<div style="font-size:11px;color:#6F7D96;text-transform:uppercase;letter-spacing:0.5px;margin:16px 0 8px;">${t('agent.available')}</div>`;
    available.forEach(cli => {
      html += `<div style="display:flex;align-items:center;gap:12px;padding:10px 12px;background:#0f1019;border-radius:8px;margin-bottom:6px;">
        <span class="cli-status available"></span>
        <div style="flex:1;min-width:0;">
          <div style="font-size:13px;font-weight:500;color:#e0e0e0;">${escapeHtml(cli.display_name)}</div>
          <div style="font-size:11px;color:#6F7D96;font-family:monospace;">${escapeHtml(cli.install_hint || cli.name)}</div>
        </div>
        ${cli.can_install ? `<button data-install-btn onclick="installCli('${cli.name}')" style="font-size:11px;color:#43e6c3;background:rgba(67,230,195,0.08);border:1px solid rgba(67,230,195,0.3);border-radius:4px;padding:4px 10px;cursor:pointer;">${t('agent.install')}</button>` : ''}
      </div>`;
    });
  }

  // Add Custom Agent button at the bottom
  html += `<div style="margin-top:16px;padding-top:16px;border-top:1px solid #2a2b3e;">
    <button onclick="showAddCustomAgent()" style="font-size:12px;color:#43e6c3;background:rgba(67,230,195,0.08);border:1px solid rgba(67,230,195,0.3);border-radius:6px;padding:8px 14px;cursor:pointer;width:100%;">${t('agent.addCustom')}</button>
  </div>`;

  container.innerHTML = html;
}

// ── Actions ──

function copyPassword() {
  const pwd = document.getElementById('info-password').textContent;
  navigator.clipboard.writeText(pwd).then(() => {
    // Brief visual feedback
    const btn = event.target;
    const orig = btn.textContent;
    btn.textContent = 'Copied!';
    setTimeout(() => btn.textContent = orig, 1500);
  });
}

async function detectAll() {
  document.getElementById('cli-list').innerHTML = `<div style="display:flex;align-items:center;gap:8px;color:#6F7D96;font-size:13px;">${t('agent.detecting')}</div>`;
  try {
    const res = await fetch('/api/cli/detect');
    const result = await res.json();
    if (result.success) {
      renderCliList(result.adapters || []);
    } else {
      document.getElementById('cli-list').innerHTML = `<p style="color:#ff6b7a;font-size:13px;">${t('agent.detectFailed')}: ${result.message}</p>`;
    }
  } catch (e) {
    console.error('Detect failed:', e);
    document.getElementById('cli-list').innerHTML = `<p style="color:#ff6b7a;font-size:13px;">${t('agent.detectFailed')}</p>`;
  }
}

async function installCli(name) {
  if (!confirm(t('agent.installConfirm', name))) return;

  // Disable all install buttons during installation
  document.querySelectorAll('[data-install-btn]').forEach(b => {
    b.disabled = true;
    b.style.opacity = '0.5';
    b.style.cursor = 'not-allowed';
  });

  // Write to install terminal
  if (window._installTerm) {
    window._installTerm.clear();
    window._installTerm.writeln(`\x1b[90m$ Installing ${name}...\x1b[0m`);
  }
  updateInstallStatus('installing');

  try {
    const res = await fetch(`/api/cli/install?name=${encodeURIComponent(name)}`);
    const result = await res.json();
    if (!result.success && result.status !== 'installing') {
      if (window._installTerm) window._installTerm.writeln(`\x1b[31m❌ ${result.message}\x1b[0m`);
      updateInstallStatus('error');
      _enableInstallButtons();
      return;
    }
    // Start polling install output
    startInstallPoll();
  } catch (e) {
    if (window._installTerm) window._installTerm.writeln(`\x1b[31m❌ Error: ${e.message}\x1b[0m`);
    updateInstallStatus('error');
    _enableInstallButtons();
  }
}

function _enableInstallButtons() {
  document.querySelectorAll('[data-install-btn]').forEach(b => {
    b.disabled = false;
    b.style.opacity = '1';
    b.style.cursor = 'pointer';
  });
}

// ── Install output polling ──
let installPollTimer = null;
let installLastIndex = 0;

function startInstallPoll() {
  stopInstallPoll();
  installLastIndex = 0;
  installPollTimer = setInterval(pollInstallOutput, 800);
}

function stopInstallPoll() {
  if (installPollTimer) { clearInterval(installPollTimer); installPollTimer = null; }
}

async function pollInstallOutput() {
  try {
    const data = await fetchJSON(`/api/cli/install-output?since=${installLastIndex}`);
    const lines = data.lines || [];
    for (const line of lines) {
      if (window._installTerm) window._installTerm.writeln(line.text);
      installLastIndex = line.index + 1;
    }
    updateInstallStatus(data.status);
    if (data.status === 'done' || data.status === 'error') {
      stopInstallPoll();
      _enableInstallButtons();
      // Refresh CLI list after install completes
      if (data.status === 'done') {
        setTimeout(loadCliList, 1000);
      }
    }
  } catch (e) { /* ignore */ }
}

function updateInstallStatus(status) {
  const el = document.getElementById('install-status');
  if (!el) return;
  const colors = { idle: '#6F7D96', installing: '#ffb454', done: '#3ddb8c', error: '#ff6b7a' };
  const labels = {
    idle: t('agent.statusIdle'),
    installing: t('agent.statusInstalling'),
    done: t('agent.statusDone'),
    error: t('agent.statusFailed'),
  };
  el.style.color = colors[status] || '#6F7D96';
  el.textContent = labels[status] || status;
}

async function testCli(name) {
  try {
    const res = await fetch(`/api/cli/test?name=${encodeURIComponent(name)}`);
    const result = await res.json();
    if (result.success) {
      alert(t('agent.testPassed', name));
    } else {
      alert(t('agent.testFailed', name, result.message));
    }
  } catch (e) {
    alert(t('agent.testFailed', name, e.message));
  }
}

async function saveKey() {
  const type = document.getElementById('key-type').value;
  const value = document.getElementById('key-value').value.trim();
  if (!value) { alert(t('apiKey.enterKey')); return; }
  try {
    const res = await fetch(`/api/keys?name=${encodeURIComponent(type)}&value=${encodeURIComponent(value)}`);
    const result = await res.json();
    if (result.success) {
      alert(t('apiKey.saved'));
      document.getElementById('key-value').value = '';
    } else {
      alert(t('apiKey.saveFailed', result.message));
    }
  } catch (e) {
    alert(t('apiKey.saveFailed', e.message));
  }
}

// ── Logs (polling with xterm.js) ──

let logPaused = false;
let logSinceIndex = 0;
let logInterval = null;
let _logTerm = null;
let _logFit = null;
let _logTermInitialized = false;

function initLogTerminal() {
  if (_logTermInitialized) return;
  _logTermInitialized = true;
  const container = document.getElementById('log-terminal-container');
  if (!container || typeof Terminal === 'undefined') return;
  _logTerm = new Terminal({
    theme: { background: '#0d0e17', foreground: '#c8d3f5', cursor: '#43e6c3' },
    fontSize: 12,
    fontFamily: "'JetBrains Mono', 'Consolas', monospace",
    cursorBlink: false,
    disableStdin: true,
    scrollback: 5000,
    convertEol: true,
  });
  _logFit = new FitAddon.FitAddon();
  _logTerm.loadAddon(_logFit);
  _logTerm.open(container);
  _logFit.fit();
  window.addEventListener('resize', () => { if (_logFit) _logFit.fit(); });
}

function startLogPolling() {
  initLogTerminal();
  if (logInterval) return;
  logInterval = setInterval(pollLogs, 1000);
  pollLogs();
}

async function pollLogs() {
  if (logPaused || !_logTerm) return;
  try {
    const res = await fetch(`/api/logs?since=${logSinceIndex}`);
    const data = await res.json();
    const entries = data.entries || [];
    const levelFilter = document.getElementById('log-level').value;
    for (const entry of entries) {
      if (entry.index > logSinceIndex) logSinceIndex = entry.index;
      if (levelFilter !== 'all' && entry.level !== levelFilter) continue;
      appendLogToTerminal(entry);
    }
  } catch (e) {
    // Silently retry
  }
}

function appendLogToTerminal(entry) {
  if (!_logTerm) return;
  const time = entry.time ? `\x1b[90m${entry.time}\x1b[0m ` : '';
  let levelColor;
  switch (entry.level) {
    case 'DEBUG': levelColor = '\x1b[90m'; break;
    case 'INFO': levelColor = '\x1b[36m'; break;
    case 'WARNING': levelColor = '\x1b[33m'; break;
    case 'ERROR': levelColor = '\x1b[31m'; break;
    default: levelColor = '\x1b[0m';
  }
  const level = `${levelColor}${(entry.level || '').padEnd(7)}\x1b[0m`;
  const msg = entry.message || '';
  _logTerm.writeln(`${time}${level} ${msg}`);
}

function clearLogs() {
  if (_logTerm) _logTerm.clear();
}

function togglePause() {
  logPaused = !logPaused;
  document.getElementById('log-pause').textContent = logPaused ? t('logs.resume') : t('logs.pause');
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// ── Project Picker ──

let _currentBrowsePath = '';

async function showProjectPicker() {
  const overlay = document.getElementById('project-picker-overlay');
  overlay.style.display = 'flex';
  await loadProjectList();
  await browseTo('');
}

function closeProjectPicker() {
  document.getElementById('project-picker-overlay').style.display = 'none';
}

// Close on overlay background click
document.getElementById('project-picker-overlay').addEventListener('click', function(e) {
  if (e.target === this) closeProjectPicker();
});

// Event delegation for project list actions
document.getElementById('project-list-container').addEventListener('click', async function(e) {
  const removeBtn = e.target.closest('[data-remove-path]');
  if (removeBtn) {
    e.stopPropagation();
    const path = removeBtn.dataset.removePath;
    if (confirm('Remove this project from the list?')) {
      await fetchJSON(`/api/project/remove?path=${encodeURIComponent(path)}`);
      await loadProjectList();
      loadStatus();
    }
    return;
  }
  const switchItem = e.target.closest('[data-switch-path]');
  if (switchItem) {
    const path = switchItem.dataset.switchPath;
    await fetchJSON(`/api/project/switch?path=${encodeURIComponent(path)}`);
    await loadProjectList();
    loadStatus();
  }
});

// Event delegation for browse list actions
document.getElementById('browse-list').addEventListener('click', async function(e) {
  const selectBtn = e.target.closest('[data-select-path]');
  if (selectBtn) {
    e.stopPropagation();
    const path = selectBtn.dataset.selectPath;
    // Add project and switch to it
    await fetchJSON(`/api/project/add?path=${encodeURIComponent(path)}`);
    await fetchJSON(`/api/project/switch?path=${encodeURIComponent(path)}`);
    await loadProjectList();
    loadStatus();
    return;
  }
  const browseItem = e.target.closest('[data-browse-path]');
  if (browseItem) {
    await browseTo(browseItem.dataset.browsePath);
  }
});

async function loadProjectList() {
  const container = document.getElementById('project-list-container');
  try {
    const data = await fetchJSON('/api/project/list');
    const projects = data.projects || [];
    if (projects.length === 0) {
      container.innerHTML = '<span style="color:#6F7D96;font-size:13px;">No projects registered. Browse below to add one.</span>';
      return;
    }
    container.innerHTML = projects.map(p => {
      const isActive = p.is_current === true;
      const name = p.name || p.path.split(/[/\\]/).pop();
      return `<div data-switch-path="${escapeHtml(p.path)}" style="display:flex;align-items:center;gap:10px;padding:10px 12px;background:${isActive ? 'rgba(67,230,195,0.08)' : '#0f1019'};border:1px solid ${isActive ? 'rgba(67,230,195,0.3)' : '#2a2b3e'};border-radius:8px;margin-bottom:6px;cursor:pointer;">
        <span style="width:8px;height:8px;border-radius:50%;background:${isActive ? '#3ddb8c' : '#6F7D96'};flex-shrink:0;"></span>
        <div style="flex:1;min-width:0;">
          <div style="font-size:13px;font-weight:500;color:#e0e0e0;">${escapeHtml(name)}</div>
          <div style="font-size:11px;color:#6F7D96;font-family:monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(p.path)}</div>
        </div>
        ${!isActive ? `<button data-remove-path="${escapeHtml(p.path)}" style="font-size:16px;color:#ff6b7a;background:none;border:none;cursor:pointer;padding:4px 8px;">×</button>` : ''}
      </div>`;
    }).join('');
  } catch (e) {
    container.innerHTML = '<span style="color:#ff6b7a;font-size:13px;">Failed to load projects</span>';
  }
}

async function switchProject(path) {
  await fetchJSON(`/api/project/switch?path=${encodeURIComponent(path)}`);
  await loadProjectList();
  loadStatus();
}

async function addProjectFromDashboard() {
  const input = document.getElementById('new-project-path');
  const path = input.value.trim();
  if (!path) return;
  await fetchJSON(`/api/project/add?path=${encodeURIComponent(path)}`);
  await fetchJSON(`/api/project/switch?path=${encodeURIComponent(path)}`);
  input.value = '';
  await loadProjectList();
  loadStatus();
}

async function removeProject(path) {
  if (!confirm('Remove this project from the list?')) return;
  await fetchJSON(`/api/project/remove?path=${encodeURIComponent(path)}`);
  await loadProjectList();
  loadStatus();
}

// ── Directory Browser ──

async function browseTo(path) {
  _currentBrowsePath = path;
  const pathBar = document.getElementById('browse-path-bar');
  const listEl = document.getElementById('browse-list');
  pathBar.textContent = path || '/ (drives)';
  listEl.innerHTML = '<span style="color:#6F7D96;font-size:12px;padding:8px;">Loading...</span>';

  try {
    const data = await fetchJSON(`/api/project/browse?path=${encodeURIComponent(path)}`);
    const dirs = data.directories || [];
    if (dirs.length === 0) {
      listEl.innerHTML = '<span style="color:#6F7D96;font-size:12px;padding:8px;">Empty directory</span>';
      return;
    }
    listEl.innerHTML = dirs.map(d => {
      const icon = d.has_git ? '📂' : '📁';
      const badge = d.project_type ? `<span style="font-size:10px;color:#43e6c3;background:rgba(67,230,195,0.1);padding:1px 5px;border-radius:3px;margin-left:6px;">${escapeHtml(d.project_type)}</span>` : '';
      return `<div data-browse-path="${escapeHtml(d.path)}" style="display:flex;align-items:center;gap:8px;padding:6px 10px;border-radius:6px;cursor:pointer;transition:background 0.1s;" onmouseover="this.style.background='rgba(255,255,255,0.03)'" onmouseout="this.style.background=''">
        <span style="font-size:14px;">${icon}</span>
        <span style="flex:1;font-size:12px;color:#e0e0e0;font-family:monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(d.name)}</span>
        ${badge}
        <button data-select-path="${escapeHtml(d.path)}" style="font-size:10px;color:#43e6c3;background:rgba(67,230,195,0.08);border:1px solid rgba(67,230,195,0.3);border-radius:4px;padding:2px 8px;cursor:pointer;">Select</button>
      </div>`;
    }).join('');
  } catch (e) {
    listEl.innerHTML = `<span style="color:#ff6b7a;font-size:12px;padding:8px;">Failed to browse</span>`;
  }
}

function browseUp() {
  if (!_currentBrowsePath) return;
  const parts = _currentBrowsePath.replace(/\\/g, '/').split('/').filter(Boolean);
  parts.pop();
  if (parts.length === 0) {
    browseTo('');
  } else {
    // Reconstruct path: on Windows keep drive letter format
    const parent = parts.length === 1 && parts[0].endsWith(':') ? parts[0] + '/' : parts.join('/');
    browseTo(parent);
  }
}

async function selectBrowsedProject(path) {
  await fetchJSON(`/api/project/add?path=${encodeURIComponent(path)}`);
  await fetchJSON(`/api/project/switch?path=${encodeURIComponent(path)}`);
  await loadProjectList();
  loadStatus();
}

// ── Custom Agent ──

function showAddCustomAgent() {
  const overlay = document.getElementById('add-agent-overlay');
  overlay.style.display = 'flex';
  // Clear previous values
  document.getElementById('ca-name').value = '';
  document.getElementById('ca-command').value = '';
  document.getElementById('ca-args').value = '';
  document.getElementById('ca-display').value = '';
  // Focus first field
  setTimeout(() => document.getElementById('ca-name').focus(), 100);
}

function closeAddAgentDialog() {
  document.getElementById('add-agent-overlay').style.display = 'none';
}

// Close dialog on overlay background click
document.getElementById('add-agent-overlay').addEventListener('click', function(e) {
  if (e.target === this) closeAddAgentDialog();
});

function submitAddAgent() {
  const name = document.getElementById('ca-name').value.trim();
  const command = document.getElementById('ca-command').value.trim();
  const argsStr = document.getElementById('ca-args').value.trim();
  const displayName = document.getElementById('ca-display').value.trim() || name;

  if (!name) { document.getElementById('ca-name').focus(); return; }
  if (!command) { document.getElementById('ca-command').focus(); return; }

  const args = argsStr ? argsStr.split(/\s+/) : [];
  closeAddAgentDialog();
  addCustomAgent(name, command, args, displayName);
}

async function addCustomAgent(name, command, args, displayName) {
  if (window._installTerm) {
    window._installTerm.clear();
    window._installTerm.writeln(`\x1b[90m$ Adding custom agent: ${displayName}\x1b[0m`);
    window._installTerm.writeln(`  Command: ${command} ${args.join(' ')}`);
  }

  try {
    const params = new URLSearchParams({
      name: name,
      command: command,
      args: JSON.stringify(args),
      display_name: displayName,
    });
    const res = await fetch(`/api/cli/add?${params.toString()}`);
    const result = await res.json();
    if (result.success) {
      if (window._installTerm) window._installTerm.writeln(`\x1b[32m✅ ${result.message || 'Added successfully'}\x1b[0m`);
      updateInstallStatus('done');
      loadCliList();
    } else {
      if (window._installTerm) window._installTerm.writeln(`\x1b[31m❌ ${result.message || 'Failed'}\x1b[0m`);
      updateInstallStatus('error');
    }
  } catch (e) {
    if (window._installTerm) window._installTerm.writeln(`\x1b[31m❌ Error: ${e.message}\x1b[0m`);
    updateInstallStatus('error');
  }
}

// ── Init ──

async function init() {
  // Load translations first, then data
  if (typeof initI18n === 'function') await initI18n();
  loadStatus();
  loadConnectInfo();
  loadCliList();
}

init();

// Refresh status every 5s
setInterval(loadStatus, 5000);

// Start log polling when logs tab is opened
document.querySelector('.nav-tab[data-tab="logs"]').addEventListener('click', () => {
  startLogPolling();
});

// ── Install terminal (xterm.js) ──
// Initialize when Agent tab is first opened
let _installTermInitialized = false;
document.querySelector('.nav-tab[data-tab="agents"]').addEventListener('click', () => {
  if (_installTermInitialized) return;
  _installTermInitialized = true;
  setTimeout(() => {
    const container = document.getElementById('install-terminal');
    if (!container || typeof Terminal === 'undefined') return;
    const term = new Terminal({
      theme: { background: '#0d0e17', foreground: '#c8d3f5', cursor: '#43e6c3' },
      fontSize: 12,
      fontFamily: "'JetBrains Mono', 'Consolas', monospace",
      cursorBlink: false,
      disableStdin: true,
      scrollback: 1000,
      convertEol: true,
    });
    const fit = new FitAddon.FitAddon();
    term.loadAddon(fit);
    term.open(container);
    fit.fit();
    term.writeln('\x1b[90m— Click Install to see output here —\x1b[0m');
    window._installTerm = term;
    window._installFit = fit;
    window.addEventListener('resize', () => fit.fit());
  }, 100);
});
