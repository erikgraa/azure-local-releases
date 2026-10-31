(function () {
  'use strict';

  var ENDING_SOON_DAYS = 60;
  var DAY_MS = 86400000;

  var state = { releases: [], status: 'supported', os: '', q: '', sortKey: 'firstAvailabilityDate', sortDir: -1 };

  var rowsEl = document.getElementById('rows');
  var searchEl = document.getElementById('search');
  var osEl = document.getElementById('os');
  var statusEl = document.getElementById('status');
  var countEl = document.getElementById('result-count');
  var emptyEl = document.getElementById('empty');
  var errorEl = document.getElementById('error');
  var cardsEl = document.getElementById('cards');

  function utcToday() {
    var now = new Date();
    return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  }

  function parseDate(iso) {
    var p = iso.split('-');
    return Date.UTC(+p[0], +p[1] - 1, +p[2]);
  }

  // Status and countdown are computed in the browser so they stay correct between daily data refreshes
  function enrich(release, today) {
    var daysLeft = Math.round((parseDate(release.endOfSupportDate) - today) / DAY_MS);
    var status = daysLeft < 0 ? 'eol' : daysLeft <= ENDING_SOON_DAYS ? 'ending' : 'supported';
    return Object.assign({}, release, { daysLeft: daysLeft, status: status });
  }

  function plural(n, unit) {
    return n + ' ' + unit + (n === 1 ? '' : 's');
  }

  function span(days) {
    if (days < 90) return plural(days, 'day');
    if (days < 730) return plural(Math.round(days / 30.4), 'month');
    return plural(Math.round(days / 365.25 * 10) / 10, 'year');
  }

  function countdown(daysLeft) {
    if (daysLeft === 0) return 'Ends today';
    if (daysLeft > 0) return 'In ' + span(daysLeft);
    return 'Ended ' + span(-daysLeft) + ' ago';
  }

  var STATUS_LABEL = { supported: 'Supported', ending: 'Ending soon', eol: 'End of support' };

  function compareVersions(a, b) {
    var pa = a.split('.').map(Number), pb = b.split('.').map(Number);
    for (var i = 0; i < Math.max(pa.length, pb.length); i++) {
      var d = (pa[i] || 0) - (pb[i] || 0);
      if (d) return d;
    }
    return 0;
  }

  function sortValueCompare(key, a, b) {
    switch (key) {
      case 'version': return compareVersions(a.version, b.version);
      case 'osBuild': return compareVersions(a.osBuild, b.osBuild);
      case 'releaseTrain': return a.releaseTrain.localeCompare(b.releaseTrain) || compareVersions(a.version, b.version);
      case 'status':
      case 'daysLeft': return a.daysLeft - b.daysLeft;
      default: return a[key].localeCompare(b[key]);
    }
  }

  function matches(r) {
    if (state.status === 'supported' && r.status === 'eol') return false;
    if (state.status === 'ending' && r.status !== 'ending') return false;
    if (state.status === 'eol' && r.status !== 'eol') return false;
    if (state.os && r.osVersion !== state.os) return false;
    if (state.q) {
      var hay = [r.version, r.releaseTrain, r.osBuild, r.osVersion, r.release].join(' ').toLowerCase();
      return state.q.toLowerCase().split(/\s+/).every(function (t) { return hay.indexOf(t) !== -1; });
    }
    return true;
  }

  function el(tag, props, children) {
    var node = document.createElement(tag);
    Object.keys(props || {}).forEach(function (k) {
      if (k === 'text') node.textContent = props[k];
      else if (k === 'class') node.className = props[k];
      else node.setAttribute(k, props[k]);
    });
    (children || []).forEach(function (c) { node.appendChild(c); });
    return node;
  }

  function safeUrl(url) {
    return /^https:\/\//.test(url || '') ? url : null;
  }

  function link(text, url) {
    var safe = safeUrl(url);
    return safe ? el('a', { href: safe, text: text, rel: 'noopener' }) : null;
  }

  function renderRow(r) {
    var versionCell = el('td', { class: 'version' }, [document.createTextNode(r.version)]);
    if (r.newDeployments) {
      versionCell.appendChild(el('span', { class: 'tag', text: 'New deployments', title: 'Microsoft recommends this build for new deployments' }));
    }

    var released = el('td', { class: 'date', text: r.firstAvailabilityDate });
    if (r.supersedes && r.supersedes.length) {
      released.title = 'First available ' + r.firstAvailabilityDate + '; latest build ' + r.availabilityDate;
    }

    var links = el('div', { class: 'links' });
    [['What\u2019s new', r.urls && r.urls.news], ['Security', r.urls && r.urls.security], ['Known issues', r.urls && r.urls.issues]].forEach(function (l) {
      var a = link(l[0], l[1]);
      if (a) links.appendChild(a);
    });
    if (r.solutionUpdate && r.solutionUpdate.uri) {
      var zip = link('ZIP', r.solutionUpdate.uri);
      if (zip) {
        zip.title = 'Solution update package' + (r.solutionUpdate.fileHash ? ' (SHA256 ' + r.solutionUpdate.fileHash + ')' : '');
        links.appendChild(zip);
      }
    }

    return el('tr', {}, [
      versionCell,
      el('td', { class: 'num', text: r.osBuild + ' (' + r.osVersion + ')' }),
      released,
      el('td', {}, [el('span', { class: 'badge ' + r.status, text: STATUS_LABEL[r.status] })]),
      el('td', { class: 'date', text: r.endOfSupportDate }),
      el('td', { class: r.status === 'supported' ? 'muted' : '', text: countdown(r.daysLeft) }),
      el('td', {}, [links])
    ]);
  }

  function render() {
    var list = state.releases.filter(matches).sort(function (a, b) {
      return sortValueCompare(state.sortKey, a, b) * state.sortDir || compareVersions(b.version, a.version);
    });

    rowsEl.textContent = '';
    list.forEach(function (r) { rowsEl.appendChild(renderRow(r)); });

    emptyEl.hidden = list.length > 0;
    countEl.textContent = 'Showing ' + list.length + ' of ' + state.releases.length + ' releases';

    document.querySelectorAll('thead th[data-sort]').forEach(function (th) {
      var active = th.dataset.sort === state.sortKey;
      if (active) th.setAttribute('aria-sort', state.sortDir === 1 ? 'ascending' : 'descending');
      else th.removeAttribute('aria-sort');
    });

    statusEl.querySelectorAll('button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.value === state.status));
    });

    saveState();
  }

  function card(label, value, detail) {
    return el('div', { class: 'card' }, [
      el('div', { class: 'label', text: label }),
      el('div', { class: 'value', text: value }),
      el('div', { class: 'detail', text: detail })
    ]);
  }

  function renderCards(data) {
    var all = state.releases;
    var supported = all.filter(function (r) { return r.status !== 'eol'; });
    var newest = all.slice().sort(function (a, b) { return compareVersions(b.version, a.version); })[0];
    var deploy = all.filter(function (r) { return r.newDeployments; })[0] || newest;
    var next = supported.slice().sort(function (a, b) { return a.daysLeft - b.daysLeft; })[0];

    cardsEl.textContent = '';
    if (deploy) cardsEl.appendChild(card('Latest for new deployments', deploy.version, 'Released ' + deploy.firstAvailabilityDate + ' · supported until ' + deploy.endOfSupportDate));
    cardsEl.appendChild(card('Supported releases', String(supported.length), supported.filter(function (r) { return r.status === 'ending'; }).length + ' ending within ' + ENDING_SOON_DAYS + ' days'));
    if (next) cardsEl.appendChild(card('Next end of support', next.endOfSupportDate, next.version + ' · ' + countdown(next.daysLeft).toLowerCase()));
    cardsEl.hidden = false;

    if (data.generatedAt) {
      document.getElementById('generated').textContent = ' (last updated ' + data.generatedAt.slice(0, 10) + ')';
    }
  }

  function loadState() {
    var p = new URLSearchParams(location.search);
    if (['supported', 'ending', 'eol', 'all'].indexOf(p.get('status')) !== -1) state.status = p.get('status');
    if (p.get('os') === '24H2' || p.get('os') === '23H2') state.os = p.get('os');
    state.q = p.get('q') || '';
    if (p.get('sort')) {
      var s = p.get('sort');
      state.sortDir = s.charAt(0) === '-' ? -1 : 1;
      var key = s.replace(/^-/, '');
      if (document.querySelector('thead th[data-sort="' + key + '"]')) state.sortKey = key;
    }
    searchEl.value = state.q;
    osEl.value = state.os;
  }

  function saveState() {
    var p = new URLSearchParams();
    if (state.status !== 'supported') p.set('status', state.status);
    if (state.os) p.set('os', state.os);
    if (state.q) p.set('q', state.q);
    if (state.sortKey !== 'firstAvailabilityDate' || state.sortDir !== -1) p.set('sort', (state.sortDir === -1 ? '-' : '') + state.sortKey);
    var qs = p.toString();
    history.replaceState(null, '', location.pathname + (qs ? '?' + qs : ''));
  }

  function bind() {
    searchEl.addEventListener('input', function () { state.q = searchEl.value.trim(); render(); });
    osEl.addEventListener('change', function () { state.os = osEl.value; render(); });
    statusEl.addEventListener('click', function (e) {
      var b = e.target.closest('button');
      if (b) { state.status = b.dataset.value; render(); }
    });
    document.querySelectorAll('thead th[data-sort] button').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var key = btn.parentNode.dataset.sort;
        if (state.sortKey === key) state.sortDir *= -1;
        else { state.sortKey = key; state.sortDir = key === 'firstAvailabilityDate' || key === 'version' || key === 'releaseTrain' || key === 'osBuild' ? -1 : 1; }
        render();
      });
    });
    document.getElementById('theme-toggle').addEventListener('click', function () {
      var root = document.documentElement;
      var dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
      root.dataset.theme = dark ? 'light' : 'dark';
      try { localStorage.setItem('theme', root.dataset.theme); } catch (e) {}
    });
  }

  loadState();
  bind();

  fetch('data/releases.json', { cache: 'no-cache' })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (data) {
      var today = utcToday();
      state.releases = data.releases.map(function (r) { return enrich(r, today); });
      renderCards(data);
      render();
    })
    .catch(function () {
      errorEl.hidden = false;
    });
})();
