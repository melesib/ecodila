// ── Rate limiting (in-memory, per instance) ──
var _rateStore = {};
var RATE_WINDOW = 60000; // 1 minute
var RATE_MAX = 10; // 10 requests/min/IP

function _getClientIp(event) {
  return (event.headers['x-forwarded-for'] || event.headers['client-ip'] || event.headers['x-real-ip'] || 'unknown').split(',')[0].trim();
}

function _checkRate(ip) {
  var now = Date.now();
  if (!_rateStore[ip]) _rateStore[ip] = [];
  _rateStore[ip] = _rateStore[ip].filter(function(t) { return now - t < RATE_WINDOW; });
  if (_rateStore[ip].length >= RATE_MAX) return false;
  _rateStore[ip].push(now);
  return true;
}

exports.handler = async function(event) {
  var clientIp = _getClientIp(event);
  var remaining = RATE_MAX - ((_rateStore[clientIp] || []).length + 1);
  var headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, x-api-key, anthropic-version',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
    'X-RateLimit-Limit': String(RATE_MAX),
    'X-RateLimit-Remaining': String(Math.max(0, remaining)),
    'X-RateLimit-Reset': String(Math.ceil((Date.now() + RATE_WINDOW) / 1000))
  };

  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: headers, body: '' };
  }

  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers: headers, body: JSON.stringify({ error: 'Method not allowed' }) };
  }

  // Rate limit check
  if (!_checkRate(clientIp)) {
    return { statusCode: 429, headers: headers, body: JSON.stringify({ error: 'Trop de requêtes. Réessayez dans 1 minute.', retry_after: 60 }) };
  }

  try {
    var apiKey = event.headers['x-api-key'] || '';
    if (!apiKey) {
      return { statusCode: 401, headers: headers, body: JSON.stringify({ error: 'API key required' }) };
    }

    var reqBody;
    try { reqBody = JSON.parse(event.body); } catch(e) { reqBody = {}; }
    
    // Cap max_tokens pour éviter les réponses trop longues → timeout
    if (!reqBody.max_tokens || reqBody.max_tokens > 2048) {
      reqBody.max_tokens = 2048;
    }
    if (!reqBody.model) {
      reqBody.model = 'claude-sonnet-4-20250514';
    }

    // Timeout 20s (Netlify Pro = 26s max)
    var controller = new AbortController();
    var timer = setTimeout(function() { controller.abort(); }, 20000);

    var resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify(reqBody),
      signal: controller.signal
    });

    clearTimeout(timer);
    var data = await resp.text();
    return { statusCode: resp.status, headers: headers, body: data };
  } catch(err) {
    var isTimeout = err.name === 'AbortError';
    return {
      statusCode: isTimeout ? 504 : 500,
      headers: headers,
      body: JSON.stringify({ 
        error: isTimeout 
          ? 'Timeout — prompt trop long. Réessayez avec un message plus court.'
          : (err.message || 'Proxy error')
      })
    };
  }
};
