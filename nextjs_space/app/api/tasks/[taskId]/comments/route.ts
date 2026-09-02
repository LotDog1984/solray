export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';
import { sendPushNotifications, createInAppNotification } from '@/lib/push-notifications';

export async function GET(request: NextRequest, { params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const comments = await prisma.comment.findMany({
    where: { taskId, parentId: null },
    orderBy: { createdAt: 'asc' },
    include: {
      author: { select: { id: true, name: true, email: true } },
      replies: {
        orderBy: { createdAt: 'asc' },
        include: { author: { select: { id: true, name: true, email: true } } },
      },
    },
  });

  return NextResponse.json(comments);
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { content, parentId } = body ?? {};

  if (!content) {
    return NextResponse.json({ error: 'Content is required' }, { status: 400 });
  }

  const comment = await prisma.comment.create({
    data: { taskId, authorId: user.id, content, parentId: parentId ?? null },
    include: { author: { select: { id: true, name: true, email: true } } },
  });

  // Notify task assignees about the comment
  const task = await prisma.task.findUnique({
    where: { id: taskId },
    include: {
      assignees: { select: { userId: true } },
      column: { include: { board: { include: { project: { select: { id: true, name: true } } } } } },
    },
  });

  const assigneeIds = (task?.assignees ?? []).map((a: any) => a?.userId).filter((id: string) => id !== user.id);
  if (assigneeIds?.length > 0) {
    const taskTitle = task?.title ?? 'Unknown Task';
    const projectId = task?.column?.board?.project?.id ?? '';

    for (const uid of assigneeIds) {
      await createInAppNotification(
        uid,
        'COMMENT_ADDED',
        'New comment',
        `${user.name} commented on "${taskTitle}"`,
        { taskId, projectId }
      );
    }
    await sendPushNotifications(assigneeIds, 'New Comment', `${user.name} commented on "${task?.title ?? ''}"`, { taskId });
  }

  return NextResponse.json(comment, { status: 201 });
}
