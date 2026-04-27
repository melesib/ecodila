/**
 * ════════════════════════════════════════════════════════════════
 * EcoDila — Image dynamique pour Open Graph
 * ════════════════════════════════════════════════════════════════
 *
 * Cette Edge Function sert les images de produits sous une URL
 * stable et publique, utilisable par les bots de scraping
 * (WhatsApp, Facebook, etc.) comme `og:image`.
 *
 * Problème résolu :
 *   - Les images uploadées dans le BO admin sont stockées en
 *     base64 (data:image/jpeg;base64,...) dans Supabase.
 *   - Les bots WhatsApp/Facebook NE PEUVENT PAS afficher
 *     d'images base64 dans leurs aperçus Open Graph.
 *   - Il leur faut une vraie URL HTTP qui retourne du binaire image.
 *
 * Solution :
 *   - Cette fonction intercepte les requêtes /og-image/PRODID(.jpg)
 *   - Lit le produit depuis Supabase
 *   - Décode l'image base64 et la renvoie en binaire
 *   - Cache CDN agressif (1 jour)
 *
 * Usage :
 *   /og-image/PROD1234567890     → image principale du produit
 *   /og-image/PROD1234567890.jpg → idem (extension optionnelle)
 *
 * ════════════════════════════════════════════════════════════════
 */

const SUPABASE_URL = "https://ftvowlmrsgcaienvhojj.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dm93bG1yc2djYWllbnZob2pqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcxMTM2NjQsImV4cCI6MjA2MjY4OTY2NH0.1cd2i2SE3J0CjxV6dCxy8PkOeNhSvc8OwUGNcS2DxQQ";

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
    console.error("[OG-IMG] fetchProduct error:", e);
    return null;
  }
}

/**
 * Décode une data URL en bytes binaires
 * Format attendu : data:image/jpeg;base64,XXXX
 */
function dataUrlToBytes(dataUrl) {
  try {
    const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
    if (!match) return null;
    const mime = match[1];
    const b64 = match[2];

    // atob() décode base64 en string ; on convertit en Uint8Array
    const binary = atob(b64);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return { bytes, mime };
  } catch (e) {
    console.error("[OG-IMG] dataUrlToBytes:", e);
    return null;
  }
}

/**
 * Récupère l'image principale d'un produit
 */
function getProductImage(product) {
  if (!product) return null;

  // Cas 1 : tableau photos
  if (Array.isArray(product.photos) && product.photos.length > 0) {
    const main = product.photos.find(p => p && p.isMain) || product.photos[0];
    if (main) {
      const url = main.url || main.dataUrl || main.image || main;
      if (typeof url === "string") return url;
    }
  }

  // Cas 2 : champ image direct
  if (product.image && typeof product.image === "string") return product.image;

  // Cas 3 : champ img direct
  if (product.img && typeof product.img === "string") return product.img;

  return null;
}

/**
 * Charge le logo en fallback (binaire)
 */
async function fetchLogoBinary(baseUrl) {
  try {
    const res = await fetch(`${baseUrl}/logo.png`);
    if (!res.ok) return null;
    const buf = await res.arrayBuffer();
    return { bytes: new Uint8Array(buf), mime: "image/png" };
  } catch (e) {
    return null;
  }
}

/**
 * ════════════════════════════════════════════════════════════════
 * Handler principal
 * ════════════════════════════════════════════════════════════════
 */
export default async (request, context) => {
  const url = new URL(request.url);

  // Extraire l'ID produit depuis le path : /og-image/PRODxxx ou /og-image/PRODxxx.jpg
  const match = url.pathname.match(/^\/og-image\/([^\/\.]+)(?:\.(?:jpg|jpeg|png|webp))?$/i);
  if (!match) {
    return new Response("Not found", { status: 404 });
  }

  const productId = match[1];
  const baseUrl = `${url.protocol}//${url.host}`;

  // Charger le produit
  const product = await fetchProduct(productId);

  let imageData = null;

  if (product) {
    const imgUrl = getProductImage(product);

    if (imgUrl) {
      // Cas A : image en data: URL → décoder
      if (imgUrl.startsWith("data:")) {
        imageData = dataUrlToBytes(imgUrl);
      }
      // Cas B : URL HTTP(S) → fetch et renvoyer
      else if (imgUrl.startsWith("http")) {
        try {
          const res = await fetch(imgUrl);
          if (res.ok) {
            const buf = await res.arrayBuffer();
            const ct = res.headers.get("content-type") || "image/jpeg";
            imageData = { bytes: new Uint8Array(buf), mime: ct };
          }
        } catch (e) {
          console.error("[OG-IMG] fetch external image error:", e);
        }
      }
    }
  }

  // Fallback : logo EcoDila
  if (!imageData) {
    imageData = await fetchLogoBinary(baseUrl);
  }

  // Si même le logo échoue, renvoyer 404
  if (!imageData) {
    return new Response("Image not available", { status: 404 });
  }

  return new Response(imageData.bytes, {
    status: 200,
    headers: {
      "content-type": imageData.mime,
      "content-length": String(imageData.bytes.length),
      // Cache 1 jour côté CDN, 1h navigateur
      "cache-control": "public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800",
      "x-edge-og-img": product ? "found" : "fallback",
    },
  });
};

export const config = {
  path: "/og-image/*",
};
