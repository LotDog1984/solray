import { auth } from '@/auth';
import { redirect } from 'next/navigation';
import { prisma } from '@/lib/prisma';
import { LoginForm } from './_components/login-form';

export default async function LoginPage() {
  const session = await auth();
  if (session?.user) redirect('/');

  const adminCount = await prisma.user.count({ where: { role: 'ADMIN' } });
  if (adminCount === 0) redirect('/setup');

  return (
    <div className="min-h-screen flex items-center justify-center bg-background hero-gradient">
      <div className="w-full max-w-md px-4">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-display font-bold tracking-tight">Solray</h1>
          <p className="text-muted-foreground mt-2">Sign in to your workspace</p>
        </div>
        <LoginForm />
      </div>
    </div>
  );
}
