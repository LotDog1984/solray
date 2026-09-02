'use client';

import { useState, useEffect, useCallback } from 'react';
import { Bell, Check, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import { ScrollArea } from '@/components/ui/scroll-area';
import { SafeDate } from '@/components/safe-format';
import { cn } from '@/lib/utils';

interface NotificationItem {
  id: string;
  type: string;
  title: string;
  message: string;
  read: boolean;
  createdAt: string;
  data: any;
}

export function NotificationBell() {
  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [open, setOpen] = useState(false);

  const fetchNotifications = useCallback(async () => {
    try {
      const res = await fetch('/api/notifications');
      if (res?.ok) {
        const data = await res.json();
        setNotifications(data?.notifications ?? []);
        setUnreadCount(data?.unreadCount ?? 0);
      }
    } catch { /* silent */ }
  }, []);

  useEffect(() => {
    fetchNotifications();
    const interval = setInterval(fetchNotifications, 30000);
    return () => clearInterval(interval);
  }, [fetchNotifications]);

  const markAllRead = async () => {
    try {
      await fetch('/api/notifications', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ markAllRead: true }),
      });
      setNotifications((prev) => (prev ?? []).map((n: NotificationItem) => ({ ...n, read: true })));
      setUnreadCount(0);
    } catch { /* silent */ }
  };

  const clearAll = async () => {
    try {
      await fetch('/api/notifications', { method: 'DELETE' });
      setNotifications([]);
      setUnreadCount(0);
    } catch { /* silent */ }
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative">
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <span className="absolute -top-0.5 -right-0.5 h-4 min-w-[16px] rounded-full bg-primary text-primary-foreground text-[10px] font-bold flex items-center justify-center px-1">
              {unreadCount > 99 ? '99+' : unreadCount}
            </span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-0" align="end">
        <div className="flex items-center justify-between px-4 py-3 border-b border-border/50">
          <h4 className="font-semibold text-sm">Notifications</h4>
          <div className="flex gap-1">
            {unreadCount > 0 && (
              <Button variant="ghost" size="icon" className="h-7 w-7" onClick={markAllRead} title="Mark all read">
                <Check className="h-3.5 w-3.5" />
              </Button>
            )}
            {(notifications?.length ?? 0) > 0 && (
              <Button variant="ghost" size="icon" className="h-7 w-7" onClick={clearAll} title="Clear all">
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            )}
          </div>
        </div>
        <ScrollArea className="max-h-80">
          {(notifications?.length ?? 0) === 0 ? (
            <p className="text-center text-sm text-muted-foreground py-8">No notifications</p>
          ) : (
            <div className="divide-y divide-border/50">
              {(notifications ?? []).map((n: NotificationItem) => (
                <div
                  key={n?.id}
                  className={cn(
                    'px-4 py-3 text-sm transition-colors',
                    !n?.read && 'bg-primary/5'
                  )}
                >
                  <p className="font-medium">{n?.title ?? ''}</p>
                  <p className="text-muted-foreground text-xs mt-0.5">{n?.message ?? ''}</p>
                  <SafeDate date={n?.createdAt ?? ''} options={{ dateStyle: 'short', timeStyle: 'short' }} className="text-xs text-muted-foreground mt-1 block" />
                </div>
              ))}
            </div>
          )}
        </ScrollArea>
      </PopoverContent>
    </Popover>
  );
}
