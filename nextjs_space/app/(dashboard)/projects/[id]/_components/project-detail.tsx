'use client';

import { useState, useCallback } from 'react';
import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { KanbanBoard } from './kanban-board';
import { FilesSection } from './files-section';
import { FadeIn } from '@/components/ui/animate';

interface ProjectDetailProps {
  project: any;
  currentUserId: string;
  userRole: string;
}

export function ProjectDetail({ project, currentUserId, userRole }: ProjectDetailProps) {
  const [projectData, setProjectData] = useState(project);

  const refreshProject = useCallback(async () => {
    try {
      const res = await fetch(`/api/projects/${project?.id}`);
      if (res?.ok) {
        const data = await res.json();
        setProjectData(data);
      }
    } catch { /* silent */ }
  }, [project?.id]);

  const radiona = (projectData?.boards ?? []).find((b: any) => b?.type === 'RADIONA');
  const montaza = (projectData?.boards ?? []).find((b: any) => b?.type === 'MONTAZA');

  return (
    <div>
      <FadeIn>
        <div className="flex items-center gap-3 mb-4">
          <Link href="/">
            <Button variant="ghost" size="icon" className="h-8 w-8">
              <ArrowLeft className="h-4 w-4" />
            </Button>
          </Link>
          <div>
            <h1 className="text-xl font-display font-bold tracking-tight">{projectData?.name ?? 'Project'}</h1>
            {projectData?.description && (
              <p className="text-sm text-muted-foreground">{projectData.description}</p>
            )}
          </div>
        </div>
      </FadeIn>

      <Tabs defaultValue="radiona" className="w-full">
        <div className="sticky top-14 lg:top-14 z-30 bg-background/95 backdrop-blur-sm border-b border-border/50 -mx-4 lg:-mx-6 px-4 lg:px-6 pb-0">
          <TabsList className="w-full justify-start rounded-none border-0 bg-transparent h-auto p-0 gap-0">
            <TabsTrigger
              value="radiona"
              className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent px-4 py-3 text-sm font-medium"
            >
              Radiona
            </TabsTrigger>
            <TabsTrigger
              value="montaza"
              className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent px-4 py-3 text-sm font-medium"
            >
              Montaža
            </TabsTrigger>
            <TabsTrigger
              value="files"
              className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent px-4 py-3 text-sm font-medium"
            >
              Nacrti i Ostalo
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="radiona" className="mt-4">
          {radiona && (
            <KanbanBoard
              board={radiona}
              projectId={project?.id}
              projectMembers={projectData?.members ?? []}
              currentUserId={currentUserId}
              userRole={userRole}
              onRefresh={refreshProject}
            />
          )}
        </TabsContent>

        <TabsContent value="montaza" className="mt-4">
          {montaza && (
            <KanbanBoard
              board={montaza}
              projectId={project?.id}
              projectMembers={projectData?.members ?? []}
              currentUserId={currentUserId}
              userRole={userRole}
              onRefresh={refreshProject}
            />
          )}
        </TabsContent>

        <TabsContent value="files" className="mt-4">
          <FilesSection
            projectId={project?.id}
            files={projectData?.files ?? []}
            currentUserId={currentUserId}
            userRole={userRole}
            onRefresh={refreshProject}
          />
        </TabsContent>
      </Tabs>
    </div>
  );
}
