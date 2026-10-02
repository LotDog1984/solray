const api = {
  token: localStorage.getItem("token") || "",
  async request(path, options = {}) {
    const headers = options.headers || {};
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    const response = await fetch(path, { ...options, headers });
    if (!response.ok) {
      let detail = "Dogodila se greška";
      try {
        const body = await response.json();
        detail = body.detail || detail;
      } catch {
        detail = response.statusText || detail;
      }
      if (response.status === 401 && path !== "/api/auth/login") {
        logout(false);
        throw new Error("Sesija je istekla. Prijavite se ponovno.");
      }
      throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
    }
    const type = response.headers.get("content-type") || "";
    return type.includes("application/json") ? response.json() : response.text();
  },
  json(path, method, body) {
    return this.request(path, {
      method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  },
  upload(path, formData) {
    return this.request(path, { method: "POST", body: formData });
  },
};

const state = {
  me: null,
  users: [],
  projects: [],
  project: null,
  board: null,
  layer: "projects",
  view: "kanban",
  notifications: [],
  appName: "Private Workspace",
  defaultColumns: [],
  defaultTodoListName: "Nabava",
  nabava: null,
  nabavaLoading: false,
  dragTaskId: null,
  openTaskId: null,
  lastBoard: null,
  searchQuery: "",
  searchResults: null,
  searchLoading: false,
  unreadCount: 0,
  filesMode: localStorage.getItem("solray_files_mode") || "list", // "list" | "grid"
};

const app = document.querySelector("#app");

/* --------------------------- PWA plumbing (1.14.0, refined 1.15.1) ---------
 * The web app installs to the iPhone/Android home screen (no app store, no
 * Apple account, nothing that expires). The service worker enables that +
 * delivers Web Push banners; the Obavijesti page hosts the enable/test UI.
 *
 * 1.15.1: on iPhone/iPad Web Push banners ONLY arrive inside the app
 * installed on the home screen — a plain Safari tab can subscribe (and the
 * server delivers just fine) but iOS shows nothing there, which looked like
 * "push is broken". The UI now detects the install context and gives honest
 * instructions, re-enabling always re-subscribes + sends a real test push.
 * -------------------------------------------------------------------------- */
let deferredInstallPrompt = null;
let pendingBoardFromUrl = null;

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(() => {});
    navigator.serviceWorker.addEventListener("message", (event) => {
      if (event.data && event.data.type === "open-board" && event.data.boardId) {
        openBoard(Number(event.data.boardId));
      }
    });
  });
}
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredInstallPrompt = event; // Android/desktop: offer the one-tap install
});
{
  const boardParam = Number(new URLSearchParams(location.search).get("board"));
  if (Number.isFinite(boardParam) && boardParam > 0) {
    pendingBoardFromUrl = boardParam; // notification tap while app was closed
    history.replaceState(null, "", location.pathname);
  }
}

function urlB64ToUint8Array(b64) {
  const pad = "=".repeat((4 - (b64.length % 4)) % 4);
  const raw = atob((b64 + pad).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

/* iPhone/iPad detection (iPadOS 13+ claims to be a Mac, hence the touch check). */
function isIosDevice() {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
}

/* Running as the installed home-screen app (not a browser tab)? */
function isStandaloneApp() {
  return (window.matchMedia && window.matchMedia("(display-mode: standalone)").matches) ||
    window.navigator.standalone === true; /* iOS sets this only in the installed app */
}

const IOS_TAB_HINT =
  'Na iPhoneu/iPadu obavijesti rade samo u aplikaciji s početnog ekrana, ne u običnom Safari tabu. ' +
  'U Safariju dodirnite <strong>Dijeli → Na početni ekran</strong>, otvorite My Team s kućnog ekrana pa se vratite ovdje.';

async function webPushStatus() {
  const supported =
    "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  if (!supported) return { supported: false, subscribed: false, permission: "unsupported" };
  try {
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    // A stored subscription without a granted permission is dead weight: iOS
    // silently drops every push until we are re-enabled (Settings or prompt).
    const permission = Notification.permission;
    return { supported: true, subscribed: !!sub && permission === "granted", permission };
  } catch {
    return { supported: true, subscribed: false, permission: Notification.permission };
  }
}

function webPushSectionHtml(wp) {
  const head = `<h2 style="margin-top:0;">Obavijesti na uređaju</h2>`;
  if (!wp.supported) {
    if (isIosDevice()) {
      return `<div class="panel" style="margin-bottom:16px;">${head}<p class="muted" style="font-size:13px;margin:0 0 6px;">${IOS_TAB_HINT}</p><p class="muted" style="font-size:13px;margin:0;">Trebate i noviju inačicu iOS-a (16.4 ili noviju).</p></div>`;
    }
    return `<div class="panel" style="margin-bottom:16px;">${head}<p class="muted" style="font-size:13px;margin:0;">Ovaj preglednik ne podržava web obavijesti.</p></div>`;
  }
  if (wp.permission === "denied") {
    const where = isIosDevice()
      ? "Postavke → Notifikacije → My Team (ili Safari)"
      : "postavkama preglednika za ovu stranicu";
    return `<div class="panel" style="margin-bottom:16px;">${head}<p class="muted" style="font-size:13px;margin:0;">Obavijesti su isključene u ${where} — uključite ih tamo pa osvježite stranicu.</p></div>`;
  }
  if (isIosDevice() && !isStandaloneApp()) {
    return `<div class="panel" style="margin-bottom:16px;">${head}<p class="muted" style="font-size:13px;margin:0;">${IOS_TAB_HINT}</p></div>`;
  }
  if (wp.subscribed) {
    return `<div class="panel" style="margin-bottom:16px;">${head}
      <p class="muted" style="font-size:13px;margin:0 0 8px;">✓ Obavijesti su uključene na ovom uređaju.</p>
      <div class="row">
        <button class="secondary" id="webPushTest">Testiraj</button>
        <button class="secondary" id="webPushOff">Isključi na ovom uređaju</button>
      </div>
      <div id="webPushMsg" class="muted" style="font-size:13px;"></div></div>`;
  }
  return `<div class="panel" style="margin-bottom:16px;">${head}
    <div class="row"><button id="webPushOn">Omogući obavijesti</button></div>
    <p class="muted" style="font-size:13px;">Za obavijesti i kad je aplikacija zatvorena, dodajte ju na početni ekran: <strong>Dijeli → Na početni ekran</strong> (iPhone) ili "Instaliraj" u adresnoj traci (računalo).</p>
    <div id="webPushMsg" class="muted" style="font-size:13px;"></div></div>`;
}

async function enableWebPush(msgEl) {
  msgEl.textContent = "Zatražujem dopuštenje…";
  try {
    if (Notification.permission === "denied") {
      msgEl.textContent = isIosDevice()
        ? "Obavijesti su isključene u iOS Postavkama: Postavke → Notifikacije → My Team, pa osvježite stranicu."
        : "Obavijesti su blokirane u postavkama preglednika za ovu stranicu.";
      return;
    }
    if (Notification.permission === "default") {
      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        msgEl.textContent = "Dopuštenje nije odobreno — obavijesti ostaju isključene.";
        return;
      }
    }
    msgEl.textContent = "Pretplaćujem…";
    const reg = await navigator.serviceWorker.ready;
    // Always re-subscribe from scratch: a stale browser subscription (fresh
    // install, wiped data, iOS update) would make the server keep delivering
    // to a dead endpoint and the user would see nothing.
    const old = await reg.pushManager.getSubscription();
    if (old) {
      try {
        await old.unsubscribe();
      } catch { /* best-effort */ }
    }
    const { public_key } = await api.json("/api/me/webpush/vapid", "GET");
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlB64ToUint8Array(public_key),
    });
    const j = sub.toJSON();
    await api.json("/api/me/webpush/subscribe", "POST", {
      endpoint: j.endpoint,
      keys_p256dh: j.keys.p256dh,
      keys_auth: j.keys.auth,
    });
    // Don't just claim it works — send the real test push and report honestly.
    msgEl.textContent = "Šaljem probnu obavijest…";
    const res = await api.json("/api/me/webpush/test", "POST", {}).catch(() => null);
    msgEl.textContent = res && res.ok
      ? `✓ Obavijesti su omogućene. ${res.reason || ""}`
      : `⚠ Pretplata je spremljena, ali probna obavijest nije poslana: ${(res && res.reason) || "nepoznata greška"}`;
    await renderNotifications();
  } catch (error) {
    msgEl.textContent = `✗ ${error.message}`;
  }
}

async function disableWebPush(msgEl) {
  try {
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    if (sub) {
      const j = sub.toJSON();
      try {
        await api.json("/api/me/webpush/unsubscribe", "POST", { endpoint: j.endpoint, keys_p256dh: "", keys_auth: "" });
      } catch { /* server row may already be gone */ }
      await sub.unsubscribe();
    }
    msgEl.textContent = "Obavijesti su isključene na ovom uređaju.";
    await renderNotifications();
  } catch (error) {
    msgEl.textContent = `✗ ${error.message}`;
  }
}

async function testWebPush(msgEl) {
  msgEl.textContent = "Slanje…";
  try {
    const res = await api.json("/api/me/webpush/test", "POST", {});
    msgEl.textContent = res.ok ? `✓ ${res.reason}` : `⚠ ${res.reason}`;
  } catch (error) {
    msgEl.textContent = `✗ ${error.message}`;
  }
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}

function formData(form) {
  return Object.fromEntries(new FormData(form).entries());
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function formatDate(value) {
  try {
    return new Date(value).toLocaleString("hr-HR");
  } catch {
    return value;
  }
}

/* --------------------- 1.15.0 attribution badge line ---------------------- */
/* Who created it, who marked it done and who edited it last — one muted line
   on task cards and To-Do rows. Backend sends additive display-name fields
   (created_by / completed_by|done_by / edited_by); legacy rows have nulls and
   simply render without a badge. */
function attributionLine(parts) {
  const clean = parts.filter((part) => part && part.name);
  // An "edited" part that just repeats a name already on the line is noise.
  const shown = clean.filter(
    (part, i) => !(part.kind === "edited" && clean.some((other, j) => j < i && other.name === part.name))
  );
  if (!shown.length) return "";
  return shown.map((part) => `${part.icon} ${escapeHtml(part.name)}`).join(" · ");
}

function taskAttribution(task) {
  return attributionLine([
    { name: task.created_by, icon: "➕", kind: "created" },
    { name: task.completed ? task.completed_by : null, icon: "✓", kind: "done" },
    { name: task.edited_by, icon: "✏️", kind: "edited" },
  ]);
}

function todoAttribution(entry) {
  return attributionLine([
    { name: entry.created_by, icon: "➕", kind: "created" },
    { name: entry.is_done ? entry.done_by : null, icon: "🛒", kind: "done" },
    { name: entry.edited_by, icon: "✏️", kind: "edited" },
  ]);
}

function logout(clearMessage = true) {
  localStorage.removeItem("token");
  api.token = "";
  state.me = null;
  state.board = null;
  state.project = null;
  state.layer = "projects";
  state.projects = [];
  renderAuth(clearMessage ? "" : "Sesija je istekla. Prijavite se ponovno.");
}

async function loadProjects() {
  state.projects = await api.json("/api/projects", "GET");
}

function applyAppName() {
  const name = state.appName || "Private Workspace";
  document.title = name;
  const brand = document.querySelector(".brand");
  if (brand) brand.textContent = name;
}

async function loadAppName() {
  try {
    const settings = await api.json("/api/settings", "GET");
    state.appName = settings.app_name || "Private Workspace";
    state.defaultColumns = Array.isArray(settings.default_columns) ? settings.default_columns : [];
    state.defaultTodoListName = settings.default_todo_list || "Nabava";
    // 1.16.0: Nabava group (user IDs) — recipients of the "Pošalji obavijest" button.
    state.nabavaGroup = Array.isArray(settings.nabava_group) ? settings.nabava_group.map(Number) : [];
  } catch {
    state.appName = "Private Workspace";
  }
  applyAppName();
}

async function boot() {
  try {
    state.me = await api.json("/api/me", "GET");
    const [users] = await Promise.all([
      api.json("/api/users", "GET"),
      loadProjects(),
    ]);
    state.users = users;
    if (!state.project && state.projects.length) state.project = state.projects[0].id;
    await loadAppName();
    renderApp();
    refreshUnreadCount();
    setInterval(refreshUnreadCount, 30000); // badge stays fresh even idle
    // 1.14.0: notification tap while the PWA was closed deep-links to the board.
    if (pendingBoardFromUrl) {
      const boardId = pendingBoardFromUrl;
      pendingBoardFromUrl = null;
      openBoard(boardId);
    }
  } catch {
    localStorage.removeItem("token");
    api.token = "";
    renderAuth();
  }
}

/* ---------------------------------- auth ---------------------------------- */

async function renderAuth(message = "") {
  await loadAppName();
  let registrationOpen = false;
  try {
    const status = await api.request("/api/auth/status");
    registrationOpen = !!status.registration_open;
  } catch {
    registrationOpen = false;
  }
  app.innerHTML = `
    <section class="auth">
      <div class="auth-card">
        <h1>${escapeHtml(state.appName || "Private Workspace")}</h1>
        <form id="loginForm" class="form">
          <input name="username" placeholder="Korisničko ime" autocomplete="username" required />
          <input name="password" type="password" placeholder="Lozinka" autocomplete="current-password" required />
          <button type="submit">Prijava</button>
          <div class="message">${escapeHtml(message)}</div>
        </form>
        ${
          registrationOpen
            ? `
        <details style="margin-top:12px;">
          <summary style="cursor:pointer;color:var(--muted);">Prvo pokretanje? Registriraj se</summary>
          <form id="registerForm" class="form" style="margin-top:10px;">
            <input name="username" placeholder="Korisničko ime" autocomplete="username" required />
            <input name="display_name" placeholder="Prikazano ime" autocomplete="name" required />
            <input name="password" type="password" placeholder="Lozinka (min. 8 znakova)" autocomplete="new-password" required />
            <button type="submit" class="secondary">Registracija</button>
            <div class="message"></div>
          </form>
        </details>`
            : ""
        }
      </div>
    </section>
  `;

  document.querySelector("#loginForm").onsubmit = async (event) => {
    event.preventDefault();
    const msg = event.currentTarget.querySelector(".message");
    msg.textContent = "";
    try {
      const payload = formData(event.currentTarget);
      const token = await api.json("/api/auth/login", "POST", payload);
      api.token = token.access_token;
      localStorage.setItem("token", api.token);
      await boot();
    } catch (error) {
      msg.textContent = error.message;
    }
  };

  const registerForm = document.querySelector("#registerForm");
  if (registerForm) {
    registerForm.onsubmit = async (event) => {
      event.preventDefault();
      const msg = event.currentTarget.querySelector(".message");
      msg.textContent = "";
      try {
        const payload = formData(event.currentTarget);
        const token = await api.json("/api/auth/register", "POST", payload);
        api.token = token.access_token;
        localStorage.setItem("token", api.token);
        await boot();
      } catch (error) {
        msg.textContent = error.message;
      }
    };
  }
}

/* ---------------------------------- shell --------------------------------- */

function renderApp() {
  app.innerHTML = `
    <div class="shell">
      <nav class="icon-rail" id="iconRail" aria-label="Glavna navigacija"></nav>
      <aside class="sidebar" id="sidebar"></aside>
      <section class="content" id="content"></section>
    </div>
  `;
  renderSidebar();
  renderView();
}

function allBoards() {
  return state.projects.flatMap((p) => p.boards);
}

function currentProject() {
  return state.projects.find((p) => p.id === state.project) || null;
}

function currentBoard() {
  return allBoards().find((b) => b.id === state.board) || null;
}

async function refreshUnreadCount() {
  try {
    const data = await api.json("/api/notifications/unread-count", "GET");
    if (data.count !== state.unreadCount) {
      state.unreadCount = data.count;
      renderSidebar();
    }
  } catch {
    /* ignore transient errors */
  }
}

async function refreshProjects() {
  await loadProjects();
  if (state.layer === "boards" && !currentProject()) state.layer = "projects";
  if (state.board && !allBoards().some((b) => b.id === state.board)) state.board = null;
  renderSidebar();
  renderView();
}

function goProjects() {
  state.layer = "projects";
  state.project = null;
  state.board = null;
  state.view = "kanban";
  state.searchResults = null;
  renderSidebar();
  renderView();
}

function goNabava() {
  state.layer = "projects";
  state.project = null;
  state.board = null;
  state.view = "nabava";
  state.searchResults = null;
  state.nabava = null;
  renderSidebar();
  renderView();
  renderNabava();
}

function goNotifications() {
  state.layer = "projects";
  state.project = null;
  state.board = null;
  state.view = "notifications";
  state.searchResults = null;
  renderSidebar();
  renderView();
  renderNotifications();
}

function goBoards(projectId) {
  state.project = projectId;
  state.layer = "boards";
  state.board = null;
  state.view = "kanban";
  state.searchResults = null;
  renderSidebar();
  renderView();
}

function openBoard(boardId) {
  const board = allBoards().find((b) => b.id === boardId);
  if (!board) return;
  state.board = boardId;
  state.project = board.project_id;
  state.layer = "app";
  state.view = "kanban";
  renderSidebar();
  renderView();
  loadBoard();
}

function countValue(value, fallback = 0) {
  const count = Number(value);
  return Number.isFinite(count) && count >= 0 ? count : fallback;
}

function projectSummary(project) {
  const boards = Array.isArray(project?.boards) ? project.boards : [];
  const taskCount = countValue(project?.task_count, boards.reduce((sum, board) => sum + countValue(board.task_count), 0));
  const openTaskCount = countValue(project?.open_task_count, boards.reduce((sum, board) => sum + countValue(board.open_task_count, countValue(board.task_count)), 0));
  const completedTaskCount = countValue(project?.completed_task_count, Math.max(0, taskCount - openTaskCount));
  return {
    boards,
    boardCount: countValue(project?.board_count, boards.length),
    taskCount,
    openTaskCount,
    completedTaskCount,
    progress: taskCount ? Math.round((completedTaskCount / taskCount) * 100) : 0,
  };
}

function boardSummary(board) {
  const total = countValue(board?.task_count);
  const completed = countValue(
    board?.completed_task_count,
    Math.max(0, total - countValue(board?.open_task_count, total)),
  );
  const open = countValue(board?.open_task_count, Math.max(0, total - completed));
  return { total, open, completed, progress: total ? Math.round((completed / total) * 100) : 0 };
}

function syncBoardSummary(board) {
  const project = state.projects.find((entry) => entry.id === state.project) || currentProject();
  if (!project) return;
  const byColumn = board.columns || [];
  const total = byColumn.reduce((sum, column) => sum + (column.tasks || []).length, 0);
  const completed = byColumn.reduce((sum, column) => sum + (column.tasks || []).filter((task) => task.completed).length, 0);
  const boardExists = (project.boards || []).some((entry) => entry.id === board.id);
  const updatedBoards = boardExists
    ? project.boards.map((entry) => entry.id === board.id
      ? { ...entry, task_count: total, completed_task_count: completed, open_task_count: total - completed }
      : entry)
    : project.boards || [];
  project.boards = updatedBoards;
  project.board_count = updatedBoards.length;
  project.task_count = updatedBoards.reduce((sum, entry) => sum + countValue(entry.task_count), 0);
  project.completed_task_count = updatedBoards.reduce((sum, entry) => sum + countValue(entry.completed_task_count), 0);
  project.open_task_count = Math.max(0, project.task_count - project.completed_task_count);
}

function updateBoardHeader(board) {
  const summary = boardSummary({
    task_count: (board.columns || []).reduce((sum, column) => sum + (column.tasks || []).length, 0),
    completed_task_count: (board.columns || []).reduce((sum, column) => sum + (column.tasks || []).filter((task) => task.completed).length, 0),
  });
  const openEl = document.querySelector("#boardOpenCount");
  const totalEl = document.querySelector("#boardTotalCount");
  const progressEl = document.querySelector("#boardProgressCount");
  if (openEl) openEl.textContent = `${summary.open} otvoreno`;
  if (totalEl) totalEl.textContent = `${summary.total} zadataka`;
  if (progressEl) progressEl.textContent = `${summary.progress}% gotovo`;
}

function renderIconRail() {
  const rail = document.querySelector("#iconRail");
  if (!rail) return;
  const active = (action) => {
    if (action === "projects") return state.view === "kanban";
    if (action === "files") return state.view === "files";
    if (action === "notifications" || action === "nabava" || action === "settings") return state.view === action;
    return false;
  };
  const badge = state.unreadCount
    ? `<span class="rail-badge">${state.unreadCount > 99 ? "99+" : state.unreadCount}</span>`
    : "";
  const userName = state.me?.display_name || state.me?.username || "My Team";
  const initials = userName.split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
  rail.innerHTML = `
    <div class="rail-mark" title="${escapeHtml(state.appName || "My Team")}">M<span>✦</span></div>
    <!-- 1.16.0: text labels under the icons — visible on iPhone PWA too, where
         title= tooltips don't exist. -->
    <button class="rail-button ${active("projects") ? "active" : ""}" data-rail-action="projects" title="Projekti" aria-label="Projekti"><span>▦</span><small class="rail-label">Projekti</small></button>
    <button class="rail-button ${active("nabava") ? "active" : ""}" data-rail-action="nabava" title="${escapeHtml(state.defaultTodoListName || "Nabava")}" aria-label="Nabava"><span>🛒</span><small class="rail-label">${escapeHtml(state.defaultTodoListName || "Nabava")}</small></button>
    <button class="rail-button ${active("files") ? "active" : ""}" data-rail-action="files" title="Datoteke" aria-label="Datoteke"><span>🗂</span><small class="rail-label">Datoteke</small></button>
    <button class="rail-button ${active("notifications") ? "active" : ""}" data-rail-action="notifications" title="Obavijesti" aria-label="Obavijesti"><span>🔔</span><small class="rail-label">Obavijesti</small>${badge}</button>
    <span class="rail-spacer"></span>
    <button class="rail-button" data-rail-action="search" title="Pretraga" aria-label="Pretraga"><span>⌕</span><small class="rail-label">Pretraga</small></button>
    <button class="rail-button ${active("settings") ? "active" : ""}" data-rail-action="settings" title="Postavke" aria-label="Postavke"><span>⚙</span><small class="rail-label">Postavke</small></button>
    <button class="rail-avatar" data-rail-action="logout" title="Odjava · ${escapeHtml(userName)}" aria-label="Odjava">${escapeHtml(initials || "MT")}</button>
  `;
  rail.querySelectorAll("[data-rail-action]").forEach((button) => {
    button.onclick = () => {
      const action = button.dataset.railAction;
      if (action === "projects") return goProjects();
      if (action === "nabava") return goNabava();
      if (action === "notifications") return goNotifications();
      if (action === "search") return document.querySelector("#searchInput")?.focus();
      if (action === "settings") {
        state.layer = "app";
        state.view = "settings";
        renderSidebar();
        renderView();
        return;
      }
      if (action === "files") {
        if (!state.project) state.project = state.projects[0]?.id || null;
        if (!state.project) return;
        state.layer = "app";
        state.board = null;
        state.view = "files";
        renderSidebar();
        renderView();
        return;
      }
      if (action === "logout") logout();
    };
  });
}

function renderSidebar() {
  const sidebar = document.querySelector("#sidebar");
  if (!sidebar) return;

  let layerHtml = "";
  if (state.layer === "projects") {
    const rows = state.projects
      .map((project) => {
        const summary = projectSummary(project);
        return `
        <div class="side-item project-side-item">
          <div class="project-side-card ${state.project === project.id ? "active" : ""}">
            <button class="project-nav" data-open-project="${project.id}" aria-label="Otvori projekt ${escapeHtml(project.name)}">
              <span class="project-nav-title">${escapeHtml(project.name)}</span>
              <span class="project-nav-meta">${summary.boardCount} ploče <i>·</i> ${summary.openTaskCount}/${summary.taskCount} zadataka</span>
            </button>
            <span class="project-progress-ring" style="--progress:${summary.progress}%" title="${summary.progress}% zadataka gotovo"><b>${summary.progress}</b></span>
            <button class="icon-action edit-toggle" title="Uredi projekt" aria-label="Uredi projekt">···</button>
          </div>
          <div class="project-progress-track"><span style="width:${summary.progress}%"></span></div>
          <div class="edit-menu" hidden>
            <button class="menu-rename" data-project-id="${project.id}">Preimenuj</button>
            <button class="menu-delete danger" data-project-id="${project.id}">Obriši</button>
          </div>
        </div>`;
      })
      .join("");
    layerHtml = `
      <div class="side-section-head"><div class="side-label">Projekti</div><span class="section-count">${state.projects.length}</span></div>
      <div class="side-list project-list">${rows || '<div class="side-empty">Nema projekata</div>'}</div>
      <form id="newProjectForm" class="side-form">
        <input name="name" placeholder="Novi projekt..." required />
        <button type="submit" title="Dodaj projekt" aria-label="Dodaj projekt">+</button>
      </form>`;
  } else {
    const project = currentProject();
    const rows = (project?.boards || [])
      .map((board) => {
        const summary = boardSummary(board);
        return `
        <div class="side-item board-side-item">
          <div class="side-row board-side-row">
            <button class="side-name ${state.board === board.id ? "active" : ""}" data-open-board="${board.id}">${escapeHtml(board.name)}</button>
            <span class="board-count-pill" title="${summary.open} otvoreno od ${summary.total} zadataka" aria-label="${summary.open} otvoreno od ${summary.total} zadataka">${summary.open}/${summary.total}</span>
            <button class="icon-action edit-toggle" title="Uredi ploču" aria-label="Uredi ploču">···</button>
          </div>
          <div class="edit-menu" hidden>
            <button class="menu-rename" data-board-id="${board.id}">Preimenuj</button>
            <button class="menu-delete danger" data-board-id="${board.id}">Obriši</button>
          </div>
        </div>`;
      })
      .join("");
    const summary = projectSummary(project);
    layerHtml = `
      <button class="side-back" id="sideBackToProjects"><span>←</span> Projekti</button>
      <div class="side-section-head"><div class="side-label">${escapeHtml(project?.name || "Ploče")}</div><span class="section-count">${summary.boardCount}</span></div>
      <div class="project-context-meta">${summary.openTaskCount} otvoreno <i>·</i> ${summary.taskCount} zadataka</div>
      <div class="side-list board-list">${rows || '<div class="side-empty">Nema ploča</div>'}</div>
      ${project ? `
      <form id="newBoardForm" class="side-form">
        <input name="name" placeholder="Nova ploča..." required />
        <button type="submit" title="Dodaj ploču" aria-label="Dodaj ploču">+</button>
      </form>` : ""}`;
  }

  const userName = state.me?.display_name || state.me?.username || "";
  sidebar.innerHTML = `
    <div class="brand-row">
      <div class="brand">${escapeHtml(state.appName || "My Team")}</div>
      <div id="versionBadge" class="version-badge" title="Verzija aplikacije"></div>
    </div>
    <div class="account-line"><span class="account-avatar">${escapeHtml(userName.split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "MT")}</span><span>Prijavljen: <b>${escapeHtml(userName)}</b></span></div>
    <form id="sideSearchForm" class="side-search">
      <input id="searchInput" type="search" placeholder="Traži projekte, ploče, zadatke, nabavu…" value="${escapeHtml(state.searchQuery || "")}" autocomplete="off" />
    </form>
    <div class="side-layer">${layerHtml}</div>
    <div class="sidebar-foot"><span class="online-dot"></span> Zajednički prostor <span class="foot-version">v<span id="sideVersionText">—</span></span></div>
  `;
  renderIconRail();
  bindSearchInput(sidebar);
  bindSidebarEvents(sidebar);
}

function bindSidebarEvents(sidebar) {
  // Version badge: what the SERVER actually serves right now. Cached copies
  // of app.js (or an old tab) can lie about the code they run, but this fetch
  // is fresh every render — if it disagrees with the expected version, the
  // browser is holding a stale page (Ctrl+F5) or the URL points elsewhere.
  fetch("/version.txt", { cache: "no-store" })
    .then((r) => (r.ok ? r.text() : null))
    .then((v) => {
      const el = document.querySelector("#versionBadge");
      const footVersion = document.querySelector("#sideVersionText");
      if (el && v) el.textContent = `v${v.trim()}`;
      if (footVersion && v) footVersion.textContent = v.trim();
    })
    .catch(() => {});

  sidebar.querySelectorAll("[data-open-project]").forEach((btn) => {
    btn.onclick = () => goBoards(Number(btn.dataset.openProject));
  });
  sidebar.querySelectorAll("[data-open-board]").forEach((btn) => {
    btn.onclick = () => openBoard(Number(btn.dataset.openBoard));
  });

  const back = sidebar.querySelector("#sideBackToProjects");
  if (back) back.onclick = () => goProjects();

  const projectForm = sidebar.querySelector("#newProjectForm");
  if (projectForm) {
    projectForm.onsubmit = async (event) => {
      event.preventDefault();
      const name = new FormData(projectForm).get("name");
      try {
        await api.json("/api/projects", "POST", { name });
        await refreshProjects();
      } catch (error) {
        alert(error.message);
      }
    };
  }

  const boardForm = sidebar.querySelector("#newBoardForm");
  if (boardForm) {
    boardForm.onsubmit = async (event) => {
      event.preventDefault();
      const project = currentProject();
      if (!project) return;
      const name = new FormData(boardForm).get("name");
      try {
        const created = await api.json("/api/boards", "POST", { name, project_id: project.id });
        await refreshProjects();
        openBoard(created.id);
      } catch (error) {
        alert(error.message);
      }
    };
  }

  bindCardMenus(sidebar, {
    onRename: async (id, type) => {
      if (type === "project") {
        const project = state.projects.find((p) => p.id === id);
        const name = prompt("Novi naziv projekta:", project?.name || "");
        if (!name || !name.trim()) return false;
        await api.json(`/api/projects/${id}`, "PATCH", { name: name.trim() });
        return true;
      }
      const board = allBoards().find((b) => b.id === id);
      const name = prompt("Novi naziv ploče:", board?.name || "");
      if (!name || !name.trim()) return false;
      await api.json(`/api/boards/${id}`, "PATCH", { name: name.trim() });
      return true;
    },
    onDelete: async (id, type) => {
      if (type === "project") {
        const project = state.projects.find((p) => p.id === id);
        if (!confirm(`Obrisati projekt "${project?.name}" sa svim pločama i zadacima?`)) return false;
        await api.request(`/api/projects/${id}`, { method: "DELETE" });
        return true;
      }
      const board = allBoards().find((b) => b.id === id);
      if (!confirm(`Obrisati ploču "${board?.name}" sa svim zadacima?`)) return false;
      await api.request(`/api/boards/${id}`, { method: "DELETE" });
      return true;
    },
    afterChange: refreshProjects,
  });

  const notificationsBtn = sidebar.querySelector("#navNotifications");
  if (notificationsBtn) {
    notificationsBtn.onclick = () => {
      state.layer = "projects";
      state.project = null;
      state.board = null;
      state.view = "notifications";
      state.searchResults = null;
      renderSidebar();
      renderView();
      renderNotifications();
    };
  }

  const nabavaBtn = sidebar.querySelector("#navNabava");
  if (nabavaBtn) nabavaBtn.onclick = () => goNabava();

  // Settings and logout live in the persistent icon rail now.
}

function closeMenus(root) {
  root.querySelectorAll(".edit-menu").forEach((menu) => (menu.hidden = true));
}

function bindCardMenus(root, handlers) {
  root.querySelectorAll(".edit-toggle").forEach((btn) => {
    btn.onclick = (event) => {
      event.stopPropagation();
      const menu = btn.closest(".side-item")?.querySelector(".edit-menu");
      if (!menu) return;
      const show = menu.hidden;
      closeMenus(root);
      menu.hidden = !show;
    };
  });
  root.querySelectorAll(".menu-rename").forEach((btn) => {
    btn.onclick = async (event) => {
      event.stopPropagation();
      const isProject = !!btn.dataset.projectId;
      const id = Number(btn.dataset.projectId || btn.dataset.boardId);
      try {
        if (await handlers.onRename(id, isProject ? "project" : "board")) await handlers.afterChange();
      } catch (error) {
        alert(error.message);
      }
    };
  });
  root.querySelectorAll(".menu-delete").forEach((btn) => {
    btn.onclick = async (event) => {
      event.stopPropagation();
      const isProject = !!btn.dataset.projectId;
      const id = Number(btn.dataset.projectId || btn.dataset.boardId);
      try {
        if (await handlers.onDelete(id, isProject ? "project" : "board")) await handlers.afterChange();
      } catch (error) {
        alert(error.message);
      }
    };
  });
}

async function openSearchResult(result) {
  try {
    // Leaving search: clear the results so the destination view renders
    // immediately (renderView keeps showing results while they are set).
    state.searchResults = null;
    state.searchQuery = "";
    if (result.type === "project" && result.project_id) {
      goBoards(result.project_id);
      return;
    }
    // 1.9.3: Nabava hits without a board (manual entries) open the global view.
    if (result.type === "nabava" && !result.board_id) {
      await goNabava();
      return;
    }
    if (result.board_id) {
      const board = allBoards().find((b) => b.id === result.board_id);
      if (board?.project_id) {
        state.project = board.project_id;
        await loadProjects();
      }
      state.layer = "app";
      state.board = result.board_id;
      state.view = "kanban";
      state.openTaskId = result.type === "task" ? result.task_id : null;
      renderSidebar();
      renderView();
    }
  } catch (error) {
    alert(error.message);
  }
}

function renderView() {
  const content = document.querySelector("#content");
  if (!content) return;
  const board = currentBoard();

  // White area: on main layers it shows search results (when a search is
  // active) or the notifications panel — never both at once.
  if (state.searchResults !== null) {
    content.innerHTML = renderSearchResults();
    bindSearchResults(content);
    return;
  }
  if (state.layer !== "app") {
    if (state.view === "nabava") {
      content.innerHTML = '<div id="nabavaView"></div>';
      renderNabava(); // Nabava is a main-page view, like Obavijesti
      return;
    }
    content.innerHTML = '<div id="notificationsView"></div>';
    renderNotifications(); // Obavijesti live on the main page
    return;
  }

  const heading = board?.name || state.appName || "My Team";
  const project = currentProject();
  const summary = board ? boardSummary(board) : null;
  const boardTaskCount = summary?.total ?? 0;
  const boardOpenCount = summary?.open ?? 0;
  const team = state.users.slice(0, 4);
  // Board tabs: only Ploča and Datoteke (Postavke is on the icon rail,
  // Obavijesti and Nabava are main views).
  const tabs = `
    ${board ? `<div class="board-breadcrumb">Projekti <span>/</span> ${escapeHtml(project?.name || "Projekt")} <span>/</span> <b>${escapeHtml(board.name)}</b></div>` : ""}
    <div class="topbar">
      <div class="board-heading">
        <h1>${escapeHtml(heading)}</h1>
        ${board ? `      <div class="board-subtitle"><span id="boardOpenCount">${boardOpenCount} otvoreno</span><i>·</i><span id="boardTotalCount">${boardTaskCount} zadataka</span><i>·</i><span id="boardProgressCount">${summary.progress}% gotovo</span></div>` : ""}
      </div>
      ${board ? `<div class="team-stack" aria-label="Članovi tima">${team.map((user, index) => `<span class="team-avatar avatar-${index + 1}" title="${escapeHtml(user.display_name || user.username)}">${escapeHtml((user.display_name || user.username || "?").split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase())}</span>`).join("")}${state.users.length > team.length ? `<span class="team-more">+${state.users.length - team.length}</span>` : ""}</div>` : ""}
      <div class="topbar-actions">
        ${board && state.view === "kanban" ? `<button class="primary" id="quickAddTask">＋ Novi zadatak</button>` : ""}
        <div class="tabs">
          <button class="${state.view === "kanban" ? "active" : ""}" data-view="kanban">Ploča</button>
          <button class="${state.view === "files" ? "active" : ""}" data-view="files">Datoteke</button>
        </div>
      </div>
    </div>
  `;

  if (state.view === "kanban") {
    content.innerHTML = tabs + '<div class="kanban" id="kanban">Učitavanje...</div>';
    bindTabs(content);
    loadBoard();
  } else if (state.view === "files") {
    content.innerHTML = tabs + '<div id="filesView"></div>';
    bindTabs(content);
    renderFiles();
  } else {
    // Postavke (opened from the left bar). Board tabs are shown only when a
    // board is open, so the user can jump straight back to Ploča/Datoteke.
    content.innerHTML = (state.board ? tabs : "") + '<div id="settingsView"></div>';
    if (state.board) bindTabs(content);
    renderSettings();
  }
}

function renderSearchResults() {
  const q = escapeHtml(state.searchQuery || "");
  let resultsHtml = "";
  if (state.searchLoading) {
    resultsHtml = '<div class="search-status">Pretraživanje…</div>';
  } else if (state.searchResults !== null) {
    if (!state.searchResults.length) {
      resultsHtml = '<div class="search-status">Nema rezultata.</div>';
    } else {
      const items = state.searchResults
        .map(
          (r, i) => `
          <button class="search-result" data-result-index="${i}">
            <span class="search-type type-${r.type}">${
              r.type === "project" ? "Projekt" : r.type === "board" ? "Ploča" : r.type === "nabava" ? "Nabava" : "Zadatak"
            }</span>
            <span class="search-label">${escapeHtml(r.label)}</span>
            ${r.snippet ? `<span class="search-snippet">${escapeHtml(r.snippet)}</span>` : ""}
            <span class="search-detail">${escapeHtml(r.detail)}</span>
          </button>`
        )
        .join("");
      resultsHtml = `<div class="search-count">${state.searchResults.length} rezultata za “${q}”</div><div class="search-list">${items}</div>`;
    }
  }
  return `<div class="search-wrap">${resultsHtml}</div>`;
}

/* The search input lives in the SIDEBAR under the app name (phone-friendly:
   no autofocus stealing the keyboard when navigating layers). Results render
   in the content area. */
function bindSearchInput(sidebar) {
  const form = sidebar.querySelector("#sideSearchForm");
  if (!form) return;
  const input = form.querySelector("#searchInput");

  let debounce = null;
  input.oninput = () => {
    clearTimeout(debounce);
    const value = input.value.trim();
    if (!value) {
      state.searchQuery = "";
      state.searchResults = null;
      state.searchLoading = false;
      renderView();
      return;
    }
    debounce = setTimeout(async () => {
      state.searchQuery = value;
      state.searchLoading = true;
      renderView(); // shows "Pretraživanje…"
      try {
        const data = await api.json(`/api/search?q=${encodeURIComponent(value)}`, "GET");
        if (state.searchQuery !== value) return; // stale response
        state.searchResults = data.results || [];
        state.searchLoading = false;
        renderView();
      } catch (error) {
        state.searchLoading = false;
        state.searchResults = [];
        alert(error.message);
      }
    }, 250);
  };

  form.onsubmit = (event) => {
    event.preventDefault();
    input.oninput({ target: input });
  };
}

function bindSearchResults(container) {
  container.querySelectorAll(".search-result").forEach((btn) => {
    btn.onclick = () => {
      const result = state.searchResults?.[Number(btn.dataset.resultIndex)];
      if (result) openSearchResult(result);
    };
  });
}

function bindTabs(container) {
  container.querySelectorAll("[data-view]").forEach((btn) => {
    btn.onclick = () => {
      state.view = btn.dataset.view;
      renderView();
    };
  });
  const quickAdd = container.querySelector("#quickAddTask");
  if (quickAdd) {
    quickAdd.onclick = () => {
      const input = document.querySelector(".new-task-form input[name='title']");
      input?.scrollIntoView({ behavior: "smooth", block: "center" });
      input?.focus({ preventScroll: true });
    };
  }
}

/* ---------------------------------- kanban -------------------------------- */

async function loadBoard() {
  const kanban = document.querySelector("#kanban");
  if (!kanban) return;
  if (!state.board) {
    kanban.innerHTML = '<div class="panel">Još nema ploča. Stvorite prvu ploču u lijevom izborniku.</div>';
    return;
  }
  try {
    const board = await api.json(`/api/boards/${state.board}`, "GET");
    state.lastBoard = board;
    syncBoardSummary(board);
    updateBoardHeader(board);
    renderKanban(board);
    bindTaskEvents(board);
    if (state.layer === "app") renderSidebar();
  } catch (error) {
    kanban.innerHTML = `<div class="panel">${escapeHtml(error.message)}</div>`;
  }
}

function renderKanban(board) {
  const kanban = document.querySelector("#kanban");
  if (!kanban) return;
  state.board = board.id;

  const columnsHtml = board.columns
    .map((col, index) => {
      const tasks = col.tasks.map((task) => renderTask(task)).join("");
      const openCount = col.tasks.filter((task) => !task.completed).length;
      return `
      <div class="column" data-column-id="${col.id}" style="--column-index:${index}">
        <h2><span class="column-dot"></span>${escapeHtml(col.name)} <small class="column-count" title="${openCount} otvoreno · ${col.tasks.length} ukupno">${openCount}</small><button type="button" class="column-add add-task-shortcut" title="Dodaj zadatak" aria-label="Dodaj zadatak">＋</button></h2>
        <div class="tasks" data-tasks-for="${col.id}">${tasks}</div>
        <form class="new-task-form" data-column-id="${col.id}">
          <div class="quick-task-row"><input name="title" placeholder="Novi zadatak..." required /><button type="submit" class="primary" title="Dodaj zadatak">＋</button></div>
          <details class="task-extra-details">
            <summary>Opis, popis i dodjela</summary>
            <textarea name="description" placeholder="Opis (@ime za tagiranje)..."></textarea>
            <div class="todo-creator">
              <div class="todo-creator-rows"></div>
              <button type="button" class="secondary add-todo-row">+ Stavka popisa</button>
            </div>
            <select name="assignee_id">
              <option value="">Nedodijeljeno</option>
              ${state.users.map((u) => `<option value="${u.id}">${escapeHtml(u.display_name || u.username)}</option>`).join("")}
            </select>
          </details>
        </form>
      </div>`;
    })
    .join("");

  // Supplies To-Do panel ("Nabava"): one automatic list per board, aggregated
  // into the global Nabava view (every Stavka shows its project + board there).
  const todoEntries = board.todo_list?.entries || [];
  const todoPanel = `
    <div class="column todo-panel" id="boardTodoPanel" data-board-id="${board.id}" style="--column-index:${board.columns.length}">
      <h2><span class="column-dot"></span>${escapeHtml(state.defaultTodoListName || "Nabava")} <small class="column-count" title="${todoEntries.filter((entry) => !entry.is_done).length} otvoreno · ${todoEntries.length} ukupno">${todoEntries.filter((entry) => !entry.is_done).length}</small></h2>
      <button type="button" class="secondary todo-notify" id="boardTodoNotify" title="Obavijesti sve korisnike u Nabava grupi da ima novih stavki">🔔 Pošalji obavijest</button>
      <div class="tasks" id="boardTodoEntries">${renderTodoEntries(todoEntries)}</div>
      <form id="boardTodoForm" style="margin-top:10px;display:grid;gap:6px;">
        <input name="title" placeholder="Nova stavka (npr. nema više vijaka 6x60)..." required />
        <button type="submit" class="secondary">Dodaj stavku</button>
      </form>
    </div>`;

  kanban.innerHTML =
    columnsHtml +
    todoPanel +
    `
    <div class="column new-column-tile" style="--column-index:${board.columns.length + 1}">
      <form id="newColumnForm">
        <input name="name" placeholder="Nova kolona..." required />
        <button type="submit" class="secondary">＋ Dodaj kolonu</button>
      </form>
    </div>`;

  bindBoardTodoEvents(board);

  // The global and per-column + buttons focus the nearest quick task field.
  kanban.querySelectorAll(".add-task-shortcut").forEach((button) => {
    button.onclick = () => button.closest(".column")?.querySelector(".new-task-form input[name='title']")?.focus();
  });

  // Bind new task forms
  kanban.querySelectorAll(".new-task-form").forEach((form) => {
    // Checklist creator rows (+ Stavka popisa)
    const rowsBox = form.querySelector(".todo-creator-rows");
    form.querySelector(".add-todo-row").onclick = () => {
      const row = document.createElement("div");
      row.className = "todo-creator-row";
      row.innerHTML = `<input name="todo_item" placeholder="Stavka popisa..." /><button type="button" class="secondary remove-todo-row" title="Ukloni">✕</button>`;
      row.querySelector(".remove-todo-row").onclick = () => row.remove();
      rowsBox.appendChild(row);
      row.querySelector("input").focus();
    };

    form.onsubmit = async (event) => {
      event.preventDefault();
      const payload = formData(form);
      const columnId = Number(form.dataset.columnId);
      const column = board.columns.find((c) => c.id === columnId);
      const items = [...form.querySelectorAll(".todo-creator-row input")]
        .map((inp, idx) => ({ title: inp.value.trim(), is_done: false, position: idx }))
        .filter((i) => i.title);
      try {
        const created = await api.json("/api/tasks", "POST", {
          column_id: columnId,
          title: payload.title,
          description: payload.description || "",
          assignee_id: payload.assignee_id ? Number(payload.assignee_id) : null,
          position: column ? column.tasks.filter((t) => !t.completed).length : 0,
          items,
        });
        if (created && created.id) state.openTaskId = created.id; // show the fresh checklist right away
        await loadBoard();
        refreshUnreadCount(); // a self-tag or assignment must bump the badge
      } catch (error) {
        alert(error.message);
      }
    };
  });

  // Bind new column form
  const columnForm = document.querySelector("#newColumnForm");
  if (columnForm) {
    columnForm.onsubmit = async (event) => {
      event.preventDefault();
      const name = new FormData(columnForm).get("name");
      try {
        await api.json("/api/columns", "POST", {
          board_id: board.id,
          name,
          position: board.columns.length,
        });
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    };
  }

  // Drag & drop between columns
  kanban.querySelectorAll(".column[data-column-id]").forEach((colEl) => {
    colEl.addEventListener("dragover", (e) => e.preventDefault());
    colEl.addEventListener("drop", async (e) => {
      e.preventDefault();
      const taskId = state.dragTaskId ?? Number(e.dataTransfer.getData("text/plain"));
      if (!taskId) return;
      const columnId = Number(colEl.dataset.columnId);
      const column = board.columns.find((c) => c.id === columnId);
      try {
        await api.json(`/api/tasks/${taskId}/move`, "PATCH", {
          column_id: columnId,
          position: column ? column.tasks.length : 0,
        });
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    });
  });
}

function renderTodoEntries(entries) {
  if (!entries.length) return '<div class="muted" style="font-size:13px;">Nema stavki — dodajte prvu ispod.</div>';
  return entries
    .map(
      (e) => `
      <div class="todo-panel-row ${e.is_done ? "is-done" : ""}" data-entry-id="${e.id}">
        <input type="checkbox" class="todo-panel-check" data-entry-id="${e.id}" ${e.is_done ? "checked" : ""} title="Označi kao nabavljeno" />
        <div class="todo-panel-main">
          <button type="button" class="link-btn todo-panel-text" title="Uredi stavku">${escapeHtml(e.title)}</button>
          ${
            todoAttribution(e)
              ? `<span class="todo-panel-attr muted">${todoAttribution(e)}</span>`
              : ""
          }
        </div>
        <button type="button" class="danger todo-panel-del" data-entry-id="${e.id}" title="Obriši stavku">✕</button>
      </div>`
    )
    .join("");
}

function bindBoardTodoEvents(board) {
  const form = document.querySelector("#boardTodoForm");
  if (form) {
    form.onsubmit = async (event) => {
      event.preventDefault();
      const title = new FormData(form).get("title");
      try {
        await api.json(`/api/boards/${board.id}/todo`, "POST", { title });
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    };
  }

  document.querySelectorAll("#boardTodoEntries .todo-panel-check").forEach((check) => {
    check.onchange = async () => {
      const row = check.closest(".todo-panel-row");
      const title = row.querySelector(".todo-panel-text").textContent;
      try {
        await api.json(`/api/boards/${board.id}/todo/${check.dataset.entryId}`, "PATCH", {
          title,
          is_done: check.checked,
        });
        await loadBoard();
      } catch (error) {
        check.checked = !check.checked;
        alert(error.message);
      }
    };
  });

  document.querySelectorAll("#boardTodoEntries .todo-panel-text").forEach((btn) => {
    btn.onclick = async () => {
      const title = prompt("Uredi stavku:", btn.textContent);
      if (title === null) return;
      const cleaned = title.trim();
      if (!cleaned) {
        alert("Stavka ne smije biti prazna");
        return;
      }
      try {
        await api.json(`/api/boards/${board.id}/todo/${btn.closest(".todo-panel-row").dataset.entryId}`, "PATCH", {
          title: cleaned,
        });
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    };
  });

  document.querySelectorAll("#boardTodoEntries .todo-panel-del").forEach((btn) => {
    btn.onclick = async () => {
      try {
        await api.request(`/api/boards/${board.id}/todo/${btn.dataset.entryId}`, { method: "DELETE" });
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    };
  });

  // 1.16.0: "Pošalji obavijest" in the board To-Do (Nabava) panel — same
  // group fan-out as the global Nabava view's button.
  const todoNotify = document.querySelector("#boardTodoNotify");
  if (todoNotify) {
    todoNotify.onclick = async () => {
      const original = todoNotify.textContent;
      todoNotify.disabled = true;
      todoNotify.textContent = "Šaljem…";
      try {
        const res = await api.json("/api/nabava/notify", "POST", {});
        alert(res.ok ? `✓ Obavijest poslana ${res.notified} korisniku/cima.` : res.reason);
      } catch (error) {
        alert(error.message);
      }
      todoNotify.textContent = original;
      todoNotify.disabled = false;
    };
  }
}

function renderTask(task) {
  const open = state.openTaskId === task.id;
  const items = task.items || [];
  const done = items.filter((i) => i.is_done).length;
  const hasItems = items.length > 0;
  return `
  <div class="task ${task.mentions_me ? "mentions-me" : ""} ${task.completed ? "completed" : ""}" draggable="true" data-task-id="${task.id}">
    <div class="task-head">
      <label class="complete-toggle" title="${hasItems ? "Završava se kad su sve stavke označene" : "Označi kao završeno"}">
        <input type="checkbox" class="toggle-complete" data-task-id="${task.id}" ${task.completed ? "checked" : ""} ${hasItems ? "disabled" : ""} />
      </label>
      <strong class="task-title">${escapeHtml(task.title)}</strong>
    </div>
    ${
      hasItems && !open
        ? `<div class="todo-progress ${task.completed ? "all-done" : ""}">${task.completed ? "✓ " : ""}${done}/${items.length} stavki</div>`
        : ""
    }
    <small>${task.assignee ? `👤 ${escapeHtml(task.assignee)}` : "Nedodijeljeno"}</small>
    ${taskAttribution(task) ? `<small class="muted">${taskAttribution(task)}</small>` : ""}
    ${task.description ? `<p>${escapeHtml(task.description)}</p>` : ""}
    ${
      hasItems && !open
        ? `<div class="todo-list" data-task-id="${task.id}">
      ${items
        .map(
          (i) => `
      <label class="todo-row ${i.is_done ? "is-done" : ""}" data-item-id="${i.id}">
        <input type="checkbox" class="todo-check" data-item-id="${i.id}" ${i.is_done ? "checked" : ""} />
        <span class="todo-row-text">${escapeHtml(i.title)}</span>
      </label>`
        )
        .join("")}
    </div>`
        : ""
    }
    <div class="row">
      <button class="secondary edit-task" data-task-id="${task.id}">Uredi</button>
      <button class="danger delete-task" data-task-id="${task.id}">Obriši</button>
    </div>
    ${
      open
        ? `
      <form class="edit-task-form" data-task-id="${task.id}" style="display:grid;gap:6px;border-top:1px solid var(--line);padding-top:8px;">
        <input name="title" value="${escapeHtml(task.title)}" required />
        <textarea name="description" style="min-height:60px;">${escapeHtml(task.description)}</textarea>
        <select name="assignee_id">
          <option value="">Nedodijeljeno</option>
          ${state.users
            .map(
              (u) =>
                `<option value="${u.id}" ${task.assignee_id === u.id ? "selected" : ""}>${escapeHtml(u.display_name || u.username)}</option>`
            )
            .join("")}
        </select>
        <div class="todo-editor" data-task-id="${task.id}">
          <div class="todo-editor-rows">
            ${items
              .map(
                (i) => `
            <div class="todo-item ${i.is_done ? "is-done" : ""}" data-item-id="${i.id}">
              <input type="checkbox" class="todo-check" data-item-id="${i.id}" ${i.is_done ? "checked" : ""} />
              <input class="todo-text" value="${escapeHtml(i.title)}" />
              <button type="button" class="secondary todo-del" data-item-id="${i.id}" title="Obriši stavku">✕</button>
            </div>`
              )
              .join("")}
          </div>
          <div class="row">
            <input class="todo-new-text" placeholder="Nova stavka popisa..." />
            <button type="button" class="secondary todo-add">Dodaj stavku</button>
          </div>
        </div>
        <div class="row">
          <button type="submit">Spremi</button>
          <button type="button" class="secondary cancel-edit">Odustani</button>
        </div>
      </form>`
        : ""
    }
  </div>`;
}

function bindTaskEvents(board) {
  document.querySelectorAll(".task").forEach((el) => {
    el.addEventListener("dragstart", (e) => {
      state.dragTaskId = Number(el.dataset.taskId);
      e.dataTransfer.setData("text/plain", el.dataset.taskId);
    });
  });
  document.querySelectorAll(".edit-task").forEach((btn) => {
    btn.onclick = () => {
      const id = Number(btn.dataset.taskId);
      state.openTaskId = state.openTaskId === id ? null : id;
      loadBoard();
    };
  });

  // Manual completion toggle — only for tasks without checklist items
  document.querySelectorAll(".toggle-complete").forEach((box) => {
    box.onchange = async () => {
      try {
        await api.json(`/api/tasks/${box.dataset.taskId}/completed`, "PATCH", {});
        await loadBoard();
      } catch (error) {
        box.checked = !box.checked;
        alert(error.message);
      }
    };
  });

  // Checklist items shown directly on the card — one click to tick
  document.querySelectorAll(".todo-list").forEach((list) => {
    const taskId = list.dataset.taskId;
    list.querySelectorAll(".todo-check").forEach((check) => {
      check.onchange = async () => {
        const row = check.closest(".todo-row");
        try {
          await api.json(`/api/tasks/${taskId}/items/${check.dataset.itemId}`, "PATCH", {
            title: row.querySelector(".todo-row-text").textContent,
            is_done: check.checked,
          });
          await loadBoard();
        } catch (error) {
          check.checked = !check.checked;
          alert(error.message);
        }
      };
    });
  });

  // Checklist item interactions (inside the expanded task editor)
  document.querySelectorAll(".todo-editor").forEach((editor) => {
    const taskId = editor.dataset.taskId;
    const rows = editor.querySelectorAll(".todo-item");

    editor.querySelectorAll(".todo-check").forEach((check) => {
      check.onchange = async () => {
        const row = check.closest(".todo-item");
        try {
          await api.json(`/api/tasks/${taskId}/items/${check.dataset.itemId}`, "PATCH", {
            title: row.querySelector(".todo-text").value,
            is_done: check.checked,
          });
          await loadBoard();
        } catch (error) {
          check.checked = !check.checked;
          alert(error.message);
        }
      };
    });

    editor.querySelectorAll(".todo-del").forEach((btn) => {
      btn.onclick = async () => {
        try {
          await api.request(`/api/tasks/${taskId}/items/${btn.dataset.itemId}`, { method: "DELETE" });
          await loadBoard();
        } catch (error) {
          alert(error.message);
        }
      };
    });

    rows.forEach((row) => {
      row.querySelector(".todo-text").onchange = async () => {
        try {
          await api.json(`/api/tasks/${taskId}/items/${row.dataset.itemId}`, "PATCH", {
            title: row.querySelector(".todo-text").value,
            is_done: row.querySelector(".todo-check").checked,
          });
          await loadBoard();
        } catch (error) {
          alert(error.message);
        }
      };
    });

    const addBtn = editor.querySelector(".todo-add");
    const addInput = editor.querySelector(".todo-new-text");
    const addItem = async () => {
      const title = addInput.value.trim();
      if (!title) return;
      try {
        await api.json(`/api/tasks/${taskId}/items`, "POST", { title, is_done: false });
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    };
    addBtn.onclick = addItem;
    addInput.onkeydown = (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        addItem();
      }
    };
  });
  document.querySelectorAll(".delete-task").forEach((btn) => {
    btn.onclick = async () => {
      if (!confirm("Obrisati ovaj zadatak?")) return;
      try {
        await api.request(`/api/tasks/${btn.dataset.taskId}`, { method: "DELETE" });
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    };
  });
  document.querySelectorAll(".edit-task-form").forEach((form) => {
    form.onsubmit = async (event) => {
      event.preventDefault();
      const payload = formData(form);
      const taskId = Number(form.dataset.taskId);
      const task = (state.lastBoard?.columns || []).flatMap((c) => c.tasks).find((t) => t.id === taskId);
      if (!task) return;
      try {
        await api.json(`/api/tasks/${taskId}`, "PATCH", {
          column_id: findTaskColumn(state.lastBoard, taskId),
          title: payload.title,
          description: payload.description || "",
          assignee_id: payload.assignee_id ? Number(payload.assignee_id) : null,
          position: task.position ?? 0,
        });
        state.openTaskId = null;
        await loadBoard();
      } catch (error) {
        alert(error.message);
      }
    };
    form.querySelector(".cancel-edit").onclick = () => {
      state.openTaskId = null;
      loadBoard();
    };
  });
}

function findTaskColumn(board, taskId) {
  if (!board) return 0;
  for (const col of board.columns || []) {
    if (col.tasks.some((t) => t.id === taskId)) return col.id;
  }
  return 0;
}

/* ---------------------------------- files --------------------------------- */

function fileIcon(contentType, name) {
  const ct = (contentType || "").toLowerCase();
  const ext = (name || "").split(".").pop().toLowerCase();
  if (ct.startsWith("image/")) return "🖼️";
  if (ct.includes("pdf") || ext === "pdf") return "📕";
  if (ct.includes("spreadsheet") || ["xls", "xlsx", "csv"].includes(ext)) return "📊";
  if (ct.includes("word") || ["doc", "docx"].includes(ext)) return "📘";
  if (ct.includes("zip") || ["zip", "rar", "7z"].includes(ext)) return "🗜️";
  if (ct.startsWith("video/")) return "🎬";
  if (ct.startsWith("audio/")) return "🎵";
  if (ct.startsWith("text/") || ["txt", "md"].includes(ext)) return "📄";
  return "📎";
}

async function renderFiles() {
  const view = document.querySelector("#filesView");
  if (!view) return;
  view.innerHTML = '<div class="panel">Učitavanje...</div>';
  let files = [];
  try {
    files = await api.json(`/api/projects/${state.project}/files`, "GET");
  } catch (error) {
    view.innerHTML = `<div class="panel">${escapeHtml(error.message)}</div>`;
    return;
  }
  const listUrl = (f) => `/api/files/${f.id}/thumb?token=${encodeURIComponent(api.token)}`;

  const items = files
    .map((f) => {
      const meta = `${formatSize(f.size)} · ${escapeHtml(f.uploaded_by)} · ${formatDate(f.created_at)}`;
      const isImg = (f.content_type || "").toLowerCase().startsWith("image/");
      const actions = `
        <div class="file-actions">
          <button type="button" class="secondary download-file" data-file-id="${f.id}">Preuzmi</button>
          <button type="button" class="secondary rename-file" data-file-id="${f.id}" aria-label="Preimenuj ${escapeHtml(f.name)}">Preimenuj</button>
          <button type="button" class="danger delete-file" data-file-id="${f.id}" aria-label="Obriši ${escapeHtml(f.name)}">Obriši</button>
        </div>`;
      if (state.filesMode === "grid") {
        return `
      <div class="file-card" data-file-id="${f.id}" title="${escapeHtml(f.name)}">
        <div class="file-thumb ${isImg ? "" : "noimg"}">
          ${isImg ? `<img loading="lazy" src="${listUrl(f)}" alt="" />` : `<span class="file-icon">${fileIcon(f.content_type, f.name)}</span>`}
        </div>
        <strong class="file-name">${escapeHtml(f.name)}</strong>
        <small class="muted">${meta}</small>
        ${actions}
      </div>`;
      }
      return `
      <div class="file-item" data-file-id="${f.id}">
        <div class="file-thumb small ${isImg ? "" : "noimg"}">
          ${isImg ? `<img loading="lazy" src="${listUrl(f)}" alt="" />` : `<span class="file-icon">${fileIcon(f.content_type, f.name)}</span>`}
        </div>
        <div class="file-meta">
          <strong>${escapeHtml(f.name)}</strong>
          <small class="muted">${meta}</small>
        </div>
        ${actions}
      </div>`;
    })
    .join("");

  view.innerHTML = `
    <div class="grid">
      <form id="uploadForm" class="panel" style="display:grid;gap:10px;">
        <strong>Datoteke projekta: ${escapeHtml(currentProject()?.name || "")}</strong>
        <input type="file" name="file" required />
        <button type="submit">Učitaj datoteku</button>
      </form>
      <div class="panel files-panel">
        <div class="files-toolbar">
          <strong>Datoteke (${files.length})</strong>
          <div class="view-toggle" role="group">
            <button type="button" class="secondary ${state.filesMode === "list" ? "active" : ""}" data-mode="list" title="Prikaz liste">☰ Lista</button>
            <button type="button" class="secondary ${state.filesMode === "grid" ? "active" : ""}" data-mode="grid" title="Prikaz mreže">▦ Mreža</button>
          </div>
        </div>
        <div class="files ${state.filesMode === "grid" ? "files-grid" : "files-list"}">${items || '<div class="muted">Nema datoteka u ovom projektu.</div>'}</div>
      </div>
    </div>
  `;

  view.querySelectorAll(".view-toggle button").forEach((btn) => {
    btn.onclick = () => {
      state.filesMode = btn.dataset.mode;
      localStorage.setItem("solray_files_mode", state.filesMode);
      renderFiles();
    };
  });

  document.querySelector("#uploadForm").onsubmit = async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const fileInput = form.querySelector('input[type="file"]');
    if (!fileInput.files.length) return;
    const fd = new FormData();
    fd.append("file", fileInput.files[0]);
    fd.append("project_id", String(state.project));
    try {
      await api.upload("/api/files", fd);
      await renderFiles();
    } catch (error) {
      alert(error.message);
    }
  };

  view.querySelectorAll(".delete-file").forEach((btn) => {
    btn.onclick = async () => {
      const file = files.find((item) => String(item.id) === btn.dataset.fileId);
      if (!file || !confirm(`Trajno obrisati datoteku "${file.name}"?`)) return;
      btn.disabled = true;
      try {
        await api.request(`/api/files/${btn.dataset.fileId}`, { method: "DELETE" });
        await renderFiles();
      } catch (error) {
        btn.disabled = false;
        alert(error.message);
      }
    };
  });

  view.querySelectorAll(".rename-file").forEach((btn) => {
    btn.onclick = async () => {
      const file = files.find((item) => String(item.id) === btn.dataset.fileId);
      if (!file) return;
      const name = prompt("Novi naziv datoteke:", file.name);
      if (name === null) return;
      const cleaned = name.trim();
      if (!cleaned) {
        alert("Naziv ne može biti prazan");
        return;
      }
      btn.disabled = true;
      try {
        await api.json(`/api/files/${btn.dataset.fileId}`, "PATCH", { name: cleaned });
        await renderFiles();
      } catch (error) {
        btn.disabled = false;
        alert(error.message);
      }
    };
  });

  view.querySelectorAll(".download-file").forEach((btn) => {
    btn.onclick = async () => {
      const file = files.find((item) => String(item.id) === btn.dataset.fileId);
      if (!file) return;
      try {
        const response = await fetch(`/api/files/${btn.dataset.fileId}/download`, {
          headers: { Authorization: `Bearer ${api.token}` },
        });
        if (!response.ok) throw new Error("Preuzimanje nije uspjelo");
        const blob = await response.blob();
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = file.name;
        a.click();
        URL.revokeObjectURL(url);
      } catch (error) {
        alert(error.message);
      }
    };
  });
}

/* ------------------------------ notifications ------------------------------ */

async function renderNotifications() {
  const view = document.querySelector("#notificationsView");
  if (!view) return;
  view.innerHTML = '<div class="panel">Učitavanje...</div>';
  try {
    state.notifications = await api.json("/api/notifications", "GET");
  } catch (error) {
    view.innerHTML = `<div class="panel">${escapeHtml(error.message)}</div>`;
    return;
  }
  const unread = state.notifications.filter((n) => !n.is_read).length;
  const rows = state.notifications
    .map(
      (n) => `
      <div class="notification ${n.is_read ? "" : "unread"} ${n.task_id && n.board_id ? "clickable" : ""}" ${n.task_id && n.board_id ? `data-task="${n.task_id}" data-board="${n.board_id}"` : ""}>
        <strong>${escapeHtml(n.message)}</strong>
        <small class="muted">${formatDate(n.created_at)}</small>
        ${n.is_read ? "" : `<button class="secondary mark-read" data-id="${n.id}">Označi kao pročitano</button>`}
      </div>`
    )
    .join("");
  view.innerHTML = `<div class="files panel">
    ${state.notifications.length ? `<div class="row" style="justify-content:flex-end;"><button class="secondary" id="markAllRead" ${unread ? "" : "disabled"}>Označi sve kao pročitano${unread ? ` (${unread})` : ""}</button></div>` : ""}
    ${rows || '<div class="muted">Nema obavijesti.</div>'}
  </div>`;

  // 1.14.0: device (web) push — status + enable/test/disable right in Obavijesti.
  // 1.15.1: self-heal — if the browser holds a healthy subscription the server
  // no longer knows about (wiped row, DB restore), re-upload it silently.
  try {
    const wp = await webPushStatus();
    if (wp.subscribed) {
      try {
        const reg = await navigator.serviceWorker.ready;
        const sub = await reg.pushManager.getSubscription();
        const known = await api.json("/api/me/webpush/subscriptions", "GET");
        if (sub && known && Array.isArray(known.endpoints) && !known.endpoints.includes(sub.endpoint)) {
          const j = sub.toJSON();
          await api.json("/api/me/webpush/subscribe", "POST", {
            endpoint: j.endpoint,
            keys_p256dh: j.keys.p256dh,
            keys_auth: j.keys.auth,
          });
        }
      } catch { /* best-effort */ }
    }
    const host = document.createElement("div");
    host.innerHTML = webPushSectionHtml(wp);
    view.prepend(host);
    const msgEl = host.querySelector("#webPushMsg");
    host.querySelector("#webPushOn")?.addEventListener("click", () => enableWebPush(msgEl));
    host.querySelector("#webPushOff")?.addEventListener("click", () => disableWebPush(msgEl));
    host.querySelector("#webPushTest")?.addEventListener("click", () => testWebPush(msgEl));
  } catch { /* push UI is best-effort */ }

  view.querySelectorAll(".notification.clickable").forEach((el) => {
    el.onclick = async (event) => {
      if (event.target.closest(".mark-read")) return;
      await openSearchResult({ type: "task", board_id: Number(el.dataset.board), task_id: Number(el.dataset.task) });
      try {
        await api.request(`/api/notifications/${el.querySelector(".mark-read")?.dataset.id || ""}/read`, { method: "PATCH" });
      } catch { /* id may be empty if already read */ }
      refreshUnreadCount();
    };
  });

  view.querySelectorAll(".mark-read").forEach((btn) => {
    btn.onclick = async () => {
      try {
        await api.request(`/api/notifications/${btn.dataset.id}/read`, { method: "PATCH" });
        await renderNotifications();
        refreshUnreadCount();
      } catch (error) {
        alert(error.message);
      }
    };
  });

  const markAll = view.querySelector("#markAllRead");
  if (markAll) {
    markAll.onclick = async () => {
      try {
        await api.request("/api/notifications/read-all", { method: "PATCH" });
        await renderNotifications();
        refreshUnreadCount();
      } catch (error) {
        alert(error.message);
      }
    };
  }
}

/* ---------------------------------- nabava --------------------------------- */

/* Global shopping list: every Stavka from every board's supplies To-Do list in
   one place. Each row shows the project + board it came from (backend sends
   project_name / board_name), and clicking the origin opens that board. */
/* 1.10.0: plain-text order for the supplier — only OPEN (unchecked) Stavke,
   so re-sending an order never repeats already-bought items. 1.10.1: just the
   item text the user typed — no project/board suffix in the export. */
function buildNabavaOrderText(data) {
  const open = (data?.entries || []).filter((e) => !e.is_done);
  if (!open.length) return "";
  return open.map((e) => `- ${e.title}`).join("\n");
}

async function renderNabava() {
  const view = document.querySelector("#nabavaView");
  if (!view) return;
  view.innerHTML = '<div class="panel">Učitavanje...</div>';
  let data;
  try {
    data = await api.json("/api/nabava", "GET");
  } catch (error) {
    view.innerHTML = `<div class="panel">${escapeHtml(error.message)}</div>`;
    return;
  }
  state.nabava = data;
  const name = data.name || state.defaultTodoListName || "Nabava";
  const openCount = data.entries.filter((e) => !e.is_done).length;
  const rows = data.entries
    .map(
      (e) => `
      <div class="nabava-row ${e.is_done ? "is-done" : ""}" data-entry-id="${e.id}">
        <input type="checkbox" class="nabava-check" data-entry-id="${e.id}" ${e.is_done ? "checked" : ""} title="Označi kao nabavljeno" />
        <div class="nabava-main">
          <button type="button" class="nabava-title" data-entry-id="${e.id}" data-board-id="${e.board_id || ""}" title="Uredi stavku">${escapeHtml(e.title)}</button>
          ${todoAttribution(e) ? `<span class="nabava-attr muted">${todoAttribution(e)}</span>` : ""}
          ${
            e.board_id
              ? `<button type="button" class="link-btn nabava-origin" data-board-id="${e.board_id}" title="Otvori ploču">📁 ${escapeHtml(e.project_name || "")} → ${escapeHtml(e.board_name || "")}</button>`
              : `<span class="nabava-origin muted" title="Dodano ručno u ovom popisu">✍️ Ručno dodano</span>`
          }
        </div>
        <button type="button" class="danger nabava-del" data-entry-id="${e.id}" data-board-id="${e.board_id || ""}" title="Obriši stavku">✕</button>
      </div>`
    )
    .join("");
  view.innerHTML = `<div class="files panel">
    <div class="row" style="justify-content:space-between;align-items:center;">
      <h2 style="margin:0;">🛒 ${escapeHtml(name)}</h2>
      <small class="muted">${openCount ? `${openCount} za nabaviti` : "Sve nabavljeno 🎉"}</small>
    </div>
    <p class="muted" style="font-size:13px;margin:6px 0 0 0;">Zajednički popis svih stavki za nabavu iz svih ploča. Svaka stavka nosi projekt i ploču u kojoj je nastala, a ovdje ih možete i ručno dodati.</p>
    <div class="row nabava-actions">
      <button type="button" id="nabavaNotify" class="primary nabava-notify" title="Obavijesti sve korisnike u Nabava grupi da ima novih stavki">🔔 Pošalji obavijest</button>
      <button type="button" id="nabavaMail" class="secondary" title="Otvori vašu poštu s popisom neoznačenih stavki">✉️ Pošalji e-mailom</button>
      <button type="button" id="nabavaClear" class="danger" title="Obriši sve označene (nabavljene) stavke iz svih popisa">Izbriši Preuzete Stvari</button>
    </div>
    <form id="nabavaAddForm" class="row nabava-add-row">
      <input name="title" placeholder="Dodaj stavku ručno…" maxlength="255" required />
      <button type="submit" class="primary">Dodaj</button>
    </form>
    <div class="nabava-list">${rows || '<div class="muted">Nema stavki za nabavu. Dodajte ih u To-Do popisu na bilo kojoj ploči ili ručno ovdje.</div>'}</div>
  </div>`;

  // 1.16.0: "Pošalji obavijest" — one tap notifies the whole Nabava group
  // (managed by the admin in Postavke) that there are new items.
  const notifyBtn = view.querySelector("#nabavaNotify");
  if (notifyBtn) {
    notifyBtn.onclick = async () => {
      const original = notifyBtn.textContent;
      notifyBtn.disabled = true;
      notifyBtn.textContent = "Šaljem…";
      try {
        const res = await api.json("/api/nabava/notify", "POST", {});
        alert(res.ok ? `✓ Obavijest poslana ${res.notified} korisniku/cima.` : res.reason);
      } catch (error) {
        alert(error.message);
      }
      notifyBtn.textContent = original;
      notifyBtn.disabled = false;
    };
  }

  // 1.9.2: edit a Stavka's text after creation (typos, wrong quantities) —
  // prompt matches the project/board rename convention. Works for both
  // manually added and board-origin entries (routes to the right endpoint).
  const editEntry = async (entryId, boardId, currentTitle) => {
    const title = prompt("Uredi stavku:", currentTitle);
    if (title === null) return;
    const cleaned = title.trim();
    if (!cleaned) {
      alert("Stavka ne smije biti prazna");
      return;
    }
    try {
      if (boardId) {
        await api.json(`/api/boards/${boardId}/todo/${entryId}`, "PATCH", { title: cleaned });
      } else {
        await api.json(`/api/nabava/items/${entryId}`, "PATCH", { title: cleaned });
      }
    } catch (error) {
      alert(error.message);
    }
    await renderNabava();
  };

  // 1.10.0: export the OPEN items as a mailto: draft (opens the user's own
  // mail app with the list prefilled in the body). The text is also copied to
  // the clipboard as a fallback — paste it if the mail app does not open.
  const mailBtn = view.querySelector("#nabavaMail");
  if (mailBtn) {
    mailBtn.onclick = async () => {
      const text = buildNabavaOrderText(data);
      if (!text) {
        alert("Nema otvorenih (neoznačenih) stavki za slanje.");
        return;
      }
      const subject = `${name} — ${new Date().toLocaleDateString("hr-HR")}`;
      let copied = false;
      try {
        await navigator.clipboard.writeText(text);
        copied = true;
      } catch (_) {}
      if (!copied) prompt("Kopirajte popis za nabavu (Ctrl+C):", text);
      const original = mailBtn.textContent;
      mailBtn.textContent = "✓ Kopirano — otvaram poštu…";
      mailBtn.disabled = true;
      window.open(`mailto:?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(text)}`, "_self");
      setTimeout(() => {
        mailBtn.textContent = original;
        mailBtn.disabled = false;
      }, 2500);
    };
  }

  // 1.10.0: housekeeping — delete every checked Stavka from ALL lists.
  const clearBtn = view.querySelector("#nabavaClear");
  if (clearBtn) {
    clearBtn.disabled = !data.entries.some((e) => e.is_done);
    clearBtn.onclick = async () => {
      if (!confirm("Obrisati SVE označene (nabavljene) stavke iz svih popisa? Ova radnja se ne može poništiti.")) return;
      try {
        await api.request("/api/nabava/checked", { method: "DELETE" });
        await renderNabava();
      } catch (error) {
        alert(error.message);
      }
    };
  }

  const addForm = view.querySelector("#nabavaAddForm");
  if (addForm) {
    addForm.onsubmit = async (event) => {
      event.preventDefault();
      const title = new FormData(addForm).get("title").trim();
      if (!title) return;
      try {
        await api.json("/api/nabava/items", "POST", { title });
        await renderNabava();
      } catch (error) {
        alert(error.message);
      }
    };
  }

  view.querySelectorAll(".nabava-check").forEach((check) => {
    check.onchange = async () => {
      const row = check.closest(".nabava-row");
      const title = row.querySelector(".nabava-title").textContent;
      const boardId = row.querySelector(".nabava-origin").dataset.boardId || null;
      try {
        if (boardId) {
          await api.json(`/api/boards/${boardId}/todo/${check.dataset.entryId}`, "PATCH", {
            title,
            is_done: check.checked,
          });
        } else {
          await api.json(`/api/nabava/items/${check.dataset.entryId}`, "PATCH", { is_done: check.checked });
        }
        await renderNabava();
      } catch (error) {
        check.checked = !check.checked;
        alert(error.message);
      }
    };
  });

  view.querySelectorAll(".nabava-origin").forEach((btn) => {
    btn.onclick = () => {
      const boardId = Number(btn.dataset.boardId);
      if (boardId) openBoard(boardId);
    }; // openBoard also fixes state.project from allBoards()
  });

  view.querySelectorAll(".nabava-title").forEach((btn) => {
    btn.onclick = () => {
      const row = btn.closest(".nabava-row");
      editEntry(Number(btn.dataset.entryId), btn.dataset.boardId || null, row.querySelector(".nabava-title").textContent);
    };
  });

  view.querySelectorAll(".nabava-del").forEach((btn) => {
    btn.onclick = async () => {
      try {
        if (btn.dataset.boardId) {
          await api.request(`/api/boards/${btn.dataset.boardId}/todo/${btn.dataset.entryId}`, { method: "DELETE" });
        } else {
          await api.request(`/api/nabava/items/${btn.dataset.entryId}`, { method: "DELETE" });
        }
        await renderNabava();
      } catch (error) {
        alert(error.message);
      }
    };
  });
}

/* --------------------------------- settings -------------------------------- */

/** Inline feedback inside a settings card (1.18.0 — replaces alert() popups). */
function setSettingStatus(card, text, ok = true) {
  const el = card ? card.querySelector(".setting-status") : null;
  if (!el) return;
  el.textContent = text;
  el.classList.toggle("bad", !ok);
  clearTimeout(el._timer);
  el._timer = setTimeout(() => {
    el.textContent = "";
  }, 4500);
}

/** One card of the 1.18.0 settings grid: icon, title, hint, body, status line. */
function settingCard({ icon, title, hint = "", body = "", wide = false }) {
  return `
    <section class="panel setting-card${wide ? " wide" : ""}">
      <header class="setting-head">
        <span class="setting-icon" aria-hidden="true">${icon}</span>
        <div>
          <h2>${escapeHtml(title)}</h2>
          ${hint ? `<p>${hint}</p>` : ""}
        </div>
      </header>
      ${body}
      <p class="setting-status"></p>
    </section>`;
}

async function renderSettings() {
  const view = document.querySelector("#settingsView");
  if (!view) return;
  view.innerHTML = '<div class="panel">Učitavanje...</div>';

  const admin = !!state.me?.is_admin;
  const users = state.users || [];
  const group = (state.nabavaGroup || []).map(Number);

  /* Every settings write needs app_name (required by the API), so always send
     the SAVED name — never whatever is currently typed in the form. */
  const saveSettings = (patch) =>
    api.json("/api/settings", "PUT", { app_name: state.appName || "Private Workspace", ...patch });

  /** Re-read every settings value into state, then redraw the grid. */
  const reloadSettings = async () => {
    try {
      const s = await api.json("/api/settings", "GET");
      state.appName = s.app_name || state.appName;
      state.defaultColumns = Array.isArray(s.default_columns) ? s.default_columns : state.defaultColumns;
      state.defaultTodoListName = s.default_todo_list || state.defaultTodoListName;
      state.nabavaGroup = Array.isArray(s.nabava_group) ? s.nabava_group.map(Number) : [];
    } catch (error) {
      /* keep what we have — the grid stays usable */
    }
    renderSettings();
  };

  const appNameCard = admin
    ? settingCard({
        icon: "✦",
        title: "Naziv aplikacije",
        hint: "Prikazuje se na stranici za prijavu i u vrhu aplikacije.",
        body: `
      <form id="appNameForm" class="row">
        <input name="app_name" placeholder="npr. My Team Firme" value="${escapeHtml(state.appName || "")}" maxlength="80" required />
        <button type="submit" class="primary">Spremi naziv</button>
      </form>`,
      })
    : "";

  const columnsCard = admin
    ? settingCard({
        icon: "▦",
        title: "Zadane kolone novih ploča",
        hint: "Svaka nova ploča automatski dobije ove kolone. Kliknite naziv i uredite ga.",
        wide: true,
        body: `
      <form id="defaultColumnsForm">
        <button type="button" class="chip-add" id="addColumnChip">＋ Dodaj novu kolonu</button>
        <div class="chip-list" id="columnChips"></div>
        <div class="chip-hint"><span>Najviše 20 kolona · naziv do 80 znakova</span><span id="columnCount"></span></div>
        <button type="submit" class="primary setting-save">Spremi kolone</button>
      </form>`,
      })
    : "";

  const todoCard = admin
    ? settingCard({
        icon: "🛒",
        title: "Naziv To-Do popisa za nabavu",
        hint: `To-Do popis na svakoj ploči i gumb u lijevoj traci (trenutno: „${escapeHtml(state.defaultTodoListName || "Nabava")}”).`,
        body: `
      <form id="defaultTodoListForm" class="row">
        <input name="todo_name" placeholder="npr. Nabava" value="${escapeHtml(state.defaultTodoListName || "Nabava")}" maxlength="80" required />
        <button type="submit" class="primary">Spremi naziv</button>
      </form>`,
      })
    : "";

  const groupCard = admin
    ? settingCard({
        icon: "🔔",
        title: "Nabava grupa",
        hint: "Korisnici koji primaju obavijest „Dodane nove stvari za nabavu” kad netko klikne „Pošalji obavijest” na Nabava popisu ili To-Do panelu ploče.",
        wide: true,
        body: `
      <div id="nabavaGroupList" class="files"></div>
      <form id="nabavaGroupForm" class="row">
        <select name="user_id" required>
          <option value="">Dodaj korisnika u grupu…</option>
          ${users
            .filter((u) => !group.includes(u.id))
            .map((u) => `<option value="${u.id}">${escapeHtml(u.display_name || u.username)} (@${escapeHtml(u.username)})</option>`)
            .join("")}
        </select>
        <button type="submit" class="primary">Dodaj u grupu</button>
      </form>`,
      })
    : "";

  const usersCard = admin
    ? settingCard({
        icon: "👥",
        title: "Korisnici",
        hint: "Novi članovi tima odmah se mogu prijaviti i na webu i u mobilnoj aplikaciji.",
        wide: true,
        body: `
      <form id="createUserForm" class="row">
        <input name="username" placeholder="Korisničko ime" required />
        <input name="display_name" placeholder="Prikazano ime" required />
        <input name="password" type="password" placeholder="Lozinka (min. 8 znakova)" required />
        <button type="submit" class="primary">Dodaj korisnika</button>
      </form>
      <div class="files" id="userList"></div>`,
      })
    : "";

  view.innerHTML = `
    <div class="settings-head">
      <div>
        <h1>Postavke</h1>
        <p>Naziv, kolone, nabava i korisnici — sve na jednom mjestu.</p>
      </div>
      <span class="settings-tag">${escapeHtml(state.appName || "")}</span>
    </div>
    <div class="settings-grid">
      ${appNameCard}
      ${columnsCard}
      ${todoCard}
      ${groupCard}
      ${usersCard}
      <section class="panel setting-card">
        <header class="setting-head">
          <span class="setting-icon" aria-hidden="true">📱</span>
          <div>
            <h2>Mobilna aplikacija</h2>
            <p>Android aplikacija nudi iste mogućnosti kao web: ploče, Nabava, datoteke, pretraga i obavijesti — s istim postavkama i podacima.</p>
          </div>
        </header>
        <a class="button-link" href="https://github.com/LotDog1984/solray/releases/latest" target="_blank" rel="noopener">Preuzmi najnoviji APK ↗</a>
        <p class="setting-status"></p>
      </section>
    </div>`;

  // ---- Naziv aplikacije ------------------------------------------------------
  const appNameForm = document.querySelector("#appNameForm");
  if (appNameForm) {
    appNameForm.onsubmit = async (event) => {
      event.preventDefault();
      const card = appNameForm.closest(".setting-card");
      const name = (new FormData(appNameForm).get("app_name") || "").trim();
      try {
        const settings = await saveSettings({ app_name: name });
        state.appName = settings.app_name;
        applyAppName();
        document.querySelector(".settings-tag").textContent = state.appName || "";
        setSettingStatus(card, "✓ Naziv spremljen.");
      } catch (error) {
        setSettingStatus(card, error.message, false);
      }
    };
  }

  // ---- Zadane kolone: editable chips (1.18.0) --------------------------------
  const columnsForm = document.querySelector("#defaultColumnsForm");
  if (columnsForm) {
    const card = columnsForm.closest(".setting-card");
    const chips = document.querySelector("#columnChips");
    const countEl = document.querySelector("#columnCount");
    let values = [...(state.defaultColumns || [])];

    const renderChips = () => {
      chips.innerHTML = values.length
        ? values
            .map(
              (name, i) => `
        <div class="chip" data-index="${i}">
          <span class="chip-index">${i + 1}</span>
          <input value="${escapeHtml(name)}" maxlength="80" placeholder="Naziv kolone" aria-label="Naziv kolone ${i + 1}" />
          <button type="button" class="chip-remove" title="Ukloni kolonu" aria-label="Ukloni kolonu">✕</button>
        </div>`
            )
            .join("")
        : '<div class="chip-empty">Još nema kolona — dodajte prvu.</div>';
      countEl.textContent = `${values.length} / 20`;
      chips.querySelectorAll(".chip").forEach((row) => {
        const i = Number(row.dataset.index);
        const field = row.querySelector("input");
        field.oninput = () => {
          values[i] = field.value;
        };
        field.onkeydown = (e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            columnsForm.requestSubmit();
          }
        };
        row.querySelector(".chip-remove").onclick = () => {
          values.splice(i, 1);
          renderChips();
        };
      });
    };

    /** Pull whatever is typed in the DOM back into `values` (indexes move). */
    const readChips = () => {
      chips.querySelectorAll(".chip").forEach((row) => {
        values[Number(row.dataset.index)] = row.querySelector("input").value;
      });
      return values;
    };

    const addChip = () => {
      if (readChips().length >= 20) {
        setSettingStatus(card, "Najviše 20 kolona.", false);
        return;
      }
      values.push("");
      renderChips();
      const last = chips.querySelector(".chip:last-child input");
      if (last) last.focus();
      setSettingStatus(card, "");
    };

    document.querySelector("#addColumnChip").onclick = addChip;
    chips.onclick = (event) => {
      if (event.target.closest(".chip-empty")) addChip();
    };

    columnsForm.onsubmit = async (event) => {
      event.preventDefault();
      const names = readChips()
        .map((n) => (n || "").trim())
        .filter(Boolean);
      if (!names.length) {
        setSettingStatus(card, "Potrebna je barem jedna kolona.", false);
        return;
      }
      try {
        const settings = await saveSettings({ default_columns: names });
        state.defaultColumns = Array.isArray(settings.default_columns) ? settings.default_columns : names;
        values = [...state.defaultColumns];
        renderChips();
        setSettingStatus(card, "✓ Kolone spremljene — nove ploče koriste ovaj popis.");
      } catch (error) {
        setSettingStatus(card, error.message, false);
      }
    };

    renderChips();
  }

  // ---- Naziv To-Do popisa za nabavu ------------------------------------------
  const todoListForm = document.querySelector("#defaultTodoListForm");
  if (todoListForm) {
    todoListForm.onsubmit = async (event) => {
      event.preventDefault();
      const todoName = (new FormData(todoListForm).get("todo_name") || "").trim();
      try {
        const settings = await saveSettings({ default_todo_list: todoName });
        state.defaultTodoListName = settings.default_todo_list;
        renderSettings();
      } catch (error) {
        setSettingStatus(todoListForm.closest(".setting-card"), error.message, false);
      }
    };
  }

  // ---- Nabava grupa (1.16.0) -------------------------------------------------
  const groupList = document.querySelector("#nabavaGroupList");
  if (groupList) {
    const card = groupList.closest(".setting-card");
    const members = users.filter((u) => group.includes(u.id));
    groupList.innerHTML = members.length
      ? members
          .map(
            (u) => `
        <div class="file-item">
          <strong>${escapeHtml(u.display_name || u.username)}</strong>
          <small class="muted">@${escapeHtml(u.username)}${u.id === state.me?.id ? " · to ste vi" : ""}</small>
          <button class="danger remove-group-user" data-id="${u.id}">Ukloni</button>
        </div>`
          )
          .join("")
      : '<small class="muted">Grupa je prazna — nitko neće primiti obavijest dok ne dodate korisnike.</small>';

    const saveNabavaGroup = async (ids) => {
      try {
        const settings = await saveSettings({ nabava_group: ids });
        state.nabavaGroup = Array.isArray(settings.nabava_group) ? settings.nabava_group.map(Number) : [];
        renderSettings();
      } catch (error) {
        setSettingStatus(card, error.message, false);
      }
    };

    groupList.querySelectorAll(".remove-group-user").forEach((btn) => {
      btn.onclick = () => saveNabavaGroup(group.filter((id) => id !== Number(btn.dataset.id)));
    });

    const groupForm = document.querySelector("#nabavaGroupForm");
    if (groupForm) {
      groupForm.onsubmit = async (event) => {
        event.preventDefault();
        const uid = Number(new FormData(groupForm).get("user_id"));
        if (!uid) return;
        await saveNabavaGroup(group.includes(uid) ? group : [...group, uid]);
      };
    }
  }

  // ---- Korisnici -------------------------------------------------------------
  if (admin) {
    const list = document.querySelector("#userList");
    list.innerHTML = users
      .map(
        (u) => `
        <div class="file-item">
          <strong>${escapeHtml(u.display_name || u.username)}</strong>
          <small class="muted">@${escapeHtml(u.username)}${u.is_admin ? " · admin" : ""}</small>
          ${u.id === state.me.id ? '<small class="muted">to ste vi</small>' : `<button class="danger delete-user" data-id="${u.id}">Obriši</button>`}
        </div>`
      )
      .join("");

    list.querySelectorAll(".delete-user").forEach((btn) => {
      btn.onclick = async () => {
        const card = list.closest(".setting-card");
        if (!confirm("Obrisati ovog korisnika? Njegovi zadaci ostaju, ali bez dodjele.")) return;
        try {
          await api.request(`/api/users/${btn.dataset.id}`, { method: "DELETE" });
          state.users = await api.json("/api/users", "GET");
          await reloadSettings();
        } catch (error) {
          setSettingStatus(card, error.message, false);
        }
      };
    });

    document.querySelector("#createUserForm").onsubmit = async (event) => {
      event.preventDefault();
      const form = event.currentTarget; // capture now — it's nulled after any await
      const card = form.closest(".setting-card");
      const payload = formData(form);
      try {
        await api.json("/api/users", "POST", payload);
        state.users = await api.json("/api/users", "GET");
        await reloadSettings();
      } catch (error) {
        setSettingStatus(card, error.message, false);
      }
    };
  }
}

/* ------------------------------- initialization ---------------------------- */

boot();
