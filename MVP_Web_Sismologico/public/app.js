'use strict';

const queryMeta = [
  {id:'C1',name:'Actividad sísmica anual',description:'Sismos del IGP con magnitud ≥ 6 entre 2010 y 2025.',metric:'cantidad_eventos',axis:'anio_utc',icon:'i-chart'},
  {id:'C2',name:'Ventanas geográficas',description:'Eventos del IGP por ventana rectangular de ±1,5° alrededor de cada estación.',metric:'eventos_en_ventana',axis:'codigo_estacion',icon:'i-map'},
  {id:'C3',name:'Calidad de lecturas',description:'Lecturas válidas e inválidas por estación, agosto–noviembre de 2026.',metric:'porcentaje_invalidas',axis:'codigo_estacion',icon:'i-wave'},
  {id:'C4',name:'Primera detección y alerta',description:'Tiempo de respuesta de detecciones y alertas para eventos simulados.',metric:'total_detecciones',axis:'id_evento',icon:'i-clock'},
  {id:'C5',name:'Sensores sin detecciones',description:'Sensores con lecturas, pero sin detecciones en agosto de 2026.',metric:'lecturas_invalidas',axis:'numero_serie',icon:'i-radio'}
];
const $ = id => document.getElementById(id);
const state = {selected:'C1',columns:[],rows:[],filtered:[],sortCol:null,sortDesc:false,requestKey:0};
const fmt = new Intl.NumberFormat('es-PE');
const mobile = window.matchMedia('(max-width: 760px)');
const icon = name => `<svg class="icon" aria-hidden="true"><use href="#${name}"/></svg>`;

function text(id,value) { $(id).textContent=String(value); }
function format(value) {
  if (value===null || value===undefined) return '—';
  if (typeof value==='boolean') return value?'Sí':'No';
  if (typeof value==='number') return fmt.format(value);
  return String(value);
}
async function api(endpoint) {
  const res=await fetch(endpoint,{cache:'no-store'});
  const value=await res.json();
  if (!res.ok) throw Error(value.error||'Error de conexión');
  return value;
}
function showConnection(ok,detail) {
  const badge=$('dbIndicator');
  badge.classList.toggle('offline',!ok);
  badge.querySelector('span').textContent=ok?('Conectado · '+detail):'Sin conexión a PostgreSQL';
}

// La bienvenida se muestra en cada visita. El menú plegado se recuerda localmente.
function enterDashboard() {
  $('welcomeScreen').classList.add('is-hidden');
  document.body.classList.remove('welcome-active');
  $('sidebarToggle').focus({preventScroll:true});
}
function returnToWelcome() {
  closeMobileMenu();
  $('welcomeScreen').classList.remove('is-hidden');
  document.body.classList.add('welcome-active');
  $('enterDashboard').focus({preventScroll:true});
}
function isCollapsed() { return $('appShell').classList.contains('sidebar-collapsed'); }
function applySidebar(collapsed) {
  $('appShell').classList.toggle('sidebar-collapsed',collapsed);
  $('sidebarToggle').setAttribute('aria-label',collapsed?'Expandir menú lateral':'Contraer menú lateral');
  $('sidebarToggle').setAttribute('title',collapsed?'Expandir menú lateral':'Contraer menú lateral');
  $('sidebarToggle').setAttribute('aria-expanded',String(!collapsed));
  $('sidebarCollapse').setAttribute('aria-label',collapsed?'Expandir menú':'Contraer menú');
  $('sidebarCollapse').setAttribute('title',collapsed?'Expandir menú':'Contraer menú');
  const label=$('sidebarCollapse').querySelector('span');
  if(label) label.textContent=collapsed?'Expandir menú':'Contraer menú';
  try { localStorage.setItem('observatorioSidebarCollapsed',String(collapsed)); } catch (_) {}
}
function openMobileMenu() {
  $('appShell').classList.add('mobile-menu-open');
  $('sidebarToggle').setAttribute('aria-expanded','true');
  document.body.classList.add('mobile-menu-visible');
}
function closeMobileMenu() {
  $('appShell').classList.remove('mobile-menu-open');
  $('sidebarToggle').setAttribute('aria-expanded',String(!isCollapsed()));
  document.body.classList.remove('mobile-menu-visible');
}
function toggleSidebar() {
  if (mobile.matches) {
    $('appShell').classList.contains('mobile-menu-open')?closeMobileMenu():openMobileMenu();
    return;
  }
  applySidebar(!isCollapsed());
}
function setupUi() {
  $('enterDashboard').addEventListener('click',enterDashboard);
  $('goHome').addEventListener('click',returnToWelcome);
  $('sidebarToggle').addEventListener('click',toggleSidebar);
  $('sidebarCollapse').addEventListener('click',toggleSidebar);
  $('sidebarScrim').addEventListener('click',closeMobileMenu);
  document.addEventListener('keydown',event=>{
    if (event.key==='Escape' && $('appShell').classList.contains('mobile-menu-open')) closeMobileMenu();
  });
  mobile.addEventListener('change',()=>closeMobileMenu());
  let collapsed=false;
  try { collapsed=localStorage.getItem('observatorioSidebarCollapsed')==='true'; } catch (_) {}
  applySidebar(collapsed);
}

function setupNav() {
  const parent=$('queryNav');
  for(const q of queryMeta) {
    const button=document.createElement('button');
    button.type='button';
    button.dataset.id=q.id;
    button.title=`${q.id} · ${q.name}`;
    button.setAttribute('aria-label',`${q.id}: ${q.name}`);
    button.innerHTML=`<span class="nav-icon">${icon(q.icon)}</span><span class="nav-label">${q.name}</span><span class="nav-num">${q.id}</span>`;
    button.addEventListener('click',()=>{
      selectQuery(q.id);
      if(mobile.matches) closeMobileMenu();
    });
    parent.appendChild(button);
  }
}
function selectQuery(id) {
  state.requestKey++;
  state.selected=id;
  state.rows=[];state.filtered=[];state.columns=[];
  state.sortCol=null;state.sortDesc=false;
  const q=queryMeta.find(item=>item.id===id);
  text('breadcrumbTitle',q.name);
  text('queryCode','CONSULTA '+id);
  text('queryTitle',q.name);
  text('queryDescription',q.description);
  text('chartTitle',q.metric.replaceAll('_',' '));
  text('runStatus','Pendiente');
  $('runStatus').className='value';
  text('runRows','—');text('runTime','—');
  $('tableSearch').value='';
  $('downloadCsv').disabled=true;
  $('runButton').disabled=false;
  for(const button of document.querySelectorAll('#queryNav button')) {
    const active=button.dataset.id===id;
    button.classList.toggle('active',active);
    if(active) button.setAttribute('aria-current','page');
    else button.removeAttribute('aria-current');
  }
  showChartMessage('Ejecuta la consulta para cargar la visualización.');
  $('tableHead').replaceChildren();
  $('tableBody').replaceChildren();
  text('tableCount','0 filas');
}
async function loadOverview() {
  try {
    const health=await api('/api/health');
    showConnection(true,health.database);
    const overview=await api('/api/overview');
    text('databaseName',overview.database);
    text('metricTotal',fmt.format(overview.total));
    text('metricIGP',fmt.format(overview.provenance.eventos_igp));
    const map=Object.fromEntries(overview.counts.map(row=>[row.tabla,Number(row.cantidad)]));
    text('metricReadings',fmt.format(map.lectura_onda||0));
    text('metricSensors',fmt.format(map.sensor||0));
  } catch (err) {
    showConnection(false,'');
    text('databaseName','PostgreSQL no disponible');
    console.warn('Vista general:',err.message);
  }
}
function showChartMessage(message) {
  const holder=$('chart');
  holder.replaceChildren();
  const empty=document.createElement('div');empty.className='empty';
  empty.innerHTML=icon('i-chart');
  const label=document.createElement('span');label.textContent=message;
  empty.appendChild(label);holder.appendChild(empty);
}
function renderChart() {
  const q=queryMeta.find(item=>item.id===state.selected);
  const data=state.rows.slice(0,14);
  const holder=$('chart');holder.replaceChildren();
  const max=Math.max(1,...data.map(r=>Number(r[q.metric])||0));
  if(!data.length) { showChartMessage('No existen resultados para esta consulta.');return; }
  for(const row of data) {
    const value=Number(row[q.metric])||0;
    const line=document.createElement('div');line.className='barrow';
    const label=document.createElement('div');label.className='barlabel';
    label.textContent=format(row[q.axis]);label.title=String(row[q.axis]??'');
    const track=document.createElement('div');track.className='bartrack';
    const bar=document.createElement('div');bar.className='bar';
    bar.style.width=`${Math.max(value>0?2:0,100*value/max)}%`;
    track.appendChild(bar);
    const number=document.createElement('div');number.className='barvalue';number.textContent=fmt.format(value);
    line.append(label,track,number);holder.appendChild(line);
  }
}
function renderTable() {
  const needle=$('tableSearch').value.trim().toLocaleLowerCase('es');
  state.filtered=state.rows.filter(row=>!needle||state.columns.some(c=>String(row[c]??'').toLocaleLowerCase('es').includes(needle)));
  if(state.sortCol) {
    const field=state.sortCol;
    state.filtered.sort((a,b)=>{
      const x=a[field],y=b[field];
      if(x==null)return 1;if(y==null)return -1;
      const nx=Number(x),ny=Number(y);
      const v=String(x).trim()!==''&&String(y).trim()!==''&&Number.isFinite(nx)&&Number.isFinite(ny)?nx-ny:String(x).localeCompare(String(y),'es');
      return state.sortDesc?-v:v;
    });
  }
  const head=$('tableHead'),body=$('tableBody');
  head.replaceChildren();body.replaceChildren();
  if(state.columns.length) {
    const tr=document.createElement('tr');
    for(const column of state.columns) {
      const th=document.createElement('th'),button=document.createElement('button');
      button.type='button';button.textContent=column.replaceAll('_',' ')+(state.sortCol===column?(state.sortDesc?' ↓':' ↑'):'');
      button.title='Ordenar por '+column;
      button.addEventListener('click',()=>{state.sortDesc=state.sortCol===column?!state.sortDesc:false;state.sortCol=column;renderTable();});
      th.appendChild(button);tr.appendChild(th);
    }
    head.appendChild(tr);
  }
  for(const row of state.filtered) {
    const tr=document.createElement('tr');
    for(const column of state.columns) {
      const td=document.createElement('td');td.textContent=format(row[column]);tr.appendChild(td);
    }
    body.appendChild(tr);
  }
  if(!state.filtered.length) {
    const tr=document.createElement('tr'),td=document.createElement('td');
    td.colSpan=Math.max(state.columns.length,1);td.textContent='No hay filas para mostrar.';
    tr.appendChild(td);body.appendChild(tr);
  }
  text('tableCount',fmt.format(state.filtered.length)+(state.filtered.length===1?' fila':' filas'));
}
async function runQuery() {
  const id=state.selected,key=++state.requestKey;
  const button=$('runButton');button.disabled=true;
  text('runStatus','Ejecutando...');$('runStatus').className='value';
  try {
    const result=await api('/api/queries/'+id);
    if(state.selected!==id||state.requestKey!==key)return;
    state.rows=result.rows;state.columns=result.columns;state.sortCol=null;state.sortDesc=false;
    text('runRows',fmt.format(result.count));
    text('runTime',fmt.format(result.duration_ms)+' ms');
    text('runStatus','Completado');$('runStatus').className='value ready';
    $('downloadCsv').disabled=false;
    renderChart();renderTable();
  } catch(err) {
    if(state.selected!==id||state.requestKey!==key)return;
    text('runStatus','Error');$('runStatus').className='value failed';
    text('runTime','—');
    showChartMessage('No fue posible cargar los resultados.');
    $('tableHead').replaceChildren();$('tableBody').replaceChildren();
    const tr=document.createElement('tr'),td=document.createElement('td');td.textContent=err.message;
    tr.appendChild(td);$('tableBody').appendChild(tr);
  } finally {
    if(state.requestKey===key)button.disabled=false;
  }
}
function exportCsv() {
  if(!state.columns.length)return;
  const fields=state.columns;
  const csv=[fields.join(','),...state.filtered.map(row=>fields.map(field=>'"'+String(row[field]??'').replaceAll('"','""')+'"').join(','))].join('\r\n');
  const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'});
  const url=URL.createObjectURL(blob),link=document.createElement('a');
  link.href=url;link.download=`${state.selected}_resultados_mvp.csv`;link.click();
  setTimeout(()=>URL.revokeObjectURL(url),3000);
}

setupUi();
setupNav();
selectQuery('C1');
$('runButton').addEventListener('click',runQuery);
$('tableSearch').addEventListener('input',renderTable);
$('downloadCsv').addEventListener('click',exportCsv);
loadOverview().then(runQuery);
