<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

## Clau architecture
- Old backend edge functions are replaced by server handlers in `src/lib/fn-handlers.server.ts`, dispatched via `/api/public/fn/$name`; client calls go through `invokeFn` in `src/lib/fn.ts`. Why: one runtime, no external backend.
- Telegram bot lives in `src/lib/bot.server.ts`, webhook at `/api/public/telegram-webhook`, guarded by a secret derived from the bot token. Admins are rows in `telegram_admins`; multi-step admin input is stored in `telegram_task_drafts`.
- Game routes (/games, /war, /101) keep the original look; other pages use the shared Clau theme tokens.
- Production frontend is hosted on Vercel (project clau-app); there `PROXY_API_ORIGIN` forwards /api/public/* to the Lovable stable dev host, which holds server secrets. Bot links use the `APP_URL` secret. Why: Vercel cannot hold the managed backend keys.
