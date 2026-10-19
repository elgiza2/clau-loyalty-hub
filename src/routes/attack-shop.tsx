import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/AttackShopPage";

export const Route = createFileRoute("/attack-shop")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Clau - Mine, Battle & Earn Gram" },
      { name: "description", content: "Clau: mine CLAU, battle monsters, and earn Gram cryptocurrency" },
    ],
  }),
});
