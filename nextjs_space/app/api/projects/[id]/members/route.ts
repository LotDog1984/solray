export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';
import { sendPushNotifications, createInAppNotification } from '@/lib/push-notifications';

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { userId } = body ?? {};

  if (!userId) {
    return NextResponse.json({ error: 'userId is required' }, { status: 400 });
  }

  const project = await prisma.project.findUnique({ where: { id }, select: { name: true } });

  const member = await prisma.projectMember.upsert({
    where: { projectId_userId: { projectId: id, userId } },
    update: {},
    create: { projectId: id, userId },
    include: { user: { select: { id: true, name: true, email: true } } },
  });

  // Notify the added member
  await createInAppNotification(
    userId,
    'PROJECT_MEMBER_ADDED',
    'Added to project',
    `You were added to project "${project?.name ?? 'Unknown'}"`,
    { projectId: id }
  );
  await sendPushNotifications([userId], 'Added to project', `You were added to "${project?.name ?? 'Unknown'}"`, { projectId: id });

  return NextResponse.json(member, { status: 201 });
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const userId = searchParams.get('userId');

  if (!userId) {
    return NextResponse.json({ error: 'userId query param is required' }, { status: 400 });
  }

  await prisma.projectMember.deleteMany({ where: { projectId: id, userId } });
  return NextResponse.json({ success: true });
}
