// ════════════════════════════════════════════════════════════════════
// EcoDila — claude-proxy.js (v83 — durci)
// ════════════════════════════════════════════════════════════════════
//
// Proxy CORS-friendly vers api.anthropic.com pour le module IA AUDITAZ.
//
// Modèle BYOK (Bring Your Own Key) : chaque utilisateur AUDITAZ saisit
// sa propre clé Anthropic. Le proxy n'en stocke aucune côté serveur.
//
// Protections en couches :
//   1. Whitelist d'origines (CORS strict — pas '*')
//   2. Validation format de clé API (sk-ant-...)
//   3. Limite taille du body (200 Ko max)
//   4. Cap max_tokens pour éviter les timeouts
//   5. Rate-limit IP (10 req/min, in-memory per instance)
//   6. Timeout 20s sur fetch Anthropic
//   7. Headers de sécurité ajoutés
//   8. Logs structurés (la clé n'est JAMAIS loggée)
//
// ════════════════════════════════════════════════════════════════════

// ── Configuration ──
var ALLOWED_ORIGINS = [
  'https://ecodila.com',
  'https://www.ecodila.com',
  'https://ecodila.netlify.app',
  // Pour dev local uniquement :
  'http://localhost:8080',
  'http://localhost:8888',
  'http://127.0.0.1:8080',
  'http://127.0.0.1:8888'
];

var RATE_WINDOW = 60000;          // 1 minute
var RATE_MAX = 10;                // 10 requêtes / minute / IP
var MAX_BODY_BYTES = 200 * 1024;  // 200 Ko max
var MAX_TOKENS_CAP = 2048;        // Cap dur sur max_tokens
var FETCH_TIMEOUT_MS = 20000;     // 20s timeout
var DEFAULT_MODEL = 'claude-sonnet-4-20250514';

// ── Rate limiting (in-memory, par instance Lambda) ──
var _rateStore = {};

function _getClientIp(event) {
  var raw = event.headers['x-forwarded-for']
         || event.headers['client-ip']
         || event.headers['x-real-ip']
         || 'unknown';
  return String(raw).split(',')[0].trim();
}

function _checkRate(ip) {
  var now = Date.now();
  if (!_rateStore[ip]) _rateStore[ip] = [];
  _rateStore[ip] = _rateStore[ip].filter(function(t) { return now - t < RATE_WINDOW; });
  if (_rateStore[ip].length >= RATE_MAX) return false;
  _rateStore[ip].push(now);
  return true;
}

function _getCorsOrigin(event) {
  var origin = event.headers['origin'] || event.headers['Origin'] || '';
  if (ALLOWED_ORIGINS.indexOf(origin) >= 0) return origin;
  return ALLOWED_ORIGINS[0];
}

function _buildHeaders(event, extra) {
  var origin = _getCorsOrigin(event);
  var h = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'Content-Type, x-api-key, anthropic-version',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '600',
    'Vary': 'Origin',
    'Content-Type': 'application/json',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer'
  };
  if (extra) {
    for (var k in extra) { if (Object.prototype.hasOwnProperty.call(extra, k)) h[k] = extra[k]; }
  }
  return h;
}

function _safeError(msg, statusCode, headers) {
  return {
    statusCode: statusCode || 500,
    headers: headers,
    body: JSON.stringify({ error: msg })
  };
}

// Logging structuré. IMPORTANT : ne JAMAIS logger la clé API ou le body.
function _log(level, event, fields) {
  try {
    var payload = {
      ts: new Date().toISOString(),
      level: level,
      ip: _getClientIp(event),
      ua: (event.headers['user-agent'] || '').substring(0, 80),
      origin: event.headers['origin'] || event.headers['Origin'] || ''
    };
    if (fields) {
      for (var k in fields) { if (Object.prototype.hasOwnProperty.call(fields, k)) payload[k] = fields[k]; }
    }
    console.log('[claude-proxy]', JSON.stringify(payload));
  } catch (e) { /* swallow */ }
}

// ════════════════════════════════════════════════════════════════════

exports.handler = async function(event) {
  var headers = _buildHeaders(event);
  var clientIp = _getClientIp(event);

  // 1. CORS preflight
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: headers, body: '' };
  }

  // 2. Méthode HTTP
  if (event.httpMethod !== 'POST') {
    _log('warn', event, { reason: 'method_not_allowed', method: event.httpMethod });
    return _safeError('Method not allowed', 405, headers);
  }

  // 3. Origin check (defense in depth)
  var origin = event.headers['origin'] || event.headers['Origin'] || '';
  if (origin && ALLOWED_ORIGINS.indexOf(origin) < 0) {
    _log('warn', event, { reason: 'origin_forbidden', origin: origin });
    return _safeError('Origin not allowed', 403, headers);
  }

  // 4. Taille du body
  var bodyStr = event.body || '';
  if (bodyStr.length > MAX_BODY_BYTES) {
    _log('warn', event, { reason: 'body_too_large', size: bodyStr.length });
    return _safeError('Payload trop grand (max 200 Ko)', 413, headers);
  }

  // 5. Rate limit IP
  if (!_checkRate(clientIp)) {
    _log('warn', event, { reason: 'rate_limit' });
    var rlHeaders = _buildHeaders(event, {
      'X-RateLimit-Limit': String(RATE_MAX),
      'X-RateLimit-Remaining': '0',
      'X-RateLimit-Reset': String(Math.ceil((Date.now() + RATE_WINDOW) / 1000)),
      'Retry-After': '60'
    });
    return _safeError('Trop de requêtes. Réessayez dans 1 minute.', 429, rlHeaders);
  }

  // 6. Validation clé API
  var apiKey = event.headers['x-api-key'] || '';
  if (!apiKey) {
    return _safeError('API key required (header x-api-key)', 401, headers);
  }
  if (typeof apiKey !== 'string' || !apiKey.startsWith('sk-ant-') || apiKey.length < 20 || apiKey.length > 200) {
    _log('warn', event, { reason: 'apikey_invalid_format' });
    return _safeError('Invalid API key format', 401, headers);
  }

  // 7. Parsing + validation du body
  var reqBody;
  try {
    reqBody = JSON.parse(bodyStr);
  } catch (e) {
    return _safeError('Invalid JSON body', 400, headers);
  }
  if (!reqBody || typeof reqBody !== 'object' || Array.isArray(reqBody)) {
    return _safeError('Invalid request body', 400, headers);
  }

  // 8. Hardening des paramètres
  if (typeof reqBody.max_tokens !== 'number' || reqBody.max_tokens > MAX_TOKENS_CAP || reqBody.max_tokens <= 0) {
    reqBody.max_tokens = MAX_TOKENS_CAP;
  }
  if (typeof reqBody.model !== 'string' || reqBody.model.length === 0 || reqBody.model.length > 100) {
    reqBody.model = DEFAULT_MODEL;
  }
  var ALLOWED_MODELS_PREFIX = ['claude-sonnet', 'claude-opus', 'claude-haiku', 'claude-3'];
  var modelOk = ALLOWED_MODELS_PREFIX.some(function(p) { return reqBody.model.indexOf(p) === 0; });
  if (!modelOk) {
    reqBody.model = DEFAULT_MODEL;
  }
  if (!Array.isArray(reqBody.messages) || reqBody.messages.length === 0) {
    return _safeError('messages array required', 400, headers);
  }
  if (reqBody.messages.length > 50) {
    return _safeError('Trop de messages (max 50)', 400, headers);
  }

  // 9. Forward to Anthropic avec timeout
  var controller = new AbortController();
  var timer = setTimeout(function() { controller.abort(); }, FETCH_TIMEOUT_MS);

  try {
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

    _log('info', event, {
      reason: 'forwarded',
      model: reqBody.model,
      max_tokens: reqBody.max_tokens,
      anthropic_status: resp.status
    });

    var rlHeaders2 = _buildHeaders(event, {
      'X-RateLimit-Limit': String(RATE_MAX),
      'X-RateLimit-Remaining': String(Math.max(0, RATE_MAX - ((_rateStore[clientIp] || []).length))),
      'X-RateLimit-Reset': String(Math.ceil((Date.now() + RATE_WINDOW) / 1000))
    });
    return { statusCode: resp.status, headers: rlHeaders2, body: data };
  } catch (err) {
    clearTimeout(timer);
    var isTimeout = err && err.name === 'AbortError';
    _log('error', event, { reason: isTimeout ? 'timeout' : 'fetch_error', msg: String(err && err.message || err).substring(0, 200) });
    return _safeError(
      isTimeout
        ? 'Timeout — prompt trop long. Réessayez avec un message plus court.'
        : 'Proxy error',
      isTimeout ? 504 : 502,
      headers
    );
  }
};
