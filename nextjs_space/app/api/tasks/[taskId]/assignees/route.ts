export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';
import { sendPushNotifications, createInAppNotification } from '@/lib/push-notifications';

export async function POST(request: NextRequest, { params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { userId } = body ?? {};

  if (!userId) {
    return NextResponse.json({ error: 'userId is required' }, { status: 400 });
  }

  const assignee = await prisma.taskAssignee.upsert({
    where: { taskId_userId: { taskId, userId } },
    update: {},
    create: { taskId, userId },
    include: { user: { select: { id: true, name: true, email: true } } },
  });

  // Get task and project info for notification
  const task = await prisma.task.findUnique({
    where: { id: taskId },
    include: { column: { include: { board: { include: { project: { select: { id: true, name: true } } } } } } },
  });

  const taskTitle = task?.title ?? 'Unknown Task';
  const projectName = task?.column?.board?.project?.name ?? 'Unknown Project';
  const projectId = task?.column?.board?.project?.id ?? '';

  // Send push notification
  await sendPushNotifications(
    [userId],
    'Task Assignment',
    `You have been assigned to: ${taskTitle} in ${projectName}`,
    { taskId, projectId }
  );

  // Create in-app notification
  await createInAppNotification(
    userId,
    'TASK_ASSIGNED',
    'New task assignment',
    `You have been assigned to: ${taskTitle} in ${projectName}`,
    { taskId, projectId }
  );

  return NextResponse.json(assignee, { status: 201 });
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const userId = searchParams.get('userId');

  if (!userId) {
    return NextResponse.json({ error: 'userId query param is required' }, { status: 400 });
  }

  await prisma.taskAssignee.deleteMany({ where: { taskId, userId } });
  return NextResponse.json({ success: true });
}
