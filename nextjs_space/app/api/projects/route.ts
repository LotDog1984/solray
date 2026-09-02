export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';
import { ensureProjectDirs } from '@/lib/file-utils';

export async function GET(request: NextRequest) {
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const projects = await prisma.project.findMany({
    include: {
      members: { include: { user: { select: { id: true, name: true, email: true } } } },
      _count: { select: { boards: true } },
    },
    orderBy: { updatedAt: 'desc' },
  });

  return NextResponse.json(projects);
}

export async function POST(request: NextRequest) {
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { name, description, memberIds } = body ?? {};

  if (!name) {
    return NextResponse.json({ error: 'Project name is required' }, { status: 400 });
  }

  // Create project with boards and default columns
  const project = await prisma.project.create({
    data: {
      name,
      description: description ?? null,
      members: {
        create: [
          { userId: user.id },
          ...((memberIds ?? []) as string[]).filter((id: string) => id !== user.id).map((id: string) => ({ userId: id })),
        ],
      },
      boards: {
        create: [
          {
            type: 'RADIONA',
            name: 'Radiona',
            columns: {
              create: [
                { name: 'Priprema', position: 0 },
                { name: 'Sklapanje', position: 1 },
                { name: 'Okovi', position: 2 },
                { name: 'Reklamacije', position: 3 },
                { name: 'Za Narudžbu', position: 4 },
              ],
            },
          },
          {
            type: 'MONTAZA',
            name: 'Montaža',
            columns: {
              create: [
                { name: 'Ostaci', position: 0 },
                { name: 'Reklamacije', position: 1 },
              ],
            },
          },
        ],
      },
    },
    include: {
      members: { include: { user: { select: { id: true, name: true, email: true } } } },
      boards: { include: { columns: true } },
    },
  });

  // Create filesystem directories
  try {
    ensureProjectDirs(name);
  } catch (e) {
    console.error('Failed to create project directories:', e);
  }

  return NextResponse.json(project, { status: 201 });
}
