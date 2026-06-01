/**
 * connection.js — Connection settings page logic.
 *
 * Handles:
 * - Loading current connection config from API
 * - Status polling (every 5s) to update mode indicators
 * - Form submission with validation error display
 * - Bearer token masking/reveal toggle
 */

// ── Status polling ──

let _connStatusInterval = null;

async function loadConnectionStatus() {
  try {
    const res = await fetch('/api/connection/status');
    const data = await res.json();
    updateStatusDisplay(data);
  } catch (e) {
    console.error('Failed to load connection status:', e);
  }
}

function updateStatusDisplay(status) {
  // LAN
  const lanDot = document.querySelector('#conn-lan-card .conn-dot');
  const lanDetail = document.getElementById('conn-lan-detail');
  if (status.lan) {
    lanDot.className = 'conn-dot ' + status.lan.status;
    lanDetail.textContent = status.lan.address || '--';
  }

  // Tunnel
  const tunnelDot = document.querySelector('#conn-tunnel-card .conn-dot');
  const tunnelDetail = document.getElementById('conn-tunnel-detail');
  if (status.tunnel) {
    tunnelDot.className = 'conn-dot ' + status.tunnel.status;
    if (status.tunnel.status === 'active') {
      tunnelDetail.textContent = 'port ' + (status.tunnel.port || '9601');
    } else if (status.tunnel.status === 'error') {
      tunnelDetail.textContent = status.tunnel.error || 'error';
      tunnelDetail.style.color = '#e57373';
    } else {
      tunnelDetail.textContent = 'not configured';
      tunnelDetail.style.color = '#888';
    }
  }

  // Relay
  const relayDot = document.querySelector('#conn-relay-card .conn-dot');
  const relayDetail = document.getElementById('conn-relay-detail');
  if (status.relay) {
    relayDot.className = 'conn-dot ' + status.relay.status;
    if (status.relay.status === 'active') {
      relayDetail.textContent = status.relay.url || '--';
    } else if (status.relay.status === 'error') {
      relayDetail.textContent = status.relay.error || 'error';
      relayDetail.style.color = '#e57373';
    } else {
      relayDetail.textContent = 'not configured';
      relayDetail.style.color = '#888';
    }
  }
}

// ── Load config into form ──

async function loadConnectionConfig() {
  try {
    const res = await fetch('/api/connection/config');
    const data = await res.json();
    document.getElementById('conn-tunnel-cert').value = data.tunnel_tls_cert || '';
    document.getElementById('conn-tunnel-key').value = data.tunnel_tls_key || '';
    document.getElementById('conn-tunnel-port').value = data.tunnel_port || 9601;
    document.getElementById('conn-relay-url').value = data.relay_url || '';
    // Token: show masked value as placeholder, don't fill the field
    const tokenInput = document.getElementById('conn-tunnel-token');
    if (data.tunnel_bearer_token_set) {
      tokenInput.placeholder = data.tunnel_bearer_token + ' (saved)';
    } else {
      tokenInput.placeholder = 'your-secret-token';
    }
    tokenInput.value = '';
  } catch (e) {
    console.error('Failed to load connection config:', e);
  }
}

// ── Save config ──

async function saveConnectionConfig() {
  const btn = document.getElementById('conn-save-btn');
  const statusEl = document.getElementById('conn-save-status');
  const errorsEl = document.getElementById('conn-errors');

  btn.disabled = true;
  statusEl.textContent = 'Saving...';
  statusEl.style.color = '#888';
  errorsEl.style.display = 'none';
  errorsEl.innerHTML = '';

  const params = new URLSearchParams();
  params.set('tunnel_tls_cert', document.getElementById('conn-tunnel-cert').value.trim());
  params.set('tunnel_tls_key', document.getElementById('conn-tunnel-key').value.trim());
  params.set('tunnel_port', document.getElementById('conn-tunnel-port').value || '9601');
  params.set('relay_url', document.getElementById('conn-relay-url').value.trim());

  // Only send token if user typed a new one (don't overwrite with empty)
  const tokenVal = document.getElementById('conn-tunnel-token').value;
  if (tokenVal) {
    params.set('tunnel_bearer_token', tokenVal);
  }

  try {
    const res = await fetch('/api/connection/config/save?' + params.toString());
    const data = await res.json();

    if (data.success) {
      statusEl.textContent = '✓ Saved & applied';
      statusEl.style.color = '#43e6c3';
      // Update status display
      if (data.status) updateStatusDisplay(data.status);
      // Reload config to show masked token
      await loadConnectionConfig();
    } else {
      statusEl.textContent = 'Validation failed';
      statusEl.style.color = '#e57373';
      // Show field errors
      if (data.errors) {
        errorsEl.style.display = 'block';
        for (const [field, msg] of Object.entries(data.errors)) {
          const div = document.createElement('div');
          div.style.cssText = 'font-size:12px;color:#e57373;margin-top:4px;';
          div.textContent = `${field}: ${msg}`;
          errorsEl.appendChild(div);
        }
      }
    }
  } catch (e) {
    statusEl.textContent = 'Network error';
    statusEl.style.color = '#e57373';
  } finally {
    btn.disabled = false;
    setTimeout(() => { statusEl.textContent = ''; }, 5000);
  }
}

// ── Token visibility toggle ──

function toggleTokenVisibility() {
  const input = document.getElementById('conn-tunnel-token');
  const btn = document.getElementById('conn-token-toggle');
  if (input.type === 'password') {
    input.type = 'text';
    btn.textContent = '🙈';
  } else {
    input.type = 'password';
    btn.textContent = '👁';
  }
}

// ── Init on tab switch ──

// Listen for tab changes to start/stop polling
const _origTabSwitch = window.switchTab;
if (typeof switchTab === 'function') {
  // Monkey-patch the existing tab switch to hook into connection tab
  const _origFn = switchTab;
  window.switchTab = function(tab) {
    _origFn(tab);
    if (tab === 'connection') {
      loadConnectionConfig();
      loadConnectionStatus();
      if (!_connStatusInterval) {
        _connStatusInterval = setInterval(loadConnectionStatus, 5000);
      }
    } else {
      if (_connStatusInterval) {
        clearInterval(_connStatusInterval);
        _connStatusInterval = null;
      }
    }
  };
}

// Also load on page load if connection tab is active
document.addEventListener('DOMContentLoaded', () => {
  // Check if connection tab is visible (unlikely on first load, but handle it)
  const connTab = document.getElementById('tab-connection');
  if (connTab && !connTab.classList.contains('hidden')) {
    loadConnectionConfig();
    loadConnectionStatus();
    _connStatusInterval = setInterval(loadConnectionStatus, 5000);
  }
});
