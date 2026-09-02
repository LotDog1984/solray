'use client';

import { useState } from 'react';
import Link from 'next/link';
import { Plus, FolderKanban, Users, Clock } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { SafeDate } from '@/components/safe-format';
import { NewProjectModal } from './new-project-modal';
import { FadeIn, Stagger, StaggerItem, HoverLift } from '@/components/ui/animate';

interface ProjectsGridProps {
  initialProjects: any[];
  users: any[];
  currentUserId: string;
  userRole: string;
}

export function ProjectsGrid({ initialProjects, users, currentUserId, userRole }: ProjectsGridProps) {
  const [projects, setProjects] = useState(initialProjects ?? []);
  const [showNewProject, setShowNewProject] = useState(false);

  const handleProjectCreated = (project: any) => {
    setProjects((prev: any[]) => [project, ...(prev ?? [])]);
    setShowNewProject(false);
  };

  return (
    <div>
      <FadeIn>
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-display font-bold tracking-tight">Projects</h1>
            <p className="text-muted-foreground text-sm mt-1">Manage your workshop projects</p>
          </div>
          <Button onClick={() => setShowNewProject(true)}>
            <Plus className="mr-2 h-4 w-4" />
            New Project
          </Button>
        </div>
      </FadeIn>

      {(projects?.length ?? 0) === 0 ? (
        <FadeIn delay={0.1}>
          <div className="text-center py-20">
            <FolderKanban className="mx-auto h-12 w-12 text-muted-foreground/50 mb-4" />
            <h3 className="text-lg font-medium">No projects yet</h3>
            <p className="text-muted-foreground text-sm mt-1">Create your first project to get started</p>
            <Button onClick={() => setShowNewProject(true)} className="mt-4">
              <Plus className="mr-2 h-4 w-4" />
              New Project
            </Button>
          </div>
        </FadeIn>
      ) : (
        <Stagger staggerDelay={0.05}>
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {(projects ?? []).map((project: any) => (
              <StaggerItem key={project?.id}>
                <HoverLift>
                  <Link href={`/projects/${project?.id}`}>
                    <Card className="cursor-pointer border-border/50 hover:border-primary/30 transition-colors h-full">
                      <CardContent className="p-5">
                        <div className="flex items-start justify-between mb-3">
                          <div className="flex items-center gap-3">
                            <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center">
                              <FolderKanban className="h-5 w-5 text-primary" />
                            </div>
                            <div>
                              <h3 className="font-semibold text-sm">{project?.name ?? 'Untitled'}</h3>
                              {project?.description && (
                                <p className="text-xs text-muted-foreground line-clamp-1 mt-0.5">
                                  {project.description}
                                </p>
                              )}
                            </div>
                          </div>
                        </div>

                        <div className="flex items-center gap-4 text-xs text-muted-foreground">
                          <div className="flex items-center gap-1">
                            <Users className="h-3.5 w-3.5" />
                            <span>{project?.members?.length ?? 0} members</span>
                          </div>
                          <div className="flex items-center gap-1">
                            <Clock className="h-3.5 w-3.5" />
                            <SafeDate date={project?.createdAt ?? ''} options={{ dateStyle: 'medium' }} />
                          </div>
                        </div>

                        {(project?.members?.length ?? 0) > 0 && (
                          <div className="flex -space-x-2 mt-3">
                            {(project?.members ?? []).slice(0, 5).map((m: any) => (
                              <Avatar key={m?.id} className="h-7 w-7 border-2 border-card">
                                <AvatarFallback className="bg-primary/10 text-primary text-[10px] font-semibold">
                                  {(m?.user?.name ?? 'U').slice(0, 2).toUpperCase()}
                                </AvatarFallback>
                              </Avatar>
                            ))}
                            {(project?.members?.length ?? 0) > 5 && (
                              <div className="h-7 w-7 rounded-full bg-muted flex items-center justify-center text-[10px] font-medium border-2 border-card">
                                +{(project?.members?.length ?? 0) - 5}
                              </div>
                            )}
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  </Link>
                </HoverLift>
              </StaggerItem>
            ))}
          </div>
        </Stagger>
      )}

      <NewProjectModal
        open={showNewProject}
        onClose={() => setShowNewProject(false)}
        onCreated={handleProjectCreated}
        users={users}
        currentUserId={currentUserId}
      />
    </div>
  );
}
