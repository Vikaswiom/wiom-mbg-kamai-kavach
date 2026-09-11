/* ═══════════════════════════════════════════════════════════════════
   daily-installation.html — deployment-mode contract

   Runs the page's own <script> against a stub DOM in each of the
   deployments it supports, and asserts the behaviours that differ
   between them. The point of the suite is the LINK deployment (a
   plain public URL opened from a CT campaign): it must never run the
   two behaviours that exist only to get an in-app popup off the
   screen, while the in-app deployments must still run both.

     node tests/daily-installation-link-mode.test.js

   No dependencies, no build step — same as the rest of the repo.
   ═══════════════════════════════════════════════════════════════ */
const fs = require('fs'), vm = require('vm'), path = require('path');
const FILE = path.join(__dirname, '..', 'daily-installation.html');

let passed = 0, failed = 0;
function ok(cond, label){
  if(cond){ passed++; }
  else { failed++; console.error('  ✗ ' + label); }
}
function group(name){ console.log('\n' + name); }

/* ── stub DOM ──────────────────────────────────────────────────── */
function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function makeEl(id){
  return {
    id, _text:'', _html:'', style:{}, listeners:{}, attrs:{}, children:[], className:'',
    get textContent(){ return this._text; },
    set textContent(v){ this._text = String(v == null ? '' : v); this._html = esc(v); },
    get innerHTML(){ return this._html; },
    set innerHTML(v){ this._html = String(v == null ? '' : v); },
    addEventListener(ev, fn){ (this.listeners[ev] = this.listeners[ev] || []).push(fn); },
    removeEventListener(){},
    setAttribute(k, v){ this.attrs[k] = String(v); },
    getAttribute(k){ return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; },
    appendChild(c){ this.children.push(c); return c; },
    querySelectorAll(){ return []; },
    click(){ (this.listeners['click'] || []).forEach(fn => fn({ target:this, preventDefault(){}, stopPropagation(){} })); }
  };
}

/* Runs the page script. opts: protocol, search, embedded, payload,
   status, spans, ctBridge. Resolves once the async paths (fetch ->
   render -> auto-close -> escalation) have had time to run.        */
function run(opts){
  const code = (() => {
    const html = fs.readFileSync(FILE, 'utf8');
    const parts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
    if(!parts.length) throw new Error('no <script> in ' + FILE);
    return parts[parts.length - 1][1];
  })();

  const els = {};
  ['cardArea','closeBtn','countPill','countText','langToggle','retryBtn',
   'ctTech','ctTechSnake','ctExec','ctExecSnake','app'].forEach(id => els[id] = makeEl(id));
  const spans = opts.spans || {};
  Object.keys(spans).forEach(k => { els[k].textContent = spans[k]; });

  const log = { events:[], navigations:[], parentMessages:[], xhrUrls:[], dismissCalls:0 };

  const document = {
    getElementById(id){ return els[id] || (els[id] = makeEl(id)); },
    createElement(tag){ return makeEl('<' + tag + '>'); },
    querySelectorAll(){ return []; },
    addEventListener(){},
    documentElement: makeEl('html'),
    title: '', body: makeEl('body')
  };
  const location = {
    protocol: opts.protocol, search: opts.search || '',
    _href: opts.protocol + '//host/daily-installation.html',
    get href(){ return this._href; },
    set href(v){ this._href = v; log.navigations.push(v); }
  };
  function XHRStub(){
    this.readyState = 0; this.status = 0; this.responseText = '';
    this.open = (m, u) => { log.xhrUrls.push(u); };
    this.setRequestHeader = () => {}; this.abort = () => {};
    this.send = () => setTimeout(() => {
      this.readyState = 4;
      this.status = opts.status == null ? 200 : opts.status;
      this.responseText = JSON.stringify(opts.payload == null ? { items:[] } : opts.payload);
      if(this.onreadystatechange) this.onreadystatechange();
    }, 5);
  }

  const w = {
    document, location, XMLHttpRequest: XHRStub,
    setTimeout, clearTimeout, setInterval, clearInterval,
    console: { log(){}, warn(){}, error(){} },
    encodeURIComponent, decodeURIComponent, URLSearchParams,
    JSON, Math, Date, parseInt, parseFloat, isNaN,
    String, Number, Object, Array, RegExp, Error,
    navigator: { userAgent:'node', language:'en' },
    addEventListener(){}, postMessage(){}
  };
  w.window = w; w.self = w; w.top = w;
  w.parent = opts.embedded
    ? { postMessage(msg){ log.parentMessages.push(msg); } }
    : w;
  if(opts.ctBridge){
    w.CleverTap = {
      pushEvent(ev, props){ log.events.push({ ev, props: props ? JSON.parse(props) : {} }); return true; },
      dismissInAppNotification(){ log.dismissCalls++; }
    };
  }

  const sandbox = Object.assign({}, w);
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  try { vm.runInContext(code, sandbox, { filename:'daily-installation.html' }); }
  catch(e){ log.error = e && e.message; }

  return new Promise(res => setTimeout(() => {
    /* events relayed to the wrapper instead of a local bridge */
    log.parentMessages
      .filter(m => m && m.__ct === 1 && m.action === 'event')
      .forEach(m => log.events.push({ ev:m.event, props:m.properties || {} }));
    log.names = log.events.map(e => e.ev);
    log.has = n => log.names.indexOf('DailyInstall_' + n) !== -1;
    log.apiUrl = log.xhrUrls.length ? log.xhrUrls[0].replace(/&_t=\d+$/, '') : '';
    res({ log, els });
  }, 1400));
}

/* ── fixtures ──────────────────────────────────────────────────── */
const ITEM = {
  execution_candidate_id:'EC1', connection_id:'CN1',
  customer_name:'Ramesh Kumar', customer_mobile:'9876543210',
  service_address: JSON.stringify({
    house:'H-12', street:'Main Road', area:'Sector 5',
    city:'Jaipur', pincode:'302001', landmark:'near temple'
  }),
  confirmed_slot_time_range_start:'10:00', confirmed_slot_time_range_end:'13:00',
  current_state:'SCHEDULED', task_status:'PENDING'
};
const FULL  = { executor_id:'10374', install_date:'2026-09-11', installation_count:1, items:[ITEM] };
const EMPTY = { executor_id:'10374', install_date:'2026-09-11', installation_count:0, items:[] };

const LINK    = { protocol:'https:', embedded:false, ctBridge:true };
const PASTED  = { protocol:'about:', embedded:false, ctBridge:true };
const WRAPPED = { protocol:'https:', embedded:true,  ctBridge:false };

(async function main(){

  group('LINK — the id travels from the campaign URL to the API');
  {
    const { log } = await run({ ...LINK, search:'?technicianId=10374', payload:FULL });
    ok(!log.error, 'script runs clean: ' + log.error);
    ok(log.xhrUrls.length === 1, 'exactly one API call');
    ok(/[?&]executorId=10374(&|$)/.test(log.apiUrl), 'sent as executorId=10374, got ' + log.apiUrl);
    ok(log.apiUrl.indexOf('technicianId=') === -1, 'never sent as technicianId');
    ok(log.apiUrl.indexOf('csp-tas-service.i2e1agents.in') !== -1, 'hits the TAS host');
    ok(log.has('Viewed'), 'Viewed fired');
    ok(log.events.every(e => e.props.mode === 'link'), 'every event carries mode=link');
    ok(log.events.every(e => e.props.technicianId === e.props.executorId), 'one id under both names');
  }
  {
    const { log } = await run({ ...LINK, search:'?executorId=10374', payload:FULL });
    ok(/[?&]executorId=10374(&|$)/.test(log.apiUrl), '?executorId= is accepted too');
  }
  {
    const { els } = await run({ ...LINK, search:'?technicianId=10374', payload:FULL });
    ok((els.cardArea.innerHTML || '').indexOf('Ramesh Kumar') !== -1, 'the customer renders');
  }

  group('LINK — no popup, so neither close behaviour may run');
  {
    const { log, els } = await run({ ...LINK, search:'?technicianId=10374', payload:EMPTY });
    ok(!log.has('Auto_Closed_Empty'), 'a zero-install day does NOT auto-close a link');
    ok(log.navigations.indexOf('clevertap://closeInApp') === -1, 'never navigates to the CT scheme');
    ok(log.navigations.length === 0, 'no navigation at all');
    ok((els.cardArea.innerHTML || '').indexOf('इंस्टॉलेशन') !== -1, 'the empty state is shown instead');
    ok(log.has('Viewed'), 'the reach is still recorded');
    ok(els.closeBtn.style.display === 'none', 'the ✕ is hidden — nothing to close');
  }

  group('IN-APP — the close behaviours are preserved');
  {
    const { log, els } = await run({ ...PASTED, spans:{ ctTech:'10374' }, payload:EMPTY });
    ok(log.has('Auto_Closed_Empty'), 'pasted creative still auto-closes an empty day');
    ok(log.navigations.indexOf('clevertap://closeInApp') !== -1, 'and still escalates to the CT scheme');
    ok(els.closeBtn.style.display !== 'none', 'pasted creative still draws its own ✕');
    ok(log.events.every(e => e.props.mode === 'inapp_pasted'), 'mode=inapp_pasted');
  }
  {
    const { log, els } = await run({ ...WRAPPED, search:'?technicianId=10374', payload:EMPTY });
    ok(log.has('Auto_Closed_Empty'), 'wrapped page still auto-closes an empty day');
    ok(log.parentMessages.some(m => m.action === 'dismiss'), 'relays dismiss to the wrapper');
    ok(log.navigations.indexOf('clevertap://closeInApp') === -1, 'embedded never self-navigates');
    ok(els.closeBtn.style.display === 'none', 'embedded hides its ✕ — the wrapper draws one');
    ok(log.events.every(e => e.props.mode === 'inapp_wrapper'), 'mode=inapp_wrapper');
  }

  group('LINK — an unsubstituted token must not reach TAS');
  {
    const { log } = await run({ ...LINK, search:'?technicianId={{Profile.technicianId}}', payload:EMPTY });
    ok(log.xhrUrls.length === 0, 'no API call with a raw Liquid token as the id');
    ok(log.has('No_Technician_Id'), 'reports No_Technician_Id instead');
    ok(log.events.every(e => e.props.idSource === 'none'), 'idSource=none, not url_param');
  }
  {
    const { log } = await run({ ...LINK, search:'?technicianId=', payload:EMPTY });
    ok(log.xhrUrls.length === 0, 'an empty id makes no API call');
    ok(log.has('No_Technician_Id'), 'and is reported');
  }
  {
    const { log } = await run({ ...LINK, search:'', payload:EMPTY });
    ok(log.xhrUrls.length === 0, 'no id at all makes no API call');
  }

  console.log('\n' + (failed ? '✗ ' : '✓ ') + passed + ' passed, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
})();
