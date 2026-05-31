exports.handler = async (event) => {
  const h = event.headers;

  // Cloudflare envoie CF-Connecting-IP (IP réelle du client)
  // On préfère IPv4 — si IPv6, on cherche une IPv4 dans X-Forwarded-For
  const cfIP = h['cf-connecting-ip'] || '';
  const forwarded = (h['x-forwarded-for'] || '').split(',').map(s => s.trim());
  const clientIP = h['client-ip'] || '';
  const realIP = h['x-real-ip'] || '';

  // Fonction pour détecter IPv4
  function isIPv4(ip) {
    return /^\d{1,3}(\.\d{1,3}){3}$/.test(ip);
  }

  // Priorité : IPv4 en premier
  let ip = '';

  // 1. CF-Connecting-IP (le plus fiable avec Cloudflare)
  if (cfIP) {
    ip = cfIP;
  }
  // 2. Chercher IPv4 dans X-Forwarded-For
  if (!isIPv4(ip)) {
    const ipv4 = forwarded.find(isIPv4);
    if (ipv4) ip = ipv4;
  }
  // 3. Fallback sur toute adresse disponible
  if (!ip) {
    ip = forwarded[0] || clientIP || realIP || 'unknown';
  }

  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    },
    body: JSON.stringify({ ip: ip.trim() || 'unknown' })
  };
};
