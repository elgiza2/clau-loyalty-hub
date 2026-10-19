import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/ServersPage";

export const Route = createFileRoute("/servers")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Clau - Mine, Battle & Earn Gram" },
      { name: "description", content: "Clau: mine CLAU, battle monsters, and earn Gram cryptocurrency" },
    ],
  }),
});
