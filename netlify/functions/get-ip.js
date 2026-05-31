exports.handler = async (event) => {
  const h = event.headers;

  // Debug: log tous les headers disponibles
  const allHeaders = Object.keys(h).filter(k => 
    k.includes('ip') || k.includes('forward') || k.includes('client') || k.includes('cf-')
  );

  function isIPv4(ip) {
    return /^\d{1,3}(\.\d{1,3}){3}$/.test(ip);
  }
  function isCloudflareIP(ip) {
    return ip.startsWith('172.6') || ip.startsWith('104.1') || 
           ip.startsWith('103.') || ip.startsWith('198.41') ||
           ip.startsWith('162.158') || ip.startsWith('188.114') ||
           ip.startsWith('190.93') || ip.startsWith('197.234');
  }

  // Priorité headers pour IP réelle
  const candidates = [
    h['x-nf-client-connection-ip'],   // Netlify: IP réelle du client
    h['cf-connecting-ip'],             // Cloudflare: IP réelle
    h['true-client-ip'],               // Cloudflare Enterprise
    h['x-real-ip'],                    // Reverse proxy standard
    ...(h['x-forwarded-for'] || '').split(',').map(s => s.trim())
  ].filter(Boolean);

  // Préférer IPv4 non-Cloudflare
  let ip = candidates.find(ip => isIPv4(ip) && !isCloudflareIP(ip))
        || candidates.find(ip => !isCloudflareIP(ip))
        || candidates[0]
        || 'unknown';

  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    },
    body: JSON.stringify({ 
      ip: ip.trim(),
      debug_headers: allHeaders
    })
  };
};
