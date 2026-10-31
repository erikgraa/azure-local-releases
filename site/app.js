(() => {
  'use strict';

  const DAY = 864e5;
  const ENDING_DAYS = 60;
  const SUPPORT_DAYS = 180;

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const safeUrl = u => (/^https:\/\//.test(u || '') ? esc(u) : '');
  const parseDate = iso => { const p = iso.split('-').map(Number); return new Date(p[0], p[1] - 1, p[2]); };
  const fmt = d => d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  const fmtShort = d => d.toLocaleDateString('en-GB', { month: 'short', year: '2-digit' });
  const addMonths = (d, m) => new Date(d.getFullYear(), d.getMonth() + m, d.getDate());
  const daysBetween = (a, b) => Math.round((b - a) / DAY);
  const plural = (n, w) => n + ' ' + w + (n === 1 ? '' : 's');

  const STATUS = {
    rec: { label: 'Recommended', cls: 's-rec', color: 'ok' },
    sup: { label: 'Supported', cls: 's-sup', color: 'info' },
    end: { label: 'Ending soon', cls: 's-end', color: 'warn' },
    eol: { label: 'End of support', cls: 's-eol', color: 'bad' }
  };

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  let releases = [];
  let trains = [];
  let recommended = null;
  const state = { status: 'active', os: '', q: '', sort: 'new', fullHistory: false };

  // Status and countdowns are calculated in the browser so they stay correct between daily data refreshes
  function classify(daysLeft, isRecommended) {
    if (daysLeft < 0) return 'eol';
    if (isRecommended) return 'rec';
    return daysLeft <= ENDING_DAYS ? 'end' : 'sup';
  }

  function enrichRelease(r) {
    const first = parseDate(r.firstAvailabilityDate);
    const eol = parseDate(r.endOfSupportDate);
    const daysLeft = daysBetween(today, eol);
    return Object.assign({}, r, {
      first, eol,
      // Support ends at the end of the end of support date
      eolEnd: new Date(eol.getFullYear(), eol.getMonth(), eol.getDate() + 1),
      daysLeft,
      status: classify(daysLeft, r.newDeployments)
    });
  }

  function enrichTrain(t, list) {
    const first = parseDate(t.firstAvailabilityDate);
    const eol = parseDate(t.endOfSupportDate);
    const daysLeft = daysBetween(today, eol);
    const isRec = list.some(r => r.releaseTrain === t.releaseTrain && r.newDeployments);
    return Object.assign({}, t, { first, eol, daysLeft, status: classify(daysLeft, isRec) });
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
    if (r.daysLeft < 0) return 'Ended <b>' + span(-r.daysLeft) + ' ago</b>';
    if (r.daysLeft === 0) return '<b>Ends today</b>';
    return '<b>' + plural(r.daysLeft, 'day') + '</b> of support left';
  }

  function copy(text, btn) {
    const done = () => {
      if (!btn) return;
      const original = btn.textContent;
      btn.textContent = 'Copied ✓';
      setTimeout(() => { btn.textContent = original; }, 1200);
    };
    const fallback = () => {
      const t = document.createElement('textarea');
      t.value = text;
      document.body.appendChild(t);
      t.select();
      try { document.execCommand('copy'); } catch (e) { /* ignore */ }
      t.remove();
      done();
    };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback);
    else fallback();
  }

  // ---- hero: recommended release ----
  function renderRecommended() {
    const R = recommended;
    const news = safeUrl(R.urls && R.urls.news);
    $('rec').innerHTML =
      '<div class="rec-top"><span class="rec-ver">' + esc(R.releaseTrain) + '</span><span class="pill s-rec">Recommended</span>' +
      '<span class="rec-build mono">' + esc(R.version) + '</span></div>' +
      '<div class="rec-meta"><span>Released <b>' + fmt(R.first) + '</b></span><span>End of support <b>' + fmt(R.eol) + '</b></span>' +
      '<span>OS build <b>' + esc(R.osBuild) + ' (' + esc(R.osVersion) + ')</b></span></div>' +
      '<div class="rec-actions">' + (news ? '<a class="btn primary" href="' + news + '" rel="noopener">View release notes →</a>' : '') +
      '<button type="button" class="btn" id="copyRec">Copy version</button></div>';
    $('copyRec').addEventListener('click', e => copy(R.version, e.currentTarget));
  }

  // ---- hero: countdown to the next end of support ----
  let countdownTimer;
  function renderCountdown(live) {
    const queue = live.slice().sort((a, b) => a.eolEnd - b.eolEnd);
    const next = queue[0];
    if (!next) {
      $('count').innerHTML = '<h2>Next end of support</h2><p class="count-foot">No supported releases were found.</p>';
      return;
    }

    const total = next.eolEnd - next.first;
    const elapsed = Math.min(1, Math.max(0, (now - next.first) / total));

    $('count').innerHTML =
      '<h2>Next end of support</h2>' +
      '<div class="ring-wrap"><div class="ring"><svg viewBox="0 0 120 120" aria-hidden="true"><defs><linearGradient id="rg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="var(--accent-2)"/><stop offset="1" stop-color="var(--accent-3)"/></linearGradient></defs>' +
      '<circle class="track" cx="60" cy="60" r="54"/><circle class="prog" id="prog" cx="60" cy="60" r="54"/></svg>' +
      '<div class="ring-label"><b id="pct">0%</b><span>elapsed</span></div></div>' +
      '<div class="clock" role="timer" aria-label="Time until ' + esc(next.releaseTrain) + ' reaches end of support"><div><b id="cd">0</b><span>days</span></div><div><b id="ch">00</b><span>hrs</span></div><div><b id="cm">00</b><span>min</span></div><div><b id="cs">00</b><span>sec</span></div></div></div>' +
      '<h4 class="qh">Retirement queue</h4><ul class="queue">' +
      queue.map(r => '<li><span class="pill ' + STATUS[r.status].cls + '" style="padding:3px 9px">' + STATUS[r.status].label + '</span><b class="mono">' + esc(r.releaseTrain) + '</b><span>' + fmt(r.eol) + '</span><span>' + r.daysLeft + 'd</span></li>').join('') + '</ul>' +
      '<p class="count-foot"><b>' + esc(next.releaseTrain) + '</b> (' + esc(next.version) + ') reaches end of support on <b>' + fmt(next.eol) + '</b>. Plan your update to <b>' + esc(recommended.releaseTrain) + '</b> before then.</p>';

    const pad = n => String(n).padStart(2, '0');
    const tick = () => {
      let ms = Math.max(0, next.eolEnd - new Date());
      const d = Math.floor(ms / DAY); ms -= d * DAY;
      const h = Math.floor(ms / 36e5); ms -= h * 36e5;
      const m = Math.floor(ms / 6e4);
      const s = Math.floor((ms - m * 6e4) / 1e3);
      $('cd').textContent = d; $('ch').textContent = pad(h); $('cm').textContent = pad(m); $('cs').textContent = pad(s);
    };
    tick();
    clearInterval(countdownTimer);
    countdownTimer = setInterval(tick, 1000);
    setTimeout(() => {
      $('prog').style.strokeDashoffset = 339.3 * (1 - elapsed);
      $('pct').textContent = Math.round(elapsed * 100) + '%';
    }, reduceMotion ? 0 : 300);
  }

  // ---- version checker ----
  function renderChecker() {
    const option = r => '<option value="' + esc(r.version) + '">' + esc(r.version) + ' (' + esc(r.releaseTrain) + ')</option>';
    const live = releases.filter(r => r.status !== 'eol').sort((a, b) => compareVersions(b.version, a.version));
    const dead = releases.filter(r => r.status === 'eol').sort((a, b) => compareVersions(b.version, a.version));
    $('mine').innerHTML = '<option value="">Select…</option><optgroup label="In support">' + live.map(option).join('') + '</optgroup><optgroup label="Out of support">' + dead.map(option).join('') + '</optgroup>';
    $('mine').addEventListener('change', () => { setVerdict(); saveState(); });
  }

  function setVerdict() {
    const r = releases.find(x => x.version === $('mine').value);
    const el = $('verdict');
    if (!r) {
      el.innerHTML = '<span class="dot"></span><span>Pick your version to see how much runway you have.</span>';
      return;
    }
    const R = '<b>' + esc(recommended.releaseTrain) + '</b>';
    const messages = {
      rec: 'You\u2019re on the release recommended for new deployments. <b>' + plural(r.daysLeft, 'day') + '</b> until end of support (' + fmt(r.eol) + ').',
      sup: 'Supported for <b>' + plural(r.daysLeft, 'more day') + '</b> (until ' + fmt(r.eol) + '). The newest release is ' + R + ', so plan your update.',
      end: 'Support ends in <b>' + plural(r.daysLeft, 'day') + '</b> (' + fmt(r.eol) + '). Update to ' + R + ' soon.',
      eol: '<b>Out of support</b> since ' + fmt(r.eol) + '. Update to ' + R + ' now. Microsoft Support can only help you update to a supported version.'
    };
    const c = STATUS[r.status].color;
    el.innerHTML = '<span class="dot" style="background:var(--' + c + ');box-shadow:0 0 12px var(--' + c + ')"></span><span>' + messages[r.status] + '</span>';
  }

  // ---- stats ----
  function renderStats(live) {
    const ending = live.filter(r => r.status === 'end').length;
    const retired = releases.length - live.length;
    const avg = live.length ? Math.round(live.reduce((a, r) => a + r.daysLeft, 0) / live.length) : 0;
    $('stats').innerHTML = [
      [live.length, 'releases in support'],
      [ending, 'ending within ' + ENDING_DAYS + ' days'],
      [retired, 'retired releases'],
      [avg + 'd', 'avg. runway remaining']
    ].map(s => '<div class="stat"><b>' + s[0] + '</b><span>' + s[1] + '</span></div>').join('');
  }

  // ---- timeline ----
  function renderTimeline() {
    const cutoff = addMonths(today, -6);
    const visible = trains.filter(t => state.fullHistory || t.eol >= cutoff);
    $('tlToggle').textContent = state.fullHistory ? 'Show recent only' : 'Show full history (' + trains.length + ' trains)';
    $('tlToggle').setAttribute('aria-pressed', String(state.fullHistory));
    $('tlToggle').hidden = trains.length === visible.length && !state.fullHistory;

    const t0 = new Date(Math.min.apply(null, visible.map(t => t.first)));
    t0.setDate(1);
    const t1 = addMonths(new Date(Math.max.apply(null, visible.map(t => t.eol))), 1);
    t1.setDate(1);
    const total = t1 - t0;
    const pos = d => Math.min(100, Math.max(0, (d - t0) / total * 100));

    const stepMonths = Math.max(1, Math.ceil(((t1 - t0) / DAY / 30.4) / 11));
    let ticks = '', gridlines = '';
    for (let d = new Date(t0); d < t1; d = addMonths(d, stepMonths)) {
      ticks += '<div class="tick" style="left:' + pos(d) + '%">' + fmtShort(d) + '</div>';
      gridlines += '<div class="gl" style="left:calc(104px + (100% - 124px) * ' + pos(d) / 100 + ')"></div>';
    }

    const rows = visible.slice().sort((a, b) => b.first - a.first || b.releaseTrain.localeCompare(a.releaseTrain)).map(t => {
      const a = pos(t.first), c = pos(t.eol);
      const endingStart = Math.max(t.first, new Date(t.eol.getTime() - ENDING_DAYS * DAY));
      const b = pos(endingStart);
      const s = STATUS[t.status];
      const segs = '<div class="seg full' + (b >= c ? ' only' : '') + '" style="left:' + a + '%;width:' + Math.max(0.4, b - a) + '%"></div>' +
        (c > b ? '<div class="seg end" style="left:' + b + '%;width:' + (c - b) + '%"></div>' : '');
      return '<div class="tl-row' + (t.status === 'eol' ? ' dim' : '') + '" role="button" tabindex="0" data-train="' + esc(t.releaseTrain) + '" aria-label="' + esc(t.releaseTrain + ', ' + s.label + ', released ' + fmt(t.first) + ', end of support ' + fmt(t.eol)) + '">' +
        '<div class="tl-label"><span class="mono">' + esc(t.releaseTrain) + '</span></div><div class="tl-track">' + segs + '</div></div>';
    }).join('');

    $('tlInner').innerHTML = '<div class="tl-axis">' + ticks + '</div>' + gridlines + rows +
      '<div class="today" style="left:calc(104px + (100% - 124px) * ' + pos(today) / 100 + ')"><em>TODAY</em></div>';

    const tl = $('tl');
    if (reduceMotion) tl.classList.add('in');
    else if (!tl.classList.contains('in')) {
      new IntersectionObserver((entries, o) => { if (entries[0].isIntersecting) { tl.classList.add('in'); o.disconnect(); } }, { threshold: 0.15 }).observe(tl);
    }

    const sc = tl.querySelector('.tl-scroll');
    sc.scrollLeft = Math.max(0, 104 + ($('tlInner').offsetWidth - 124) * pos(today) / 100 - sc.clientWidth / 2);
  }

  function bindTimeline() {
    const tip = $('tip');
    const inner = $('tlInner');
    const trainOf = row => trains.find(t => t.releaseTrain === row.dataset.train);

    inner.addEventListener('mousemove', e => {
      const row = e.target.closest('.tl-row');
      const t = row && trainOf(row);
      if (!t) { tip.classList.remove('on'); return; }
      tip.innerHTML = '<b>' + esc(t.releaseTrain) + ' · ' + STATUS[t.status].label + '</b><div>Released ' + fmt(t.first) + '</div><div>End of support ' + fmt(t.eol) + '</div><div>' + esc(t.versions.join(', ')) + '</div>';
      tip.classList.add('on');
      const x = Math.min(innerWidth - tip.offsetWidth - 12, Math.max(12, e.clientX + 14));
      tip.style.left = x + 'px';
      tip.style.top = Math.min(innerHeight - tip.offsetHeight - 12, e.clientY + 16) + 'px';
    });
    inner.addEventListener('mouseleave', () => tip.classList.remove('on'));
    inner.addEventListener('click', e => { const row = e.target.closest('.tl-row'); if (row) jumpToTrain(row.dataset.train); });
    inner.addEventListener('keydown', e => {
      const row = e.target.closest('.tl-row');
      if (row && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); jumpToTrain(row.dataset.train); }
    });
    $('tlToggle').addEventListener('click', () => { state.fullHistory = !state.fullHistory; renderTimeline(); });
  }

  function jumpToTrain(train) {
    state.status = 'all'; state.os = ''; state.q = 'train:' + train;
    syncControls();
    draw();
    $('releases').scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth' });
  }

  // ---- cards ----
  const CHIPS = [['active', 'In support'], ['rec', 'Recommended'], ['end', 'Ending soon'], ['eol', 'End of support'], ['all', 'All']];

  function matchesStatus(r) {
    switch (state.status) {
      case 'active': return r.status !== 'eol';
      case 'all': return true;
      default: return r.status === state.status;
    }
  }

  function filtered() {
    const terms = state.q.toLowerCase().split(/\s+/).filter(Boolean);
    return releases.filter(r => {
      if (!matchesStatus(r)) return false;
      if (state.os && r.osVersion !== state.os) return false;
      const hay = [r.version, r.releaseTrain, r.osBuild, r.osVersion, r.release, STATUS[r.status].label].join(' ').toLowerCase();
      // "train:2610" matches the release train exactly (a plain "2610" also matches OS build 26100.x)
      return terms.every(t => t.indexOf('train:') === 0 ? r.releaseTrain === t.slice(6) : hay.indexOf(t) !== -1);
    });
  }

  function renderChips() {
    const count = k => k === 'all' ? releases.length : k === 'active' ? releases.filter(r => r.status !== 'eol').length : releases.filter(r => r.status === k).length;
    $('chips').innerHTML = CHIPS.map(c => '<button type="button" class="chip" data-k="' + c[0] + '" aria-pressed="' + (c[0] === state.status) + '">' + c[1] + '<small>' + count(c[0]) + '</small></button>').join('');
  }

  function cardHtml(r, i) {
    const s = STATUS[r.status];
    const total = r.eol - r.first;
    const endingStart = Math.max(r.first, new Date(r.eol.getTime() - ENDING_DAYS * DAY));
    const fullPct = Math.min(100, Math.max(0, (endingStart - r.first) / total * 100));
    const nowPct = Math.min(100, Math.max(0, (today - r.first) / total * 100));
    const u = r.urls || {};
    const links = [['What\u2019s new', u.news], ['Security update', u.security], ['Known issues', u.issues]]
      .filter(l => safeUrl(l[1])).map(l => '<a href="' + safeUrl(l[1]) + '" rel="noopener">' + l[0] + '</a>');
    const zip = r.solutionUpdate && safeUrl(r.solutionUpdate.uri);
    if (zip) links.push('<a href="' + zip + '" rel="noopener" title="Solution update package for limited connectivity">Update ZIP</a>');
    const builds = [r.version + ' · ' + fmt(parseDate(r.availabilityDate))]
      .concat((r.supersedes || []).map(b => b.version + ' · ' + fmt(parseDate(b.availabilityDate))));
    const hash = r.solutionUpdate && r.solutionUpdate.fileHash;
    const features = (Array.isArray(r.features) ? r.features : []).filter(f => f && f.title);
    const notes = safeUrl(u.news);
    const featureHtml = features.length
      ? '<ul class="features">' + features.map(f =>
        '<li><span class="ft-title"><b>' + esc(f.title) + '</b>' + (f.preview ? '<span class="tag">Preview</span>' : '') + '</span>' +
        (f.summary ? '<span class="ft-summary">' + esc(f.summary) + '</span>' : '') + '</li>').join('') + '</ul>' +
        (notes ? '<a class="all-notes" href="' + notes + '" rel="noopener">Full release notes →</a>' : '')
      : '<p class="muted small">No feature highlights are listed for this release.' + (notes ? ' See the <a href="' + notes + '" rel="noopener">release notes</a>.' : '') + '</p>';

    return '<article class="card ' + s.cls + '" id="c-' + esc(r.version) + '" style="animation-delay:' + Math.min(i, 8) * 55 + 'ms">' +
      '<div class="card-top"><div><div class="ver">' + esc(r.releaseTrain) + '</div><div class="build mono">' + esc(r.version) + '</div></div><span class="pill">' + s.label + '</span></div>' +
      '<div class="tags"><span class="tag">' + esc(r.osVersion) + '</span><span class="tag">OS build ' + esc(r.osBuild) + '</span>' + (r.newDeployments ? '<span class="tag">New deployments</span>' : '') + '</div>' +
      '<div class="meter" title="Support window progress"><i class="m-full" style="width:' + fullPct + '%"></i><i class="m-end" style="width:' + (100 - fullPct) + '%"></i><span class="now" style="left:calc(' + nowPct + '% - 1px)"></span></div>' +
      '<div class="dates"><span>' + fmtShort(r.first) + '</span><span>' + fmtShort(r.eol) + '</span></div>' +
      '<div class="dates" style="margin-top:2px"><span>Released ' + fmt(r.first) + '</span><span>Ends ' + fmt(r.eol) + '</span></div>' +
      '<div class="left">' + leftText(r) + '</div>' +
      '<details class="more"><summary>Details' + (features.length ? '<small>' + features.length + ' features</small>' : '') + '</summary>' +
      '<h4>Features</h4>' + featureHtml +
      '<h4>Build</h4><p class="muted small">OS build <b class="mono">' + esc(r.osBuild) + '</b> (' + esc(r.osVersion) + ')</p>' +
      '<ul class="builds">' + builds.map(b => '<li class="mono">' + esc(b) + '</li>').join('') + '</ul>' +
      (links.length ? '<div class="links">' + links.join('') + '</div>' : '') +
      '<div class="row"><button type="button" class="mini" data-copy="' + esc(r.version) + '">Copy version</button>' +
      (hash ? '<button type="button" class="mini" data-copy="' + esc(hash) + '">Copy ZIP SHA256</button>' : '') + '</div></details>' +
      '</article>';
  }

  function draw() {
    const list = filtered().sort((a, b) => {
      if (state.sort === 'old') return a.first - b.first || compareVersions(a.version, b.version);
      if (state.sort === 'eol') return (a.status === 'eol') - (b.status === 'eol') || a.eol - b.eol || compareVersions(a.version, b.version);
      return b.first - a.first || compareVersions(b.version, a.version);
    });
    $('grid').innerHTML = list.length ? list.map(cardHtml).join('') : '<div class="empty">No releases match. Try a different search or filter.</div>';
    $('result-count').textContent = 'Showing ' + list.length + ' of ' + releases.length + ' releases';
    renderChips();
    saveState();
  }

  function syncControls() {
    $('q').value = state.q;
    $('os').value = state.os;
    $('sort').value = state.sort;
  }

  // ---- URL state ----
  function loadState() {
    const p = new URLSearchParams(location.search);
    if (CHIPS.some(c => c[0] === p.get('status'))) state.status = p.get('status');
    if (p.get('os') === '24H2' || p.get('os') === '23H2') state.os = p.get('os');
    if (['new', 'old', 'eol'].indexOf(p.get('sort')) !== -1) state.sort = p.get('sort');
    state.q = p.get('q') || '';
    return p.get('mine') || '';
  }

  function saveState() {
    const p = new URLSearchParams();
    if (state.status !== 'active') p.set('status', state.status);
    if (state.os) p.set('os', state.os);
    if (state.q) p.set('q', state.q);
    if (state.sort !== 'new') p.set('sort', state.sort);
    const mine = $('mine').value;
    if (mine) p.set('mine', mine);
    const qs = p.toString();
    history.replaceState(null, '', location.pathname + (qs ? '?' + qs : '') + location.hash);
  }

  function bind() {
    $('q').addEventListener('input', e => { state.q = e.target.value.trim(); draw(); });
    $('os').addEventListener('change', e => { state.os = e.target.value; draw(); });
    $('sort').addEventListener('change', e => { state.sort = e.target.value; draw(); });
    $('chips').addEventListener('click', e => {
      const b = e.target.closest('.chip');
      if (b) { state.status = b.dataset.k; draw(); }
    });
    $('grid').addEventListener('click', e => {
      const b = e.target.closest('[data-copy]');
      if (b) copy(b.dataset.copy, b);
    });
    addEventListener('keydown', e => {
      const typing = /^(input|textarea|select)$/i.test(document.activeElement && document.activeElement.tagName);
      if (e.key === '/' && !typing) { e.preventDefault(); $('q').focus(); }
    });
    $('theme').addEventListener('click', () => {
      const root = document.documentElement;
      root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
      try { localStorage.setItem('theme', root.dataset.theme); } catch (e) { /* ignore */ }
    });
    bindTimeline();
  }

  function init(data) {
    releases = data.releases.map(enrichRelease);
    trains = data.trains.map(t => enrichTrain(t, data.releases));

    const live = releases.filter(r => r.status !== 'eol');
    recommended = releases.filter(r => r.newDeployments)[0] ||
      releases.slice().sort((a, b) => compareVersions(b.version, a.version))[0];

    if (data.generatedAt) $('updated').textContent = ' · updated ' + fmt(new Date(data.generatedAt));

    renderRecommended();
    renderCountdown(live);
    renderStats(live);
    renderChecker();
    renderTimeline();

    const mine = loadState();
    syncControls();
    if (mine && releases.some(r => r.version === mine)) $('mine').value = mine;
    setVerdict();
    draw();
  }

  bind();

  fetch('data/releases.json', { cache: 'no-cache' })
    .then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(init)
    .catch(err => {
      console.error(err);
      $('error').hidden = false;
      $('rec').innerHTML = '<p class="loading">Release data is unavailable.</p>';
    });

  // Cache the site so it keeps working offline after the first visit
  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) {
    navigator.serviceWorker.register('sw.js').catch(() => { /* offline support is best effort */ });
  }
})();
