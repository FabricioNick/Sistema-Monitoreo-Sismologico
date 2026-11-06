'use strict';
const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const { performance } = require('node:perf_hooks');
const { QUERIES, QUERY_SQL } = require('./queries');

const PUBLIC = path.resolve(__dirname, '../public');
const MIME = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.ico':'image/x-icon'};
const COUNTS_SQL = `SELECT 'estacion_sismica' AS tabla, COUNT(*)::integer AS cantidad FROM estacion_sismica
UNION ALL SELECT 'sensor', COUNT(*)::integer FROM sensor
UNION ALL SELECT 'evento_sismico', COUNT(*)::integer FROM evento_sismico
UNION ALL SELECT 'lectura_onda', COUNT(*)::integer FROM lectura_onda
UNION ALL SELECT 'deteccion', COUNT(*)::integer FROM deteccion
UNION ALL SELECT 'alerta', COUNT(*)::integer FROM alerta`;
const PROVENANCE_SQL = `SELECT COUNT(*) FILTER (WHERE id_evento BETWEEN 200000000 AND 299999999)::integer AS eventos_igp,
COUNT(*) FILTER (WHERE id_evento NOT BETWEEN 200000000 AND 299999999)::integer AS eventos_simulados
FROM evento_sismico`;

function json(res, status, payload) {
  res.writeHead(status, {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(JSON.stringify(payload));
}
async function readonly(pool, callback) {
  const client = await pool.connect();
  let transaction = false;
  try {
    await client.query('BEGIN READ ONLY'); transaction = true;
    await client.query("SET LOCAL statement_timeout = '30000ms'");
    await client.query('SET LOCAL search_path TO monitoreo_sismologico, public');
    return await callback(client);
  } finally {
    if (transaction) { try { await client.query('ROLLBACK'); } catch (err) { console.error('Rollback:', err.message); } }
    client.release();
  }
}
function createApp({pool, logger = console} = {}) {
  if (!pool) throw new Error('Se requiere un pool PostgreSQL.');
  return http.createServer(async (req, res) => {
    const url = new URL(req.url || '/', 'http://localhost');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'");
    if (req.method !== 'GET') { json(res,405,{error:'Solo se permiten solicitudes GET.'}); return; }
    try {
      if (url.pathname === '/api/queries') { json(res,200,{queries:Object.values(QUERIES)}); return; }
      if (url.pathname === '/api/health') {
        const data = await readonly(pool, async client => {
          const result = await client.query('SELECT current_database() AS database, current_setting(\'server_version\') AS version');
          return result.rows[0];
        });
        json(res,200,{ok:true,...data,mode:'solo_lectura'}); return;
      }
      if (url.pathname === '/api/overview') {
        const data = await readonly(pool,async client => {
          const info = await client.query('SELECT current_database() AS database');
          const counts = await client.query(COUNTS_SQL);
          const source = await client.query(PROVENANCE_SQL);
          return {database:info.rows[0].database,counts:counts.rows,total:counts.rows.reduce((s,r)=>s+Number(r.cantidad),0),provenance:source.rows[0]};
        });
        json(res,200,data); return;
      }
      const match = /^\/api\/queries\/(C[1-5])$/.exec(url.pathname);
      if (match) {
        const id=match[1]; const start=performance.now();
        const result = await readonly(pool,client=>client.query(QUERY_SQL[id]));
        json(res,200,{query:QUERIES[id],columns:result.fields.map(f=>f.name),rows:result.rows,count:result.rowCount,duration_ms:Math.round((performance.now()-start)*100)/100});
        return;
      }
      if (url.pathname.startsWith('/api/')) { json(res,404,{error:'Endpoint no encontrado.'}); return; }
      const allowed = new Set(['/','/index.html','/styles.css','/app.js','/favicon.svg']);
      if (!allowed.has(url.pathname)) { json(res,404,{error:'Recurso no encontrado.'}); return; }
      const file = url.pathname === '/' ? '/index.html' : url.pathname;
      const body = await fs.readFile(path.join(PUBLIC,file));
      res.writeHead(200, {'Content-Type':MIME[path.extname(file)] || 'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
      res.end(body);
    } catch (err) {
      logger.error?.('[MVP]',url.pathname,err.message);
      json(res,503,{error:'No fue posible completar la consulta. Comprueba que PostgreSQL esté encendido y revisa la configuración .env.'});
    }
  });
}
module.exports = {createApp,readonly,COUNTS_SQL};
