import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Pickaxe, Zap } from "lucide-react";
import { useApp } from "@/context/AppContext";
import SpotlightHero from "@/components/hero/SpotlightHero";
import MiningBoosters from "@/components/MiningBoosters";

const TON_ICON = "/images/gram-icon.png";
const USDT_ICON = "/images/usdt.png";
const ease = [0.22, 1, 0.36, 1] as const;

const MiningPage = () => {
  const { user, startMining, getMiningTimeLeft, getMiningProgress } = useApp();
  const [timeLeft, setTimeLeft] = useState("00:00:00");
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const interval = setInterval(() => {
      setTimeLeft(getMiningTimeLeft());
      setProgress(getMiningProgress());
    }, 1000);
    return () => clearInterval(interval);
  }, [getMiningTimeLeft, getMiningProgress]);

  const name = user.telegramUser?.first_name || "Miner";
  const ring = 2 * Math.PI * 88;

  return (
    <SpotlightHero title="Clau">
      <div className="flex w-full flex-col px-5 pb-28 pt-4">
        <header className="flex items-center justify-between">
          <div>
            <p className="nv-eyebrow">Welcome back</p>
            <h1 className="hero-title mt-1 text-2xl">{name}</h1>
          </div>
          <div className="flex items-center gap-2 rounded-full border border-border bg-card/70 px-3 py-1.5">
            <span className={`h-2 w-2 rounded-full ${user.isMining ? "bg-primary animate-pulse" : "bg-muted-foreground"}`} />
            <span className="text-xs font-medium text-muted-foreground">{user.isMining ? "Mining" : "Idle"}</span>
          </div>
        </header>

        <motion.div
          className="relative mx-auto mt-8 flex h-[220px] w-[220px] items-center justify-center"
          initial={{ opacity: 0, scale: 0.94 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.5, ease }}
        >
          <svg className="absolute inset-0 -rotate-90" viewBox="0 0 200 200">
            <circle cx="100" cy="100" r="88" fill="none" stroke="hsl(var(--foreground) / 0.08)" strokeWidth="6" />
            <circle
              cx="100" cy="100" r="88" fill="none" stroke="url(#clauRing)" strokeWidth="6" strokeLinecap="round"
              strokeDasharray={ring} strokeDashoffset={ring * (1 - (user.isMining ? progress : 0) / 100)}
              style={{ transition: "stroke-dashoffset 1s linear" }}
            />
            <defs>
              <linearGradient id="clauRing" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stopColor="hsl(var(--primary))" />
                <stop offset="100%" stopColor="hsl(var(--accent))" />
              </linearGradient>
            </defs>
          </svg>
          <div className="absolute inset-6 rounded-full bg-primary/10 blur-2xl" />
          <div className="relative text-center">
            <p className="nv-eyebrow">$CLAU</p>
            <p className="hero-title mt-1 text-[44px] leading-none tracking-tight">
              {user.siriBalance.toLocaleString("en-US", { maximumFractionDigits: 2 })}
            </p>
            <p className="mt-2 font-mono text-xs text-muted-foreground">
              {user.isMining ? timeLeft : "Ready to mine"}
            </p>
          </div>
        </motion.div>

        <button
          onClick={user.isMining ? undefined : startMining}
          disabled={user.isMining}
          className="nv-pill mt-8 w-full disabled:opacity-60"
        >
          {user.isMining ? <Zap className="h-5 w-5" /> : <Pickaxe className="h-5 w-5" />}
          {user.isMining ? `Mining · ${progress.toFixed(0)}%` : "Start Mining"}
        </button>

        <motion.div
          className="mt-4 grid grid-cols-2 gap-3"
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.08, duration: 0.4, ease }}
        >
          {[
            { label: "Gram", value: user.tonBalance, icon: TON_ICON },
            { label: "USDT", value: user.usdtBalance, icon: USDT_ICON },
          ].map((s) => (
            <div key={s.label} className="nv-card flex items-center gap-3 p-4">
              <img src={s.icon} alt={s.label} className="h-9 w-9 shrink-0 rounded-xl object-cover" loading="lazy" />
              <div className="min-w-0">
                <p className="text-xs text-muted-foreground">{s.label}</p>
                <p className="nv-stat-num truncate text-xl">
                  {Number(s.value || 0).toLocaleString("en-US", { maximumFractionDigits: 4 })}
                </p>
              </div>
            </div>
          ))}
        </motion.div>

        <MiningBoosters />
      </div>
    </SpotlightHero>
  );
};

export default MiningPage;
