'use client';

import { useState } from 'react';
import { Upload, Download, Trash2, FileIcon, ImageIcon, Eye, ChevronDown, ChevronUp, Camera, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { SafeDate } from '@/components/safe-format';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';

interface FilesSectionProps {
  projectId: string;
  files: any[];
  currentUserId: string;
  userRole: string;
  onRefresh: () => void;
}

export function FilesSection({ projectId, files, currentUserId, userRole, onRefresh }: FilesSectionProps) {
  const [nacrtOpen, setNacrtOpen] = useState(true);
  const [slikeOpen, setSlikeOpen] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);

  const nacrti = (files ?? []).filter((f: any) => f?.category === 'NACRTI');
  const slike = (files ?? []).filter((f: any) => f?.category === 'SLIKE');

  const uploadFile = async (category: string, file: File) => {
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('category', category);
      const res = await fetch(`/api/projects/${projectId}/files`, {
        method: 'POST',
        body: formData,
      });
      if (res?.ok) {
        toast.success('File uploaded');
        onRefresh();
      } else {
        toast.error('Upload failed');
      }
    } catch {
      toast.error('Upload failed');
    }
    setUploading(false);
  };

  const deleteFile = async (fileId: string) => {
    if (!confirm('Delete this file?')) return;
    try {
      await fetch(`/api/projects/${projectId}/files/${fileId}`, { method: 'DELETE' });
      toast.success('File deleted');
      onRefresh();
    } catch {
      toast.error('Failed to delete');
    }
  };

  const isImage = (fileType: string) =>
    ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'].includes(fileType?.toLowerCase?.() ?? '');

  const getFileUrl = (filePath: string) => `/api/files/serve?path=${encodeURIComponent(filePath ?? '')}`;

  return (
    <div className="space-y-4">
      {/* Lightbox */}
      {previewUrl && (
        <div
          className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-8"
          onClick={() => setPreviewUrl(null)}
        >
          <img
            src={previewUrl}
            alt="Preview"
            className="max-w-full max-h-full object-contain rounded-lg"
          />
        </div>
      )}

      {/* Nacrti */}
      <Collapsible open={nacrtOpen} onOpenChange={setNacrtOpen}>
        <Card>
          <CollapsibleTrigger asChild>
            <CardHeader className="cursor-pointer hover:bg-accent/50 transition-colors">
              <div className="flex items-center justify-between">
                <CardTitle className="text-base flex items-center gap-2">
                  <FileIcon className="h-4 w-4 text-primary" />
                  Nacrti
                  <span className="text-xs text-muted-foreground font-normal">({nacrti?.length ?? 0} files)</span>
                </CardTitle>
                {nacrtOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
              </div>
            </CardHeader>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <CardContent className="pt-0">
              <div className="flex gap-2 mb-4">
                <label>
                  <input
                    type="file"
                    className="hidden"
                    accept=".pdf,.dwg,.dxf,.jpg,.jpeg,.png,.gif,.webp"
                    onChange={(e) => {
                      const f = e.target?.files?.[0];
                      if (f) uploadFile('NACRTI', f);
                      e.target.value = '';
                    }}
                  />
                  <Button variant="outline" size="sm" asChild disabled={uploading}>
                    <span>
                      <Upload className="mr-1 h-3.5 w-3.5" /> Upload File
                    </span>
                  </Button>
                </label>
              </div>

              {nacrti?.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-4">No files uploaded yet</p>
              ) : (
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                  {nacrti.map((f: any) => (
                    <div key={f?.id} className="group rounded-lg border border-border/50 p-3 hover:border-primary/30 transition-colors">
                      <div className="flex items-center justify-center h-20 mb-2 rounded bg-muted/50">
                        {isImage(f?.fileType ?? '') ? (
                          <img
                            src={getFileUrl(f?.filePath)}
                            alt={f?.fileName ?? ''}
                            className="max-h-full max-w-full object-contain rounded cursor-pointer"
                            onClick={() => setPreviewUrl(getFileUrl(f?.filePath))}
                          />
                        ) : (
                          <FileIcon className="h-8 w-8 text-muted-foreground" />
                        )}
                      </div>
                      <p className="text-xs font-medium truncate">{f?.fileName ?? 'File'}</p>
                      <p className="text-[10px] text-muted-foreground">{f?.uploadedBy?.name ?? 'Unknown'}</p>
                      <SafeDate date={f?.createdAt ?? ''} options={{ dateStyle: 'short' }} className="text-[10px] text-muted-foreground block" />
                      <div className="flex gap-1 mt-2 opacity-0 group-hover:opacity-100 transition-opacity">
                        <a href={getFileUrl(f?.filePath)} download>
                          <Button variant="ghost" size="icon" className="h-6 w-6">
                            <Download className="h-3 w-3" />
                          </Button>
                        </a>
                        {isImage(f?.fileType ?? '') && (
                          <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => setPreviewUrl(getFileUrl(f?.filePath))}>
                            <Eye className="h-3 w-3" />
                          </Button>
                        )}
                        {(f?.uploadedById === currentUserId || userRole === 'ADMIN') && (
                          <Button variant="ghost" size="icon" className="h-6 w-6 text-destructive" onClick={() => deleteFile(f?.id)}>
                            <Trash2 className="h-3 w-3" />
                          </Button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </CollapsibleContent>
        </Card>
      </Collapsible>

      {/* Slike */}
      <Collapsible open={slikeOpen} onOpenChange={setSlikeOpen}>
        <Card>
          <CollapsibleTrigger asChild>
            <CardHeader className="cursor-pointer hover:bg-accent/50 transition-colors">
              <div className="flex items-center justify-between">
                <CardTitle className="text-base flex items-center gap-2">
                  <ImageIcon className="h-4 w-4 text-primary" />
                  Slike
                  <span className="text-xs text-muted-foreground font-normal">({slike?.length ?? 0} photos)</span>
                </CardTitle>
                {slikeOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
              </div>
            </CardHeader>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <CardContent className="pt-0">
              <div className="flex gap-2 mb-4">
                <label>
                  <input
                    type="file"
                    className="hidden"
                    accept="image/jpeg,image/jpg,image/png,image/gif,image/webp,image/heic"
                    onChange={(e) => {
                      const f = e.target?.files?.[0];
                      if (f) uploadFile('SLIKE', f);
                      e.target.value = '';
                    }}
                  />
                  <Button variant="outline" size="sm" asChild disabled={uploading}>
                    <span>
                      <Camera className="mr-1 h-3.5 w-3.5" /> Upload Photo
                    </span>
                  </Button>
                </label>
              </div>

              {slike?.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-4">No photos uploaded yet</p>
              ) : (
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                  {slike.map((f: any) => (
                    <div
                      key={f?.id}
                      className="group relative aspect-square rounded-lg overflow-hidden cursor-pointer border border-border/50 hover:border-primary/30 transition-colors"
                      onClick={() => setPreviewUrl(getFileUrl(f?.filePath))}
                    >
                      <img
                        src={getFileUrl(f?.filePath)}
                        alt={f?.fileName ?? ''}
                        className="w-full h-full object-cover"
                      />
                      <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-end">
                        <div className="p-2 opacity-0 group-hover:opacity-100 transition-opacity w-full flex justify-between items-center">
                          <span className="text-white text-xs truncate">{f?.fileName ?? ''}</span>
                          {(f?.uploadedById === currentUserId || userRole === 'ADMIN') && (
                            <button
                              onClick={(e) => { e.stopPropagation(); deleteFile(f?.id); }}
                              className="text-white hover:text-red-400"
                            >
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </CollapsibleContent>
        </Card>
      </Collapsible>
    </div>
  );
}
