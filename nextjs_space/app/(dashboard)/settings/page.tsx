export const dynamic = 'force-dynamic';

import { auth } from '@/auth';
import { redirect } from 'next/navigation';
import { prisma } from '@/lib/prisma';
import { SettingsClient } from './_components/settings-client';

export default async function SettingsPage() {
  const session = await auth();
  if (!session?.user) redirect('/login');

  const role = (session.user as any)?.role ?? 'MEMBER';
  let users: any[] = [];

  if (role === 'ADMIN') {
    users = await prisma.user.findMany({
      select: { id: true, name: true, email: true, role: true, active: true, createdAt: true },
      orderBy: { createdAt: 'asc' },
    });
  }

  return (
    <SettingsClient
      user={{
        id: session.user.id,
        name: session.user.name ?? '',
        email: session.user.email ?? '',
        role,
      }}
      users={JSON.parse(JSON.stringify(users))}
    />
  );
}
