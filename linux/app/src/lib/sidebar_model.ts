export interface ChatBrief {
  id: string;
  title?: string | null;
  lastMessage?: string | null;
  hasActiveTurn?: boolean;
  isPinned?: boolean;
  pinned?: boolean;
  isArchived?: boolean;
  archived?: boolean;
  projectId?: string | null;
  project_id?: string | null;
  projectName?: string | null;
  project_name?: string | null;
  cwd?: string | null;
}

export interface ProjectBrief {
  id?: string | null;
  title?: string | null;
  name?: string | null;
  cwd?: string | null;
}

export interface SidebarProject {
  id: string;
  name: string;
  chats: ChatBrief[];
}

export interface SidebarModel {
  all: ChatBrief[];
  pinned: ChatBrief[];
  archived: ChatBrief[];
  projects: SidebarProject[];
  projectless: ChatBrief[];
}

export type ChatCollectionKind = "all" | "pinned" | "archived" | "project" | "projects";

export interface ChatCollection {
  kind: ChatCollectionKind;
  title: string;
  empty: string;
  chats: ChatBrief[];
  projects: SidebarProject[];
}

export function deriveSidebarModel(chats: ChatBrief[], explicitProjects: ProjectBrief[] = []): SidebarModel {
  const all = chats.filter((chat) => !isArchivedChat(chat));
  const pinned = all.filter(isPinnedChat);
  const archived = chats.filter(isArchivedChat);
  const projectBuckets = new Map<string, SidebarProject>();
  const projectless: ChatBrief[] = [];

  for (const chat of all) {
    const projectId = chatProjectKey(chat);
    if (!projectId) {
      projectless.push(chat);
      continue;
    }

    const existing = projectBuckets.get(projectId);
    if (existing) {
      existing.chats.push(chat);
      continue;
    }

    projectBuckets.set(projectId, {
      id: projectId,
      name: projectName(chat, projectId),
      chats: [chat]
    });
  }

  for (const project of explicitProjects) {
    const id = projectBriefKey(project);
    if (!id || projectBuckets.has(id)) continue;
    projectBuckets.set(id, {
      id,
      name: projectName(project, id),
      chats: []
    });
  }

  return {
    all,
    pinned,
    archived,
    projects: Array.from(projectBuckets.values()).sort((a, b) => a.name.localeCompare(b.name)),
    projectless
  };
}

export function collectionForPath(
  chats: ChatBrief[],
  path: string,
  explicitProjects: ProjectBrief[] = []
): ChatCollection {
  const model = deriveSidebarModel(chats, explicitProjects);
  const normalizedPath = path.replace(/\/+$/, "") || "/";

  if (normalizedPath === "/pinned") {
    return {
      kind: "pinned",
      title: "Pinned",
      empty: "You do not have any pinned chats yet.",
      chats: model.pinned,
      projects: []
    };
  }

  if (normalizedPath === "/archived") {
    return {
      kind: "archived",
      title: "Archived",
      empty: "No archived chats yet.",
      chats: model.archived,
      projects: []
    };
  }

  if (normalizedPath === "/projects") {
    return {
      kind: "projects",
      title: "Projects",
      empty: "No projects yet.",
      chats: [],
      projects: model.projects
    };
  }

  if (normalizedPath.startsWith("/projects/")) {
    const projectId = decodeURIComponent(normalizedPath.slice("/projects/".length));
    const project = model.projects.find((item) => item.id === projectId);
    return {
      kind: "project",
      title: project?.name ?? "Project",
      empty: "No chats in this project yet.",
      chats: project?.chats ?? [],
      projects: []
    };
  }

  return {
    kind: "all",
    title: "All Chats",
    empty: "Start a conversation.",
    chats: model.all,
    projects: []
  };
}

function isPinnedChat(chat: ChatBrief): boolean {
  return chat.isPinned === true || chat.pinned === true;
}

function isArchivedChat(chat: ChatBrief): boolean {
  return chat.isArchived === true || chat.archived === true;
}

function chatProjectKey(chat: ChatBrief): string | null {
  return clean(chat.projectId) ?? clean(chat.project_id) ?? clean(chat.cwd);
}

function projectBriefKey(project: ProjectBrief): string | null {
  return clean(project.id) ?? clean(project.cwd);
}

function projectName(source: ChatBrief | ProjectBrief, fallback: string): string {
  return clean("projectName" in source ? source.projectName : null)
    ?? clean("project_name" in source ? source.project_name : null)
    ?? clean("title" in source ? source.title : null)
    ?? clean("name" in source ? source.name : null)
    ?? basename(fallback);
}

function clean(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function basename(value: string): string {
  const parts = value.split("/").filter(Boolean);
  return parts.at(-1) ?? value;
}
