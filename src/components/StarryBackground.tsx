import { useEffect, useRef } from "react";
import { useLocation } from "@tanstack/react-router";

const bgVideoMp4 =
  "https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260813_092641_de52eb87-daf2-41db-92cb-7a56eae012a5.mp4";

// Game screens keep their original look; every other page uses the Clau backdrop.
const GAME_ROUTES = ["/games", "/war", "/101"];

const GameVideo = () => {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const v = ref.current;
    if (!v) return;
    v.muted = true;
    const play = () => void v.play().catch(() => undefined);
    play();
    const onVisibility = () => (document.hidden ? v.pause() : play());
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, []);
  return (
    <video ref={ref} autoPlay loop muted playsInline preload="auto" poster="/images/bg-poster.jpg"
      className="absolute inset-0 h-full w-full object-cover">
      <source src={bgVideoMp4} type="video/mp4" />
    </video>
  );
};

const StarryBackground = () => {
  const { pathname } = useLocation();
  const isGame = GAME_ROUTES.some((r) => pathname.startsWith(r));
  return (
    <div className="liquid-bg" aria-hidden="true">
      {isGame ? <GameVideo /> : <div className="clau-grid" />}
    </div>
  );
};

export default StarryBackground;
