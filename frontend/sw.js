/* My Team service worker (1.14.0) — makes the web app installable as a PWA
 * (iPhone home screen / Android / desktop) without any app store.
 *
 * Strategy: network-first for everything, with (a) an offline fallback page
 * when the network is gone and (b) a cached shell so the very first
 * standalone launch paints even before the network answers. The app itself
 * is a live API client — nothing stale may be served silently (nginx already
 * sends no-cache for the shell; the SW mirrors that by never caching HTML or
 * /api/ responses). Push: clicking a notification focuses the app and opens
 * the pushed board when possible.
 */
const VERSION = "v1.14.0";
const SHELL_CACHE = `shell-${VERSION}`;
const OFFLINE_URL = "/offline.html";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(SHELL_CACHE)
      .then((cache) => cache.addAll([OFFLINE_URL]))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k !== SHELL_CACHE)
            .map((k) => caches.delete(k))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET") return;
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/api/")) return; // live data only

  // Navigations: network first, offline page as the last resort.
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request)
        .then((res) => {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((cache) => cache.put("/", copy));
          return res;
        })
        .catch(() =>
          caches
            .match(event.request)
            .then((hit) => hit || caches.match(OFFLINE_URL))
        )
    );
    return;
  }

  // Same-origin static assets: network first, cache as offline fallback.
  event.respondWith(
    fetch(event.request)
      .then((res) => {
        if (res.ok && res.type === "basic") {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((cache) => cache.put(event.request, copy));
        }
        return res;
      })
      .catch(() => caches.match(event.request))
  );
});

/* ------------------------------ notifications ------------------------------ */

self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch {
    payload = { title: "My Team", body: event.data ? event.data.text() : "" };
  }
  if (!payload.body) return; // nothing to show
  event.waitUntil(
    self.registration.showNotification(payload.title || "My Team", {
      body: payload.body,
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-192.png",
      tag: payload.boardId ? `board-${payload.boardId}` : undefined,
      data: { boardId: payload.boardId ?? null },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const boardId = event.notification.data && event.notification.data.boardId;
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) {
          client.focus();
          if (boardId && "postMessage" in client) {
            client.postMessage({ type: "open-board", boardId });
          }
          return;
        }
      }
      return self.clients.openWindow(boardId ? `/?board=${boardId}` : "/");
    })
  );
});
