// Injaz — service worker: shows push notifications, opens the app when one is tapped,
// and keeps a copy of the app files so it can open without internet (network first, cache as fallback).
// Supabase API calls are never cached.
const CACHE = 'dmc-shell-v36';
const APP = 'injaz.dc.html';
// app files kept from the first install, so the app opens without internet even if it was opened only once
const SHELL = ['./', APP, 'support.js', 'config.js', 'manifest.json', 'icon-192.png', 'icon-512.png', 'injaz-mark.svg', 'login-art.svg'];
self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => Promise.all(SHELL.map((u) => c.add(u).catch(() => {})))));
});
// the page sends the list of files it loaded (libraries, fonts) — keep a copy of each
self.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.type !== 'dmc-cache' || !Array.isArray(d.urls)) return;
  e.waitUntil(caches.open(CACHE).then(async (c) => {
    for (const u of d.urls.slice(0, 200)) {
      try { if (await c.match(u)) continue; const res = await fetch(u); if (res && (res.ok || res.type === 'opaque')) await c.put(u, res); } catch (_) {}
    }
  }));
});
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
  e.waitUntil(self.registration.showNotification(d.title || 'Injaz', {
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
      if (c.url.indexOf(APP) >= 0 || c.url.indexOf('injaz') >= 0) {
        await c.focus();
        c.postMessage({ type: 'dmc-push-open', url: e.notification.data && e.notification.data.url || '' });
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});
