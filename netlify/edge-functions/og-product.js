/**
 * ════════════════════════════════════════════════════════════════
 * EcoDila — Open Graph dynamique pour produits
 * ════════════════════════════════════════════════════════════════
 *
 * Cette Edge Function intercepte les requêtes vers le site et :
 *
 *   1. Détecte si le visiteur est un BOT de scraping
 *      (WhatsApp, Facebook, Twitter/X, LinkedIn, Telegram, Slack,
 *       Discord, iMessage, Skype, Pinterest, etc.)
 *
 *   2. Si bot ET URL contient ?p=PRODUITID :
 *        - Fetch le produit depuis Supabase
 *        - Réécrit les meta tags <title>, og:title, og:description,
 *          og:image, og:url, twitter:* du HTML servi
 *        - Le bot voit alors un beau preview avec image + nom + prix
 *
 *   3. Si humain : laisse passer normalement
 *      → Le router JS côté client met à jour les meta dynamiquement
 *
 *   4. Idem pour les pages : ?page=parrainage etc.
 *
 * Performance : très rapide car la fonction tourne au niveau du CDN
 * (Deno runtime), pas sur un serveur Node distant.
 *
 * ════════════════════════════════════════════════════════════════
 */

// Configuration Supabase (URL publique + anon key suffisent en lecture)
const SUPABASE_URL = "https://ftvowlmrsgcaienvhojj.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dm93bG1yc2djYWllbnZob2pqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcxMTM2NjQsImV4cCI6MjA2MjY4OTY2NH0.1cd2i2SE3J0CjxV6dCxy8PkOeNhSvc8OwUGNcS2DxQQ";

// Liste des User-Agents de bots de scraping pour Open Graph
// (ordre non-important, on cherche un match "includes")
const BOT_USER_AGENTS = [
  // WhatsApp
  "WhatsApp",
  "whatsapp",

  // Facebook
  "facebookexternalhit",
  "Facebot",
  "Facebook",

  // Twitter / X
  "Twitterbot",

  // LinkedIn
  "LinkedInBot",

  // Telegram
  "TelegramBot",

  // Slack
  "Slackbot",
  "Slack-ImgProxy",

  // Discord
  "Discordbot",

  // iMessage / Apple
  "AppleBot",
  "Applebot",
  "iMessage",

  // Pinterest
  "Pinterest",
  "Pinterestbot",

  // Skype
  "SkypeUriPreview",

  // Reddit
  "redditbot",

  // Bots SEO Google/Bing (utile pour SEO)
  "Googlebot",
  "Bingbot",
  "DuckDuckBot",
  "YandexBot",
  "Baiduspider",

  // Generic preview bots
  "embedly",
  "quora link preview",
  "showyoubot",
  "outbrain",
  "vkShare",
  "W3C_Validator",
];

/**
 * Détecte si un User-Agent est un bot de scraping
 */
function isBot(userAgent) {
  if (!userAgent) return false;
  const ua = userAgent.toLowerCase();
  return BOT_USER_AGENTS.some(bot => ua.includes(bot.toLowerCase()));
}

/**
 * Échappe une string pour insertion sûre dans HTML attribute
 */
function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/**
 * Fetch un produit depuis Supabase
 */
async function fetchProduct(productId) {
  try {
    const url = `${SUPABASE_URL}/rest/v1/products?id=eq.${encodeURIComponent(productId)}&select=*`;
    const res = await fetch(url, {
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
      },
    });
    if (!res.ok) return null;
    const data = await res.json();
    return Array.isArray(data) && data.length > 0 ? data[0] : null;
  } catch (e) {
    console.error("[OG] fetchProduct error:", e);
    return null;
  }
}

/**
 * Construit les meta tags Open Graph pour un produit
 */
function buildProductMeta(product, baseUrl) {
  const brand = product.brand || "";
  const model = product.model || "";
  const nom = product.nom || `${brand} ${model}`.trim() || "Produit EcoDila";

  // Prix formaté
  let priceStr = "";
  if (product.prix) {
    priceStr = ` — ${Number(product.prix).toLocaleString("fr-FR")} FCFA`;
  }

  const title = `${nom}${priceStr} | EcoDila`;

  // Description riche
  const parts = [];
  parts.push(nom);
  if (priceStr) parts.push(`à ${priceStr.replace(" — ", "")}`);
  parts.push("sur EcoDila");
  if (product.qualite) parts.push(`— ${product.qualite}`);

  const specs = [];
  if (product.memory) {
    const memSplit = (product.memory || "").split("|RAM:");
    if (memSplit[0]) specs.push(memSplit[0]);
    if (memSplit[1]) specs.push(`${memSplit[1]} RAM`);
  }
  if (product.screen) specs.push(`écran ${product.screen}`);
  if (specs.length) parts.push(`(${specs.join(", ")})`);

  parts.push(". Marketplace d'appareils reconditionnés en Côte d'Ivoire. Garantie 3 mois, livraison Abidjan, paiement à la livraison.");

  const description = parts.join(" ").substring(0, 300);

  // Image
  let image = "";
  if (Array.isArray(product.photos) && product.photos.length > 0) {
    const main = product.photos.find(p => p && p.isMain) || product.photos[0];
    image = (main && (main.url || main)) || "";
  }
  if (!image && product.image) image = product.image;
  if (!image) image = `${baseUrl}/logo.png`;

  // Image absolue
  if (image && !image.startsWith("http") && !image.startsWith("data:")) {
    image = `${baseUrl}${image.startsWith("/") ? "" : "/"}${image}`;
  }

  // URL canonique
  const productUrl = `${baseUrl}/?p=${encodeURIComponent(product.id)}`;

  return {
    title,
    description,
    image,
    url: productUrl,
  };
}

/**
 * Meta tags pour les pages connues
 */
function buildPageMeta(pageName, baseUrl) {
  const titles = {
    parrainage: "Devenez parrain EcoDila — Gagnez 5 à 10% de commissions sur chaque vente",
    acheter: "Acheter un appareil reconditionné — EcoDila Côte d'Ivoire",
    troquer: "Troquer votre appareil — Estimation gratuite EcoDila",
    avis: "Avis clients EcoDila — Témoignages réels de la marketplace #1 en Côte d'Ivoire",
    termes: "Conditions Générales d'Utilisation — EcoDila",
    "retours-client": "Politique de Retours et Garantie — EcoDila",
    profil: "Mon espace — EcoDila",
  };
  const descs = {
    parrainage: "Rejoignez le programme parrainage EcoDila. Gagnez 5 à 10% de commission sur chaque vente. Inscription gratuite, paiement instantané.",
    acheter: "Achetez votre prochain smartphone, TV, ordinateur ou drone reconditionné sur EcoDila. Garantie 3 mois, livraison Abidjan, paiement à la livraison.",
    troquer: "Troquez votre ancien appareil contre un nouveau sur EcoDila. Estimation gratuite et instantanée.",
    avis: "Découvrez les avis et témoignages des clients d'EcoDila — la marketplace de confiance en Côte d'Ivoire.",
    termes: "Conditions Générales d'Utilisation d'EcoDila. Marketplace ivoirienne d'appareils électroniques reconditionnés.",
    "retours-client": "Politique de retours et garantie EcoDila — 3 mois de garantie sur tous les produits reconditionnés.",
    profil: "Gérez votre compte EcoDila — commandes, trocs, parrainage.",
  };
  return {
    title: titles[pageName] || titles.parrainage,
    description: descs[pageName] || descs.parrainage,
    image: `${baseUrl}/logo.png`,
    url: `${baseUrl}/?page=${encodeURIComponent(pageName)}`,
  };
}

/**
 * Réécrit les meta tags dans le HTML
 */
function injectMeta(html, meta) {
  const t = escapeHtml(meta.title);
  const d = escapeHtml(meta.description);
  const i = escapeHtml(meta.image);
  const u = escapeHtml(meta.url);

  // 1) Réécrire le <title>
  html = html.replace(
    /<title>[\s\S]*?<\/title>/,
    `<title>${t}</title>`
  );

  // 2) Réécrire ou injecter les meta description
  if (/<meta\s+name=["']description["']/i.test(html)) {
    html = html.replace(
      /<meta\s+name=["']description["']\s+content=["'][^"']*["']\s*\/?>/i,
      `<meta name="description" content="${d}">`
    );
  } else {
    html = html.replace(
      /<\/head>/i,
      `<meta name="description" content="${d}">\n</head>`
    );
  }

  // 3) Réécrire ou injecter Open Graph tags
  const ogTags = [
    `<meta property="og:type" content="product">`,
    `<meta property="og:title" content="${t}">`,
    `<meta property="og:description" content="${d}">`,
    `<meta property="og:image" content="${i}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta property="og:url" content="${u}">`,
    `<meta property="og:site_name" content="EcoDila">`,
    `<meta property="og:locale" content="fr_FR">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${t}">`,
    `<meta name="twitter:description" content="${d}">`,
    `<meta name="twitter:image" content="${i}">`,
  ];

  // Retirer les anciens og: et twitter: existants
  html = html.replace(/<meta\s+property=["']og:[^"']+["'][^>]*>/gi, "");
  html = html.replace(/<meta\s+name=["']twitter:[^"']+["'][^>]*>/gi, "");

  // Réinjecter les nouveaux avant </head>
  html = html.replace(/<\/head>/i, ogTags.join("\n") + "\n</head>");

  // 4) Mettre à jour la canonical
  if (/<link\s+rel=["']canonical["']/i.test(html)) {
    html = html.replace(
      /<link\s+rel=["']canonical["']\s+href=["'][^"']*["']\s*\/?>/i,
      `<link rel="canonical" href="${u}">`
    );
  } else {
    html = html.replace(
      /<\/head>/i,
      `<link rel="canonical" href="${u}">\n</head>`
    );
  }

  return html;
}

/**
 * ════════════════════════════════════════════════════════════════
 * Handler principal de l'Edge Function
 * ════════════════════════════════════════════════════════════════
 */
export default async (request, context) => {
  const url = new URL(request.url);
  const userAgent = request.headers.get("user-agent") || "";

  // Si pas un bot → laisser passer normalement
  if (!isBot(userAgent)) {
    return context.next();
  }

  // Vérifier si l'URL contient un paramètre p= ou page=
  const productId = url.searchParams.get("p");
  const pageName = url.searchParams.get("page");

  // Pas de paramètre intéressant → laisser passer
  if (!productId && !pageName) {
    return context.next();
  }

  // Récupérer le HTML normal
  const response = await context.next();
  let html;
  try {
    html = await response.text();
  } catch (e) {
    return response;
  }

  const baseUrl = `${url.protocol}//${url.host}`;
  let meta = null;

  // Cas 1 : Produit
  if (productId) {
    const product = await fetchProduct(productId);
    if (product) {
      meta = buildProductMeta(product, baseUrl);
    }
  }
  // Cas 2 : Page
  else if (pageName) {
    meta = buildPageMeta(pageName, baseUrl);
  }

  if (!meta) {
    // Pas de meta à injecter → renvoyer l'original
    return new Response(html, {
      status: response.status,
      headers: response.headers,
    });
  }

  // Injecter les meta tags
  html = injectMeta(html, meta);

  // Renvoyer le HTML modifié
  return new Response(html, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers),
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300, stale-while-revalidate=600",
      "x-edge-og": productId ? "product" : "page",
    },
  });
};

export const config = {
  // S'exécuter UNIQUEMENT sur la racine et index.html
  // (pas sur /admin, /parrain, /auditaz, ni sur les assets)
  path: ["/", "/index.html"],
};
