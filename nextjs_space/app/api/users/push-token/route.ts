export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';
import { getAuthUser } from '@/lib/auth-helpers';

export async function POST(request: NextRequest) {
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const { token, platform } = body ?? {};

  if (!token) {
    return NextResponse.json({ error: 'Token is required' }, { status: 400 });
  }

  const pushToken = await prisma.pushToken.upsert({
    where: { token },
    update: { userId: user.id, platform: platform ?? 'expo' },
    create: { userId: user.id, token, platform: platform ?? 'expo' },
  });

  return NextResponse.json({ id: pushToken.id, token: pushToken.token }, { status: 201 });
}
