export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';
import { saveUploadedFile, getProjectDir } from '@/lib/file-utils';
import path from 'path';

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const category = searchParams.get('category');

  const where: any = { projectId: id };
  if (category === 'NACRTI' || category === 'SLIKE') {
    where.category = category;
  }

  const files = await prisma.projectFile.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    include: { uploadedBy: { select: { id: true, name: true } } },
  });

  return NextResponse.json(files);
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const formData = await request.formData();
  const file = formData.get('file') as File | null;
  const category = (formData.get('category') as string) ?? 'NACRTI';

  if (!file) {
    return NextResponse.json({ error: 'File is required' }, { status: 400 });
  }

  const project = await prisma.project.findUnique({ where: { id }, select: { name: true } });
  if (!project) {
    return NextResponse.json({ error: 'Project not found' }, { status: 404 });
  }

  const baseDir = getProjectDir(project.name);
  const subDir = category === 'SLIKE' ? 'slike' : 'nacrti';
  const targetDir = path.join(baseDir, subDir);

  const saved = await saveUploadedFile(file, targetDir);

  const projectFile = await prisma.projectFile.create({
    data: {
      projectId: id,
      fileName: saved.fileName,
      filePath: saved.filePath,
      fileType: saved.fileType,
      fileSize: saved.fileSize,
      category: category === 'SLIKE' ? 'SLIKE' : 'NACRTI',
      uploadedById: user.id,
    },
    include: { uploadedBy: { select: { id: true, name: true } } },
  });

  return NextResponse.json(projectFile, { status: 201 });
}
