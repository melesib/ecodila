exports.handler = async (event) => {
  const ip = (event.headers['x-forwarded-for'] || event.headers['client-ip'] || event.headers['x-real-ip'] || '').split(',')[0].trim();
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    },
    body: JSON.stringify({ ip: ip || 'unknown' })
  };
};
