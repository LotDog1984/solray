'use client';

import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { CheckCircle2, MessageSquare, Paperclip, Calendar } from 'lucide-react';
import { SafeDate } from '@/components/safe-format';
import { cn } from '@/lib/utils';

const priorityColors: Record<string, string> = {
  LOW: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400',
  MEDIUM: 'bg-amber-500/10 text-amber-600 dark:text-amber-400',
  HIGH: 'bg-red-500/10 text-red-600 dark:text-red-400',
};

interface TaskCardItemProps {
  task: any;
  onClick: () => void;
  isDragging: boolean;
}

export function TaskCardItem({ task, onClick, isDragging }: TaskCardItemProps) {
  const commentCount = task?._count?.comments ?? 0;
  const fileCount = task?._count?.files ?? 0;
  const assignees = task?.assignees ?? [];

  return (
    <Card
      onClick={onClick}
      className={cn(
        'p-3 cursor-pointer border-border/50 hover:border-primary/30 transition-all bg-card',
        isDragging && 'shadow-lg rotate-2 opacity-90',
        task?.done && 'opacity-60'
      )}
    >
      <div className="flex items-start gap-2">
        {task?.done && <CheckCircle2 className="h-4 w-4 text-emerald-500 mt-0.5 flex-shrink-0" />}
        <p className={cn('text-sm font-medium flex-1', task?.done && 'line-through text-muted-foreground')}>
          {task?.title ?? 'Untitled'}
        </p>
      </div>

      <div className="flex items-center gap-2 mt-2 flex-wrap">
        <Badge variant="outline" className={cn('text-[10px] px-1.5 py-0 h-5', priorityColors[task?.priority ?? 'MEDIUM'])}>
          {task?.priority ?? 'MEDIUM'}
        </Badge>

        {task?.dueDate && (
          <div className="flex items-center gap-1 text-[10px] text-muted-foreground">
            <Calendar className="h-3 w-3" />
            <SafeDate date={task.dueDate} options={{ month: 'short', day: 'numeric' }} />
          </div>
        )}

        {commentCount > 0 && (
          <div className="flex items-center gap-0.5 text-[10px] text-muted-foreground">
            <MessageSquare className="h-3 w-3" />
            {commentCount}
          </div>
        )}

        {fileCount > 0 && (
          <div className="flex items-center gap-0.5 text-[10px] text-muted-foreground">
            <Paperclip className="h-3 w-3" />
            {fileCount}
          </div>
        )}
      </div>

      {assignees?.length > 0 && (
        <div className="flex -space-x-1.5 mt-2">
          {assignees.slice(0, 3).map((a: any) => (
            <Avatar key={a?.id} className="h-5 w-5 border border-card">
              <AvatarFallback className="bg-primary/10 text-primary text-[8px] font-semibold">
                {(a?.user?.name ?? 'U').slice(0, 2).toUpperCase()}
              </AvatarFallback>
            </Avatar>
          ))}
          {assignees?.length > 3 && (
            <span className="h-5 w-5 rounded-full bg-muted flex items-center justify-center text-[8px] border border-card">
              +{assignees.length - 3}
            </span>
          )}
        </div>
      )}
    </Card>
  );
}
