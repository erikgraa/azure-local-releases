(() => {
  'use strict';

  const DAY = 864e5;
  const ENDING_DAYS = 60;

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const safeUrl = u => (/^https:\/\//.test(u || '') ? esc(u) : '');
  const parseDate = iso => { const p = iso.split('-').map(Number); return new Date(p[0], p[1] - 1, p[2]); };
  const fmt = d => d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  const plural = (n, w) => n + ' ' + w + (n === 1 ? '' : 's');

  const today = (() => { const n = new Date(); return new Date(n.getFullYear(), n.getMonth(), n.getDate()); })();
  const STATUS = { sup: 'Supported', end: 'Ending soon', eol: 'End of support' };

  let releases = [];
  let recommended = null;
  const state = { q: '', os: '', retired: false };

  // Status and countdowns are calculated in the browser so they stay correct between daily data refreshes
  function enrich(r) {
    const first = parseDate(r.firstAvailabilityDate);
    const eol = parseDate(r.endOfSupportDate);
    const daysLeft = Math.round((eol - today) / DAY);
    return Object.assign({}, r, { first, eol, daysLeft, status: daysLeft < 0 ? 'eol' : daysLeft <= ENDING_DAYS ? 'end' : 'sup' });
  }

  function compareVersions(a, b) {
    const pa = a.split('.').map(Number), pb = b.split('.').map(Number);
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
      const d = (pa[i] || 0) - (pb[i] || 0);
      if (d) return d;
    }
    return 0;
  }

  function span(days) {
    if (days < 90) return plural(days, 'day');
    if (days < 730) return plural(Math.round(days / 30.4), 'month');
    return plural(Math.round(days / 365.25 * 10) / 10, 'year');
  }

  function leftText(r) {
    if (r.daysLeft < 0) return 'ended ' + span(-r.daysLeft) + ' ago';
    if (r.daysLeft === 0) return 'ends today';
    return span(r.daysLeft) + ' left';
  }

  function statusHtml(r) {
    return '<span class="status st-' + r.status + '"><span class="label">' + STATUS[r.status] + '</span><small>' + esc(leftText(r)) + '</small></span>';
  }

  // ---- summary ----
  function renderFacts() {
    const R = recommended;
    $('fact-rec').innerHTML = esc(R.version) + '<span class="sub">Release ' + esc(R.releaseTrain) + ', supported until ' + fmt(R.eol) + '</span>';

    const next = releases.filter(r => r.status !== 'eol').sort((a, b) => a.eol - b.eol)[0];
    $('fact-next').innerHTML = next
      ? 'Release ' + esc(next.releaseTrain) + ', ' + fmt(next.eol) + '<span class="sub">' + esc(leftText(next)) + '</span>'
      : 'None';
  }

  // ---- version checker ----
  function renderChecker() {
    const option = r => '<option value="' + esc(r.version) + '">' + esc(r.version) + ' (' + esc(r.releaseTrain) + ')</option>';
    const sorted = releases.slice().sort((a, b) => compareVersions(b.version, a.version));
    $('mine').innerHTML = '<option value="">Select a version</option>' +
      '<optgroup label="In support">' + sorted.filter(r => r.status !== 'eol').map(option).join('') + '</optgroup>' +
      '<optgroup label="Out of support">' + sorted.filter(r => r.status === 'eol').map(option).join('') + '</optgroup>';
    $('mine').addEventListener('change', () => { setVerdict(); saveState(); updateChips(); });
    renderChips(sorted.filter(r => r.status !== 'eol'));
  }

  // One-click buttons for the supported releases, kept in sync with the dropdown
  function renderChips(supported) {
    const group = $('chips');
    group.innerHTML = supported.map(r => {
      const duplicate = supported.filter(x => x.releaseTrain === r.releaseTrain).length > 1;
      const label = duplicate ? r.version.split('.').slice(0, 2).join('.') : r.releaseTrain;
      return '<button type="button" class="chip" data-version="' + esc(r.version) + '" aria-pressed="false" title="' + esc(r.version) + '" aria-label="' + esc(label + ' (' + r.version + ')') + '">' + esc(label) + '</button>';
    }).join('');
    group.hidden = supported.length === 0;
    group.addEventListener('click', e => {
      const btn = e.target.closest('button.chip');
      if (!btn) return;
      $('mine').value = $('mine').value === btn.dataset.version ? '' : btn.dataset.version;
      setVerdict(); saveState(); updateChips();
    });
  }

  function updateChips() {
    $('chips').querySelectorAll('button.chip').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.version === $('mine').value)));
  }

  function setVerdict() {
    const r = releases.find(x => x.version === $('mine').value);
    const el = $('verdict');
    if (!r) { el.innerHTML = ''; return; }
    const target = '<b>' + esc(recommended.releaseTrain) + '</b>';
    el.innerHTML = {
      sup: 'Supported until <b>' + fmt(r.eol) + '</b> (' + esc(leftText(r)) + ').',
      end: 'Support ends <b>' + fmt(r.eol) + '</b> (' + esc(leftText(r)) + '). Plan your update to ' + target + '.',
      eol: '<b>Out of support</b> since ' + fmt(r.eol) + '. Update to ' + target + '. Microsoft Support can only help you update to a supported version.'
    }[r.status];
  }

  // ---- table ----
  function detailHtml(r) {
    const features = (Array.isArray(r.features) ? r.features : []).filter(f => f && f.title);
    const u = r.urls || {};
    const notes = safeUrl(u.news);
    const links = [['What\u2019s new', u.news], ['Security update', u.security], ['Known issues', u.issues]]
      .filter(l => safeUrl(l[1])).map(l => '<a href="' + safeUrl(l[1]) + '" rel="noopener">' + l[0] + '</a>');
    const zip = r.solutionUpdate && safeUrl(r.solutionUpdate.uri);
    if (zip) links.push('<a href="' + zip + '" rel="noopener">Update ZIP</a>');

    const featureHtml = features.length
      ? '<ul>' + features.map(f => '<li><b>' + esc(f.title) + '</b>' + (f.preview ? '<span class="tag">Preview</span>' : '') +
        (f.summary ? '<span>' + esc(f.summary) + '</span>' : '') + '</li>').join('') + '</ul>'
      : '<p class="muted">No feature highlights are listed for this release.' + (notes ? ' See the <a href="' + notes + '" rel="noopener">release notes</a>.' : '') + '</p>';

    const builds = [r.version + '  ' + r.availabilityDate].concat((r.supersedes || []).map(b => b.version + '  ' + b.availabilityDate));

    return '<div class="cols"><div><h3>Features</h3>' + featureHtml + '</div>' +
      '<div><h3>Build</h3><p>OS build <b>' + esc(r.osBuild) + '</b> (' + esc(r.osVersion) + ')' + (r.newDeployments ? '<br>Recommended for new deployments' : '') + '</p>' +
      '<ul class="builds">' + builds.map(b => '<li>' + esc(b) + '</li>').join('') + '</ul>' +
      (links.length ? '<div class="links">' + links.join('') + '</div>' : '') + '</div></div>';
  }

  function matches(r) {
    if (!state.retired && r.status === 'eol') return false;
    if (state.os && r.osVersion !== state.os) return false;
    const hay = [r.version, r.releaseTrain, r.osBuild, r.osVersion].join(' ').toLowerCase();
    return state.q.toLowerCase().split(/\s+/).filter(Boolean).every(t => t.indexOf('train:') === 0 ? r.releaseTrain === t.slice(6) : hay.indexOf(t) !== -1);
  }

  function draw() {
    const list = releases.filter(matches).sort((a, b) => b.first - a.first || compareVersions(b.version, a.version));

    $('rows').innerHTML = list.map(r =>
      '<tr class="row" tabindex="0" aria-expanded="false" data-v="' + esc(r.version) + '">' +
      '<td class="rel">' + esc(r.releaseTrain) + '</td>' +
      '<td class="mono">' + esc(r.version) + '</td>' +
      '<td class="date">' + fmt(r.first) + '</td>' +
      '<td class="date">' + fmt(r.eol) + '</td>' +
      '<td>' + statusHtml(r) + '</td></tr>' +
      '<tr class="detail" hidden><td colspan="5">' + detailHtml(r) + '</td></tr>').join('');

    $('empty').hidden = list.length > 0;
    $('count').textContent = list.length + ' of ' + releases.length + ' releases' + (state.retired ? '' : ' (retired releases hidden)');
    saveState();
  }

  function toggle(row) {
    const open = row.getAttribute('aria-expanded') !== 'true';
    row.setAttribute('aria-expanded', String(open));
    row.nextElementSibling.hidden = !open;
  }

  // ---- URL state ----
  function loadState() {
    const p = new URLSearchParams(location.search);
    state.q = p.get('q') || '';
    state.os = p.get('os') === '24H2' || p.get('os') === '23H2' ? p.get('os') : '';
    state.retired = p.get('retired') === '1';
    $('q').value = state.q;
    $('os').value = state.os;
    $('retired').checked = state.retired;
    return p.get('mine') || '';
  }

  function saveState() {
    const p = new URLSearchParams();
    if (state.q) p.set('q', state.q);
    if (state.os) p.set('os', state.os);
    if (state.retired) p.set('retired', '1');
    if ($('mine').value) p.set('mine', $('mine').value);
    const qs = p.toString();
    history.replaceState(null, '', location.pathname + (qs ? '?' + qs : ''));
  }

  function bind() {
    $('q').addEventListener('input', e => { state.q = e.target.value.trim(); draw(); });
    $('os').addEventListener('change', e => { state.os = e.target.value; draw(); });
    $('retired').addEventListener('change', e => { state.retired = e.target.checked; draw(); });
    $('rows').addEventListener('click', e => {
      if (e.target.closest('a')) return;
      const row = e.target.closest('tr.row');
      if (row) toggle(row);
    });
    $('rows').addEventListener('keydown', e => {
      const row = e.target.closest('tr.row');
      if (row && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); toggle(row); }
    });
  }

  function init(data) {
    releases = data.releases.map(enrich);
    recommended = releases.filter(r => r.newDeployments)[0] || releases.slice().sort((a, b) => compareVersions(b.version, a.version))[0];

    if (data.generatedAt) $('updated').textContent = 'Data last changed ' + fmt(new Date(data.generatedAt));

    renderFacts();
    renderChecker();
    const mine = loadState();
    if (mine && releases.some(r => r.version === mine)) $('mine').value = mine;
    setVerdict();
    updateChips();
    draw();
  }

  bind();

  fetch('data/releases.json', { cache: 'no-cache' })
    .then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(init)
    .catch(err => {
      console.error(err);
      $('error').hidden = false;
    });

  // Cache the site so it keeps working offline after the first visit
  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) {
    navigator.serviceWorker.register('sw.js').catch(() => { /* offline support is best effort */ });
  }
})();
