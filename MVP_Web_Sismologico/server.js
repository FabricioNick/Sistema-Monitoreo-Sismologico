'use strict';
const path = require('node:path');
const fs = require('node:fs');
const { Pool, types } = require('pg');
// Preserva TIMESTAMP WITHOUT TIME ZONE tal como figura en PostgreSQL.
types.setTypeParser(1114, value => value);
const { createApp } = require('./server/app');

const envPath=path.join(__dirname,'.env');
if (fs.existsSync(envPath)) process.loadEnvFile(envPath);
const port=Number(process.env.MVP_PORT || 3000);
const pool=new Pool({
  host:process.env.PGHOST || '127.0.0.1',
  port:Number(process.env.PGPORT || 5432),
  user:process.env.PGUSER || 'postgres',
  password:process.env.PGPASSWORD || '',
  database:process.env.PGDATABASE || 'bd_sismologico_exp_1000000',
  max:4,
  connectionTimeoutMillis:6000,
  idleTimeoutMillis:15000
});
const app=createApp({pool});
app.listen(port,'127.0.0.1',()=>{
  console.log(`MVP Sismológico: http://127.0.0.1:${port}`);
  console.log(`Base configurada: ${process.env.PGDATABASE || 'bd_sismologico_exp_1000000'}`);
  console.log('La aplicación solo ejecuta consultas SELECT en transacciones READ ONLY.');
});
async function shutdown(){ app.close(); await pool.end(); }
process.once('SIGINT',()=>shutdown().finally(()=>process.exit(0)));
process.once('SIGTERM',()=>shutdown().finally(()=>process.exit(0)));
