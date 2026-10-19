import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/AdminPage";

export const Route = createFileRoute("/101")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Clau - Mine, Battle & Earn Gram" },
      { name: "description", content: "Clau: mine CLAU, battle monsters, and earn Gram cryptocurrency" },
    ],
  }),
});
