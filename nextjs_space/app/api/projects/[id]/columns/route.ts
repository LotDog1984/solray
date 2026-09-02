export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id: projectId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { boardId, name } = body ?? {};

  if (!boardId || !name) {
    return NextResponse.json({ error: 'boardId and name are required' }, { status: 400 });
  }

  const maxPos = await prisma.column.aggregate({ where: { boardId }, _max: { position: true } });
  const position = (maxPos?._max?.position ?? -1) + 1;

  const column = await prisma.column.create({
    data: { boardId, name, position },
  });

  return NextResponse.json(column, { status: 201 });
}
