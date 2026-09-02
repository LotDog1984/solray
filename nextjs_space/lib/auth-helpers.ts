import { auth } from '@/auth';
import jwt from 'jsonwebtoken';
import { NextRequest } from 'next/server';

export async function getAuthUser(request?: NextRequest) {
  // Try session auth first
  const session = await auth();
  if (session?.user?.id) {
    return {
      id: session.user.id,
      email: session.user.email ?? '',
      name: session.user.name ?? '',
      role: (session.user as any)?.role ?? 'MEMBER',
    };
  }

  // Try bearer token (mobile)
  if (request) {
    const authHeader = request.headers.get('authorization');
    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.substring(7);
      try {
        const secret = process.env.NEXTAUTH_SECRET ?? process.env.AUTH_SECRET ?? '';
        const decoded = jwt.verify(token, secret) as any;
        if (decoded?.id) {
          return {
            id: decoded.id,
            email: decoded.email ?? '',
            name: decoded.name ?? '',
            role: decoded.role ?? 'MEMBER',
          };
        }
      } catch {
        return null;
      }
    }
  }

  return null;
}
