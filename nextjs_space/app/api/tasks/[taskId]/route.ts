export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';

export async function GET(request: NextRequest, { params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const task = await prisma.task.findUnique({
    where: { id: taskId },
    include: {
      assignees: { include: { user: { select: { id: true, name: true, email: true } } } },
      createdBy: { select: { id: true, name: true } },
      comments: {
        orderBy: { createdAt: 'asc' },
        include: {
          author: { select: { id: true, name: true, email: true } },
          replies: {
            orderBy: { createdAt: 'asc' },
            include: { author: { select: { id: true, name: true, email: true } } },
          },
        },
        where: { parentId: null },
      },
      files: {
        orderBy: { createdAt: 'desc' },
        include: { uploadedBy: { select: { id: true, name: true } } },
      },
      column: { include: { board: { select: { projectId: true, type: true } } } },
    },
  });

  if (!task) {
    return NextResponse.json({ error: 'Task not found' }, { status: 404 });
  }

  return NextResponse.json(task);
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const updateData: any = {};

  if (body?.title !== undefined) updateData.title = body.title;
  if (body?.description !== undefined) updateData.description = body.description;
  if (typeof body?.done === 'boolean') updateData.done = body.done;
  if (body?.priority) updateData.priority = body.priority;
  if (body?.dueDate !== undefined) updateData.dueDate = body.dueDate ? new Date(body.dueDate) : null;
  if (body?.columnId) updateData.columnId = body.columnId;
  if (typeof body?.position === 'number') updateData.position = body.position;

  const task = await prisma.task.update({
    where: { id: taskId },
    data: updateData,
    include: {
      assignees: { include: { user: { select: { id: true, name: true, email: true } } } },
      createdBy: { select: { id: true, name: true } },
      _count: { select: { comments: true, files: true } },
    },
  });

  return NextResponse.json(task);
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  await prisma.task.delete({ where: { id: taskId } });
  return NextResponse.json({ success: true });
}
