import fs from 'fs';
import path from 'path';

const FILE_UPLOAD_BASE = process.env.FILE_UPLOAD_BASE ?? '/tmp/solray-uploads';

export function getUploadBase(): string {
  return FILE_UPLOAD_BASE;
}

export function getProjectDir(projectName: string): string {
  const safeName = projectName.replace(/[^a-zA-Z0-9_\-\s]/g, '').replace(/\s+/g, '-').toLowerCase();
  return path.join(FILE_UPLOAD_BASE, safeName);
}

export function ensureProjectDirs(projectName: string): string {
  const projectDir = getProjectDir(projectName);
  const nacrtDir = path.join(projectDir, 'nacrti');
  const slikeDir = path.join(projectDir, 'slike');

  fs.mkdirSync(projectDir, { recursive: true });
  fs.mkdirSync(nacrtDir, { recursive: true });
  fs.mkdirSync(slikeDir, { recursive: true });

  return projectDir;
}

export function generateUniqueFileName(originalName: string): string {
  const ext = path.extname(originalName);
  const base = path.basename(originalName, ext).replace(/[^a-zA-Z0-9_\-]/g, '_');
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  return `${timestamp}-${random}-${base}${ext}`;
}

export async function saveUploadedFile(
  file: File,
  targetDir: string
): Promise<{ fileName: string; filePath: string; fileSize: number; fileType: string }> {
  fs.mkdirSync(targetDir, { recursive: true });

  const uniqueName = generateUniqueFileName(file?.name ?? 'upload');
  const filePath = path.join(targetDir, uniqueName);
  const buffer = Buffer.from(await file.arrayBuffer());

  fs.writeFileSync(filePath, buffer);

  return {
    fileName: file?.name ?? 'upload',
    filePath,
    fileSize: file?.size ?? 0,
    fileType: file?.type ?? 'application/octet-stream',
  };
}

export function deleteFile(filePath: string): boolean {
  try {
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
      return true;
    }
    return false;
  } catch {
    return false;
  }
}

export function isImageFile(fileType: string): boolean {
  return ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/heic'].includes(
    fileType?.toLowerCase?.() ?? ''
  );
}
