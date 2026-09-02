import { auth } from '@/auth';
import { redirect } from 'next/navigation';
import { DashboardShell } from './_components/dashboard-shell';

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const session = await auth();
  if (!session?.user) redirect('/login');

  return (
    <DashboardShell
      user={{
        id: session.user.id,
        name: session.user.name ?? '',
        email: session.user.email ?? '',
        role: (session.user as any)?.role ?? 'MEMBER',
      }}
    >
      {children}
    </DashboardShell>
  );
}
