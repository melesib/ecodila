/**
 * ════════════════════════════════════════════════════════════════════
 * EcoDila — Back-Office Gate (Edge Function)
 * ════════════════════════════════════════════════════════════════════
 *
 * Protection serveur AVANT que le HTML ne soit servi par le CDN.
 *
 * Stratégie par route :
 *
 *   /admin, /admin.html      → HTTP Basic Auth (interne uniquement)
 *                              env vars : ADMIN_AUTH_USER + ADMIN_AUTH_PASS
 *
 *   /auditaz, /auditaz.html  → HTTP Basic Auth (interne uniquement)
 *                              env vars : AUDITAZ_AUTH_USER + AUDITAZ_AUTH_PASS
 *
 *   /parrain, /parrain.html  → Filtrage User-Agent (bots/scrapers/IA bloqués)
 *                              Pas d'auth car parrains externes se connectent
 *                              côté client via Supabase. Cette gate bloque
 *                              uniquement les crawlers/scrapers/IA.
 *
 * Configuration Netlify :
 *   Site settings → Environment variables → ajouter :
 *     ADMIN_AUTH_USER     = (login admin)
 *     ADMIN_AUTH_PASS     = (mot de passe fort)
 *     AUDITAZ_AUTH_USER   = (login auditaz, peut être différent)
 *     AUDITAZ_AUTH_PASS   = (mot de passe fort)
 *
 * Si les variables ne sont pas configurées → page d'erreur 503 explicite
 * (fail-closed : impossible d'oublier la config).
 *
 * ⚠️ Cette gate est la PREMIÈRE ligne de défense serveur. Elle complète :
 *   - le robots.txt / ai.txt (signaling pour bots respectueux)
 *   - les meta tags noindex/noai (signaling moteurs)
 *   - l'auth client-side Supabase (logique métier, RLS)
 *
 * © 2026 EcoDila. Tous droits réservés.
 * ════════════════════════════════════════════════════════════════════
 */

// ─── Bots/scrapers/IA à bloquer (substring match insensible à la casse) ─────
const BLOCKED_UA = [
  // IA / LLM training crawlers
  "gptbot", "chatgpt-user", "oai-searchbot",
  "claudebot", "claude-web", "anthropic-ai", "claude-searchbot", "claude-user",
  "google-extended", "googleother",
  "perplexitybot", "perplexity-user",
  "ccbot",
  "bytespider",
  "applebot-extended",
  "facebookbot", "meta-externalagent", "meta-externalfetcher",
  "cohere-ai", "cohere-training-data-crawler",
  "ai2bot",
  "diffbot",
  "amazonbot",
  "duckassistbot",
  "omgilibot", "omgili",
  "timpibot",
  "webzio-extended",
  "imagesiftbot",
  "pangubot",
  "icc-crawler",
  // Crawlers IA récents (2025-2026)
  "mistralai-user", "magpie-crawler",
  "youbot", "phindbot",
  "kagibot",
  "scoop.it",

  // SEO / data-mining commerciaux
  "ahrefsbot", "semrushbot", "mj12bot", "dotbot", "blexbot",
  "seekportbot", "serpstatbot", "siteauditbot", "backlinkcrawler",
  "petalbot", "awariobot",
  "barkrowler",

  // Outils de scraping génériques (UA par défaut des libs)
  "scrapy",
  "python-requests", "python-urllib", "aiohttp",
  "curl/", "wget/", "libwww-perl",
  "go-http-client", "okhttp", "java/", "apache-httpclient",
  "node-fetch", "axios/",
  "headlesschrome", "phantomjs", "puppeteer", "playwright",
  "selenium", "webdriver",

  // Outils pentest / reconnaissance (à bannir agressivement)
  "sqlmap", "nikto", "nmap", "masscan",
  "dirb", "dirbuster", "gobuster", "ffuf", "wfuzz",
  "burp", "burpsuite", "acunetix", "nessus", "qualys",
  "wpscan", "joomscan", "drupalscan",
  "metasploit", "shodan",
  "zgrab", "zoomeye", "censys",
  "morfeus", "fimap",
  "havij",
];

// ─── Réponse 401 / 403 standardisées ────────────────────────────────────────
function unauthorized(realm) {
  return new Response(
    "🔒 Accès restreint — authentification requise.\n\nCe back-office EcoDila est strictement réservé aux personnes autorisées.\nToute tentative d'accès non autorisée est tracée et peut faire l'objet de poursuites.\n\n© 2026 EcoDila",
    {
      status: 401,
      headers: {
        "WWW-Authenticate": `Basic realm="${realm}", charset="UTF-8"`,
        "Content-Type": "text/plain; charset=utf-8",
        "X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet, noai, noimageai",
        "Cache-Control": "no-store, no-cache, must-revalidate, private",
        "Pragma": "no-cache",
      },
    }
  );
}

function forbiddenBot() {
  return new Response("403 Forbidden — automated access is not permitted.\n\nSee /LICENSE.txt and /ai.txt for usage policy.\n\n© 2026 EcoDila", {
    status: 403,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet, noai, noimageai",
      "Cache-Control": "no-store, no-cache, must-revalidate, private",
    },
  });
}

function configRequiredPage(envPrefix) {
  return new Response(
    `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><meta name="robots" content="noindex,nofollow"><title>Configuration requise — EcoDila</title>
<style>body{font-family:system-ui,-apple-system,Segoe UI,sans-serif;max-width:680px;margin:60px auto;padding:0 24px;line-height:1.6;color:#1a1a1a;background:#fafafa}h1{color:#d63031;margin-top:0}code{background:#f0f0f0;padding:3px 8px;border-radius:4px;font-family:ui-monospace,monospace;font-size:.9em}.box{background:#fff;border:1px solid #e5e5e5;border-radius:12px;padding:24px;margin:20px 0;box-shadow:0 1px 3px rgba(0,0,0,.04)}ol li{margin:8px 0}</style>
</head><body>
<h1>🔒 Configuration sécurité requise</h1>
<div class="box">
<p>L'accès à cette page est protégé par authentification serveur, mais les <strong>variables d'environnement ne sont pas configurées</strong>.</p>
<p>Pour activer la protection :</p>
<ol>
<li>Aller sur <strong>Netlify → Site settings → Environment variables</strong></li>
<li>Ajouter ces deux variables :
  <ul>
    <li><code>${envPrefix}_AUTH_USER</code> = nom d'utilisateur</li>
    <li><code>${envPrefix}_AUTH_PASS</code> = mot de passe fort</li>
  </ul>
</li>
<li>Redéployer le site (Deploys → Trigger deploy → Deploy site)</li>
</ol>
</div>
<p style="color:#666;font-size:.85rem;text-align:center;margin-top:40px">© 2026 EcoDila — Tous droits réservés</p>
</body></html>`,
    {
      status: 503,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "X-Robots-Tag": "noindex, nofollow, noarchive, noai, noimageai",
        "Cache-Control": "no-store, no-cache, must-revalidate, private",
      },
    }
  );
}

// ─── Vérification HTTP Basic Auth ───────────────────────────────────────────
async function checkBasicAuth(req, envUser, envPass) {
  const auth = req.headers.get("authorization") || "";
  if (!auth.toLowerCase().startsWith("basic ")) return false;
  try {
    const decoded = atob(auth.slice(6));
    const idx = decoded.indexOf(":");
    if (idx < 0) return false;
    const user = decoded.slice(0, idx);
    const pass = decoded.slice(idx + 1);
    // Comparaison constante-temps pour éviter timing attacks
    return safeEquals(user, envUser) && safeEquals(pass, envPass);
  } catch (e) {
    return false;
  }
}

function safeEquals(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// ─── Filtre User-Agent (pour /parrain.html) ─────────────────────────────────
function isBlockedBot(req) {
  const ua = (req.headers.get("user-agent") || "").toLowerCase();
  // UA absent ou trop court → suspect
  if (!ua || ua.length < 10) return true;
  for (const bot of BLOCKED_UA) {
    if (ua.includes(bot)) return true;
  }
  return false;
}

// ─── Handler principal ──────────────────────────────────────────────────────
export default async function handler(req, context) {
  const url = new URL(req.url);
  const path = url.pathname.toLowerCase();

  // ── /admin → Basic Auth ──
  if (path === "/admin" || path === "/admin/" || path === "/admin.html") {
    // Defense in depth : bloquer aussi les outils pentest avant même d'évaluer l'auth
    if (isBlockedBot(req)) return forbiddenBot();

    const u = Netlify.env.get("ADMIN_AUTH_USER");
    const p = Netlify.env.get("ADMIN_AUTH_PASS");
    if (!u || !p) return configRequiredPage("ADMIN");
    const ok = await checkBasicAuth(req, u, p);
    if (!ok) {
      // Anti-brute-force : délai 1s sur chaque échec → slowdown attaquant
      // (5 essais = 5s, 60 essais = 1 min, dissuasif sans bloquer les humains)
      await new Promise(function(r) { setTimeout(r, 1000); });
      return unauthorized("EcoDila Back Office Administration");
    }
    // Auth OK → laisser passer
    const res = await context.next();
    return addNoCache(res);
  }

  // ── /auditaz → Basic Auth ──
  if (path === "/auditaz" || path === "/auditaz/" || path === "/auditaz.html") {
    // Defense in depth : bloquer aussi les outils pentest avant même d'évaluer l'auth
    if (isBlockedBot(req)) return forbiddenBot();

    const u = Netlify.env.get("AUDITAZ_AUTH_USER");
    const p = Netlify.env.get("AUDITAZ_AUTH_PASS");
    if (!u || !p) return configRequiredPage("AUDITAZ");
    const ok = await checkBasicAuth(req, u, p);
    if (!ok) {
      // Anti-brute-force : délai 1s sur chaque échec
      await new Promise(function(r) { setTimeout(r, 1000); });
      return unauthorized("EcoDila AUDITAZ Securite Audit");
    }
    const res = await context.next();
    return addNoCache(res);
  }

  // ── /parrain → filtrage bot/UA uniquement (pas d'auth, espace public) ──
  if (path === "/parrain" || path === "/parrain/" || path === "/parrain.html") {
    if (isBlockedBot(req)) return forbiddenBot();
    return; // laisser Netlify servir normalement
  }

  // Tout autre path → ne rien faire (la fonction n'est pas censée recevoir
  // d'autres routes vu sa config, mais on est défensif)
  return;
}

// Renforce les headers de cache sur les réponses authentifiées
function addNoCache(res) {
  try {
    const headers = new Headers(res.headers);
    headers.set("Cache-Control", "no-store, no-cache, must-revalidate, private");
    headers.set("Pragma", "no-cache");
    headers.set("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet, noimageindex, noai, noimageai");
    return new Response(res.body, { status: res.status, headers });
  } catch (e) {
    return res;
  }
}

export const config = {
  path: [
    "/admin",
    "/admin/",
    "/admin.html",
    "/auditaz",
    "/auditaz/",
    "/auditaz.html",
    "/parrain",
    "/parrain/",
    "/parrain.html",
  ],
};
