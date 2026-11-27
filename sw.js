// Service worker de Holpin: recibe avisos push y muestra las notificaciones.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('push',e=>{
  let d={};
  try{d=e.data?e.data.json():{}}catch(_){d={body:e.data?e.data.text():''}}
  e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{
    if(list.some(c=>c.visibilityState==='visible'))return; // la app está a la vista: avisa ella misma
    const icon=new URL('icon-192.png.jpeg',self.registration.scope).href;
    return self.registration.showNotification(d.title||'Holpin',{
      body:d.body||'Tenés un mensaje nuevo',
      icon,tag:'holpin-msg',renotify:true,silent:false,vibrate:[200,100,200]
    });
  }));
});
self.addEventListener('notificationclick',e=>{
  e.notification.close();
  const target=e.notification.data&&e.notification.data.url?e.notification.data.url:'./';
  e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async list=>{
    for(const c of list){if('focus' in c){await c.focus();if('navigate' in c)await c.navigate(target);return;}}
    return self.clients.openWindow(target);
  }));
});

