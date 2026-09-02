export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';

export async function POST(request: NextRequest) {
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { taskId, sourceColumnId, destinationColumnId, newPosition } = body ?? {};

  if (!taskId || typeof newPosition !== 'number') {
    return NextResponse.json({ error: 'taskId and newPosition are required' }, { status: 400 });
  }

  // Update the task's column and position
  const updateData: any = { position: newPosition };
  if (destinationColumnId) {
    updateData.columnId = destinationColumnId;
  }

  await prisma.task.update({
    where: { id: taskId },
    data: updateData,
  });

  // Reorder other tasks in destination column
  const destColId = destinationColumnId ?? sourceColumnId;
  if (destColId) {
    const tasks = await prisma.task.findMany({
      where: { columnId: destColId },
      orderBy: { position: 'asc' },
    });

    // Re-index positions
    for (let i = 0; i < (tasks?.length ?? 0); i++) {
      const t = tasks?.[i];
      if (t && t.position !== i) {
        await prisma.task.update({ where: { id: t.id }, data: { position: i } });
      }
    }
  }

  // If moved between columns, re-index source column too
  if (sourceColumnId && destinationColumnId && sourceColumnId !== destinationColumnId) {
    const sourceTasks = await prisma.task.findMany({
      where: { columnId: sourceColumnId },
      orderBy: { position: 'asc' },
    });
    for (let i = 0; i < (sourceTasks?.length ?? 0); i++) {
      const t = sourceTasks?.[i];
      if (t && t.position !== i) {
        await prisma.task.update({ where: { id: t.id }, data: { position: i } });
      }
    }
  }

  return NextResponse.json({ success: true });
}
