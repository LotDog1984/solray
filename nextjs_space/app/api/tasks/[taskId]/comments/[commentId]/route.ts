export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ taskId: string; commentId: string }> }) {
  const { commentId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const comment = await prisma.comment.findUnique({ where: { id: commentId } });
  if (!comment || comment.authorId !== user.id) {
    return NextResponse.json({ error: 'Not allowed' }, { status: 403 });
  }

  const body = await request.json();
  const updated = await prisma.comment.update({
    where: { id: commentId },
    data: { content: body?.content ?? comment.content },
    include: { author: { select: { id: true, name: true, email: true } } },
  });

  return NextResponse.json(updated);
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ taskId: string; commentId: string }> }) {
  const { commentId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const comment = await prisma.comment.findUnique({ where: { id: commentId } });
  if (!comment || (comment.authorId !== user.id && user.role !== 'ADMIN')) {
    return NextResponse.json({ error: 'Not allowed' }, { status: 403 });
  }

  await prisma.comment.delete({ where: { id: commentId } });
  return NextResponse.json({ success: true });
}
