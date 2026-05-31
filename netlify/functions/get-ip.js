exports.handler = async (event) => {
  const h = event.headers;

  // Avec Cloudflare : cf-connecting-ip = IP réelle du client (toujours)
  // Sans Cloudflare : x-nf-client-connection-ip (Netlify natif)
  // Fallback : premier X-Forwarded-For
  const ip = (
    h['cf-connecting-ip'] ||
    h['x-nf-client-connection-ip'] ||
    (h['x-forwarded-for'] || '').split(',')[0].trim() ||
    'unknown'
  ).trim();

  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    },
    body: JSON.stringify({ ip })
  };
};
