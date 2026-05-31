/**
 * i18n.js — Lightweight internationalization for MobileFlow Dashboard.
 *
 * Detects browser language, loads the corresponding JSON translation file,
 * and provides a t() function for string lookup with parameter substitution.
 *
 * Usage:
 *   await initI18n();           // Call once on page load
 *   t('nav.home')               // → "Home" or "首页"
 *   t('agent.testPassed', name) // → "claude-code test passed ✅"
 *
 * HTML elements with data-i18n="key" are auto-translated on init.
 * Elements with data-i18n-placeholder="key" get their placeholder translated.
 */

let _translations = {};
let _lang = 'en';

/**
 * Initialize i18n: detect language and load translations.
 * Call this once before using t() or translatePage().
 */
async function initI18n() {
  _lang = navigator.language.startsWith('zh') ? 'zh' : 'en';

  try {
    const res = await fetch(`/i18n/${_lang}.json`);
    if (res.ok) {
      _translations = await res.json();
    } else {
      // Fallback to English if preferred language file not found
      if (_lang !== 'en') {
        const fallback = await fetch('/i18n/en.json');
        if (fallback.ok) _translations = await fallback.json();
      }
    }
  } catch (e) {
    console.warn('i18n: Failed to load translations', e);
  }

  translatePage();
}

/**
 * Translate a key with optional parameter substitution.
 *
 * Parameters are positional: {0}, {1}, {2}, etc.
 * Example: t('backend.installFailed', 'Claude Code', 'network error')
 *          → "Claude Code install failed: network error"
 *
 * @param {string} key - Translation key (e.g. 'nav.home')
 * @param {...string} args - Positional parameters to substitute
 * @returns {string} Translated string, or the key itself if not found
 */
function t(key, ...args) {
  let str = _translations[key] || key;
  for (let i = 0; i < args.length; i++) {
    str = str.replace(`{${i}}`, args[i]);
  }
  return str;
}

/**
 * Translate a backend message_key with fallback to raw message.
 *
 * Backend responses include both `message` (Chinese default) and
 * `message_key` (translation key). This function tries the key first,
 * falls back to the raw message if key is not found.
 *
 * @param {object} response - Backend response with message and message_key
 * @param {...string} args - Parameters for the translation key
 * @returns {string} Translated message
 */
function tBackend(response, ...args) {
  if (response.message_key && _translations[response.message_key]) {
    return t(response.message_key, ...args);
  }
  return response.message || '';
}

/**
 * Auto-translate all DOM elements with data-i18n attributes.
 * Called once after translations are loaded.
 */
function translatePage() {
  // Translate text content
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (_translations[key]) {
      el.textContent = _translations[key];
    }
  });

  // Translate placeholders
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    const key = el.getAttribute('data-i18n-placeholder');
    if (_translations[key]) {
      el.placeholder = _translations[key];
    }
  });

  // Translate title/tooltip
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    const key = el.getAttribute('data-i18n-title');
    if (_translations[key]) {
      el.title = _translations[key];
    }
  });
}

/**
 * Get the current language code.
 * @returns {string} 'en' or 'zh'
 */
function getLang() {
  return _lang;
}
