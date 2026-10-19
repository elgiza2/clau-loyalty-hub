import { useEffect, useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { ArrowUpRight, X } from "lucide-react";
import { GRAM_USD_FALLBACK, prizeInGram } from "@/lib/prize";

const prizeImage = { url: "/images/prize-notify-1.jpg" };

/**
 * Congrats popup: tells every player they won $25,000 and links to the wallet.
 * No storage gate of any kind, so it appears for every visitor on every visit —
 * existing players, returning players and anyone who joins later.
 */
const PrizePopup = () => {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    const timer = window.setTimeout(() => setOpen(true), 1200);
    return () => window.clearTimeout(timer);
  }, []);


  const goWithdraw = () => {
    setOpen(false);
    navigate({ to: "/wallet" });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="w-[calc(100%-1.5rem)] max-w-[380px] overflow-hidden rounded-3xl border border-border bg-card p-0 shadow-2xl [&>button]:hidden">
        <Button
          type="button"
          variant="ghost"
          size="icon"
          onClick={() => setOpen(false)}
          className="absolute right-3 top-3 z-20 h-9 w-9 rounded-full bg-background/75 text-foreground backdrop-blur-md hover:bg-background"
          aria-label="Close"
        >
          <X className="h-4 w-4" />
        </Button>

        <div className="relative aspect-[16/9] overflow-hidden">
          <img
            src={prizeImage.url}
            alt="Nova prize reward"
            className="h-full w-full object-cover"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-card via-card/15 to-transparent" />
        </div>

        <div className="px-6 pb-6 pt-1 text-center">
          <p className="text-[10px] font-semibold uppercase tracking-[0.2em] text-primary">Prize confirmed</p>
          <h2 className="mt-2 font-display text-3xl text-foreground">Congratulations</h2>
          <p className="mt-1 text-sm text-muted-foreground">You won a prize worth</p>
          <p className="mt-2 font-display text-5xl leading-none text-gold">$25,000</p>
          <p className="mt-1 text-xs font-semibold text-muted-foreground">
            {prizeInGram(GRAM_USD_FALLBACK).toLocaleString("en-US", { maximumFractionDigits: 2 })} GRAM
          </p>
          <p className="mx-auto mt-4 max-w-[280px] text-xs leading-relaxed text-muted-foreground">
            Your reward is ready. Open your wallet and choose the amount you want to withdraw.
          </p>
          <Button onClick={goWithdraw} className="mt-5 h-13 w-full rounded-xl text-sm font-semibold" size="lg">
            Withdraw prize
            <ArrowUpRight className="h-4 w-4" />
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default PrizePopup;
