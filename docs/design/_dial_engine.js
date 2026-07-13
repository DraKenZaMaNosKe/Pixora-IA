/* ============================================================
   Pixora · Dial Curvo — MOTOR COMPARTIDO (no modificar por skin)
   Contrato de DOM que cada skin DEBE proveer con estos IDs/clases:
     #phone   contenedor (recibe la clase .open al abrir)
     #screen  área de la pantalla (captura el drag)
     #wall    fondo del wallpaper (conserva la clase base "wall";
              el motor le pega .bgA..bgF para el preview en vivo)
     #capName #capKick  texto de la sección activa
     #fab     botón que abre el dial
     #scrim   capa que cierra al tocar fuera
     #dialWrap contenedor del dial (recibe visibilidad vía .open del #phone)
     #dial    el motor inyecta aquí los .opt
     #apply   botón aplicar (cierra confirmando)
   El motor crea cada opción como:
     <div class="opt"><div class="ic"><svg>…</svg></div>
       <div class="lb">Nombre<small>kicker</small></div></div>
   y le agrega .active (en la aguja) y .snap (transición al soltar).
   Geometría pensada para un teléfono de 340px de ancho.
============================================================ */
const SECTIONS = [
  {name:'Estáticos', kick:'Fondos fijos', bg:'bgA', ic:'<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 15l4-4 4 4 3-3 5 5"/>'},
  {name:'Live',      kick:'Video vivo',   bg:'bgB', ic:'<circle cx="12" cy="12" r="8"/><path d="M10 9l5 3-5 3z" fill="currentColor" stroke="none"/>'},
  {name:'3D',        kick:'Parallax',     bg:'bgD', ic:'<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z"/><path d="M12 3v18M4 7.5l8 4.5 8-4.5"/>'},
  {name:'Amor',      kick:'Para dos',     bg:'bgC', ic:'<path d="M12 20s-7-4.6-7-9a4 4 0 017-2.6A4 4 0 0119 11c0 4.4-7 9-7 9z"/>'},
  {name:'Cultura',   kick:'Arte & mito',  bg:'bgF', ic:'<circle cx="12" cy="12" r="4"/><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/>'},
  {name:'Eventos',   kick:'Temporada',    bg:'bgE', ic:'<path d="M12 3l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9 6.8 19.2l1-5.8L3.5 9.2l5.9-.9z"/>'},
  {name:'Arcano',    kick:'Místico',      bg:'bgF', ic:'<path d="M20 14a8 8 0 11-8-11 6 6 0 008 11z"/>'},
  {name:'Día',       kick:'Ciclo solar',  bg:'bgE', ic:'<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>'},
  {name:'AURA',      kick:'Bienestar',    bg:'bgB', ic:'<path d="M9 18V6l10-2v12"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="16" r="2"/>'},
  {name:'Favoritos', kick:'Tus guardados',bg:'bgD', ic:'<path d="M7 4h10v16l-5-3-5 3z"/>'},
];

(function(){
  const dial   = document.getElementById('dial');
  const screen = document.getElementById('screen');
  const phone  = document.getElementById('phone');
  const STEP = 25, CX = -70, R = 250;
  let rot = 0, activeIdx = 0;

  const els = SECTIONS.map((s,i)=>{
    const el = document.createElement('div');
    el.className='opt';
    el.innerHTML = `<div class="ic"><svg viewBox="0 0 24 24">${s.ic}</svg></div>
      <div class="lb">${s.name}<small>${s.kick}</small></div>`;
    el.addEventListener('click',(e)=>{ e.stopPropagation(); onOptClick(i); });
    dial.appendChild(el);
    return el;
  });

  function layout(){
    const cy = screen.clientHeight/2 + 8;
    els.forEach((el,i)=>{
      const ang = (i*STEP - rot), th = ang*Math.PI/180;
      const x = CX + R*Math.cos(th), y = cy + R*Math.sin(th);
      const d = Math.abs(ang);
      const scale = Math.max(.5, 1 - d/150);
      const op = d>78 ? 0 : Math.max(0, 1 - d/72);
      el.style.left = x+'px'; el.style.top = y+'px';
      el.style.transform = `translate(-6px,-50%) scale(${scale})`;
      el.style.opacity = op;
      el.style.pointerEvents = op<.15 ? 'none':'auto';
      el.classList.toggle('active', d < STEP/2);
    });
    const idx = Math.round(rot/STEP);
    if(idx!==activeIdx && idx>=0 && idx<SECTIONS.length){ activeIdx = idx; previewSection(idx); }
  }
  function previewSection(i){
    const s = SECTIONS[i];
    document.getElementById('wall').className = 'wall '+s.bg;
    document.getElementById('capName').textContent = s.name;
    document.getElementById('capKick').textContent = s.kick;
  }

  let dragging=false, lastY=0, moved=false;
  function down(e){
    if(!phone.classList.contains('open')) return;
    dragging=true; moved=false;
    lastY = (e.touches?e.touches[0].clientY:e.clientY);
    els.forEach(el=>el.classList.remove('snap'));
  }
  function move(e){
    if(!dragging) return;
    const y = (e.touches?e.touches[0].clientY:e.clientY);
    const dy = y-lastY; lastY=y;
    if(Math.abs(dy)>1) moved=true;
    rot += dy*0.42;
    rot = Math.max(-STEP*0.5, Math.min((SECTIONS.length-1)*STEP+STEP*0.5, rot));
    layout();
  }
  function up(){ if(!dragging) return; dragging=false; snapTo(Math.round(rot/STEP)); }
  function snapTo(idx){
    idx = Math.max(0, Math.min(SECTIONS.length-1, idx));
    els.forEach(el=>el.classList.add('snap'));
    rot = idx*STEP; layout();
  }
  function onOptClick(i){ if(i===activeIdx && !moved){ applyAndClose(); } else { snapTo(i); } }

  screen.addEventListener('pointerdown',down);
  window.addEventListener('pointermove',move);
  window.addEventListener('pointerup',up);

  const fab=document.getElementById('fab');
  const scrim=document.getElementById('scrim');
  const apply=document.getElementById('apply');
  fab.addEventListener('click',()=>{ phone.classList.add('open'); layout(); });
  scrim.addEventListener('click',()=>{ phone.classList.remove('open'); });
  apply.addEventListener('click',(e)=>{ e.stopPropagation(); applyAndClose(); });
  function applyAndClose(){ previewSection(activeIdx); phone.classList.remove('open'); }

  previewSection(0);
  window.addEventListener('resize',layout);
  layout();
})();
