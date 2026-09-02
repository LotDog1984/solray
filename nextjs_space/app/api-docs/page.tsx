export const dynamic = 'force-dynamic';

export default function ApiDocsPage() {
  const endpoints = [
    { method: 'POST', path: '/api/signup', desc: 'First-run admin registration (disabled after first admin created)', auth: false },
    { method: 'POST', path: '/api/auth/login', desc: 'Login with email/password', auth: false },
    { method: 'POST', path: '/api/auth/mobile-login', desc: 'Mobile login - returns Bearer token', auth: false },
    { method: 'GET', path: '/api/auth/check-setup', desc: 'Check if admin account exists', auth: false },
    { method: 'GET', path: '/api/users', desc: 'List all users', auth: true },
    { method: 'POST', path: '/api/users', desc: 'Create user (admin only)', auth: true },
    { method: 'PATCH', path: '/api/users/:id', desc: 'Update user', auth: true },
    { method: 'POST', path: '/api/users/push-token', desc: 'Register Expo push token', auth: true },
    { method: 'DELETE', path: '/api/users/push-token/:token', desc: 'Unregister push token', auth: true },
    { method: 'GET', path: '/api/projects', desc: 'List all projects', auth: true },
    { method: 'POST', path: '/api/projects', desc: 'Create project', auth: true },
    { method: 'GET', path: '/api/projects/:id', desc: 'Get project detail with boards, tasks, files', auth: true },
    { method: 'PATCH', path: '/api/projects/:id', desc: 'Update project', auth: true },
    { method: 'DELETE', path: '/api/projects/:id', desc: 'Delete project (admin only)', auth: true },
    { method: 'POST', path: '/api/projects/:id/members', desc: 'Add member to project', auth: true },
    { method: 'DELETE', path: '/api/projects/:id/members?userId=', desc: 'Remove member from project', auth: true },
    { method: 'POST', path: '/api/projects/:id/columns', desc: 'Create column', auth: true },
    { method: 'PATCH', path: '/api/projects/:id/columns/:columnId', desc: 'Update column', auth: true },
    { method: 'DELETE', path: '/api/projects/:id/columns/:columnId', desc: 'Delete column (admin only)', auth: true },
    { method: 'POST', path: '/api/tasks', desc: 'Create task', auth: true },
    { method: 'GET', path: '/api/tasks/:taskId', desc: 'Get task detail', auth: true },
    { method: 'PATCH', path: '/api/tasks/:taskId', desc: 'Update task', auth: true },
    { method: 'DELETE', path: '/api/tasks/:taskId', desc: 'Delete task', auth: true },
    { method: 'POST', path: '/api/tasks/:taskId/assignees', desc: 'Assign user to task (sends push notification)', auth: true },
    { method: 'DELETE', path: '/api/tasks/:taskId/assignees?userId=', desc: 'Unassign user from task', auth: true },
    { method: 'GET', path: '/api/tasks/:taskId/comments', desc: 'List comments', auth: true },
    { method: 'POST', path: '/api/tasks/:taskId/comments', desc: 'Add comment', auth: true },
    { method: 'PATCH', path: '/api/tasks/:taskId/comments/:commentId', desc: 'Edit comment (own only)', auth: true },
    { method: 'DELETE', path: '/api/tasks/:taskId/comments/:commentId', desc: 'Delete comment', auth: true },
    { method: 'GET', path: '/api/tasks/:taskId/files', desc: 'List task files', auth: true },
    { method: 'POST', path: '/api/tasks/:taskId/files', desc: 'Upload file to task (multipart)', auth: true },
    { method: 'DELETE', path: '/api/tasks/:taskId/files/:fileId', desc: 'Delete task file', auth: true },
    { method: 'GET', path: '/api/projects/:id/files?category=NACRTI|SLIKE', desc: 'List project files', auth: true },
    { method: 'POST', path: '/api/projects/:id/files', desc: 'Upload project file (multipart)', auth: true },
    { method: 'DELETE', path: '/api/projects/:id/files/:fileId', desc: 'Delete project file', auth: true },
    { method: 'GET', path: '/api/files/serve?path=', desc: 'Serve uploaded file', auth: true },
    { method: 'POST', path: '/api/reorder', desc: 'Reorder tasks (drag-and-drop)', auth: true },
    { method: 'GET', path: '/api/notifications', desc: 'Get notifications + unread count', auth: true },
    { method: 'PATCH', path: '/api/notifications', desc: 'Mark notification(s) as read', auth: true },
    { method: 'DELETE', path: '/api/notifications', desc: 'Clear all notifications', auth: true },
  ];

  const methodColors: Record<string, string> = {
    GET: 'bg-emerald-500/10 text-emerald-600',
    POST: 'bg-blue-500/10 text-blue-600',
    PATCH: 'bg-amber-500/10 text-amber-600',
    DELETE: 'bg-red-500/10 text-red-600',
    PUT: 'bg-violet-500/10 text-violet-600',
  };

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-2">Solray API Documentation</h1>
      <p className="text-gray-500 mb-8">REST API endpoints. All authenticated endpoints accept session cookies or Bearer tokens.</p>

      <div className="space-y-2">
        {endpoints.map((ep, i) => (
          <div key={i} className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 dark:border-gray-800">
            <span className={`px-2 py-1 rounded text-xs font-mono font-bold ${methodColors[ep.method] ?? ''}`}>
              {ep.method}
            </span>
            <code className="text-sm font-mono flex-shrink-0">{ep.path}</code>
            <span className="text-sm text-gray-500 flex-1">{ep.desc}</span>
            {ep.auth && (
              <span className="text-[10px] bg-primary/10 text-primary px-2 py-0.5 rounded-full">Auth</span>
            )}
          </div>
        ))}
      </div>

      <div className="mt-8 p-4 bg-muted/50 rounded-lg">
        <h2 className="font-semibold mb-2">Authentication</h2>
        <p className="text-sm text-muted-foreground">
          For web: session cookies via NextAuth (POST to /api/auth/callback/credentials).<br />
          For mobile: POST to /api/auth/mobile-login with &#123;email, password&#125; to get a Bearer token.
          Include <code className="bg-muted px-1 rounded">Authorization: Bearer &lt;token&gt;</code> in all subsequent requests.
        </p>
      </div>

      <div className="mt-4 p-4 bg-muted/50 rounded-lg">
        <h2 className="font-semibold mb-2">Push Notifications</h2>
        <p className="text-sm text-muted-foreground">
          Register Expo push tokens via POST /api/users/push-token &#123;token, platform: &quot;expo&quot;&#125;.<br />
          Notifications are sent automatically when users are assigned to tasks or receive comments.
        </p>
      </div>
    </div>
  );
}
