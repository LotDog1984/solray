export const dynamic = 'force-dynamic';

import { NextRequest, NextResponse } from 'next/server';
import { getAuthUser } from '@/lib/auth-helpers';
import fs from 'fs';
import path from 'path';

export async function GET(request: NextRequest) {
  const user = await getAuthUser(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const filePath = searchParams.get('path');

  if (!filePath) {
    return NextResponse.json({ error: 'File path is required' }, { status: 400 });
  }

  const base = process.env.FILE_UPLOAD_BASE ?? '/tmp/solray-uploads';
  const resolved = path.resolve(filePath);

  // Security: ensure the file is within the upload base
  if (!resolved.startsWith(path.resolve(base))) {
    return NextResponse.json({ error: 'Access denied' }, { status: 403 });
  }

  if (!fs.existsSync(resolved)) {
    return NextResponse.json({ error: 'File not found' }, { status: 404 });
  }

  const buffer = fs.readFileSync(resolved);
  const ext = path.extname(resolved).toLowerCase();
  const mimeTypes: Record<string, string> = {
    '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
    '.gif': 'image/gif', '.webp': 'image/webp', '.pdf': 'application/pdf',
    '.dwg': 'application/octet-stream', '.dxf': 'application/octet-stream',
    '.heic': 'image/heic',
  };

  return new NextResponse(buffer, {
    headers: {
      'Content-Type': mimeTypes[ext] ?? 'application/octet-stream',
      'Content-Disposition': `inline; filename="${path.basename(resolved)}"`,
      'Cache-Control': 'private, max-age=3600',
    },
  });
}
