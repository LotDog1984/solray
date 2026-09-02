export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';
import { deleteFile } from '@/lib/file-utils';

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ taskId: string; fileId: string }> }) {
  const { fileId } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const file = await prisma.taskFile.findUnique({ where: { id: fileId } });
  if (!file) {
    return NextResponse.json({ error: 'File not found' }, { status: 404 });
  }

  if (file.uploadedById !== user.id && user.role !== 'ADMIN') {
    return NextResponse.json({ error: 'Not allowed' }, { status: 403 });
  }

  deleteFile(file.filePath);
  await prisma.taskFile.delete({ where: { id: fileId } });

  return NextResponse.json({ success: true });
}
