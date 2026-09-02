export const dynamic = 'force-dynamic';

import { NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';

export async function GET() {
  try {
    const adminCount = await prisma.user.count({ where: { role: 'ADMIN' } });
    return NextResponse.json({ setupComplete: adminCount > 0 });
  } catch (error: any) {
    console.error('Check setup error:', error);
    return NextResponse.json({ setupComplete: false });
  }
}
