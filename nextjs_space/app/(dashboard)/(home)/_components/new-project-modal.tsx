'use client';

import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { toast } from 'sonner';
import { Loader2 } from 'lucide-react';

interface NewProjectModalProps {
  open: boolean;
  onClose: () => void;
  onCreated: (project: any) => void;
  users: any[];
  currentUserId: string;
}

export function NewProjectModal({ open, onClose, onCreated, users, currentUserId }: NewProjectModalProps) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [selectedMembers, setSelectedMembers] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);

  const toggleMember = (userId: string) => {
    setSelectedMembers((prev: string[]) =>
      (prev ?? []).includes(userId)
        ? (prev ?? []).filter((id: string) => id !== userId)
        : [...(prev ?? []), userId]
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) {
      toast.error('Project name is required');
      return;
    }
    setLoading(true);

    try {
      const res = await fetch('/api/projects', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: name.trim(), description: description.trim() || null, memberIds: selectedMembers }),
      });

      if (!res.ok) {
        const data = await res.json();
        toast.error(data?.error ?? 'Failed to create project');
        return;
      }

      const project = await res.json();
      toast.success('Project created!');
      onCreated(project);
      setName('');
      setDescription('');
      setSelectedMembers([]);
    } catch {
      toast.error('Failed to create project');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>New Project</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="project-name">Project Name</Label>
            <Input
              id="project-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Kitchen Renovation"
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="project-desc">Description (optional)</Label>
            <Textarea
              id="project-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Brief project description..."
              rows={3}
            />
          </div>
          {(users?.length ?? 0) > 0 && (
            <div className="space-y-2">
              <Label>Assign Members</Label>
              <div className="max-h-40 overflow-y-auto space-y-2 border rounded-lg p-3">
                {(users ?? []).filter((u: any) => u?.id !== currentUserId).map((u: any) => (
                  <label key={u?.id} className="flex items-center gap-2 cursor-pointer">
                    <Checkbox
                      checked={(selectedMembers ?? []).includes(u?.id)}
                      onCheckedChange={() => toggleMember(u?.id)}
                    />
                    <span className="text-sm">{u?.name}</span>
                    <span className="text-xs text-muted-foreground">({u?.email})</span>
                  </label>
                ))}
              </div>
            </div>
          )}
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit" disabled={loading}>
              {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Create Project
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
