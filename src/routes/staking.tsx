import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/StakingPage";

export const Route = createFileRoute("/staking")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Gram Staking Bonds | Clau" },
      { name: "description", content: "Open Gram and CLAU staking bonds, track yield, and manage active investments." },
      { property: "og:title", content: "Gram Staking Bonds | Clau" },
      { property: "og:description", content: "Open Gram and CLAU staking bonds and track your active investments." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});
