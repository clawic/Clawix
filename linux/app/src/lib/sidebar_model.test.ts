import { describe, expect, it } from "vitest";
import { collectionForPath, deriveSidebarModel, type ChatBrief } from "./sidebar_model";

const chats: ChatBrief[] = [
  { id: "1", title: "Pinned project", isPinned: true, projectId: "alpha", projectName: "Alpha" },
  { id: "2", title: "Project chat", project_id: "beta", project_name: "Beta" },
  { id: "3", title: "Loose chat" },
  { id: "4", title: "Archived pinned", pinned: true, archived: true, projectId: "alpha" }
];

describe("deriveSidebarModel", () => {
  it("separates all, pinned, archived, project, and projectless chats", () => {
    const model = deriveSidebarModel(chats, [{ id: "gamma", title: "Gamma" }]);

    expect(model.all.map((chat) => chat.id)).toEqual(["1", "2", "3"]);
    expect(model.pinned.map((chat) => chat.id)).toEqual(["1"]);
    expect(model.archived.map((chat) => chat.id)).toEqual(["4"]);
    expect(model.projectless.map((chat) => chat.id)).toEqual(["3"]);
    expect(model.projects.map((project) => [project.id, project.name, project.chats.map((chat) => chat.id)])).toEqual([
      ["alpha", "Alpha", ["1"]],
      ["beta", "Beta", ["2"]],
      ["gamma", "Gamma", []]
    ]);
  });
});

describe("collectionForPath", () => {
  it("returns pinned, project list, project detail, archived, and all chat collections", () => {
    expect(collectionForPath(chats, "/pinned").chats.map((chat) => chat.id)).toEqual(["1"]);
    expect(collectionForPath(chats, "/projects").projects.map((project) => project.id)).toEqual(["alpha", "beta"]);
    expect(collectionForPath(chats, "/projects", [{ cwd: "/tmp/gamma", title: "Gamma" }]).projects.map((project) => project.id)).toEqual(["alpha", "beta", "/tmp/gamma"]);
    expect(collectionForPath(chats, "/projects/beta").chats.map((chat) => chat.id)).toEqual(["2"]);
    expect(collectionForPath(chats, "/archived").chats.map((chat) => chat.id)).toEqual(["4"]);
    expect(collectionForPath(chats, "/all-chats").chats.map((chat) => chat.id)).toEqual(["1", "2", "3"]);
  });
});
