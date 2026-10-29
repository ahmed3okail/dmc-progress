// DMC Progress ERP — service worker: shows push notifications and opens the app when one is tapped.
// No offline caching (the app always loads fresh from the server).
const APP = 'DMC%20Progress%20ERP.dc.html';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : '' }; }
  const rtl = d.lang !== 'en';
  e.waitUntil(self.registration.showNotification(d.title || 'DMC Progress', {
    body: d.body || '',
    tag: d.tag || undefined,
    renotify: !!d.tag,
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    dir: rtl ? 'rtl' : 'ltr',
    lang: rtl ? 'ar' : 'en',
    data: { url: d.url || '' },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const target = new URL(APP + (e.notification.data && e.notification.data.url || ''), self.registration.scope).href;
  e.waitUntil((async () => {
    const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of list) {
      if (c.url.indexOf(APP) >= 0 || c.url.indexOf('DMC Progress ERP') >= 0) {
        await c.focus();
        c.postMessage({ type: 'dmc-push-open', url: e.notification.data && e.notification.data.url || '' });
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});
