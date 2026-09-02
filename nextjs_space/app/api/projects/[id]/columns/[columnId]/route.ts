export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string; columnId: string }> }) {
  const { columnId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const updateData: any = {};
  if (body?.name) updateData.name = body.name;
  if (typeof body?.position === 'number') updateData.position = body.position;

  const column = await prisma.column.update({ where: { id: columnId }, data: updateData });
  return NextResponse.json(column);
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ id: string; columnId: string }> }) {
  const { columnId } = await params;
  const user = await getAuthUser(request);
  if (!user || user.role !== 'ADMIN') {
    return NextResponse.json({ error: 'Admin access required' }, { status: 403 });
  }

  await prisma.column.delete({ where: { id: columnId } });
  return NextResponse.json({ success: true });
}
