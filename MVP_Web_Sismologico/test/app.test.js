'use strict';
const assert=require('node:assert/strict');
const test=require('node:test');
const fs=require('node:fs');
const path=require('node:path');
const {createApp}=require('../server/app');
const {QUERY_SQL}=require('../server/queries');

function createMockPool(){
  const calls=[];
  const client={
    query:async sql=>{
      calls.push(sql);
      if(sql.includes('current_database()')&&sql.includes('server_version'))return {rows:[{database:'bd_sismologico_exp_1000000',version:'18.6'}]};
      if(sql.includes('SELECT current_database()'))return {rows:[{database:'bd_sismologico_exp_1000000'}]};
      if(sql.includes('UNION ALL SELECT'))return {rows:[{tabla:'estacion_sismica',cantidad:100},{tabla:'sensor',cantidad:300},{tabla:'evento_sismico',cantidad:120000},{tabla:'lectura_onda',cantidad:875000},{tabla:'deteccion',cantidad:3500},{tabla:'alerta',cantidad:1100}]};
      if(sql.includes('AS eventos_igp'))return {rows:[{eventos_igp:24289,eventos_simulados:95711}]};
      if(Object.values(QUERY_SQL).includes(sql))return {rows:[{anio_utc:2025,cantidad_eventos:10}],rowCount:1,fields:[{name:'anio_utc'},{name:'cantidad_eventos'}]};
      return {rows:[],rowCount:0,fields:[]};
    },
    release:()=>{calls.push('RELEASE');}
  };
  return {connect:async()=>client,calls};
}
const read=(p)=>fs.readFileSync(path.resolve(__dirname,p),'utf8');

test('las cinco consultas del MVP coinciden con el archivo oficial del proyecto',()=>{
  // Este test contrasta las consultas con una copia fuente guardada en el MVP.
  const canonical=read('../SQL_ORIGINAL_15_consultas_5_1.sql');
  const parts=canonical.split(/\\echo\s*\n\\echo\s+CONSULTA\s+\d+\.[^\n]*\n/).slice(1);
  assert.equal(parts.length,5);
  for(let i=0;i<5;i++){
    const cleaned=parts[i].split('\n').filter(line=>!line.trim().startsWith('--')).join('\n').trim();
    assert.equal(QUERY_SQL['C'+(i+1)],cleaned);
  }
  assert.match(QUERY_SQL.C4,/810000001 AND 810000008/);
  assert.doesNotMatch(QUERY_SQL.C4,/8100000001/);
});

test('API: resumen, consultas en solo lectura, y rutas restringidas',async t=>{
  const pool=createMockPool();const server=createApp({pool,logger:{error:()=>{}}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const base=`http://127.0.0.1:${server.address().port}`;
  const health=await (await fetch(base+'/api/health')).json();assert.equal(health.ok,true);
  assert.equal(health.database,'bd_sismologico_exp_1000000');
  const overview=await (await fetch(base+'/api/overview')).json();assert.equal(overview.total,1000000);
  for(let n=1;n<=5;n++){
    const res=await fetch(base+'/api/queries/C'+n);
    assert.equal(res.status,200);
    const payload=await res.json();assert.equal(payload.query.id,'C'+n);assert.equal(payload.count,1);
  }
  assert.equal((await fetch(base+'/api/queries/C6')).status,404);
  assert.equal((await fetch(base+'/api/queries/C1',{method:'POST'})).status,405);
  assert.equal((await fetch(base+'/%2e%2e/server.js')).status,404);
  assert.equal((await fetch(base+'/styles.css')).status,200);
  const begins=pool.calls.filter(sql=>sql==='BEGIN READ ONLY').length;
  const rollbacks=pool.calls.filter(sql=>sql==='ROLLBACK').length;
  assert.equal(begins,7);assert.equal(rollbacks,7);
});
