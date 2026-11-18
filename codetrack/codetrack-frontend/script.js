/* =====================================================================
   CodeTrack — frontend (plain JS, hash routing, no dependencies)
   ===================================================================== */
'use strict';

const API_BASE = 'http://localhost:8080/api';

/* ---------------------------------------------------------------------
   Constants
   --------------------------------------------------------------------- */
const STORAGE_TOKEN = 'codetrack.token';
const STORAGE_USER = 'codetrack.user';
const NETWORK_ERROR_MSG = "Can't reach the CodeTrack server — is the backend running on port 8080?";
const SESSION_EXPIRED_MSG = 'Your session has expired, please log in again';

/** Platform metadata. `stats` lists [label, field] pairs shown on cards. */
const PLATFORMS = [
  {
    key: 'LEETCODE', name: 'LeetCode', color: '#ffa116', mono: 'LC',
    example: 'https://leetcode.com/u/your-username/',
    stats: [['Solved', 'totalSolved'], ['Rating', 'rating'], ['Contests', 'contests'],
            ['Easy', 'easySolved'], ['Medium', 'mediumSolved'], ['Hard', 'hardSolved']],
  },
  {
    key: 'GEEKSFORGEEKS', name: 'GeeksforGeeks', color: '#2f8d46', mono: 'GfG',
    example: 'https://www.geeksforgeeks.org/user/your-username/',
    stats: [['Solved', 'totalSolved'], ['Score', 'score'], ['Hard', 'hardSolved'],
            ['Easy', 'easySolved'], ['Medium', 'mediumSolved'], ['Rank', 'globalRank']],
  },
  {
    key: 'CODECHEF', name: 'CodeChef', color: '#b8794b', mono: 'CC',
    example: 'https://www.codechef.com/users/your-username',
    stats: [['Rating', 'rating'], ['Max rating', 'maxRating'], ['Stars', 'rankTitle'],
            ['Contests', 'contests'], ['Solved', 'totalSolved'], ['Global rank', 'globalRank']],
  },
  {
    key: 'CODEFORCES', name: 'Codeforces', color: '#1f8acb', mono: 'CF',
    example: 'https://codeforces.com/profile/your-handle',
    stats: [['Rating', 'rating'], ['Max rating', 'maxRating'], ['Rank', 'rankTitle'],
            ['Contests', 'contests'], ['Solved', 'totalSolved']],
  },
  {
    key: 'GITHUB', name: 'GitHub', color: '#e6edf3', mono: 'GH',
    example: 'https://github.com/your-username',
    stats: [['Repos', 'repos'], ['Stars', 'stars'], ['Followers', 'followers']],
  },
];
const PLATFORM_BY_KEY = Object.fromEntries(PLATFORMS.map((p) => [p.key, p]));

const ROLE_LABEL = { STUDENT: 'Student', COLLEGE: 'College', RECRUITER: 'Recruiter' };

/** Navigable routes. `roles` = who may open it. */
const ROUTES = {
  dashboard:   { title: 'Dashboard',          roles: ['STUDENT'],                         icon: 'home',   render: renderDashboard },
  platforms:   { title: 'Platforms',          roles: ['STUDENT'],                         icon: 'plug',   render: renderPlatforms },
  leaderboard: { title: 'Leaderboard',        roles: ['STUDENT'],                         icon: 'trophy', render: () => renderLeaderboard('leaderboard') },
  college:     { title: 'College Dashboard',  roles: ['COLLEGE'],                         icon: 'school', render: renderCollege },
  explore:     { title: 'Explore Students',   roles: ['COLLEGE', 'RECRUITER'],            icon: 'search', render: () => renderLeaderboard('explore') },
  profile:     { title: 'Profile',            roles: ['STUDENT', 'COLLEGE', 'RECRUITER'], icon: 'user',   render: renderProfile },
};
const NAV_BY_ROLE = {
  STUDENT: ['dashboard', 'platforms', 'leaderboard', 'profile'],
  COLLEGE: ['college', 'explore', 'profile'],
  RECRUITER: ['explore', 'profile'],
};
const HOME_BY_ROLE = { STUDENT: 'dashboard', COLLEGE: 'college', RECRUITER: 'explore' };

const ICONS = {
  home: '<path d="M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z"/>',
  plug: '<path d="M9 2v6M15 2v6M6 8h12v3a6 6 0 01-12 0zM12 17v5"/>',
  trophy: '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 01-10 0zM17 5h3v2a3 3 0 01-3 3M7 5H4v2a3 3 0 003 3"/>',
  school: '<path d="M2 9l10-5 10 5-10 5zM6 11v5c3 2 9 2 12 0v-5M22 9v6"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0116 0"/>',
  code: '<path d="M9 6l-6 6 6 6M15 6l6 6-6 6"/>',
  check: '<path d="M20 6L9 17l-5-5"/>',
  layers: '<path d="M12 3l9 5-9 5-9-5zM3 13l9 5 9-5"/>',
  flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  medal: '<circle cx="12" cy="15" r="6"/><path d="M8 3l4 6 4-6"/>',
  star: '<path d="M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z"/>',
  sync: '<path d="M21 12a9 9 0 01-15.5 6.2M3 12A9 9 0 0118.5 5.8M21 4v5h-5M3 20v-5h5"/>',
  ext: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1h5"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  pin: '<path d="M12 21s-7-6.5-7-12a7 7 0 0114 0c0 5.5-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/>',
  cal: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  cap: '<path d="M2 9l10-5 10 5-10 5zM6 11v5c3 2 9 2 12 0v-5"/>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2 20a7 7 0 0114 0M16 4.5a3.5 3.5 0 010 7M22 20a7 7 0 00-4-6.3"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a1 1 0 011-1h10"/>',
};
function icon(name, size = 18) {
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;
}

/* ---------------------------------------------------------------------
   DOM refs
   --------------------------------------------------------------------- */
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

const els = {
  authView: document.getElementById('auth-view'),
  authPlatforms: document.getElementById('auth-platforms'),
  loginForm: document.getElementById('login-form'),
  loginError: document.getElementById('login-error'),
  loginSubmit: document.getElementById('login-submit'),
  registerForm: document.getElementById('register-form'),
  registerError: document.getElementById('register-error'),
  registerSubmit: document.getElementById('register-submit'),
  app: document.getElementById('app'),
  nav: document.getElementById('nav'),
  userName: document.getElementById('user-name'),
  userRole: document.getElementById('user-role'),
  userAvatar: document.getElementById('user-avatar'),
  logoutBtn: document.getElementById('logout-btn'),
  menuToggle: document.getElementById('menu-toggle'),
  sidebarBackdrop: document.getElementById('sidebar-backdrop'),
  main: document.getElementById('main'),
  view: document.getElementById('view'),
  modalRoot: document.getElementById('modal-root'),
  toastRoot: document.getElementById('toast-root'),
};

/* ---------------------------------------------------------------------
   Utilities: escaping, formatting, dates, urls
   --------------------------------------------------------------------- */
/** Escape any value for safe insertion into HTML text or attribute values. */
function esc(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Format a number with locale separators; null/undefined/NaN → "—". */
function fmt(n) {
  if (n === null || n === undefined || n === '') return '—';
  const num = Number(n);
  return Number.isFinite(num) ? num.toLocaleString() : esc(n);
}
/** Like fmt but for possibly-string values (e.g. rankTitle). Always escaped. */
function fmtAny(v) {
  if (v === null || v === undefined || v === '') return '—';
  return typeof v === 'number' ? v.toLocaleString() : esc(v);
}
const num = (n) => (Number.isFinite(Number(n)) && n !== null ? Number(n) : 0);

/** Only allow http(s) URLs into href attributes. Returns escaped URL or null. */
function safeUrl(url) {
  if (!url || typeof url !== 'string') return null;
  try {
    const u = new URL(url);
    return u.protocol === 'http:' || u.protocol === 'https:' ? esc(u.href) : null;
  } catch {
    return null;
  }
}

function relativeTime(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const sec = Math.round((Date.now() - d.getTime()) / 1000);
  if (sec < 45) return 'just now';
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} min ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr} h ago`;
  const day = Math.round(hr / 24);
  if (day < 30) return `${day} day${day === 1 ? '' : 's'} ago`;
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}
function formatDate(iso, opts = { day: 'numeric', month: 'short', year: 'numeric' }) {
  if (!iso) return '—';
  const d = new Date(iso.length === 10 ? iso + 'T00:00:00' : iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString(undefined, opts);
}

function initials(name) {
  return String(name || '?').trim().split(/\s+/).slice(0, 2).map((s) => s[0]).join('').toUpperCase() || '?';
}

function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

/* ---------------------------------------------------------------------
   Session storage (token + user)
   --------------------------------------------------------------------- */
const session = {
  get token() { try { return localStorage.getItem(STORAGE_TOKEN); } catch { return null; } },
  get user() {
    try { return JSON.parse(localStorage.getItem(STORAGE_USER) || 'null'); } catch { return null; }
  },
  set(token, user) {
    if (token) localStorage.setItem(STORAGE_TOKEN, token);
    if (user) localStorage.setItem(STORAGE_USER, JSON.stringify(user));
    renderUserChip();
  },
  setUser(user) {
    if (!user) return;
    localStorage.setItem(STORAGE_USER, JSON.stringify(user));
    renderUserChip();
  },
  clear() {
    try { localStorage.removeItem(STORAGE_TOKEN); localStorage.removeItem(STORAGE_USER); } catch { /* ignore */ }
  },
  get loggedIn() { return !!(this.token && this.user); },
};

/* ---------------------------------------------------------------------
   API helper
   --------------------------------------------------------------------- */
class ApiError extends Error {
  constructor(status, message, fields = null) {
    super(message);
    this.status = status;
    this.fields = fields;
    this.handled = false; // true when we already reacted globally (e.g. session expired)
  }
}

/**
 * Call the backend.
 * @param {string} path  path relative to API_BASE, e.g. "/dashboard"
 * @param {object} opts  { method, body, auth = true, logoutOn401 = true }
 */
async function api(path, { method = 'GET', body, auth = true, logoutOn401 = true } = {}) {
  const headers = { Accept: 'application/json' };
  const token = auth ? session.token : null;
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  let res;
  try {
    res = await fetch(API_BASE + path, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError(0, NETWORK_ERROR_MSG);
  }

  let data = null;
  if (res.status !== 204) {
    const text = await res.text().catch(() => '');
    if (text) { try { data = JSON.parse(text); } catch { data = null; } }
  }

  if (!res.ok) {
    const message = (data && data.message) || defaultErrorMessage(res.status);
    const err = new ApiError(res.status, message, data && data.fields);
    if (res.status === 401 && token && logoutOn401 && path !== '/auth/login') {
      err.handled = true;
      sessionExpired();
    }
    throw err;
  }
  return data;
}

function defaultErrorMessage(status) {
  if (status === 401) return 'Please log in to continue.';
  if (status === 403) return "You don't have access to this.";
  if (status === 404) return 'Not found.';
  if (status >= 500) return 'The server ran into a problem. Please try again.';
  return `Request failed (${status}).`;
}

function sessionExpired() {
  session.clear();
  closeModal();
  toast(SESSION_EXPIRED_MSG, 'error');
  if (location.hash !== '#/login') location.hash = '#/login';
  else router();
}

/** Show an error toast unless it was already handled globally. */
function toastError(err) {
  if (err && err.handled) return;
  toast((err && err.message) || 'Something went wrong.', 'error');
}

/* ---------------------------------------------------------------------
   Toasts
   --------------------------------------------------------------------- */
function toast(message, type = 'info', ms = 4200) {
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.setAttribute('role', type === 'error' ? 'alert' : 'status');
  el.textContent = message;
  els.toastRoot.appendChild(el);
  setTimeout(() => {
    el.classList.add('leaving');
    setTimeout(() => el.remove(), 220);
  }, ms);
}

/* ---------------------------------------------------------------------
   Busy buttons
   --------------------------------------------------------------------- */
/** Disable `btn`, show a spinner, run `fn`, restore. Returns fn's result. */
async function withBusy(btn, fn, busyLabel) {
  if (!btn) return fn();
  if (btn.disabled) return undefined;
  const original = btn.innerHTML;
  btn.disabled = true;
  btn.setAttribute('aria-busy', 'true');
  btn.innerHTML = `<span class="spinner" aria-hidden="true"></span>${busyLabel ? esc(busyLabel) : original}`;
  try {
    return await fn();
  } finally {
    if (btn.isConnected) {
      btn.disabled = false;
      btn.removeAttribute('aria-busy');
      btn.innerHTML = original;
    }
  }
}

/* ---------------------------------------------------------------------
   Modals
   --------------------------------------------------------------------- */
let activeModal = null;

/**
 * Open a modal. `content` is trusted HTML (callers escape). Returns { el, close }.
 */
function openModal({ title, content, onClose, iconHtml = '' }) {
  closeModal();
  const previousFocus = document.activeElement;
  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';
  backdrop.innerHTML = `
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
      <div class="modal-head">
        ${iconHtml}
        <h2 id="modal-title">${esc(title)}</h2>
        <button type="button" class="icon-btn modal-close" aria-label="Close dialog">${icon('close', 16)}</button>
      </div>
      <div class="modal-body">${content}</div>
    </div>`;
  els.modalRoot.appendChild(backdrop);
  document.body.style.overflow = 'hidden';

  const close = () => {
    if (!backdrop.isConnected) return;
    backdrop.remove();
    document.removeEventListener('keydown', onKey, true);
    document.body.style.overflow = '';
    if (activeModal && activeModal.backdrop === backdrop) activeModal = null;
    if (previousFocus && previousFocus.isConnected) previousFocus.focus();
    if (onClose) onClose();
  };
  const onKey = (e) => {
    if (e.key === 'Escape') { e.stopPropagation(); close(); return; }
    if (e.key === 'Tab') trapFocus(e, backdrop);
  };
  backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) close(); });
  $('.modal-close', backdrop).addEventListener('click', close);
  document.addEventListener('keydown', onKey, true);

  const focusTarget = $('input, select, textarea', backdrop) || $('.modal-body button', backdrop) || $('.modal-close', backdrop);
  setTimeout(() => focusTarget && focusTarget.focus(), 20);

  activeModal = { backdrop, close };
  return { el: backdrop, close };
}
function closeModal() { if (activeModal) activeModal.close(); }

function trapFocus(e, root) {
  const f = $$('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])', root)
    .filter((n) => !n.disabled && n.offsetParent !== null);
  if (!f.length) return;
  const first = f[0];
  const last = f[f.length - 1];
  if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
  else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
}

/** Promise-based confirm dialog. Resolves true if confirmed. */
function confirmDialog({ title, message, confirmText = 'Confirm', danger = false }) {
  return new Promise((resolve) => {
    let result = false;
    const m = openModal({
      title,
      content: `
        <p class="lead">${esc(message)}</p>
        <div class="form-actions">
          <button type="button" class="btn btn-ghost" data-act="cancel">Cancel</button>
          <button type="button" class="btn ${danger ? 'btn-danger-solid' : 'btn-primary'}" data-act="ok">${esc(confirmText)}</button>
        </div>`,
      onClose: () => resolve(result),
    });
    $('[data-act="cancel"]', m.el).addEventListener('click', () => m.close());
    $('[data-act="ok"]', m.el).addEventListener('click', () => { result = true; m.close(); });
    setTimeout(() => $('[data-act="ok"]', m.el).focus(), 30);
  });
}

/* ---------------------------------------------------------------------
   Form helpers (field errors)
   --------------------------------------------------------------------- */
function clearFormErrors(form) {
  $$('.field-error', form).forEach((p) => { p.textContent = ''; });
  $$('.invalid', form).forEach((i) => { i.classList.remove('invalid'); i.removeAttribute('aria-invalid'); });
  const fe = $('.form-error', form);
  if (fe) fe.textContent = '';
}
/** Show per-field messages: `fields` is { name: message }. Returns true if any shown. */
function showFieldErrors(form, fields) {
  if (!fields) return false;
  let any = false;
  Object.entries(fields).forEach(([name, msg]) => {
    const p = $(`.field-error[data-for="${CSS.escape(name)}"]`, form);
    const input = form.elements[name];
    if (p) { p.textContent = String(msg); any = true; }
    if (input && input.classList) { input.classList.add('invalid'); input.setAttribute('aria-invalid', 'true'); }
  });
  return any;
}
function setFormError(form, msg) {
  const fe = $('.form-error', form);
  if (fe) fe.textContent = msg || '';
}
function handleFormError(form, err) {
  if (err.handled) return;
  const shown = showFieldErrors(form, err.fields);
  setFormError(form, shown && err.status === 400 && !err.message ? '' : err.message);
}
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/* ---------------------------------------------------------------------
   Shared UI components
   --------------------------------------------------------------------- */
function platformIcon(key, small = false) {
  const p = PLATFORM_BY_KEY[key] || { color: '#a78bfa', mono: '?' };
  return `<span class="p-icon${small ? ' p-icon-sm' : ''}" style="--pc:${p.color}" aria-hidden="true">${esc(p.mono)}</span>`;
}
function platformChip(key) {
  const p = PLATFORM_BY_KEY[key];
  if (!p) return `<span class="chip">${esc(key)}</span>`;
  return `<span class="chip" style="--pc:${p.color}"><span class="chip-dot"></span>${esc(p.name)}</span>`;
}
function platformDot(key) {
  const p = PLATFORM_BY_KEY[key];
  if (!p) return '';
  return `<span class="dot-chip" style="--pc:${p.color}" title="${esc(p.name)}" aria-label="${esc(p.name)}">${esc(p.mono)}</span>`;
}

function statCard(label, value, sub, iconName) {
  return `
    <div class="stat">
      <div class="stat-label">${iconName ? `<span class="stat-icon">${icon(iconName, 15)}</span>` : ''}${esc(label)}</div>
      <div class="stat-value">${value}</div>
      ${sub ? `<div class="stat-sub">${sub}</div>` : ''}
    </div>`;
}

function pageHead(title, subtitle, actionsHtml = '') {
  return `
    <div class="page-head">
      <div><h1>${esc(title)}</h1>${subtitle ? `<p>${subtitle}</p>` : ''}</div>
      ${actionsHtml ? `<div class="row">${actionsHtml}</div>` : ''}
    </div>`;
}

function emptyState({ title, text = '', iconName = 'code', actionHtml = '', small = false }) {
  return `
    <div class="empty${small ? ' empty-sm' : ''}">
      ${small ? '' : `<div class="empty-icon">${icon(iconName, 26)}</div>`}
      <h3>${esc(title)}</h3>
      ${text ? `<p>${text}</p>` : ''}
      ${actionHtml}
    </div>`;
}

function errorState(err, retryLabel = 'Try again') {
  return `
    <div class="card error-box">
      ${emptyState({ title: 'Something went wrong', text: esc(err.message), iconName: 'close',
        actionHtml: `<button type="button" class="btn" data-retry>${esc(retryLabel)}</button>` })}
    </div>`;
}
/** Wire up any [data-retry] button inside the view to re-run the router. */
function bindRetry() {
  $$('[data-retry]', els.view).forEach((b) => b.addEventListener('click', () => router()));
}

function skeletonDashboard() {
  return `
    <div class="sk-line skeleton" style="width:220px;height:28px;margin-bottom:10px"></div>
    <div class="sk-line skeleton" style="width:320px;margin-bottom:26px"></div>
    <div class="stats">${'<div class="skeleton" style="height:96px"></div>'.repeat(5)}</div>
    <div class="grid grid-2" style="margin-top:16px">
      <div class="skeleton" style="height:200px"></div><div class="skeleton" style="height:200px"></div>
    </div>
    <div class="skeleton" style="height:260px;margin-top:16px"></div>`;
}
function skeletonCards(n = 5) {
  return `<div class="platform-grid">${'<div class="skeleton" style="height:210px"></div>'.repeat(n)}</div>`;
}
function skeletonRows(n = 6) {
  return `<div class="stack" style="gap:8px">${'<div class="skeleton" style="height:52px;border-radius:10px"></div>'.repeat(n)}</div>`;
}

/** Difficulty breakdown: stacked bar + legend. */
function difficultyBlock(s) {
  const e = num(s.easySolved), m = num(s.mediumSolved), h = num(s.hardSolved);
  const total = e + m + h;
  if (!total) {
    return emptyState({ title: 'No difficulty data yet', text: 'Connect LeetCode or GeeksforGeeks and sync to see your easy / medium / hard split.', small: true });
  }
  const pct = (x) => (x / total) * 100;
  const pctLabel = (x) => `${Math.round(pct(x))}%`;
  return `
    <div class="diff-bar" role="img" aria-label="Easy ${e}, Medium ${m}, Hard ${h}">
      <span style="width:${pct(e)}%;background:var(--easy)"></span>
      <span style="width:${pct(m)}%;background:var(--medium)"></span>
      <span style="width:${pct(h)}%;background:var(--hard)"></span>
    </div>
    <div class="diff-legend">
      <div class="diff-item" style="--c:var(--easy)"><div class="k">Easy</div><div class="v">${fmt(e)}</div><div class="p">${pctLabel(e)}</div></div>
      <div class="diff-item" style="--c:var(--medium)"><div class="k">Medium</div><div class="v">${fmt(m)}</div><div class="p">${pctLabel(m)}</div></div>
      <div class="diff-item" style="--c:var(--hard)"><div class="k">Hard</div><div class="v">${fmt(h)}</div><div class="p">${pctLabel(h)}</div></div>
    </div>`;
}

/** Best ratings per platform list. */
function ratingsBlock(bestRatings) {
  const entries = Object.entries(bestRatings || {}).filter(([, v]) => v !== null && v !== undefined);
  if (!entries.length) {
    return emptyState({ title: 'No ratings yet', text: 'Take part in contests on Codeforces, LeetCode or CodeChef to see ratings here.', small: true });
  }
  entries.sort((a, b) => num(b[1]) - num(a[1]));
  return `<div class="ratings">${entries.map(([k, v]) => {
    const p = PLATFORM_BY_KEY[k];
    return `<div class="rating-row">${platformIcon(k, true)}<span class="name">${esc(p ? p.name : k)}</span><span class="val">${fmt(v)}</span></div>`;
  }).join('')}</div>`;
}

/** Inline-SVG line chart for ProgressPoint[]. */
function progressChart(points) {
  const pts = (points || []).filter((p) => p && p.date).slice().sort((a, b) => (a.date < b.date ? -1 : 1));
  if (pts.length === 0) {
    return emptyState({ title: 'No progress history yet', text: 'Each day you sync, we record your total solved count. Check back after a couple of syncs.', small: true });
  }
  if (pts.length === 1) {
    return emptyState({ title: 'Your progress chart starts here',
      text: `Tracking began on <strong>${esc(formatDate(pts[0].date))}</strong> with <strong>${fmt(pts[0].totalSolved)}</strong> solved. Sync again on another day to see the trend.`, small: true });
  }
  const W = 640, H = 240, padL = 46, padR = 16, padT = 16, padB = 30;
  const vals = pts.map((p) => num(p.totalSolved));
  let min = Math.min(...vals), max = Math.max(...vals);
  if (min === max) { min = Math.max(0, min - 5); max += 5; }
  const range = max - min;
  min = Math.max(0, Math.floor(min - range * 0.08));
  max = Math.ceil(max + range * 0.08);
  const x = (i) => padL + (i / (pts.length - 1)) * (W - padL - padR);
  const y = (v) => padT + (1 - (v - min) / (max - min)) * (H - padT - padB);

  const ticks = 4;
  let grid = '';
  for (let i = 0; i <= ticks; i++) {
    const v = min + ((max - min) * i) / ticks;
    const yy = y(v).toFixed(1);
    grid += `<line class="grid-line" x1="${padL}" x2="${W - padR}" y1="${yy}" y2="${yy}"/>`;
    grid += `<text class="axis-label" x="${padL - 8}" y="${yy}" text-anchor="end" dominant-baseline="middle">${Math.round(v).toLocaleString()}</text>`;
  }
  const labelIdx = pts.length <= 3 ? pts.map((_, i) => i) : [0, Math.floor((pts.length - 1) / 2), pts.length - 1];
  const xLabels = labelIdx.map((i) => {
    const anchor = i === 0 ? 'start' : i === pts.length - 1 ? 'end' : 'middle';
    return `<text class="axis-label" x="${x(i).toFixed(1)}" y="${H - 8}" text-anchor="${anchor}">${esc(formatDate(pts[i].date, { day: 'numeric', month: 'short' }))}</text>`;
  }).join('');

  const line = pts.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(num(p.totalSolved)).toFixed(1)}`).join(' ');
  const area = `${line} L${x(pts.length - 1).toFixed(1)},${H - padB} L${x(0).toFixed(1)},${H - padB} Z`;
  const showDots = pts.length <= 60;
  const dots = showDots ? pts.map((p, i) =>
    `<circle class="pt" cx="${x(i).toFixed(1)}" cy="${y(num(p.totalSolved)).toFixed(1)}" r="3.5"><title>${esc(formatDate(p.date))}: ${num(p.totalSolved).toLocaleString()} solved</title></circle>`
  ).join('') : '';
  const first = num(pts[0].totalSolved), last = num(pts[pts.length - 1].totalSolved);
  const gid = `g${Math.random().toString(36).slice(2, 8)}`;

  return `
    <svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Total solved went from ${first} to ${last} between ${esc(formatDate(pts[0].date))} and ${esc(formatDate(pts[pts.length - 1].date))}">
      <defs><linearGradient id="${gid}" x1="0" x2="0" y1="0" y2="1">
        <stop offset="0%" stop-color="#8b5cf6" stop-opacity="0.35"/><stop offset="100%" stop-color="#8b5cf6" stop-opacity="0"/>
      </linearGradient></defs>
      ${grid}${xLabels}
      <path d="${area}" fill="url(#${gid})"/>
      <path class="line" d="${line}"/>
      ${dots}
    </svg>`;
}

/** Sync status footer for a PlatformProfile. */
function syncStatusHtml(p) {
  const status = p.syncStatus || 'PENDING';
  const when = relativeTime(p.lastSyncedAt);
  if (status === 'ERROR') {
    return `<div class="sync-error" role="note"><strong>Sync failed:</strong> ${esc(p.syncMessage || 'Unknown error')}</div>
            <div class="pcard-foot">${when ? `Last synced ${esc(when)}` : 'Never synced successfully'}</div>`;
  }
  if (status === 'PENDING') {
    return `<div class="pcard-foot"><span class="status status-pending">Not synced yet</span></div>`;
  }
  return `<div class="pcard-foot"><span class="status status-ok">Synced</span>${when ? `<span>· ${esc(when)}</span>` : ''}</div>`;
}

/** Card for a connected platform. `actionsHtml` is optional (Platforms page). */
function platformCard(p, actionsHtml = '') {
  const meta = PLATFORM_BY_KEY[p.platform] || { name: p.displayName || p.platform, color: '#a78bfa', stats: [] };
  const url = safeUrl(p.profileUrl);
  const stats = meta.stats.map(([label, field]) =>
    `<div class="pstat"><div class="pstat-label">${esc(label)}</div><div class="pstat-value">${fmtAny(p[field])}</div></div>`
  ).join('');
  return `
    <article class="pcard" style="--pc:${meta.color}">
      <div class="pcard-head">
        ${platformIcon(p.platform)}
        <div class="pcard-title">
          <div class="pcard-name">${esc(p.displayName || meta.name)}</div>
          <div class="pcard-user">@${esc(p.username)}</div>
        </div>
        ${url ? `<a class="ext-link" href="${url}" target="_blank" rel="noopener noreferrer" aria-label="Open ${esc(meta.name)} profile in a new tab">Profile ${icon('ext', 13)}</a>` : ''}
      </div>
      <div class="pcard-stats">${stats}</div>
      ${syncStatusHtml(p)}
      ${actionsHtml}
    </article>`;
}

/** Horizontal bar list: items = [{label, value, color?, iconHtml?}] */
function barsBlock(items) {
  const max = Math.max(1, ...items.map((i) => num(i.value)));
  return `<div class="bars">${items.map((i) => `
    <div class="bar-row">
      <span class="bl">${i.iconHtml || ''}${esc(i.label)}</span>
      <div class="bar-track" role="img" aria-label="${esc(i.label)}: ${num(i.value)}"><div class="bar-fill" style="width:${(num(i.value) / max) * 100}%;${i.color ? `--pc:${i.color}` : ''}"></div></div>
      <span class="bv">${fmt(i.value)}</span>
    </div>`).join('')}</div>`;
}

/** Leaderboard table. */
function leaderboardTable(entries, { showRank = true } = {}) {
  return `
    <div class="table-wrap">
      <table class="table">
        <thead><tr>
          ${showRank ? '<th scope="col">#</th>' : ''}
          <th scope="col">Student</th>
          <th scope="col">Platforms</th>
          <th scope="col" class="num">Solved</th>
          <th scope="col" class="num">Hard</th>
          <th scope="col" class="num" title="Codeforces rating">CF</th>
          <th scope="col" class="num" title="LeetCode rating">LC</th>
          <th scope="col" class="num" title="CodeChef rating">CC</th>
        </tr></thead>
        <tbody>
          ${entries.map((e) => {
            const sub = [e.college, e.branch, e.graduationYear ? `'${String(e.graduationYear).slice(-2)}` : null].filter(Boolean).map(esc).join(' · ');
            const r = Number(e.rank);
            return `
              <tr class="${e.me ? 'me' : ''}" data-user="${esc(e.userId)}" tabindex="0" aria-label="Open profile of ${esc(e.name)}">
                ${showRank ? `<td><span class="rank${r >= 1 && r <= 3 ? ` rank-${r}` : ''}">${fmt(e.rank)}</span></td>` : ''}
                <td><div class="person"><span class="n">${esc(e.name)}${e.me ? '<span class="you-tag">You</span>' : ''}</span><span class="s">${sub || '—'}</span></div></td>
                <td><div class="chips">${(e.platforms || []).map(platformDot).join('') || '<span class="faint">—</span>'}</div></td>
                <td class="num"><strong>${fmt(e.totalSolved)}</strong></td>
                <td class="num">${fmt(e.hardSolved)}</td>
                <td class="num">${fmt(e.codeforcesRating)}</td>
                <td class="num">${fmt(e.leetcodeRating)}</td>
                <td class="num">${fmt(e.codechefRating)}</td>
              </tr>`;
          }).join('')}
        </tbody>
      </table>
    </div>`;
}
/** Rows navigate to the public profile (click or Enter). */
function bindProfileRows(root) {
  $$('tr[data-user]', root).forEach((tr) => {
    const go = () => { location.hash = `#/u/${encodeURIComponent(tr.dataset.user)}`; };
    tr.addEventListener('click', (e) => { if (!e.target.closest('a,button')) go(); });
    tr.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } });
  });
}

/* ---------------------------------------------------------------------
   Router
   --------------------------------------------------------------------- */
let routeSeq = 0; // increments on every navigation; async renders check it to avoid stale writes

function parseHash() {
  const raw = (location.hash || '').replace(/^#\/?/, '');
  const [path] = raw.split('?');
  const parts = path.split('/').filter(Boolean);
  return { name: parts[0] || '', params: parts.slice(1) };
}

function router() {
  const seq = ++routeSeq;
  document.body.classList.remove('booting', 'nav-open');
  els.menuToggle.setAttribute('aria-expanded', 'false');
  const { name, params } = parseHash();
  const loggedIn = session.loggedIn;

  // Public profile: works with or without login
  if (name === 'u' && params[0]) {
    showApp(!loggedIn);
    setActiveNav(null);
    renderPublicProfile(params[0], seq);
    return;
  }

  if (!loggedIn) {
    showAuth(name === 'register' ? 'register' : 'login');
    if (name !== 'login' && name !== 'register') history.replaceState(null, '', '#/login');
    return;
  }

  const role = session.user.role || 'STUDENT';
  const allowed = NAV_BY_ROLE[role] || NAV_BY_ROLE.STUDENT;
  if (!allowed.includes(name)) {
    location.replace(`#/${HOME_BY_ROLE[role] || 'dashboard'}`);
    return;
  }

  showApp(false);
  setActiveNav(name);
  const route = ROUTES[name];
  document.title = `${route.title} · CodeTrack`;
  els.view.innerHTML = '';
  route.render(seq);
  els.main.scrollTop = 0;
  window.scrollTo(0, 0);
}
const isCurrent = (seq) => seq === routeSeq;

function showAuth(tab) {
  closeModal();
  els.app.hidden = true;
  els.authView.hidden = false;
  document.body.classList.remove('guest');
  document.title = 'CodeTrack — sign in';
  switchAuthTab(tab, false);
}

function showApp(guest) {
  els.authView.hidden = true;
  els.app.hidden = false;
  document.body.classList.toggle('guest', !!guest);
  if (!guest) { buildNav(); renderUserChip(); }
}

function buildNav() {
  const role = (session.user && session.user.role) || 'STUDENT';
  const items = NAV_BY_ROLE[role] || NAV_BY_ROLE.STUDENT;
  const sig = items.join(',');
  if (els.nav.dataset.sig === sig) return;
  els.nav.dataset.sig = sig;
  els.nav.innerHTML = items.map((k) =>
    `<li><a href="#/${k}" data-route="${k}">${icon(ROUTES[k].icon)}<span>${esc(ROUTES[k].title)}</span></a></li>`
  ).join('');
}
function setActiveNav(name) {
  $$('a[data-route]', els.nav).forEach((a) => {
    const on = a.dataset.route === name;
    a.classList.toggle('active', on);
    if (on) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
  });
}
function renderUserChip() {
  const u = session.user;
  if (!u) return;
  els.userName.textContent = u.name || u.email || '';
  els.userName.title = u.name || '';
  els.userRole.textContent = ROLE_LABEL[u.role] || u.role || '';
  els.userAvatar.textContent = initials(u.name);
}

function logout(message) {
  session.clear();
  els.nav.dataset.sig = '';
  if (message) toast(message, 'success');
  location.hash = '#/login';
}

/* ---------------------------------------------------------------------
   Auth view
   --------------------------------------------------------------------- */
function switchAuthTab(tab, focus = true) {
  const isLogin = tab !== 'register';
  els.loginForm.hidden = !isLogin;
  els.registerForm.hidden = isLogin;
  $$('.auth-tab').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === (isLogin ? 'login' : 'register'))));
  const want = isLogin ? '#/login' : '#/register';
  if (location.hash !== want && !session.loggedIn) history.replaceState(null, '', want);
  if (focus) $('input', isLogin ? els.loginForm : els.registerForm).focus();
}

function initAuth() {
  els.authPlatforms.innerHTML = PLATFORMS.map((p) => `<li>${platformChip(p.key)}</li>`).join('');

  $$('.auth-tab').forEach((b) => b.addEventListener('click', () => switchAuthTab(b.dataset.tab)));
  $$('[data-switch-tab]').forEach((b) => b.addEventListener('click', () => switchAuthTab(b.dataset.switchTab)));

  // Login
  els.loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = els.loginForm;
    clearFormErrors(form);
    const email = form.elements.email.value.trim();
    const password = form.elements.password.value;
    const errs = {};
    if (!email) errs.email = 'Email is required';
    else if (!EMAIL_RE.test(email)) errs.email = 'Enter a valid email address';
    if (!password) errs.password = 'Password is required';
    if (Object.keys(errs).length) { showFieldErrors(form, errs); return; }

    await withBusy(els.loginSubmit, async () => {
      try {
        const data = await api('/auth/login', { method: 'POST', body: { email, password }, auth: false });
        onAuthenticated(data, `Welcome back, ${(data.user && data.user.name) || ''}!`);
        form.reset();
      } catch (err) {
        handleFormError(form, err);
      }
    }, 'Logging in…');
  });

  // Register
  els.registerForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = els.registerForm;
    clearFormErrors(form);
    const body = {
      name: form.elements.name.value.trim(),
      email: form.elements.email.value.trim(),
      password: form.elements.password.value,
      college: form.elements.college.value.trim() || null,
      role: form.elements.role.value,
    };
    const errs = {};
    if (!body.name) errs.name = 'Full name is required';
    if (!body.email) errs.email = 'Email is required';
    else if (!EMAIL_RE.test(body.email)) errs.email = 'Enter a valid email address';
    if (body.password.length < 8) errs.password = 'Password must be at least 8 characters';
    else if (body.password.length > 72) errs.password = 'Password must be at most 72 characters';
    if (Object.keys(errs).length) { showFieldErrors(form, errs); return; }

    await withBusy(els.registerSubmit, async () => {
      try {
        const data = await api('/auth/register', { method: 'POST', body, auth: false });
        onAuthenticated(data, 'Account created — welcome to CodeTrack!');
        form.reset();
      } catch (err) {
        handleFormError(form, err);
      }
    }, 'Creating account…');
  });
}

function onAuthenticated(data, message) {
  if (!data || !data.token || !data.user) {
    toast('Unexpected response from server.', 'error');
    return;
  }
  session.set(data.token, data.user);
  els.nav.dataset.sig = '';
  toast(message, 'success');
  location.hash = `#/${HOME_BY_ROLE[data.user.role] || 'dashboard'}`;
}

/* ---------------------------------------------------------------------
   View: Student Dashboard
   --------------------------------------------------------------------- */
async function renderDashboard(seq) {
  els.view.innerHTML = skeletonDashboard();
  let data;
  try {
    data = await api('/dashboard');
  } catch (err) {
    if (!isCurrent(seq) || err.handled) return;
    els.view.innerHTML = pageHead('Dashboard') + errorState(err);
    bindRetry();
    return;
  }
  if (!isCurrent(seq)) return;
  if (data.user) session.setUser(data.user);

  const u = data.user || session.user || {};
  const s = data.summary || {};
  const platforms = data.platforms || [];
  const firstName = String(u.name || '').split(/\s+/)[0];
  const hour = new Date().getHours();
  const greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const lastSync = relativeTime(s.lastSyncedAt);

  const rank = s.collegeRank != null
    ? `#${fmt(s.collegeRank)}${s.collegeSize != null ? ` <span class="faint" style="font-size:15px;font-weight:600">of ${fmt(s.collegeSize)}</span>` : ''}`
    : '—';
  const rankSub = s.collegeRank != null ? esc(u.college || 'In your college')
    : (u.college ? 'Make your profile public to be ranked' : 'Add your college in Profile');

  const syncBtn = platforms.length
    ? `<button type="button" class="btn btn-primary" id="sync-all-btn">${icon('sync', 16)}Sync all</button>` : '';

  const head = pageHead(`${greet}${firstName ? `, ${firstName}` : ''}`,
    platforms.length ? `Here's your coding progress across ${platforms.length} platform${platforms.length === 1 ? '' : 's'}${lastSync ? ` · last synced ${esc(lastSync)}` : ''}.`
      : 'Connect your coding profiles to get started.', syncBtn);

  if (!platforms.length) {
    els.view.innerHTML = head + `
      <div class="card">
        ${emptyState({
          title: 'No platforms connected yet',
          text: 'Link your LeetCode, GeeksforGeeks, CodeChef, Codeforces or GitHub profile and we\'ll pull in your stats automatically.',
          iconName: 'plug',
          actionHtml: `<div class="chips" style="justify-content:center;margin:4px 0 8px">${PLATFORMS.map((p) => platformChip(p.key)).join('')}</div>
            <a class="btn btn-primary" href="#/platforms">Connect a platform</a>`,
        })}
      </div>`;
    return;
  }

  els.view.innerHTML = head + `
    <div class="stats">
      ${statCard('Total solved', fmt(s.totalSolved), 'Across all platforms', 'check')}
      ${statCard('Platforms connected', `${fmt(s.platformsConnected)}<span class="faint" style="font-size:15px;font-weight:600"> / ${PLATFORMS.length}</span>`, '', 'layers')}
      ${statCard('Contests', fmt(s.contests), 'Rated contests attended', 'flag')}
      ${statCard('College rank', rank, rankSub, 'medal')}
      ${statCard('GitHub', `${fmt(s.githubRepos)} <span class="faint" style="font-size:14px;font-weight:600">repos</span>`, `${fmt(s.githubStars)} stars`, 'star')}
    </div>

    <div class="grid grid-2" style="margin-top:16px">
      <section class="card"><h2 class="card-title">Difficulty breakdown</h2>${difficultyBlock(s)}</section>
      <section class="card"><h2 class="card-title">Best ratings</h2>${ratingsBlock(s.bestRatings)}</section>
    </div>

    <section class="card" style="margin-top:16px">
      <h2 class="card-title">Progress <span class="card-sub">Total solved over time</span></h2>
      ${progressChart(data.progress)}
    </section>

    <h2 class="section-title">Connected platforms <a class="btn btn-sm btn-ghost" href="#/platforms">Manage</a></h2>
    <div class="platform-grid">${platforms.map((p) => platformCard(p)).join('')}</div>`;

  const btn = document.getElementById('sync-all-btn');
  if (btn) btn.addEventListener('click', () => syncAll(btn, seq));
}

async function syncAll(btn, seq) {
  await withBusy(btn, async () => {
    try {
      const res = await api('/platforms/sync', { method: 'POST' });
      const failed = (res || []).filter((p) => p.syncStatus === 'ERROR').length;
      if (failed) toast(`Synced, but ${failed} platform${failed === 1 ? '' : 's'} reported an error.`, 'error');
      else toast('All platforms synced.', 'success');
      if (isCurrent(seq)) router();
    } catch (err) {
      toastError(err);
    }
  }, 'Syncing…');
}

/* ---------------------------------------------------------------------
   View: Platforms
   --------------------------------------------------------------------- */
async function renderPlatforms(seq) {
  const head = pageHead('Platforms', 'Connect your coding profiles. Paste a profile URL or just your username.',
    '<button type="button" class="btn" id="sync-all-btn" disabled>' + icon('sync', 16) + 'Sync all</button>');
  els.view.innerHTML = head + skeletonCards(5);
  let list;
  try {
    list = await api('/platforms');
  } catch (err) {
    if (!isCurrent(seq) || err.handled) return;
    els.view.innerHTML = pageHead('Platforms') + errorState(err);
    bindRetry();
    return;
  }
  if (!isCurrent(seq)) return;

  const byKey = Object.fromEntries((list || []).map((p) => [p.platform, p]));
  const cards = PLATFORMS.map((meta) => {
    const p = byKey[meta.key];
    if (p) {
      return platformCard(p, `
        <div class="pcard-actions">
          <button type="button" class="btn btn-sm" data-act="sync" data-p="${meta.key}">${icon('sync', 14)}Sync</button>
          <button type="button" class="btn btn-sm btn-ghost" data-act="edit" data-p="${meta.key}">Edit</button>
          <button type="button" class="btn btn-sm btn-danger" data-act="remove" data-p="${meta.key}">Remove</button>
        </div>`);
    }
    return `
      <article class="pcard disconnected" style="--pc:${meta.color}">
        <div class="pcard-head">
          ${platformIcon(meta.key)}
          <div class="pcard-title"><div class="pcard-name">${esc(meta.name)}</div><div class="pcard-user">Not connected</div></div>
        </div>
        <p class="pcard-empty">Link your ${esc(meta.name)} profile to include it in your dashboard and leaderboard stats.</p>
        <div class="pcard-actions" style="margin-top:auto">
          <button type="button" class="btn btn-sm btn-primary" data-act="connect" data-p="${meta.key}">Connect</button>
        </div>
      </article>`;
  }).join('');

  els.view.innerHTML = head + `<div class="platform-grid">${cards}</div>`;
  const syncBtn = document.getElementById('sync-all-btn');
  syncBtn.disabled = !(list && list.length);
  syncBtn.addEventListener('click', () => syncAll(syncBtn, seq));

  $$('[data-act]', els.view).forEach((btn) => {
    const key = btn.dataset.p;
    const act = btn.dataset.act;
    btn.addEventListener('click', () => {
      if (act === 'connect' || act === 'edit') openConnectModal(key, byKey[key]);
      else if (act === 'sync') syncOne(btn, key, seq);
      else if (act === 'remove') removePlatform(btn, key, seq);
    });
  });
}

function openConnectModal(key, existing) {
  const meta = PLATFORM_BY_KEY[key];
  const m = openModal({
    title: `${existing ? 'Edit' : 'Connect'} ${meta.name}`,
    iconHtml: platformIcon(key),
    content: `
      <form class="form" id="connect-form" novalidate>
        <div class="field">
          <label for="connect-input">Profile URL or username</label>
          <input id="connect-input" name="input" type="text" autocomplete="off" spellcheck="false" required
                 placeholder="${esc(meta.example)}" value="${existing ? esc(existing.profileUrl || existing.username) : ''}" />
          <p class="hint">e.g. ${esc(meta.example)} — or just the username.</p>
          <p class="field-error" data-for="input"></p>
        </div>
        <p class="form-error" role="alert"></p>
        <div class="form-actions">
          <button type="button" class="btn btn-ghost" data-act="cancel">Cancel</button>
          <button type="submit" class="btn btn-primary" id="connect-submit">${existing ? 'Save & sync' : 'Connect'}</button>
        </div>
      </form>`,
  });
  const form = $('#connect-form', m.el);
  $('[data-act="cancel"]', m.el).addEventListener('click', m.close);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearFormErrors(form);
    const input = form.elements.input.value.trim();
    if (!input) { showFieldErrors(form, { input: 'Enter a profile URL or username' }); return; }
    await withBusy($('#connect-submit', form), async () => {
      try {
        const p = await api(`/platforms/${key.toLowerCase()}`, { method: 'PUT', body: { input } });
        m.close();
        if (p && p.syncStatus === 'ERROR') toast(`${meta.name} saved, but sync failed: ${p.syncMessage || 'unknown error'}`, 'error');
        else toast(`${meta.name} connected${p && p.username ? ` as @${p.username}` : ''}.`, 'success');
        router();
      } catch (err) {
        handleFormError(form, err);
      }
    }, 'Connecting…');
  });
}

async function syncOne(btn, key, seq) {
  const meta = PLATFORM_BY_KEY[key];
  await withBusy(btn, async () => {
    try {
      const p = await api(`/platforms/${key.toLowerCase()}/sync`, { method: 'POST' });
      if (p && p.syncStatus === 'ERROR') toast(`${meta.name} sync failed: ${p.syncMessage || 'unknown error'}`, 'error');
      else toast(`${meta.name} synced.`, 'success');
      if (isCurrent(seq)) router();
    } catch (err) {
      toastError(err);
    }
  }, 'Syncing…');
}

async function removePlatform(btn, key, seq) {
  const meta = PLATFORM_BY_KEY[key];
  const ok = await confirmDialog({
    title: `Remove ${meta.name}?`,
    message: `Your ${meta.name} stats will no longer be included in your dashboard or the leaderboard. You can reconnect any time.`,
    confirmText: 'Remove', danger: true,
  });
  if (!ok) return;
  await withBusy(btn, async () => {
    try {
      await api(`/platforms/${key.toLowerCase()}`, { method: 'DELETE' });
      toast(`${meta.name} removed.`, 'success');
      if (isCurrent(seq)) router();
    } catch (err) {
      toastError(err);
    }
  });
}

/* ---------------------------------------------------------------------
   View: Leaderboard / Explore (shared component)
   --------------------------------------------------------------------- */
const leaderboardFilters = { q: '', college: '', platform: '', minSolved: '', sort: 'solved' };
let leaderboardReq = 0;

function renderLeaderboard(mode) {
  const isExplore = mode === 'explore';
  const title = isExplore ? 'Explore Students' : 'Leaderboard';
  const subtitle = isExplore
    ? 'Browse public student profiles. Click a student to see their full portfolio.'
    : 'See how you stack up against other students with public profiles.';
  const f = leaderboardFilters;
  const sortOpts = [['solved', 'Total solved'], ['hard', 'Hard solved'], ['codeforces', 'Codeforces rating'], ['leetcode', 'LeetCode rating'], ['codechef', 'CodeChef rating']];

  els.view.innerHTML = pageHead(title, subtitle) + `
    <form class="filters" id="lb-filters" role="search" onsubmit="return false">
      <div class="field f-q">
        <label for="lb-q">Search</label>
        <input id="lb-q" name="q" type="search" placeholder="Name or college" value="${esc(f.q)}" autocomplete="off" />
      </div>
      <div class="field">
        <label for="lb-college">College</label>
        <input id="lb-college" name="college" type="text" placeholder="Any college" value="${esc(f.college)}" autocomplete="off" />
      </div>
      <div class="field">
        <label for="lb-platform">Platform</label>
        <select id="lb-platform" name="platform">
          <option value="">All platforms</option>
          ${PLATFORMS.map((p) => `<option value="${p.key}"${f.platform === p.key ? ' selected' : ''}>${esc(p.name)}</option>`).join('')}
        </select>
      </div>
      <div class="field">
        <label for="lb-min">Min solved</label>
        <input id="lb-min" name="minSolved" type="number" min="0" step="1" inputmode="numeric" placeholder="0" value="${esc(f.minSolved)}" />
      </div>
      <div class="field">
        <label for="lb-sort">Sort by</label>
        <select id="lb-sort" name="sort">
          ${sortOpts.map(([v, l]) => `<option value="${v}"${f.sort === v ? ' selected' : ''}>${esc(l)}</option>`).join('')}
        </select>
      </div>
    </form>
    <div id="lb-results">${skeletonRows()}</div>`;

  const form = document.getElementById('lb-filters');
  const read = () => {
    f.q = form.elements.q.value.trim();
    f.college = form.elements.college.value.trim();
    f.platform = form.elements.platform.value;
    const min = form.elements.minSolved.value.trim();
    f.minSolved = min && Number(min) >= 0 ? String(Math.floor(Number(min))) : '';
    f.sort = form.elements.sort.value;
  };
  const debounced = debounce(() => { read(); loadLeaderboard(); }, 350);
  ['q', 'college', 'minSolved'].forEach((n) => form.elements[n].addEventListener('input', debounced));
  ['platform', 'sort'].forEach((n) => form.elements[n].addEventListener('change', () => { read(); loadLeaderboard(); }));

  loadLeaderboard();
}

async function loadLeaderboard() {
  const target = document.getElementById('lb-results');
  if (!target) return;
  const req = ++leaderboardReq;
  const f = leaderboardFilters;
  const params = new URLSearchParams();
  if (f.q) params.set('q', f.q);
  if (f.college) params.set('college', f.college);
  if (f.platform) params.set('platform', f.platform);
  if (f.minSolved) params.set('minSolved', f.minSolved);
  params.set('sort', f.sort || 'solved');
  params.set('limit', '50');

  target.setAttribute('aria-busy', 'true');
  if (!target.querySelector('table')) target.innerHTML = skeletonRows();
  else target.style.opacity = '0.6';

  try {
    const entries = await api(`/leaderboard?${params}`);
    if (req !== leaderboardReq || !target.isConnected) return;
    target.style.opacity = '';
    target.removeAttribute('aria-busy');
    if (!entries || !entries.length) {
      const filtered = f.q || f.college || f.platform || f.minSolved;
      target.innerHTML = `<div class="card">${emptyState({
        title: filtered ? 'No students match these filters' : 'No public profiles yet',
        text: filtered ? 'Try clearing a filter or lowering the minimum solved count.' : 'Students appear here once they make their profile public.',
        iconName: 'users',
      })}</div>`;
      return;
    }
    target.innerHTML = `<p class="muted small" style="margin-bottom:10px">Showing ${entries.length.toLocaleString()} student${entries.length === 1 ? '' : 's'}</p>` + leaderboardTable(entries);
    bindProfileRows(target);
  } catch (err) {
    if (req !== leaderboardReq || !target.isConnected || err.handled) return;
    target.style.opacity = '';
    target.removeAttribute('aria-busy');
    target.innerHTML = errorState(err);
    $('[data-retry]', target).addEventListener('click', loadLeaderboard);
  }
}

/* ---------------------------------------------------------------------
   View: College Dashboard
   --------------------------------------------------------------------- */
async function renderCollege(seq) {
  els.view.innerHTML = skeletonDashboard();
  let d;
  try {
    d = await api('/college/overview');
  } catch (err) {
    if (!isCurrent(seq) || err.handled) return;
    if (err.status === 400) {
      els.view.innerHTML = pageHead('College Dashboard') + `
        <div class="card">${emptyState({
          title: 'Set your college first', text: esc(err.message), iconName: 'school',
          actionHtml: '<a class="btn btn-primary" href="#/profile">Go to Profile</a>',
        })}</div>`;
      return;
    }
    els.view.innerHTML = pageHead('College Dashboard') + errorState(err);
    bindRetry();
    return;
  }
  if (!isCurrent(seq)) return;

  const adoption = PLATFORMS.map((p) => ({
    label: p.name, value: (d.platformAdoption || {})[p.key] ?? 0, color: p.color, iconHtml: platformDot(p.key),
  }));
  const distOrder = ['0', '1-50', '51-200', '201-500', '500+'];
  const dist = d.distribution || {};
  const distKeys = [...distOrder.filter((k) => k in dist), ...Object.keys(dist).filter((k) => !distOrder.includes(k))];
  const distItems = distKeys.map((k) => ({ label: `${k} solved`, value: dist[k] }));
  const top = d.topStudents || [];
  const activePct = d.studentCount ? Math.round((num(d.activeCount) / num(d.studentCount)) * 100) : null;

  els.view.innerHTML = pageHead('College Dashboard', esc(d.college || ''),
    '<a class="btn" href="#/explore">' + icon('search', 16) + 'Explore students</a>') + `
    <div class="stats">
      ${statCard('Students', fmt(d.studentCount), 'With public profiles', 'users')}
      ${statCard('Active', fmt(d.activeCount), activePct != null ? `${activePct}% of students` : '', 'check')}
      ${statCard('Total solved', fmt(d.totalSolved), 'Across all students', 'code')}
      ${statCard('Average solved', fmt(d.averageSolved != null ? Math.round(d.averageSolved) : null), 'Per student', 'chart')}
    </div>
    <div class="grid grid-2" style="margin-top:16px">
      <section class="card"><h2 class="card-title">Platform adoption <span class="card-sub">students connected</span></h2>${barsBlock(adoption)}</section>
      <section class="card"><h2 class="card-title">Solved distribution <span class="card-sub">students per bucket</span></h2>
        ${distItems.length ? barsBlock(distItems) : emptyState({ title: 'No data yet', small: true })}</section>
    </div>
    <h2 class="section-title">Top students</h2>
    ${top.length ? leaderboardTable(top) : `<div class="card">${emptyState({ title: 'No ranked students yet', text: 'Students from your college appear here once they connect platforms and make their profile public.', iconName: 'trophy' })}</div>`}`;
  bindProfileRows(els.view);
}

/* ---------------------------------------------------------------------
   View: Profile (settings)
   --------------------------------------------------------------------- */
function shareLink(id) {
  return `${location.origin}${location.pathname}#/u/${id}`;
}

async function renderProfile(seq) {
  els.view.innerHTML = pageHead('Profile') + `<div class="skeleton" style="height:420px"></div>`;
  let u = session.user;
  try {
    u = await api('/users/me');
    if (!isCurrent(seq)) return;
    session.setUser(u);
  } catch (err) {
    if (!isCurrent(seq) || err.handled) return;
    if (!u) { els.view.innerHTML = pageHead('Profile') + errorState(err); bindRetry(); return; }
    toastError(err); // fall back to cached user
  }

  const isStudent = u.role === 'STUDENT';
  const v = (x) => esc(x == null ? '' : x);
  const thisYear = new Date().getFullYear();

  els.view.innerHTML = pageHead('Profile', 'Manage your personal details and account security.') + `
    <div class="stack">
      <section class="card">
        <h2 class="card-title">Personal details</h2>
        <form class="form" id="profile-form" novalidate>
          <div class="form-grid">
            <div class="field">
              <label for="pf-name">Full name</label>
              <input id="pf-name" name="name" type="text" required maxlength="100" value="${v(u.name)}" autocomplete="name" />
              <p class="field-error" data-for="name"></p>
            </div>
            <div class="field">
              <label for="pf-email">Email</label>
              <input id="pf-email" type="email" value="${v(u.email)}" readonly aria-describedby="pf-email-hint" />
              <p class="hint" id="pf-email-hint">Email can't be changed.</p>
            </div>
            <div class="field">
              <label for="pf-college">College${u.role === 'COLLEGE' ? '' : ' <span class="optional">(optional)</span>'}</label>
              <input id="pf-college" name="college" type="text" maxlength="150" value="${v(u.college)}" autocomplete="organization" />
              <p class="field-error" data-for="college"></p>
            </div>
            <div class="field">
              <label for="pf-location">Location <span class="optional">(optional)</span></label>
              <input id="pf-location" name="location" type="text" maxlength="100" value="${v(u.location)}" />
              <p class="field-error" data-for="location"></p>
            </div>
            ${isStudent ? `
            <div class="field">
              <label for="pf-course">Course <span class="optional">(optional)</span></label>
              <input id="pf-course" name="course" type="text" maxlength="100" placeholder="B.Tech" value="${v(u.course)}" />
              <p class="field-error" data-for="course"></p>
            </div>
            <div class="field">
              <label for="pf-branch">Branch <span class="optional">(optional)</span></label>
              <input id="pf-branch" name="branch" type="text" maxlength="100" placeholder="CSE" value="${v(u.branch)}" />
              <p class="field-error" data-for="branch"></p>
            </div>
            <div class="field">
              <label for="pf-year">Graduation year <span class="optional">(optional)</span></label>
              <input id="pf-year" name="graduationYear" type="number" min="1950" max="${thisYear + 10}" step="1" inputmode="numeric" placeholder="${thisYear + 1}" value="${v(u.graduationYear)}" />
              <p class="field-error" data-for="graduationYear"></p>
            </div>` : ''}
            <div class="field full">
              <label for="pf-bio">Bio <span class="optional">(optional)</span></label>
              <textarea id="pf-bio" name="bio" maxlength="1000" rows="4" placeholder="A few lines about you, your interests and what you're working on.">${v(u.bio)}</textarea>
              <p class="field-error" data-for="bio"></p>
            </div>
            ${isStudent ? `
            <div class="field full">
              <label class="toggle" for="pf-public">
                <input id="pf-public" name="publicProfile" type="checkbox"${u.publicProfile ? ' checked' : ''} />
                <span class="toggle-track" aria-hidden="true"></span>
                <span><strong>Make my profile public</strong><br /><span class="muted small">Public profiles appear on the leaderboard and can be viewed by colleges and recruiters.</span></span>
              </label>
            </div>
            <div class="field full" id="share-wrap"></div>` : ''}
          </div>
          <p class="form-error" role="alert"></p>
          <div class="form-actions"><button type="submit" class="btn btn-primary" id="profile-submit">Save changes</button></div>
        </form>
      </section>

      <div class="grid grid-2">
        <section class="card">
          <h2 class="card-title">Change password</h2>
          <form class="form" id="password-form" novalidate>
            <div class="field">
              <label for="pw-current">Current password</label>
              <input id="pw-current" name="currentPassword" type="password" autocomplete="current-password" required />
              <p class="field-error" data-for="currentPassword"></p>
            </div>
            <div class="field">
              <label for="pw-new">New password</label>
              <input id="pw-new" name="newPassword" type="password" autocomplete="new-password" minlength="8" maxlength="72" required aria-describedby="pw-new-hint" />
              <p class="hint" id="pw-new-hint">At least 8 characters. Other devices will be signed out.</p>
              <p class="field-error" data-for="newPassword"></p>
            </div>
            <div class="field">
              <label for="pw-confirm">Confirm new password</label>
              <input id="pw-confirm" name="confirmPassword" type="password" autocomplete="new-password" required />
              <p class="field-error" data-for="confirmPassword"></p>
            </div>
            <p class="form-error" role="alert"></p>
            <div class="form-actions"><button type="submit" class="btn btn-primary" id="password-submit">Update password</button></div>
          </form>
        </section>

        <div class="stack">
          <section class="card">
            <h2 class="card-title">Sessions</h2>
            <p class="muted" style="margin-bottom:14px">Signed in on a shared computer? Sign out of CodeTrack on every device, including this one.</p>
            <button type="button" class="btn" id="logout-all-btn">Sign out everywhere</button>
          </section>
          <section class="card danger-zone">
            <h2 class="card-title">Danger zone</h2>
            <p class="muted" style="margin-bottom:14px">Permanently delete your account, connected platforms and progress history. This cannot be undone.</p>
            <button type="button" class="btn btn-danger" id="delete-account-btn">Delete account</button>
          </section>
        </div>
      </div>
    </div>`;

  const form = document.getElementById('profile-form');
  if (isStudent) {
    renderShareLink(u);
    form.elements.publicProfile.addEventListener('change', () => {
      const wrap = document.getElementById('share-wrap');
      if (wrap && !form.elements.publicProfile.checked) wrap.innerHTML = '<p class="hint">Your profile will be private after you save.</p>';
      else renderShareLink(session.user, !session.user.publicProfile);
    });
  }

  form.addEventListener('submit', (e) => { e.preventDefault(); saveProfile(form, u); });
  document.getElementById('password-form').addEventListener('submit', (e) => { e.preventDefault(); changePassword(e.target); });
  document.getElementById('logout-all-btn').addEventListener('click', (e) => logoutAll(e.currentTarget));
  document.getElementById('delete-account-btn').addEventListener('click', openDeleteAccountModal);
}

function renderShareLink(u, pendingSave = false) {
  const wrap = document.getElementById('share-wrap');
  if (!wrap) return;
  if (!u.publicProfile && !pendingSave) { wrap.innerHTML = ''; return; }
  if (pendingSave) { wrap.innerHTML = '<p class="hint">Save changes to get your shareable link.</p>'; return; }
  const link = shareLink(u.id);
  wrap.innerHTML = `
    <label for="share-link">Your public profile link</label>
    <div class="share">
      <input id="share-link" type="text" readonly value="${esc(link)}" />
      <button type="button" class="btn" id="copy-link-btn">${icon('copy', 15)}Copy</button>
      <a class="btn btn-ghost" href="#/u/${encodeURIComponent(u.id)}">View</a>
    </div>`;
  document.getElementById('copy-link-btn').addEventListener('click', () => copyText(link, document.getElementById('share-link')));
}

async function copyText(text, inputEl) {
  try {
    await navigator.clipboard.writeText(text);
    toast('Link copied to clipboard.', 'success');
  } catch {
    if (inputEl) { inputEl.focus(); inputEl.select(); }
    try { document.execCommand('copy'); toast('Link copied to clipboard.', 'success'); }
    catch { toast('Press Ctrl/Cmd + C to copy the link.', 'info'); }
  }
}

async function saveProfile(form, current) {
  clearFormErrors(form);
  const el = form.elements;
  const val = (n) => (el[n] ? el[n].value.trim() : undefined);
  const orNull = (s) => (s === undefined ? undefined : s || null);
  const body = {
    name: val('name'),
    college: orNull(val('college')),
    location: orNull(val('location')),
    bio: orNull(val('bio')),
    publicProfile: el.publicProfile ? el.publicProfile.checked : !!current.publicProfile,
  };
  if (el.course) {
    body.course = orNull(val('course'));
    body.branch = orNull(val('branch'));
    const y = val('graduationYear');
    body.graduationYear = y ? Number(y) : null;
  } else {
    // Non-students don't edit these; preserve existing values.
    body.course = current.course ?? null;
    body.branch = current.branch ?? null;
    body.graduationYear = current.graduationYear ?? null;
  }
  const errs = {};
  if (!body.name) errs.name = 'Name is required';
  if (body.graduationYear != null && (!Number.isInteger(body.graduationYear) || body.graduationYear < 1950 || body.graduationYear > 2100)) {
    errs.graduationYear = 'Enter a valid year';
  }
  if (Object.keys(errs).length) { showFieldErrors(form, errs); return; }

  await withBusy(document.getElementById('profile-submit'), async () => {
    try {
      const updated = await api('/users/me', { method: 'PUT', body });
      session.setUser(updated);
      toast('Profile saved.', 'success');
      if (updated.role === 'STUDENT') renderShareLink(updated);
    } catch (err) {
      handleFormError(form, err);
    }
  }, 'Saving…');
}

async function changePassword(form) {
  clearFormErrors(form);
  const currentPassword = form.elements.currentPassword.value;
  const newPassword = form.elements.newPassword.value;
  const confirm = form.elements.confirmPassword.value;
  const errs = {};
  if (!currentPassword) errs.currentPassword = 'Enter your current password';
  if (newPassword.length < 8) errs.newPassword = 'Password must be at least 8 characters';
  else if (newPassword.length > 72) errs.newPassword = 'Password must be at most 72 characters';
  if (newPassword !== confirm) errs.confirmPassword = "Passwords don't match";
  if (Object.keys(errs).length) { showFieldErrors(form, errs); return; }

  await withBusy(document.getElementById('password-submit'), async () => {
    try {
      // Don't auto-logout on 401 here: a wrong current password may be reported as 401.
      const data = await api('/users/me/password', { method: 'PUT', body: { currentPassword, newPassword }, logoutOn401: false });
      if (data && data.token) session.set(data.token, data.user);
      form.reset();
      toast('Password updated. Other devices have been signed out.', 'success');
    } catch (err) {
      handleFormError(form, err);
    }
  }, 'Updating…');
}

async function logoutAll(btn) {
  const ok = await confirmDialog({
    title: 'Sign out everywhere?',
    message: 'You will be signed out of CodeTrack on all devices, including this one.',
    confirmText: 'Sign out everywhere',
  });
  if (!ok) return;
  await withBusy(btn, async () => {
    try {
      await api('/auth/logout-all', { method: 'POST' });
      logout('Signed out on all devices.');
    } catch (err) {
      toastError(err);
    }
  });
}

function openDeleteAccountModal() {
  const m = openModal({
    title: 'Delete account',
    content: `
      <p class="lead">This permanently deletes your account, connected platforms and progress history. <strong style="color:var(--danger)">This cannot be undone.</strong></p>
      <form class="form" id="delete-form" novalidate>
        <div class="field">
          <label for="delete-password">Enter your password to confirm</label>
          <input id="delete-password" name="password" type="password" autocomplete="current-password" required />
          <p class="field-error" data-for="password"></p>
        </div>
        <p class="form-error" role="alert"></p>
        <div class="form-actions">
          <button type="button" class="btn btn-ghost" data-act="cancel">Cancel</button>
          <button type="submit" class="btn btn-danger-solid" id="delete-submit">Delete my account</button>
        </div>
      </form>`,
  });
  const form = $('#delete-form', m.el);
  $('[data-act="cancel"]', m.el).addEventListener('click', m.close);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearFormErrors(form);
    const password = form.elements.password.value;
    if (!password) { showFieldErrors(form, { password: 'Password is required' }); return; }
    await withBusy($('#delete-submit', form), async () => {
      try {
        await api('/users/me', { method: 'DELETE', body: { password }, logoutOn401: false });
        m.close();
        logout('Your account has been deleted.');
      } catch (err) {
        handleFormError(form, err);
      }
    }, 'Deleting…');
  });
}

/* ---------------------------------------------------------------------
   View: Public profile (#/u/<id>) — works with or without login
   --------------------------------------------------------------------- */
async function renderPublicProfile(id, seq) {
  document.title = 'Student profile · CodeTrack';
  els.view.innerHTML = `<div class="skeleton" style="height:150px;margin-bottom:16px"></div>` + skeletonDashboard();
  let p;
  try {
    // Public endpoint: never send the token, so a stale token can't log the visitor out.
    p = await api(`/public/users/${encodeURIComponent(id)}`, { auth: false });
  } catch (err) {
    if (!isCurrent(seq)) return;
    if (err.status === 404 || err.status === 400) {
      els.view.innerHTML = `<div class="card" style="margin-top:24px">${emptyState({
        title: "This profile is private or doesn't exist",
        text: 'The student may have made their profile private, or the link is incorrect.',
        iconName: 'user',
        actionHtml: session.loggedIn ? `<a class="btn" href="#/">Back to CodeTrack</a>` : `<a class="btn btn-primary" href="#/login">Sign in to CodeTrack</a>`,
      })}</div>`;
      return;
    }
    els.view.innerHTML = errorState(err);
    bindRetry();
    return;
  }
  if (!isCurrent(seq)) return;

  document.title = `${p.name || 'Student'} · CodeTrack`;
  const s = p.summary || {};
  const platforms = p.platforms || [];
  const edu = [p.course, p.branch].filter(Boolean).map(esc).join(' · ');
  const meta = [
    p.college ? `<span>${icon('school', 15)}${esc(p.college)}</span>` : '',
    edu || p.graduationYear ? `<span>${icon('cap', 15)}${edu}${edu && p.graduationYear ? ' · ' : ''}${p.graduationYear ? `Class of ${esc(p.graduationYear)}` : ''}</span>` : '',
    p.location ? `<span>${icon('pin', 15)}${esc(p.location)}</span>` : '',
    p.memberSince ? `<span>${icon('cal', 15)}Member since ${esc(formatDate(p.memberSince, { month: 'long', year: 'numeric' }))}</span>` : '',
  ].filter(Boolean).join('');
  const isMe = session.user && String(session.user.id) === String(p.id);

  els.view.innerHTML = `
    <section class="card profile-hero">
      <div class="avatar avatar-xl" aria-hidden="true">${esc(initials(p.name))}</div>
      <div style="flex:1;min-width:0">
        <h1>${esc(p.name)}</h1>
        ${meta ? `<div class="profile-meta">${meta}</div>` : ''}
        ${p.bio ? `<p class="profile-bio">${esc(p.bio)}</p>` : ''}
        ${platforms.length ? `<div class="chips" style="margin-top:14px">${platforms.map((x) => platformChip(x.platform)).join('')}</div>` : ''}
      </div>
      ${isMe ? '<a class="btn btn-sm" href="#/profile">Edit profile</a>' : ''}
    </section>

    <div class="stats" style="margin-top:16px">
      ${statCard('Total solved', fmt(s.totalSolved), '', 'check')}
      ${statCard('Hard solved', fmt(s.hardSolved), '', 'flag')}
      ${statCard('Contests', fmt(s.contests), '', 'trophy')}
      ${statCard('Platforms', fmt(s.platformsConnected ?? platforms.length), '', 'layers')}
      ${s.collegeRank != null ? statCard('College rank', `#${fmt(s.collegeRank)}${s.collegeSize != null ? ` <span class="faint" style="font-size:15px;font-weight:600">of ${fmt(s.collegeSize)}</span>` : ''}`, '', 'medal') : ''}
      ${s.githubRepos != null ? statCard('GitHub', `${fmt(s.githubRepos)} <span class="faint" style="font-size:14px;font-weight:600">repos</span>`, `${fmt(s.githubStars)} stars`, 'star') : ''}
    </div>

    <div class="grid grid-2" style="margin-top:16px">
      <section class="card"><h2 class="card-title">Difficulty breakdown</h2>${difficultyBlock(s)}</section>
      <section class="card"><h2 class="card-title">Best ratings</h2>${ratingsBlock(s.bestRatings)}</section>
    </div>

    <section class="card" style="margin-top:16px">
      <h2 class="card-title">Progress <span class="card-sub">Total solved over time</span></h2>
      ${progressChart(p.progress)}
    </section>

    <h2 class="section-title">Platforms</h2>
    ${platforms.length
      ? `<div class="platform-grid">${platforms.map((x) => platformCard(x)).join('')}</div>`
      : `<div class="card">${emptyState({ title: 'No platforms connected yet', iconName: 'plug', small: true })}</div>`}
    ${session.loggedIn ? '' : `<p class="center muted small" style="margin-top:32px">Track your own progress — <a href="#/register">create a free CodeTrack account</a>.</p>`}`;
}

/* ---------------------------------------------------------------------
   Shell wiring + boot
   --------------------------------------------------------------------- */
function initShell() {
  els.logoutBtn.addEventListener('click', () => logout('You have been logged out.'));

  const setNav = (open) => {
    document.body.classList.toggle('nav-open', open);
    els.menuToggle.setAttribute('aria-expanded', String(open));
    els.menuToggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
  };
  els.menuToggle.addEventListener('click', () => setNav(!document.body.classList.contains('nav-open')));
  els.sidebarBackdrop.addEventListener('click', () => setNav(false));
  els.nav.addEventListener('click', (e) => { if (e.target.closest('a')) setNav(false); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && document.body.classList.contains('nav-open') && !activeModal) setNav(false);
  });

  // Keep multiple tabs in sync (login/logout elsewhere)
  window.addEventListener('storage', (e) => {
    if (e.key === STORAGE_TOKEN || e.key === STORAGE_USER) {
      els.nav.dataset.sig = '';
      router();
    }
  });
}

initAuth();
initShell();
window.addEventListener('hashchange', router);
router();
