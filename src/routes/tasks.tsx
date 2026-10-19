import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/TasksPage";

export const Route = createFileRoute("/tasks")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Clau - Mine, Battle & Earn Gram" },
      { name: "description", content: "Clau: mine CLAU, battle monsters, and earn Gram cryptocurrency" },
    ],
  }),
});
