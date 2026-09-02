export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';
import bcrypt from 'bcryptjs';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const authUser = await getAuthUser(request);
  if (!authUser) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const isSelf = authUser.id === id;
  const isAdmin = authUser.role === 'ADMIN';

  if (!isSelf && !isAdmin) {
    return NextResponse.json({ error: 'Access denied' }, { status: 403 });
  }

  const body = await request.json();
  const updateData: any = {};

  if (body?.name) updateData.name = body.name;
  if (body?.email) updateData.email = body.email;
  if (body?.password) updateData.password = await bcrypt.hash(body.password, 12);
  if (isAdmin && body?.role) updateData.role = body.role;
  if (isAdmin && typeof body?.active === 'boolean') updateData.active = body.active;

  const updated = await prisma.user.update({
    where: { id },
    data: updateData,
    select: { id: true, name: true, email: true, role: true, active: true, createdAt: true },
  });

  return NextResponse.json(updated);
}
