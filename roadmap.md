# Clau roadmap

- [x] Enable Lovable Cloud (new database, old one untouched)
- [x] Build final schema from old repo (old cron jobs/URLs stripped), split into /tmp/chunk0-4.sql
- [x] Apply schema parts 1-2
- [ ] Apply schema parts 3-5 (tables, policies, grants, seed data: servers, staking plans, pvp)
- [ ] Copy repo code into project; remove hardcoded old backend fallbacks (supabase-config, tonconnect-manifest, __root preconnect)
- [ ] Rename app branding Nova -> Clau
- [ ] New design for all pages except the Crash game page
- [ ] Save bot token secret (TELEGRAM_BOT_TOKEN) and move bot to a server route + set webhook
- [ ] Admin panel: user count, broadcast to all users, add/delete tasks (bot asks name, then image, then link step by step)
- [ ] Test end-to-end
