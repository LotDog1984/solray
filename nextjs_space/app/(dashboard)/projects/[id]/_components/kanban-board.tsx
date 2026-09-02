'use client';

import { useState, useCallback } from 'react';
import { DragDropContext, Droppable, Draggable, DropResult } from '@hello-pangea/dnd';
import { Plus, MoreHorizontal, Trash2, Edit2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card } from '@/components/ui/card';
import { ScrollArea } from '@/components/ui/scroll-area';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { toast } from 'sonner';
import { TaskCardItem } from './task-card-item';
import { TaskDetailModal } from './task-detail-modal';
import { cn } from '@/lib/utils';

interface KanbanBoardProps {
  board: any;
  projectId: string;
  projectMembers: any[];
  currentUserId: string;
  userRole: string;
  onRefresh: () => void;
}

export function KanbanBoard({ board, projectId, projectMembers, currentUserId, userRole, onRefresh }: KanbanBoardProps) {
  const [columns, setColumns] = useState(board?.columns ?? []);
  const [newColumnName, setNewColumnName] = useState('');
  const [addingColumn, setAddingColumn] = useState(false);
  const [addingTaskColumn, setAddingTaskColumn] = useState<string | null>(null);
  const [newTaskTitle, setNewTaskTitle] = useState('');
  const [selectedTask, setSelectedTask] = useState<any>(null);
  const [editingColumnId, setEditingColumnId] = useState<string | null>(null);
  const [editColumnName, setEditColumnName] = useState('');

  const handleDragEnd = useCallback(async (result: DropResult) => {
    if (!result?.destination) return;

    const { source, destination, draggableId } = result;
    const sourceColId = source?.droppableId;
    const destColId = destination?.droppableId;
    const destIndex = destination?.index ?? 0;

    setColumns((prev: any[]) => {
      const newCols = (prev ?? []).map((col: any) => ({ ...col, tasks: [...(col?.tasks ?? [])] }));
      const sourceCol = newCols.find((c: any) => c?.id === sourceColId);
      const destCol = newCols.find((c: any) => c?.id === destColId);
      if (!sourceCol || !destCol) return prev;

      const [moved] = sourceCol.tasks.splice(source?.index ?? 0, 1);
      if (!moved) return prev;
      destCol.tasks.splice(destIndex, 0, moved);
      return newCols;
    });

    try {
      await fetch('/api/reorder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          taskId: draggableId,
          sourceColumnId: sourceColId,
          destinationColumnId: destColId,
          newPosition: destIndex,
        }),
      });
    } catch {
      toast.error('Failed to reorder');
      onRefresh();
    }
  }, [onRefresh]);

  const addColumn = async () => {
    if (!newColumnName.trim()) return;
    try {
      const res = await fetch(`/api/projects/${projectId}/columns`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ boardId: board?.id, name: newColumnName.trim() }),
      });
      if (res?.ok) {
        const col = await res.json();
        setColumns((prev: any[]) => [...(prev ?? []), { ...col, tasks: [] }]);
        setNewColumnName('');
        setAddingColumn(false);
      }
    } catch {
      toast.error('Failed to add column');
    }
  };

  const deleteColumn = async (columnId: string) => {
    try {
      await fetch(`/api/projects/${projectId}/columns/${columnId}`, { method: 'DELETE' });
      setColumns((prev: any[]) => (prev ?? []).filter((c: any) => c?.id !== columnId));
      toast.success('Column deleted');
    } catch {
      toast.error('Failed to delete column');
    }
  };

  const renameColumn = async (columnId: string) => {
    if (!editColumnName.trim()) return;
    try {
      await fetch(`/api/projects/${projectId}/columns/${columnId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: editColumnName.trim() }),
      });
      setColumns((prev: any[]) =>
        (prev ?? []).map((c: any) => c?.id === columnId ? { ...c, name: editColumnName.trim() } : c)
      );
      setEditingColumnId(null);
    } catch {
      toast.error('Failed to rename column');
    }
  };

  const addTask = async (columnId: string) => {
    if (!newTaskTitle.trim()) return;
    try {
      const res = await fetch('/api/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ columnId, title: newTaskTitle.trim() }),
      });
      if (res?.ok) {
        const task = await res.json();
        setColumns((prev: any[]) =>
          (prev ?? []).map((c: any) =>
            c?.id === columnId ? { ...c, tasks: [...(c?.tasks ?? []), task] } : c
          )
        );
        setNewTaskTitle('');
        setAddingTaskColumn(null);
      }
    } catch {
      toast.error('Failed to add task');
    }
  };

  const handleTaskUpdate = useCallback(() => {
    onRefresh();
    // Also refresh local state
    fetch(`/api/projects/${projectId}`)
      .then((r) => r?.json?.())
      .then((data) => {
        const b = (data?.boards ?? []).find((bb: any) => bb?.id === board?.id);
        if (b) setColumns(b?.columns ?? []);
      })
      .catch(() => {});
  }, [onRefresh, projectId, board?.id]);

  return (
    <div className="kanban-scroll pb-4">
      <DragDropContext onDragEnd={handleDragEnd}>
        <div className="flex gap-4 items-start min-w-max">
          {(columns ?? []).map((column: any) => (
            <div key={column?.id} className="w-72 flex-shrink-0">
              <div className="flex items-center justify-between mb-3 px-1">
                {editingColumnId === column?.id ? (
                  <form
                    onSubmit={(e) => { e.preventDefault(); renameColumn(column?.id); }}
                    className="flex gap-1 flex-1"
                  >
                    <Input
                      value={editColumnName}
                      onChange={(e) => setEditColumnName(e.target.value)}
                      className="h-7 text-sm"
                      autoFocus
                      onBlur={() => setEditingColumnId(null)}
                    />
                  </form>
                ) : (
                  <h3 className="font-semibold text-sm text-foreground">
                    {column?.name ?? 'Column'}
                    <span className="ml-2 text-xs text-muted-foreground font-normal">
                      {column?.tasks?.length ?? 0}
                    </span>
                  </h3>
                )}
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="ghost" size="icon" className="h-7 w-7">
                      <MoreHorizontal className="h-3.5 w-3.5" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem onClick={() => { setEditingColumnId(column?.id); setEditColumnName(column?.name ?? ''); }}>
                      <Edit2 className="mr-2 h-3.5 w-3.5" /> Rename
                    </DropdownMenuItem>
                    {userRole === 'ADMIN' && (
                      <DropdownMenuItem className="text-destructive" onClick={() => deleteColumn(column?.id)}>
                        <Trash2 className="mr-2 h-3.5 w-3.5" /> Delete
                      </DropdownMenuItem>
                    )}
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>

              <Droppable droppableId={column?.id ?? ''}>
                {(provided, snapshot) => (
                  <div
                    ref={provided.innerRef}
                    {...provided.droppableProps}
                    className={cn(
                      'min-h-[200px] rounded-lg p-2 space-y-2 transition-colors',
                      snapshot?.isDraggingOver ? 'bg-primary/5' : 'bg-muted/50'
                    )}
                  >
                    {(column?.tasks ?? []).map((task: any, index: number) => (
                      <Draggable key={task?.id} draggableId={task?.id ?? ''} index={index}>
                        {(provided, snapshot) => (
                          <div
                            ref={provided.innerRef}
                            {...provided.draggableProps}
                            {...provided.dragHandleProps}
                          >
                            <TaskCardItem
                              task={task}
                              onClick={() => setSelectedTask(task)}
                              isDragging={snapshot?.isDragging ?? false}
                            />
                          </div>
                        )}
                      </Draggable>
                    ))}
                    {provided.placeholder}

                    {addingTaskColumn === column?.id ? (
                      <form
                        onSubmit={(e) => { e.preventDefault(); addTask(column?.id); }}
                        className="space-y-2"
                      >
                        <Input
                          value={newTaskTitle}
                          onChange={(e) => setNewTaskTitle(e.target.value)}
                          placeholder="Task title..."
                          className="text-sm"
                          autoFocus
                        />
                        <div className="flex gap-1">
                          <Button type="submit" size="sm" className="h-7 text-xs">Add</Button>
                          <Button type="button" variant="ghost" size="sm" className="h-7 text-xs" onClick={() => setAddingTaskColumn(null)}>Cancel</Button>
                        </div>
                      </form>
                    ) : (
                      <Button
                        variant="ghost"
                        size="sm"
                        className="w-full justify-start text-xs text-muted-foreground h-8"
                        onClick={() => { setAddingTaskColumn(column?.id); setNewTaskTitle(''); }}
                      >
                        <Plus className="mr-1 h-3.5 w-3.5" /> Add Task
                      </Button>
                    )}
                  </div>
                )}
              </Droppable>
            </div>
          ))}

          {/* Add Column */}
          <div className="w-72 flex-shrink-0">
            {addingColumn ? (
              <form onSubmit={(e) => { e.preventDefault(); addColumn(); }} className="space-y-2">
                <Input
                  value={newColumnName}
                  onChange={(e) => setNewColumnName(e.target.value)}
                  placeholder="Column name..."
                  autoFocus
                />
                <div className="flex gap-1">
                  <Button type="submit" size="sm">Add</Button>
                  <Button type="button" variant="ghost" size="sm" onClick={() => setAddingColumn(false)}>Cancel</Button>
                </div>
              </form>
            ) : (
              <Button
                variant="outline"
                className="w-full border-dashed"
                onClick={() => setAddingColumn(true)}
              >
                <Plus className="mr-2 h-4 w-4" /> Add Column
              </Button>
            )}
          </div>
        </div>
      </DragDropContext>

      {selectedTask && (
        <TaskDetailModal
          taskId={selectedTask?.id}
          projectId={projectId}
          projectMembers={projectMembers}
          currentUserId={currentUserId}
          userRole={userRole}
          open={!!selectedTask}
          onClose={() => setSelectedTask(null)}
          onUpdate={handleTaskUpdate}
        />
      )}
    </div>
  );
}
