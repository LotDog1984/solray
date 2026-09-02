'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Separator } from '@/components/ui/separator';
import { ScrollArea } from '@/components/ui/scroll-area';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  CheckCircle2,
  Calendar,
  Flag,
  Users,
  MessageSquare,
  Paperclip,
  Trash2,
  Upload,
  X,
  Download,
  FileIcon,
  ImageIcon,
  Send,
  Loader2,
} from 'lucide-react';
import { toast } from 'sonner';
import { SafeDate } from '@/components/safe-format';
import { cn } from '@/lib/utils';

interface TaskDetailModalProps {
  taskId: string;
  projectId: string;
  projectMembers: any[];
  currentUserId: string;
  userRole: string;
  open: boolean;
  onClose: () => void;
  onUpdate: () => void;
}

const priorityOptions = [
  { value: 'LOW', label: 'Low', color: 'text-emerald-500' },
  { value: 'MEDIUM', label: 'Medium', color: 'text-amber-500' },
  { value: 'HIGH', label: 'High', color: 'text-red-500' },
];

export function TaskDetailModal({
  taskId,
  projectId,
  projectMembers,
  currentUserId,
  userRole,
  open,
  onClose,
  onUpdate,
}: TaskDetailModalProps) {
  const [task, setTask] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [newComment, setNewComment] = useState('');
  const [uploading, setUploading] = useState(false);

  const fetchTask = useCallback(async () => {
    try {
      const res = await fetch(`/api/tasks/${taskId}`);
      if (res?.ok) {
        const data = await res.json();
        setTask(data);
        setTitle(data?.title ?? '');
        setDescription(data?.description ?? '');
      }
    } catch { /* silent */ }
    setLoading(false);
  }, [taskId]);

  useEffect(() => {
    if (open && taskId) {
      setLoading(true);
      fetchTask();
    }
  }, [open, taskId, fetchTask]);

  const updateTask = async (data: any) => {
    try {
      const res = await fetch(`/api/tasks/${taskId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (res?.ok) {
        await fetchTask();
        onUpdate();
      }
    } catch {
      toast.error('Failed to update task');
    }
  };

  const toggleDone = () => updateTask({ done: !task?.done });

  const updatePriority = (priority: string) => updateTask({ priority });

  const updateDueDate = (date: string) => updateTask({ dueDate: date || null });

  const saveDescription = () => {
    if (description !== (task?.description ?? '')) {
      updateTask({ description });
    }
  };

  const saveTitle = () => {
    if (title.trim() && title !== task?.title) {
      updateTask({ title: title.trim() });
    }
  };

  const assignUser = async (userId: string) => {
    try {
      await fetch(`/api/tasks/${taskId}/assignees`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId }),
      });
      await fetchTask();
      onUpdate();
    } catch {
      toast.error('Failed to assign user');
    }
  };

  const unassignUser = async (userId: string) => {
    try {
      await fetch(`/api/tasks/${taskId}/assignees?userId=${userId}`, { method: 'DELETE' });
      await fetchTask();
      onUpdate();
    } catch {
      toast.error('Failed to unassign user');
    }
  };

  const addComment = async () => {
    if (!newComment.trim()) return;
    try {
      await fetch(`/api/tasks/${taskId}/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content: newComment.trim() }),
      });
      setNewComment('');
      await fetchTask();
    } catch {
      toast.error('Failed to add comment');
    }
  };

  const deleteComment = async (commentId: string) => {
    try {
      await fetch(`/api/tasks/${taskId}/comments/${commentId}`, { method: 'DELETE' });
      await fetchTask();
    } catch {
      toast.error('Failed to delete comment');
    }
  };

  const uploadFile = async (file: File) => {
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      const res = await fetch(`/api/tasks/${taskId}/files`, { method: 'POST', body: formData });
      if (res?.ok) {
        await fetchTask();
        toast.success('File uploaded');
      }
    } catch {
      toast.error('Upload failed');
    }
    setUploading(false);
  };

  const deleteFile = async (fileId: string) => {
    try {
      await fetch(`/api/tasks/${taskId}/files/${fileId}`, { method: 'DELETE' });
      await fetchTask();
    } catch {
      toast.error('Failed to delete file');
    }
  };

  const deleteTask = async () => {
    if (!confirm('Delete this task?')) return;
    try {
      await fetch(`/api/tasks/${taskId}`, { method: 'DELETE' });
      toast.success('Task deleted');
      onUpdate();
      onClose();
    } catch {
      toast.error('Failed to delete task');
    }
  };

  const assignedIds = (task?.assignees ?? []).map((a: any) => a?.user?.id ?? a?.userId);
  const unassignedMembers = (projectMembers ?? []).filter(
    (m: any) => !assignedIds.includes(m?.user?.id ?? m?.userId)
  );

  const isImage = (fileType: string) =>
    ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'].includes(fileType?.toLowerCase?.() ?? '');

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-2xl max-h-[85vh] p-0 overflow-hidden">
        <ScrollArea className="max-h-[85vh]">
          <div className="p-6">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <>
                {/* Header */}
                <div className="flex items-start gap-3 mb-4">
                  <button onClick={toggleDone} className="mt-1">
                    <CheckCircle2
                      className={cn('h-5 w-5 transition-colors', task?.done ? 'text-emerald-500 fill-emerald-500' : 'text-muted-foreground')}
                    />
                  </button>
                  <Input
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    onBlur={saveTitle}
                    className={cn(
                      'text-lg font-semibold border-0 p-0 h-auto focus-visible:ring-0 bg-transparent',
                      task?.done && 'line-through text-muted-foreground'
                    )}
                  />
                  <Button variant="ghost" size="icon" className="h-8 w-8 text-destructive" onClick={deleteTask}>
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>

                {/* Meta row */}
                <div className="flex flex-wrap items-center gap-3 mb-4">
                  <div className="flex items-center gap-2">
                    <Flag className="h-4 w-4 text-muted-foreground" />
                    <Select value={task?.priority ?? 'MEDIUM'} onValueChange={updatePriority}>
                      <SelectTrigger className="h-8 w-28 text-xs">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {priorityOptions.map((p) => (
                          <SelectItem key={p.value} value={p.value}>
                            <span className={p.color}>{p.label}</span>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="flex items-center gap-2">
                    <Calendar className="h-4 w-4 text-muted-foreground" />
                    <Input
                      type="date"
                      value={task?.dueDate ? new Date(task.dueDate).toISOString().split('T')[0] : ''}
                      onChange={(e) => updateDueDate(e.target.value)}
                      className="h-8 w-40 text-xs"
                    />
                  </div>
                </div>

                <Separator className="my-4" />

                {/* Description */}
                <div className="mb-4">
                  <Label className="text-xs text-muted-foreground mb-2 block">Description</Label>
                  <Textarea
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    onBlur={saveDescription}
                    placeholder="Add a description..."
                    rows={3}
                    className="text-sm"
                  />
                </div>

                <Separator className="my-4" />

                {/* Assignees */}
                <div className="mb-4">
                  <Label className="text-xs text-muted-foreground mb-2 flex items-center gap-1">
                    <Users className="h-3.5 w-3.5" /> Assigned Members
                  </Label>
                  <div className="flex flex-wrap gap-2 mb-2">
                    {(task?.assignees ?? []).map((a: any) => (
                      <Badge key={a?.id} variant="secondary" className="flex items-center gap-1 pr-1">
                        <Avatar className="h-4 w-4">
                          <AvatarFallback className="text-[8px] bg-primary/10 text-primary">
                            {(a?.user?.name ?? 'U').slice(0, 2).toUpperCase()}
                          </AvatarFallback>
                        </Avatar>
                        {a?.user?.name ?? 'User'}
                        <button onClick={() => unassignUser(a?.user?.id)} className="ml-1 hover:text-destructive">
                          <X className="h-3 w-3" />
                        </button>
                      </Badge>
                    ))}
                  </div>
                  {unassignedMembers?.length > 0 && (
                    <Select onValueChange={assignUser}>
                      <SelectTrigger className="h-8 w-60 text-xs">
                        <SelectValue placeholder="Assign a member..." />
                      </SelectTrigger>
                      <SelectContent>
                        {unassignedMembers.map((m: any) => (
                          <SelectItem key={m?.user?.id ?? m?.id} value={m?.user?.id ?? m?.id ?? ''}>
                            {m?.user?.name ?? 'User'}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </div>

                <Separator className="my-4" />

                {/* Files */}
                <div className="mb-4">
                  <Label className="text-xs text-muted-foreground mb-2 flex items-center gap-1">
                    <Paperclip className="h-3.5 w-3.5" /> Files
                  </Label>
                  <div className="grid grid-cols-2 gap-2 mb-2">
                    {(task?.files ?? []).map((f: any) => (
                      <div key={f?.id} className="flex items-center gap-2 p-2 rounded-lg bg-muted/50 text-sm">
                        {isImage(f?.fileType ?? '') ? (
                          <ImageIcon className="h-4 w-4 text-primary flex-shrink-0" />
                        ) : (
                          <FileIcon className="h-4 w-4 text-muted-foreground flex-shrink-0" />
                        )}
                        <span className="truncate flex-1 text-xs">{f?.fileName ?? 'File'}</span>
                        <a
                          href={`/api/files/serve?path=${encodeURIComponent(f?.filePath ?? '')}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="flex-shrink-0"
                        >
                          <Download className="h-3.5 w-3.5 text-muted-foreground hover:text-foreground" />
                        </a>
                        {(f?.uploadedById === currentUserId || userRole === 'ADMIN') && (
                          <button onClick={() => deleteFile(f?.id)} className="flex-shrink-0">
                            <Trash2 className="h-3.5 w-3.5 text-muted-foreground hover:text-destructive" />
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="file"
                      className="hidden"
                      onChange={(e) => {
                        const f = e.target?.files?.[0];
                        if (f) uploadFile(f);
                        e.target.value = '';
                      }}
                    />
                    <Button variant="outline" size="sm" className="text-xs" disabled={uploading} asChild>
                      <span>
                        {uploading ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" /> : <Upload className="mr-1 h-3.5 w-3.5" />}
                        {uploading ? 'Uploading...' : 'Upload File'}
                      </span>
                    </Button>
                  </label>
                </div>

                <Separator className="my-4" />

                {/* Comments */}
                <div>
                  <Label className="text-xs text-muted-foreground mb-2 flex items-center gap-1">
                    <MessageSquare className="h-3.5 w-3.5" /> Comments
                  </Label>
                  <div className="space-y-3 mb-3">
                    {(task?.comments ?? []).map((c: any) => (
                      <div key={c?.id} className="group">
                        <div className="flex items-start gap-2">
                          <Avatar className="h-6 w-6 mt-0.5">
                            <AvatarFallback className="text-[8px] bg-primary/10 text-primary">
                              {(c?.author?.name ?? 'U').slice(0, 2).toUpperCase()}
                            </AvatarFallback>
                          </Avatar>
                          <div className="flex-1">
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-medium">{c?.author?.name ?? 'User'}</span>
                              <SafeDate date={c?.createdAt ?? ''} options={{ dateStyle: 'short', timeStyle: 'short' }} className="text-[10px] text-muted-foreground" />
                            </div>
                            <p className="text-sm mt-0.5">{c?.content ?? ''}</p>
                            {/* Replies */}
                            {(c?.replies ?? []).map((r: any) => (
                              <div key={r?.id} className="ml-4 mt-2 flex items-start gap-2">
                                <Avatar className="h-5 w-5 mt-0.5">
                                  <AvatarFallback className="text-[7px] bg-muted text-muted-foreground">
                                    {(r?.author?.name ?? 'U').slice(0, 2).toUpperCase()}
                                  </AvatarFallback>
                                </Avatar>
                                <div>
                                  <div className="flex items-center gap-2">
                                    <span className="text-xs font-medium">{r?.author?.name ?? 'User'}</span>
                                    <SafeDate date={r?.createdAt ?? ''} options={{ dateStyle: 'short', timeStyle: 'short' }} className="text-[10px] text-muted-foreground" />
                                  </div>
                                  <p className="text-xs mt-0.5">{r?.content ?? ''}</p>
                                </div>
                              </div>
                            ))}
                          </div>
                          {(c?.author?.id === currentUserId || userRole === 'ADMIN') && (
                            <button
                              onClick={() => deleteComment(c?.id)}
                              className="opacity-0 group-hover:opacity-100 transition-opacity"
                            >
                              <Trash2 className="h-3.5 w-3.5 text-muted-foreground hover:text-destructive" />
                            </button>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                  <form
                    onSubmit={(e) => { e.preventDefault(); addComment(); }}
                    className="flex gap-2"
                  >
                    <Input
                      value={newComment}
                      onChange={(e) => setNewComment(e.target.value)}
                      placeholder="Write a comment..."
                      className="text-sm"
                    />
                    <Button type="submit" size="icon" className="h-9 w-9 flex-shrink-0" disabled={!newComment.trim()}>
                      <Send className="h-4 w-4" />
                    </Button>
                  </form>
                </div>
              </>
            )}
          </div>
        </ScrollArea>
      </DialogContent>
    </Dialog>
  );
}
