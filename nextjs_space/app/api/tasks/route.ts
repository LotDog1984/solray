export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';

export async function POST(request: NextRequest) {
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { columnId, title, description, priority, dueDate } = body ?? {};

  if (!columnId || !title) {
    return NextResponse.json({ error: 'columnId and title are required' }, { status: 400 });
  }

  const maxPos = await prisma.task.aggregate({ where: { columnId }, _max: { position: true } });
  const position = (maxPos?._max?.position ?? -1) + 1;

  const task = await prisma.task.create({
    data: {
      columnId,
      title,
      description: description ?? null,
      priority: priority ?? 'MEDIUM',
      dueDate: dueDate ? new Date(dueDate) : null,
      position,
      createdById: user.id,
    },
    include: {
      assignees: { include: { user: { select: { id: true, name: true, email: true } } } },
      createdBy: { select: { id: true, name: true } },
      _count: { select: { comments: true, files: true } },
    },
  });

  return NextResponse.json(task, { status: 201 });
}
