import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/MiningPage";

export const Route = createFileRoute("/")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Clau — Mine $CLAU & Earn Rewards" },
      { name: "description", content: "Mine $CLAU, complete tasks and earn rewards in the Clau Telegram app." },
      { property: "og:title", content: "Clau — Mine $CLAU & Earn Rewards" },
      { property: "og:description", content: "Mine $CLAU, complete tasks and earn rewards in the Clau Telegram app." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});
