import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/StakingPage";

export const Route = createFileRoute("/staking")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Gram Staking Bonds | Nova AI" },
      { name: "description", content: "Open Gram and NOVA staking bonds, track yield, and manage active investments." },
      { property: "og:title", content: "Gram Staking Bonds | Nova AI" },
      { property: "og:description", content: "Open Gram and NOVA staking bonds and track your active investments." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});
