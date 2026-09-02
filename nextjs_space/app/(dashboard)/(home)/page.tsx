export const dynamic = 'force-dynamic';

import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';
import { redirect } from 'next/navigation';
import { ProjectsGrid } from './_components/projects-grid';

export default async function HomePage() {
  const session = await auth();
  if (!session?.user) redirect('/login');

  const projects = await prisma.project.findMany({
    include: {
      members: {
        include: { user: { select: { id: true, name: true, email: true } } },
      },
      _count: { select: { boards: true } },
    },
    orderBy: { updatedAt: 'desc' },
  });

  const users = await prisma.user.findMany({
    where: { active: true },
    select: { id: true, name: true, email: true },
    orderBy: { name: 'asc' },
  });

  const role = (session.user as any)?.role ?? 'MEMBER';

  return (
    <ProjectsGrid
      initialProjects={JSON.parse(JSON.stringify(projects))}
      users={JSON.parse(JSON.stringify(users))}
      currentUserId={session.user.id}
      userRole={role}
    />
  );
}
