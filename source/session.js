(() => {
  if (location.origin !== 'https://next.vestmarkets.com' || window.top !== window) return;
  const api = 'https://api-gateway.hz.vestmarkets.com';
  const allowed = new Set(['/v3/accounts', '/v3/capital/accounts/active', '/v3/positions/opened']);
  const fetchVest = window.fetch.bind(window);
  let session;
  let busy = false;
  const equity = new Map();
  const report = value => window.webkit.messageHandlers.islandSnapshot.postMessage(JSON.stringify(value));
  function observe(url, auth) {
    try {
      const target = new URL(url, location.href);
      if (target.origin !== api || !allowed.has(target.pathname) || !auth?.startsWith('Bearer ')) return;
      const claims = JSON.parse(atob(auth.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
      if (!claims.userId || claims.accountId || !(claims.exp * 1000 > Date.now())) return;
      if (session?.auth === auth) return;
      if (session?.user !== claims.userId) equity.clear();
      session = { auth, user: claims.userId, expires: claims.exp * 1000 };
      void refresh();
    } catch {}
  }
  window.fetch = function(input, options) {
    try {
      observe(input?.url ?? input, new Headers(options?.headers ?? input?.headers).get('authorization'));
    } catch {}
    return fetchVest(input, options);
  };
  const requests = new WeakMap();
  const open = XMLHttpRequest.prototype.open;
  const header = XMLHttpRequest.prototype.setRequestHeader;
  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url, ...args) {
    requests.set(this, { url });
    return open.call(this, method, url, ...args);
  };
  XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
    if (name.toLowerCase() === 'authorization' && requests.has(this)) requests.get(this).auth = value;
    return header.call(this, name, value);
  };
  XMLHttpRequest.prototype.send = function(...args) {
    const request = requests.get(this);
    if (request) observe(request.url, request.auth);
    return send.apply(this, args);
  };

  async function read(path, auth, params = {}, body) {
    const url = new URL(path, api);
    for (const [key, val] of Object.entries(params)) url.searchParams.set(key, val);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 7000);
    try {
      const result = await fetchVest(url, {
        method: body ? 'POST' : 'GET', redirect: 'error', cache: 'no-store', signal: controller.signal,
        headers: { ...(auth ? { Authorization: auth } : {}), ...(body ? {'Content-Type':'application/json'} : {}) },
        body: body ? JSON.stringify(body) : undefined
      });
      if (!result.ok) throw new Error(String(result.status));
      return await result.json();
    } finally {
      clearTimeout(timeout);
    }
  }
  function number(value) {
    return value == null || value === '' || !Number.isFinite(Number(value)) ? null : Number(value);
  }
  async function accountEquity(id, auth) {
    const now = Date.now();
    const cached = equity.get(id);
    if (cached && now - cached.at < 60000) return cached.value;
    const issued = cached?.expires > now + 30000 ? cached : await read('/v3/auth/account-token', auth, {}, {accountId:id});
    if (!issued.accessToken) return null;
    const series = await read('/v3/trading-performance/series', 'Bearer ' + issued.accessToken,
      {from:now - 1200000, to:now, points:24});
    const point = series.items?.reduce((a,b) => !a || +b.ts > +a.ts ? b : a, null);
    if (!point || !(+point.ts > now - 300000)) return null;
    const collateral = number(point.collateral_value), pnl = number(point.total_unrealized_pnl);
    const value = number(point.equity_value) ?? (collateral !== null && pnl !== null ? collateral + pnl : null);
    if (value !== null && session?.auth === auth) equity.set(id, {
      at:now, value, accessToken:issued.accessToken, expires:issued.expires ?? issued.accessExpiresAtMs
    });
    return value;
  }

  async function refresh() {
    if (busy || !session) return;
    if (session.expires <= Date.now()) {
      session = undefined;
      equity.clear();
      report({state:'reconnecting',at:Date.now()});
      return;
    }
    const current = session;
    const {auth} = current;
    busy = true;
    try {
      const [roster, opened] = await Promise.all([
        read('/v3/capital/accounts/active',auth), read('/v3/positions/opened',auth)
      ]);
      if (!Array.isArray(roster.accounts) || !Array.isArray(opened.positions)) throw new Error('Unexpected data');
      const rows = opened.positions.filter(p => !(number(p.closeDate) > 0) && number(p.quantity) > 0);
      if (rows.some(p => !(p.accountId ?? p.account_id) || !p.symbol || !p.positionId)) throw new Error('Incomplete positions');
      const symbols = [...new Set(rows.map(p => p.symbol))];
      const quoteAt = Date.now();
      const quotes = symbols.length ? await read('/v3/ticker/latest',null,{symbols:symbols.join(',')}) : {tickers:[]};
      const tickerBySymbol = new Map(quotes.tickers.map(ticker => [ticker.symbol, ticker]));
      const accounts = [];
      const ids = new Set();
      const entries = roster.accounts.filter(a => a.id && number(a.initial_capital) > 0);
      for (let i = 0; i < entries.length; i += 5) {
        accounts.push(...await Promise.all(entries.slice(i,i+5).map(async a => {
          const id = String(a.id), size = number(a.initial_capital), floor = number(a.max_drawdown_limit);
          const daily = number(a.daily_loss_floor);
          const value = number(a.equity ?? a.current_equity) ?? await accountEquity(id,auth).catch(() => null);
          const index = number(a.attempt_index ?? a.index);
          const name = size >= 1000 ? size / 1000 + 'k' : '$' + size;
          ids.add(id);
          return { id, label:index === null ? name : '#' + (index+1) + ' · ' + name,
            drawdown:value === null ? null : Math.max(0,size-value), limit:floor === null ? null : size-floor,
            room:value === null || floor === null ? null : value-Math.max(floor,daily ?? floor) };
        })));
      }
      const accountByID = new Map(accounts.map(a => [a.id,a]));
      const exposures = new Map();
      for (const p of rows) {
        const key = JSON.stringify([String(p.accountId ?? p.account_id), p.symbol]);
        const size = number(p.quantity);
        const signed = p.side === 'long' ? size : p.side === 'short' ? -size : NaN;
        exposures.set(key, (exposures.get(key) ?? 0) + signed);
      }
      const positions = rows.map(p => {
        const accountId = String(p.accountId ?? p.account_id);
        if (!ids.has(accountId)) {
          ids.add(accountId);
          accounts.push({id:accountId,label:'…'+accountId.slice(-6)});
        }
        const size = number(p.quantity), entry = number(p.openPrice);
        const ticker = tickerBySymbol.get(p.symbol);
        // Vest's position P&L uses the trading quote rather than the margin quote.
        const currentPrice = number(ticker?.markPrice);
        const marginMark = number(ticker?.marginMarkPrice) || currentPrice;
        const side = String(p.side);
        const pnl = currentPrice > 0 && entry > 0 && (side === 'long' || side === 'short')
          ? (currentPrice-entry)*size*(side === 'long' ? 1 : -1) : null;
        const room = accountByID.get(accountId)?.room;
        const exposure = exposures.get(JSON.stringify([accountId,p.symbol]));
        const estimated = room > 0 && marginMark > 0 && Math.abs(exposure) > 1e-12 ? marginMark-room/exposure : null;
        const fail = number(p.failPrice ?? p.fail_price);
        return {id:String(p.positionId),accountId,market:p.symbol,side,entry,current:currentPrice > 0 ? currentPrice : null,pnl,
          fail:fail > 0 ? fail : estimated > 0 ? estimated : null,failEstimated:!(fail > 0)};
      });
      if (session === current) report({state:'live',at:quoteAt,accounts,positions});
    } catch (error) {
      if (session === current) report({state:error.message === '401' ? 'reconnecting' : 'error',at:Date.now()});
    } finally {
      busy = false;
    }
  }
  window.addEventListener('vest-silo-refresh', () => { void refresh(); });
})();
