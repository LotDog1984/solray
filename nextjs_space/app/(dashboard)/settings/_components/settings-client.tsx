'use client';

import { useState } from 'react';
import { useTheme } from 'next-themes';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { User, Moon, Sun, Shield, UserPlus, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { FadeIn } from '@/components/ui/animate';
import { SafeDate } from '@/components/safe-format';
import { cn } from '@/lib/utils';
import { ClientOnly } from '@/components/client-only';

interface SettingsClientProps {
  user: { id: string; name: string; email: string; role: string };
  users: any[];
}

export function SettingsClient({ user, users: initialUsers }: SettingsClientProps) {
  const { theme, setTheme } = useTheme();
  const [name, setName] = useState(user?.name ?? '');
  const [email, setEmail] = useState(user?.email ?? '');
  const [password, setPassword] = useState('');
  const [saving, setSaving] = useState(false);
  const [users, setUsers] = useState(initialUsers ?? []);
  const [showNewUser, setShowNewUser] = useState(false);
  const [newUserName, setNewUserName] = useState('');
  const [newUserEmail, setNewUserEmail] = useState('');
  const [newUserPassword, setNewUserPassword] = useState('');
  const [newUserRole, setNewUserRole] = useState('MEMBER');
  const [creatingUser, setCreatingUser] = useState(false);

  const isAdmin = user?.role === 'ADMIN';

  const saveProfile = async () => {
    setSaving(true);
    try {
      const data: any = { name, email };
      if (password) data.password = password;
      const res = await fetch(`/api/users/${user.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (res?.ok) {
        toast.success('Profile updated');
        setPassword('');
      } else {
        const err = await res.json();
        toast.error(err?.error ?? 'Failed to update');
      }
    } catch {
      toast.error('Failed to update profile');
    }
    setSaving(false);
  };

  const createUser = async () => {
    if (!newUserName || !newUserEmail || !newUserPassword) {
      toast.error('All fields are required');
      return;
    }
    setCreatingUser(true);
    try {
      const res = await fetch('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: newUserName,
          email: newUserEmail,
          password: newUserPassword,
          role: newUserRole,
        }),
      });
      if (res?.ok) {
        const newUser = await res.json();
        setUsers((prev: any[]) => [...(prev ?? []), newUser]);
        toast.success('User created');
        setShowNewUser(false);
        setNewUserName('');
        setNewUserEmail('');
        setNewUserPassword('');
        setNewUserRole('MEMBER');
      } else {
        const err = await res.json();
        toast.error(err?.error ?? 'Failed to create user');
      }
    } catch {
      toast.error('Failed to create user');
    }
    setCreatingUser(false);
  };

  const toggleUserActive = async (userId: string, active: boolean) => {
    try {
      const res = await fetch(`/api/users/${userId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ active }),
      });
      if (res?.ok) {
        setUsers((prev: any[]) =>
          (prev ?? []).map((u: any) => u?.id === userId ? { ...u, active } : u)
        );
        toast.success(active ? 'User activated' : 'User deactivated');
      }
    } catch {
      toast.error('Failed to update user');
    }
  };

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <FadeIn>
        <h1 className="text-2xl font-display font-bold tracking-tight">Settings</h1>
        <p className="text-muted-foreground text-sm mt-1">Manage your account and preferences</p>
      </FadeIn>

      {/* Theme */}
      <FadeIn delay={0.05}>
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <ClientOnly fallback={<Sun className="h-4 w-4" />}>
                {theme === 'dark' ? <Moon className="h-4 w-4" /> : <Sun className="h-4 w-4" />}
              </ClientOnly>
              Appearance
            </CardTitle>
            <CardDescription>Choose your preferred theme</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex items-center justify-between">
              <span className="text-sm">Dark Mode</span>
              <ClientOnly fallback={<Switch />}>
                <Switch
                  checked={theme === 'dark'}
                  onCheckedChange={(checked: boolean) => setTheme(checked ? 'dark' : 'light')}
                />
              </ClientOnly>
            </div>
          </CardContent>
        </Card>
      </FadeIn>

      {/* Profile */}
      <FadeIn delay={0.1}>
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <User className="h-4 w-4" /> Profile
            </CardTitle>
            <CardDescription>Update your personal information</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="settings-name">Name</Label>
              <Input id="settings-name" value={name} onChange={(e) => setName(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="settings-email">Email</Label>
              <Input id="settings-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="settings-password">New Password (leave blank to keep current)</Label>
              <Input id="settings-password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" />
            </div>
            <Button onClick={saveProfile} disabled={saving}>
              {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Save Changes
            </Button>
          </CardContent>
        </Card>
      </FadeIn>

      {/* Admin: User Management */}
      {isAdmin && (
        <FadeIn delay={0.15}>
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-base flex items-center gap-2">
                    <Shield className="h-4 w-4" /> User Management
                  </CardTitle>
                  <CardDescription>Create and manage team members</CardDescription>
                </div>
                <Button size="sm" onClick={() => setShowNewUser(true)}>
                  <UserPlus className="mr-2 h-3.5 w-3.5" /> Add User
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {(users ?? []).map((u: any) => (
                  <div key={u?.id} className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium">{u?.name ?? 'User'}</span>
                        <Badge variant={u?.role === 'ADMIN' ? 'default' : 'secondary'} className="text-[10px] h-5">
                          {u?.role ?? 'MEMBER'}
                        </Badge>
                        {!u?.active && (
                          <Badge variant="outline" className="text-[10px] h-5 text-destructive">Inactive</Badge>
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground">{u?.email ?? ''}</p>
                    </div>
                    {u?.id !== user?.id && (
                      <Switch
                        checked={u?.active ?? false}
                        onCheckedChange={(checked: boolean) => toggleUserActive(u?.id, checked)}
                      />
                    )}
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </FadeIn>
      )}

      {/* New User Dialog */}
      <Dialog open={showNewUser} onOpenChange={(v) => !v && setShowNewUser(false)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Create New User</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Name</Label>
              <Input value={newUserName} onChange={(e) => setNewUserName(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Email</Label>
              <Input type="email" value={newUserEmail} onChange={(e) => setNewUserEmail(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Password</Label>
              <Input type="password" value={newUserPassword} onChange={(e) => setNewUserPassword(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Role</Label>
              <Select value={newUserRole} onValueChange={setNewUserRole}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="MEMBER">Member</SelectItem>
                  <SelectItem value="ADMIN">Admin</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setShowNewUser(false)}>Cancel</Button>
              <Button onClick={createUser} disabled={creatingUser}>
                {creatingUser && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Create User
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
