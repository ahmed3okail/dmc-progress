// DME Progress Tracker — service worker: shows push notifications, opens the app when one is tapped,
// and keeps a copy of the app files so it can open without internet (network first, cache as fallback).
// Supabase API calls are never cached.
const CACHE = 'dmc-shell-v1';
const APP = 'DMC%20Progress%20ERP.dc.html';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil((async () => {
  for (const k of await caches.keys()) if (k.startsWith('dmc-shell-') && k !== CACHE) await caches.delete(k);
  await self.clients.claim();
})()));

self.addEventListener('fetch', (e) => {
  const r = e.request;
  if (r.method !== 'GET') return;
  const u = new URL(r.url);
  const ok = u.origin === self.location.origin || /(^|\.)(esm\.sh|cdnjs\.cloudflare\.com|unpkg\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(u.hostname);
  if (!ok || u.pathname.endsWith('/sw.js')) return;
  e.respondWith((async () => {
    try {
      const res = await fetch(r);
      if (res && (res.ok || res.type === 'opaque')) { const c = await caches.open(CACHE); c.put(r, res.clone()).catch(() => {}); }
      return res;
    } catch (err) {
      const hit = await caches.match(r, { ignoreSearch: u.origin === self.location.origin });
      if (hit) return hit;
      throw err;
    }
  })());
});

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : '' }; }
  const rtl = d.lang !== 'en';
  e.waitUntil(self.registration.showNotification(d.title || 'DME Progress Tracker', {
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
