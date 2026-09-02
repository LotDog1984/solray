export const dynamic = 'force-dynamic';

import { auth } from '@/auth';
import { prisma } from '@/lib/prisma';
import { redirect, notFound } from 'next/navigation';
import { ProjectDetail } from './_components/project-detail';

export default async function ProjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await auth();
  if (!session?.user) redirect('/login');

  const project = await prisma.project.findUnique({
    where: { id },
    include: {
      members: {
        include: { user: { select: { id: true, name: true, email: true, role: true } } },
      },
      boards: {
        include: {
          columns: {
            orderBy: { position: 'asc' },
            include: {
              tasks: {
                orderBy: [{ done: 'asc' }, { position: 'asc' }],
                include: {
                  assignees: { include: { user: { select: { id: true, name: true, email: true } } } },
                  createdBy: { select: { id: true, name: true } },
                  _count: { select: { comments: true, files: true } },
                },
              },
            },
          },
        },
      },
      files: {
        orderBy: { createdAt: 'desc' },
        include: { uploadedBy: { select: { id: true, name: true } } },
      },
    },
  });

  if (!project) notFound();

  const role = (session.user as any)?.role ?? 'MEMBER';

  return (
    <ProjectDetail
      project={JSON.parse(JSON.stringify(project))}
      currentUserId={session.user.id}
      userRole={role}
    />
  );
}
