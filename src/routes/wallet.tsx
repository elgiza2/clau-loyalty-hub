import { createFileRoute } from "@tanstack/react-router";
import Page from "@/pages/WalletPage";

export const Route = createFileRoute("/wallet")({
  component: Page,
  head: () => ({
    meta: [
      { title: "Clau - Mine, Battle & Earn Gram" },
      { name: "description", content: "Clau: mine CLAU, battle monsters, and earn Gram cryptocurrency" },
    ],
  }),
});
