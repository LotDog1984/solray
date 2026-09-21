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
  dragTaskId: null,
  openTaskId: null,
  lastBoard: null,
  searchQuery: "",
  searchResults: null,
  searchLoading: false,
  unreadCount: 0,
};

const app = document.querySelector("#app");

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

function renderSidebar() {
  const sidebar = document.querySelector("#sidebar");
  if (!sidebar) return;

  let layerHtml = "";
  if (state.layer === "projects") {
    const rows = state.projects
      .map(
        (project) => `
        <div class="side-item">
          <div class="side-row">
            <button class="side-name" data-open-project="${project.id}">${escapeHtml(project.name)}</button>
            <button class="icon-action edit-toggle" title="Uredi projekt">✎</button>
          </div>
          <div class="edit-menu" hidden>
            <button class="menu-rename" data-project-id="${project.id}">Preimenuj</button>
            <button class="menu-delete danger" data-project-id="${project.id}">Obriši</button>
          </div>
        </div>`
      )
      .join("");
    layerHtml = `
      <div class="side-label">Projekti</div>
      <div class="side-list">${rows || '<div class="side-empty">Nema projekata</div>'}</div>
      <form id="newProjectForm" class="side-form">
        <input name="name" placeholder="Novi projekt..." required />
        <button type="submit" title="Dodaj projekt">+</button>
      </form>
      <button class="secondary notif-btn ${state.view === "notifications" ? "active" : ""}" id="navNotifications">Obavijesti${state.unreadCount ? `<span class="badge">${state.unreadCount > 99 ? "99+" : state.unreadCount}</span>` : ""}</button>`;
  } else {
    const project = currentProject();
    const rows = (project?.boards || [])
      .map(
        (board) => `
        <div class="side-item">
          <div class="side-row">
            <button class="side-name ${state.board === board.id ? "active" : ""}" data-open-board="${board.id}">${escapeHtml(board.name)}</button>
            <button class="icon-action edit-toggle" title="Uredi ploču">✎</button>
          </div>
          <div class="edit-menu" hidden>
            <button class="menu-rename" data-board-id="${board.id}">Preimenuj</button>
            <button class="menu-delete danger" data-board-id="${board.id}">Obriši</button>
          </div>
        </div>`
      )
      .join("");
    layerHtml = `
      <button class="side-back" id="sideBackToProjects">← Projekti</button>
      <div class="side-label">${escapeHtml(project?.name || "Ploče")}</div>
      <div class="side-list">${rows || '<div class="side-empty">Nema ploča</div>'}</div>
      ${project ? `
      <form id="newBoardForm" class="side-form">
        <input name="name" placeholder="Nova ploča..." required />
        <button type="submit" title="Dodaj ploču">+</button>
      </form>` : ""}`;
  }

  sidebar.innerHTML = `
    <div class="brand-row">
      <div class="brand">${escapeHtml(state.appName || "Private Workspace")}</div>
      <div id="versionBadge" class="version-badge" title="Verzija aplikacije"></div>
    </div>
    <div style="color:#94a3b8;font-size:13px;">Prijavljen: ${escapeHtml(state.me?.display_name || state.me?.username || "")}</div>
    <form id="sideSearchForm" class="side-search">
      <input id="searchInput" type="search" placeholder="Traži projekte, ploče, zadatke…" value="${escapeHtml(state.searchQuery || "")}" autocomplete="off" />
    </form>
    <div class="side-layer">${layerHtml}</div>
    <div style="display:grid;gap:8px;">
      <button class="secondary" id="navSettings">Postavke</button>
      <button class="danger" id="logoutBtn">Odjava</button>
    </div>
  `;
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
      if (el && v) el.textContent = `v${v.trim()}`;
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

  const settingsBtn = sidebar.querySelector("#navSettings");
  if (settingsBtn) {
    settingsBtn.onclick = () => {
      state.layer = "app";
      state.view = "settings";
      renderView();
    };
  }

  const logoutBtn = sidebar.querySelector("#logoutBtn");
  if (logoutBtn) logoutBtn.onclick = () => logout();
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
    if (result.type === "project" && result.project_id) {
      goBoards(result.project_id);
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
    content.innerHTML = '<div id="notificationsView"></div>';
    renderNotifications(); // Obavijesti live on the main page
    return;
  }

  const heading = board?.name || state.appName || "Private Workspace";
  // Board tabs: only Ploča and Datoteke (Postavke lives in the left bar,
  // Obavijesti on the main page).
  const tabs = `
    <div class="topbar">
      <h1>${escapeHtml(heading)}</h1>
      <div class="tabs">
        <button class="${state.view === "kanban" ? "active" : ""}" data-view="kanban">Ploča</button>
        <button class="${state.view === "files" ? "active" : ""}" data-view="files">Datoteke</button>
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
              r.type === "project" ? "Projekt" : r.type === "board" ? "Ploča" : "Zadatak"
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
    renderKanban(board);
    bindTaskEvents(board);
  } catch (error) {
    kanban.innerHTML = `<div class="panel">${escapeHtml(error.message)}</div>`;
  }
}

function renderKanban(board) {
  const kanban = document.querySelector("#kanban");
  if (!kanban) return;
  state.board = board.id;

  const columnsHtml = board.columns
    .map((col) => {
      const tasks = col.tasks.map((task) => renderTask(task)).join("");
      return `
      <div class="column" data-column-id="${col.id}">
        <h2>${escapeHtml(col.name)} <small style="color:var(--muted);">(${col.tasks.length})</small></h2>
        <div class="tasks" data-tasks-for="${col.id}">${tasks}</div>
        <form class="new-task-form" data-column-id="${col.id}" style="margin-top:10px;display:grid;gap:6px;">
          <input name="title" placeholder="Novi zadatak..." required />
          <textarea name="description" placeholder="Opis (@ime za tagiranje)..." style="min-height:50px;"></textarea>
          <div class="todo-creator">
            <div class="todo-creator-rows"></div>
            <button type="button" class="secondary add-todo-row">+ Stavka popisa</button>
          </div>
          <div class="row">
            <select name="assignee_id" style="flex:2;">
              <option value="">Nedodijeljeno</option>
              ${state.users
                .map(
                  (u) =>
                    `<option value="${u.id}">${escapeHtml(u.display_name || u.username)}</option>`
                )
                .join("")}
            </select>
            <button type="submit" style="flex:1;">Dodaj</button>
          </div>
        </form>
      </div>`;
    })
    .join("");

  kanban.innerHTML =
    columnsHtml +
    `
    <div class="column" style="background:transparent;border-style:dashed;">
      <form id="newColumnForm" style="display:grid;gap:8px;">
        <input name="name" placeholder="Nova kolona..." required />
        <button type="submit" class="secondary">Dodaj kolonu</button>
      </form>
    </div>`;

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
        await api.json("/api/tasks", "POST", {
          column_id: columnId,
          title: payload.title,
          description: payload.description || "",
          assignee_id: payload.assignee_id ? Number(payload.assignee_id) : null,
          position: column ? column.tasks.filter((t) => !t.completed).length : 0,
          items,
        });
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
    ${task.description ? `<p>${escapeHtml(task.description)}</p>` : ""}
    ${
      hasItems && !open
        ? `<div class="todo-progress ${task.completed ? "all-done" : ""}">${task.completed ? "✓ " : ""}${done}/${items.length} stavki</div>`
        : ""
    }
    <small>${task.assignee ? `👤 ${escapeHtml(task.assignee)}` : "Nedodijeljeno"}</small>
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
            <div class="todo-item" data-item-id="${i.id}">
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

async function renderFiles() {
  const view = document.querySelector("#filesView");
  if (!view) return;
  view.innerHTML = '<div class="panel">Učitavanje...</div>';
  let files = [];
  try {
    files = await api.json("/api/files", "GET");
  } catch (error) {
    view.innerHTML = `<div class="panel">${escapeHtml(error.message)}</div>`;
    return;
  }

  const rows = files
    .map(
      (f) => `
      <div class="file-item">
        <strong>${escapeHtml(f.name)}</strong>
        <small class="muted">${formatSize(f.size)} · ${escapeHtml(f.uploaded_by)} · ${formatDate(f.created_at)}</small>
        <button class="secondary download-file" data-file-id="${f.id}">Preuzmi</button>
      </div>`
    )
    .join("");

  view.innerHTML = `
    <div class="grid">
      <form id="uploadForm" class="panel" style="display:grid;gap:10px;">
        <input type="file" name="file" required />
        <button type="submit">Učitaj datoteku</button>
      </form>
      <div class="files panel">
        ${rows || '<div class="muted">Nema datoteka.</div>'}
      </div>
    </div>
  `;

  document.querySelector("#uploadForm").onsubmit = async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const fileInput = form.querySelector('input[type="file"]');
    if (!fileInput.files.length) return;
    const fd = new FormData();
    fd.append("file", fileInput.files[0]);
    try {
      await api.upload("/api/files", fd);
      await renderFiles();
    } catch (error) {
      alert(error.message);
    }
  };

  view.querySelectorAll(".download-file").forEach((btn) => {
    btn.onclick = async () => {
      try {
        const response = await fetch(`/api/files/${btn.dataset.fileId}/download`, {
          headers: { Authorization: `Bearer ${api.token}` },
        });
        if (!response.ok) throw new Error("Preuzimanje nije uspjelo");
        const blob = await response.blob();
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = btn.closest(".file-item").querySelector("strong").textContent;
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

/* --------------------------------- settings -------------------------------- */

async function renderSettings() {
  const view = document.querySelector("#settingsView");
  if (!view) return;
  view.innerHTML = '<div class="panel">Učitavanje...</div>';

  const adminSection = state.me?.is_admin
    ? `
      <div class="panel" style="margin-top:16px;">
        <h2 style="margin-top:0;">Korisnici</h2>
        <form id="createUserForm" class="row" style="margin-bottom:14px;">
          <input name="username" placeholder="Korisničko ime" required />
          <input name="display_name" placeholder="Prikazano ime" required />
          <input name="password" type="password" placeholder="Lozinka (min. 8 znakova)" required />
          <button type="submit">Dodaj korisnika</button>
        </form>
        <div class="files" id="userList"></div>
      </div>`
    : "";

  const appNameSection = state.me?.is_admin
    ? `
    <div class="panel">
      <h2 style="margin-top:0;">Naziv aplikacije</h2>
      <form id="appNameForm" class="row">
        <input name="app_name" placeholder="npr. SolRay Firm" value="${escapeHtml(state.appName || "")}" maxlength="80" required />
        <button type="submit">Spremi naziv</button>
      </form>
      <p class="muted" style="font-size:13px;">Naziv se prikazuje na stranici za prijavu i u gornjem lijevom kutu aplikacije.</p>
    </div>`
    : "";

  const columnsSection = state.me?.is_admin
    ? `
    <div class="panel">
      <h2 style="margin-top:0;">Zadane kolone novih ploča</h2>
      <form id="defaultColumnsForm" style="display:grid;gap:10px;">
        <textarea name="columns" placeholder="Jedna kolona po retku..." style="min-height:110px;">${escapeHtml((state.defaultColumns || []).join("\n"))}</textarea>
        <button type="submit">Spremi kolone</button>
      </form>
      <p class="muted" style="font-size:13px;">Svaka nova ploča automatski dobije ove kolone (jedan naziv po retku, najviše 20).</p>
    </div>`
    : "";

  view.innerHTML = `
    ${appNameSection}
    ${columnsSection}
    <div class="panel">
      <h2 style="margin-top:0;">Moj ntfy topic</h2>
      <form id="ntfyForm" class="row">
        <input name="topic" placeholder="npr. branko-private-123" value="${escapeHtml(state.me?.ntfy_topic || "")}" />
        <button type="submit">Spremi</button>
        <button type="button" class="secondary" id="ntfyTest">Testiraj</button>
      </form>
      <p class="muted" style="font-size:13px;">Unesite isti topic i u ntfy aplikaciji na telefonu (npr. https://ntfy.sh/vas-topic) pa kliknite „Testiraj” — na telefon bi trebala stići obavijest.</p>
      <div id="ntfyTestResult" class="muted" style="font-size:13px;"></div>
    </div>
    ${adminSection}
  `;

  document.querySelector("#ntfyForm").onsubmit = async (event) => {
    event.preventDefault();
    const topic = new FormData(event.currentTarget).get("topic");
    try {
      state.me = await api.json("/api/me/ntfy", "PATCH", { topic: topic || null });
      alert("Topic spremljen.");
    } catch (error) {
      alert(error.message);
    }
  };

  document.querySelector("#ntfyTest").onclick = async () => {
    const out = document.querySelector("#ntfyTestResult");
    out.textContent = "Slanje...";
    try {
      const res = await api.json("/api/me/ntfy/test", "POST", {});
      out.textContent = res.ok ? `✓ Poslano na topic „${res.topic}” — provjerite telefon.` : `✗ ${res.reason}`;
    } catch (error) {
      out.textContent = `✗ ${error.message}`;
    }
  };

  const appNameForm = document.querySelector("#appNameForm");
  if (appNameForm) {
    appNameForm.onsubmit = async (event) => {
      event.preventDefault();
      const name = new FormData(event.currentTarget).get("app_name");
      try {
        const settings = await api.json("/api/settings", "PUT", { app_name: name });
        state.appName = settings.app_name;
        applyAppName();
        alert("Naziv spremljen.");
      } catch (error) {
        alert(error.message);
      }
    };
  }

  const columnsForm = document.querySelector("#defaultColumnsForm");
  if (columnsForm) {
    columnsForm.onsubmit = async (event) => {
      event.preventDefault();
      const raw = new FormData(event.currentTarget).get("columns") || "";
      const names = raw.split("\n").map((line) => line.trim()).filter(Boolean);
      try {
        const settings = await api.json("/api/settings", "PUT", {
          app_name: state.appName || "Private Workspace",
          default_columns: names,
        });
        state.defaultColumns = settings.default_columns;
        alert("Kolone spremljene. Nove ploče koristit će ove kolone.");
      } catch (error) {
        alert(error.message);
      }
    };
  }

  if (state.me?.is_admin) {
    const list = document.querySelector("#userList");
    const renderList = (users) => {
      list.innerHTML = users
        .map(
          (u) => `
          <div class="file-item">
            <strong>${escapeHtml(u.display_name || u.username)}</strong>
            <small class="muted">@${escapeHtml(u.username)}${u.is_admin ? " · admin" : ""}</small>
            ${
              u.id === state.me.id
                ? '<small class="muted">to ste vi</small>'
                : `<button class="danger delete-user" data-id="${u.id}">Obriši</button>`
            }
          </div>`
        )
        .join("");
      list.querySelectorAll(".delete-user").forEach((btn) => {
        btn.onclick = async () => {
          if (!confirm("Obrisati ovog korisnika?")) return;
          try {
            await api.request(`/api/users/${btn.dataset.id}`, { method: "DELETE" });
            state.users = await api.json("/api/users", "GET");
            renderList(state.users);
          } catch (error) {
            alert(error.message);
          }
        };
      });
    };
    renderList(state.users);

    document.querySelector("#createUserForm").onsubmit = async (event) => {
      event.preventDefault();
      const form = event.currentTarget; // capture now — it's nulled after any await
      const payload = formData(form);
      try {
        await api.json("/api/users", "POST", payload);
        state.users = await api.json("/api/users", "GET");
        form.reset();
        renderList(state.users);
      } catch (error) {
        alert(error.message);
      }
    };
  }
}

/* ------------------------------- initialization ---------------------------- */

boot();
