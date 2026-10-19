import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/GamesPage";

export const Route = createFileRoute("/ai")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Clau Games - Play Crash & Earn Gram" },
      { name: "description", content: "Play Crash and other games in Clau and win Gram." },
      { property: "og:title", content: "Clau Games - Play Crash & Earn Gram" },
      { property: "og:description", content: "Play Crash and other games in Clau and win Gram." },
    ],
  }),
});
