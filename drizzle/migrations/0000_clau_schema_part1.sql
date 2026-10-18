SET check_function_bodies = false;
CREATE TYPE public.app_role AS ENUM ('admin','user');
CREATE FUNCTION public.__exec_sql(sql text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
EXECUTE sql;
END;
$$;
CREATE FUNCTION public.ad_watch_claim(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_count integer; v_p public.profiles%ROWTYPE;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'NO_PROFILE'); END IF;
UPDATE public.ad_watch_progress
SET ads_watched = ads_watched - 500,
total_claims = total_claims + 1,
updated_at = now()
WHERE user_id = v_uid AND ads_watched >= 500
RETURNING ads_watched INTO v_count;
IF NOT FOUND THEN
SELECT COALESCE(ads_watched, 0) INTO v_count FROM public.ad_watch_progress WHERE user_id = v_uid;
RETURN jsonb_build_object('success', false, 'error', 'NOT_ENOUGH_ADS', 'adsWatched', COALESCE(v_count, 0));
END IF;
UPDATE public.profiles SET ton_balance = ton_balance + 0.5 WHERE id = v_uid;
SELECT * INTO v_p FROM public.profiles WHERE id = v_uid;
RETURN jsonb_build_object('success', true, 'rewardAmount', 0.5, 'rewardType', 'ton', 'adsWatched', v_count,
'balances', jsonb_build_object('siri', v_p.siri_balance, 'ton', v_p.ton_balance, 'usdt', v_p.usdt_balance));
END; $$;
CREATE FUNCTION public.ad_watch_claim(_telegram_id bigint, _tier text DEFAULT 'a'::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_count integer; v_p public.profiles%ROWTYPE; v_goal integer; v_reward numeric;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'NO_PROFILE'); END IF;
IF _tier = 'b' THEN
v_goal := 1000; v_reward := 5;
UPDATE public.ad_watch_progress
SET ads_watched_b = ads_watched_b - v_goal,
total_claims_b = total_claims_b + 1,
updated_at = now()
WHERE user_id = v_uid AND ads_watched_b >= v_goal
RETURNING ads_watched_b INTO v_count;
ELSE
v_goal := 500; v_reward := 0.5;
UPDATE public.ad_watch_progress
SET ads_watched = ads_watched - v_goal,
total_claims = total_claims + 1,
updated_at = now()
WHERE user_id = v_uid AND ads_watched >= v_goal
RETURNING ads_watched INTO v_count;
END IF;
IF NOT FOUND THEN
IF _tier = 'b' THEN
SELECT COALESCE(ads_watched_b, 0) INTO v_count FROM public.ad_watch_progress WHERE user_id = v_uid;
ELSE
SELECT COALESCE(ads_watched, 0) INTO v_count FROM public.ad_watch_progress WHERE user_id = v_uid;
END IF;
RETURN jsonb_build_object('success', false, 'error', 'NOT_ENOUGH_ADS', 'adsWatched', COALESCE(v_count, 0));
END IF;
UPDATE public.profiles SET ton_balance = ton_balance + v_reward WHERE id = v_uid;
SELECT * INTO v_p FROM public.profiles WHERE id = v_uid;
RETURN jsonb_build_object('success', true, 'rewardAmount', v_reward, 'rewardType', 'ton', 'adsWatched', v_count,
'balances', jsonb_build_object('siri', v_p.siri_balance, 'ton', v_p.ton_balance, 'usdt', v_p.usdt_balance));
END; $$;
CREATE FUNCTION public.ad_watch_get_progress(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_r public.ad_watch_progress%ROWTYPE;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'adsWatched', 0, 'totalClaims', 0, 'adsWatchedB', 0, 'totalClaimsB', 0); END IF;
SELECT * INTO v_r FROM public.ad_watch_progress WHERE user_id = v_uid;
RETURN jsonb_build_object(
'success', true,
'adsWatched', COALESCE(v_r.ads_watched, 0),
'totalClaims', COALESCE(v_r.total_claims, 0),
'adsWatchedB', COALESCE(v_r.ads_watched_b, 0),
'totalClaimsB', COALESCE(v_r.total_claims_b, 0)
);
END; $$;
CREATE FUNCTION public.ad_watch_increment(_telegram_id bigint, _tier text DEFAULT 'a'::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_a integer; v_b integer; v_last timestamptz;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'adsWatched', 0, 'adsWatchedB', 0); END IF;
SELECT updated_at, ads_watched, ads_watched_b INTO v_last, v_a, v_b
FROM public.ad_watch_progress WHERE user_id = v_uid;
IF v_last IS NOT NULL AND v_last > now() - interval '10 seconds' THEN
RETURN jsonb_build_object('success', false, 'error', 'too_fast',
'adsWatched', COALESCE(v_a, 0), 'adsWatchedB', COALESCE(v_b, 0));
END IF;
IF _tier = 'b' THEN
INSERT INTO public.ad_watch_progress (user_id, ads_watched_b)
VALUES (v_uid, 1)
ON CONFLICT (user_id) DO UPDATE
SET ads_watched_b = LEAST(public.ad_watch_progress.ads_watched_b + 1, 1000), updated_at = now()
RETURNING ads_watched, ads_watched_b INTO v_a, v_b;
ELSE
INSERT INTO public.ad_watch_progress (user_id, ads_watched)
VALUES (v_uid, 1)
ON CONFLICT (user_id) DO UPDATE
SET ads_watched = LEAST(public.ad_watch_progress.ads_watched + 1, 500), updated_at = now()
RETURNING ads_watched, ads_watched_b INTO v_a, v_b;
END IF;
RETURN jsonb_build_object('success', true, 'adsWatched', COALESCE(v_a, 0), 'adsWatchedB', COALESCE(v_b, 0));
END; $$;
CREATE FUNCTION public.admin_activate_character_for_telegram(_telegram_id bigint, _character_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
UPDATE public.characters SET is_active = false WHERE is_active = true;
UPDATE public.characters SET is_active = true WHERE id = _character_id;
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.admin_activate_reward_for_telegram(_telegram_id bigint, _reward_amount numeric) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public'
AS $$ SELECT jsonb_build_object('updated', 0, 'disabled', true) $$;
CREATE FUNCTION public.admin_broadcast_notification_for_telegram(_telegram_id bigint, _title text, _message text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_count integer;
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
INSERT INTO public.game_notifications (user_id, title, message)
SELECT id, _title, _message FROM public.profiles WHERE telegram_id IS NOT NULL AND is_banned = false;
GET DIAGNOSTICS v_count = ROW_COUNT;
RETURN jsonb_build_object('success', true, 'queued', v_count);
END; $$;
CREATE FUNCTION public.admin_cleanup_expired_rewards() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_cleaned integer := 0;
BEGIN
UPDATE public.profiles
SET reward_balance = 0, reward_expires_at = NULL
WHERE reward_expires_at IS NOT NULL AND reward_expires_at <= now() AND reward_balance > 0;
GET DIAGNOSTICS _cleaned = ROW_COUNT;
RETURN jsonb_build_object('success', true, 'cleaned', _cleaned);
END;
$$;
CREATE FUNCTION public.admin_create_character_for_telegram(_telegram_id bigint, _name text, _image_url text, _max_hp integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_character_id UUID;
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN
RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
END IF;
INSERT INTO public.characters (name, image_url, max_hp, current_hp, is_active)
VALUES (
COALESCE(_name, 'Unnamed Boss'),
COALESCE(_image_url, 'monster-1'),
GREATEST(COALESCE(_max_hp, 100), 1),
GREATEST(COALESCE(_max_hp, 100), 1),
false
)
RETURNING id INTO _character_id;
RETURN jsonb_build_object('success', true, 'characterId', _character_id);
END;
$$;
CREATE FUNCTION public.admin_create_character_for_telegram(_telegram_id bigint, _name text, _image_url text, _max_hp bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
INSERT INTO public.characters (name, image_url, max_hp, current_hp) VALUES (_name, _image_url, _max_hp, _max_hp) RETURNING id INTO v_id;
RETURN jsonb_build_object('success', true, 'characterId', v_id);
END; $$;
CREATE FUNCTION public.admin_create_server_for_telegram(_telegram_id bigint, _name text, _image_url text, _price_ton numeric, _rarity text, _mining_boost integer, _attack_boost integer, _ton_mining_rate numeric, _usdt_mining_rate numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_server_id UUID;
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN
RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
END IF;
INSERT INTO public.servers (name, image_url, price_ton, rarity, mining_boost, attack_boost, ton_mining_rate, usdt_mining_rate, is_active) VALUES (
COALESCE(_name, 'Unnamed Server'),
COALESCE(_image_url, 'server-1'),
GREATEST(COALESCE(_price_ton, 0.15), 0.15),
LOWER(COALESCE(_rarity, 'common')),
COALESCE(_mining_boost, 0),
COALESCE(_attack_boost, 0),
COALESCE(_ton_mining_rate, 0),
GREATEST(COALESCE(_usdt_mining_rate, 0.3), 0.3),
true
)
RETURNING id INTO _server_id;
RETURN jsonb_build_object('success', true, 'serverId', _server_id);
END;
$$;
CREATE FUNCTION public.admin_create_server_for_telegram(_telegram_id bigint, _name text, _image_url text, _price_ton numeric, _rarity text, _mining_boost numeric, _attack_boost numeric, _ton_mining_rate numeric, _usdt_mining_rate numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
INSERT INTO public.servers (name, image_url, price_ton, rarity, mining_boost, attack_boost, ton_mining_rate, usdt_mining_rate)
VALUES (_name, _image_url, _price_ton, _rarity, _mining_boost, _attack_boost, _ton_mining_rate, _usdt_mining_rate)
RETURNING id INTO v_id;
RETURN jsonb_build_object('success', true, 'serverId', v_id);
END; $$;
CREATE FUNCTION public.admin_delete_task_for_telegram(_telegram_id bigint, _task_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
DELETE FROM public.tasks WHERE id = _task_id;
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.admin_get_dashboard_for_telegram(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN
RETURN jsonb_build_object('success', false, 'error', 'forbidden');
END IF;
RETURN jsonb_build_object('success', true,
'users', COALESCE((SELECT jsonb_agg(to_jsonb(u)) FROM (SELECT id, telegram_id, first_name, username, photo_url, siri_balance, ton_balance, usdt_balance, is_banned, created_at FROM public.profiles WHERE telegram_id IS NOT NULL ORDER BY created_at DESC LIMIT 200) u), '[]'::jsonb),
'tasks', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM (SELECT * FROM public.tasks ORDER BY is_pinned DESC, created_at DESC) t), '[]'::jsonb),
'characters', COALESCE((SELECT jsonb_agg(to_jsonb(c)) FROM (SELECT * FROM public.characters ORDER BY created_at DESC) c), '[]'::jsonb),
'servers', COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM (SELECT * FROM public.servers ORDER BY price_ton) s), '[]'::jsonb),
'transactions', COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM public.transactions ORDER BY created_at DESC LIMIT 100) x), '[]'::jsonb),
'notifications', COALESCE((SELECT jsonb_agg(to_jsonb(n)) FROM (SELECT * FROM public.game_notifications ORDER BY created_at DESC LIMIT 50) n), '[]'::jsonb),
'stats', jsonb_build_object(
'total_users', (SELECT count(*) FROM public.profiles WHERE telegram_id IS NOT NULL),
'total_transactions', (SELECT count(*) FROM public.transactions),
'total_ton_volume', COALESCE((SELECT sum(amount) FROM public.transactions WHERE currency = 'ton' AND status = 'completed'), 0),
'active_miners', (SELECT count(*) FROM public.mining_sessions WHERE claimed = false AND ends_at > now()),
'total_attacks', (SELECT count(*) FROM public.attacks)));
END; $$;
CREATE FUNCTION public.admin_pin_task_for_telegram(_telegram_id bigint, _task_id uuid, _is_pinned boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
UPDATE public.tasks SET is_pinned = _is_pinned WHERE id = _task_id;
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.admin_set_welcome_image_for_telegram(_telegram_id bigint, _url text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN
RETURN jsonb_build_object('success', false, 'error', 'not_admin');
END IF;
UPDATE public.telegram_admins SET welcome_image_url = _url WHERE telegram_id = _telegram_id;
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.admin_toggle_ban_for_telegram(_telegram_id bigint, _profile_id uuid, _is_banned boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
UPDATE public.profiles SET is_banned = _is_banned WHERE id = _profile_id;
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.admin_toggle_task_for_telegram(_telegram_id bigint, _task_id uuid, _is_active boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
UPDATE public.tasks SET is_active = _is_active WHERE id = _task_id;
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.admin_upsert_task_for_telegram(_telegram_id bigint, _task_id uuid, _title text, _reward_amount numeric, _reward_type text, _task_type text, _link text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
IF NOT public.is_telegram_admin(_telegram_id) THEN RETURN jsonb_build_object('success', false); END IF;
IF _task_id IS NULL THEN
INSERT INTO public.tasks (title, reward_amount, reward_type, task_type, link)
VALUES (_title, _reward_amount, _reward_type, _task_type, _link) RETURNING id INTO v_id;
ELSE
UPDATE public.tasks SET title = _title, reward_amount = _reward_amount, reward_type = _reward_type,
task_type = _task_type, link = _link WHERE id = _task_id RETURNING id INTO v_id;
END IF;
RETURN jsonb_build_object('success', true, 'taskId', v_id);
END; $$;
CREATE TABLE public.ai_subscriptions (
id uuid DEFAULT gen_random_uuid() NOT NULL,
profile_id uuid NOT NULL,
plan text DEFAULT 'free'::text NOT NULL,
status text DEFAULT 'none'::text NOT NULL,
expires_at timestamp with time zone,
period_start timestamp with time zone DEFAULT now() NOT NULL,
images_used integer DEFAULT 0 NOT NULL,
videos_used integer DEFAULT 0 NOT NULL,
created_at timestamp with time zone DEFAULT now() NOT NULL,
updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE FUNCTION public.ai_activate_plan(_profile_id uuid, _plan text, _price numeric) RETURNS public.ai_subscriptions
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_bal numeric;
_row public.ai_subscriptions;
BEGIN
SELECT COALESCE(usdt_balance, 0) INTO _bal FROM public.profiles WHERE id = _profile_id FOR UPDATE;
IF _bal IS NULL THEN
RAISE EXCEPTION 'profile_not_found';
END IF;
IF _bal < _price THEN
RAISE EXCEPTION 'insufficient_balance';
END IF;
UPDATE public.profiles SET usdt_balance = COALESCE(usdt_balance, 0) - _price WHERE id = _profile_id;
INSERT INTO public.ai_subscriptions (profile_id, plan, status, expires_at, period_start, images_used, videos_used)
VALUES (_profile_id, _plan, 'active', now() + interval '30 days', now(), 0, 0)
ON CONFLICT (profile_id) DO UPDATE
SET plan = EXCLUDED.plan,
status = 'active',
expires_at = now() + interval '30 days',
period_start = now(),
images_used = 0,
videos_used = 0
RETURNING * INTO _row;
RETURN _row;
END;
$$;
CREATE FUNCTION public.ai_activate_plan_with_intent(_profile_id uuid, _telegram_id bigint, _plan text, _intent_id uuid) RETURNS public.ai_subscriptions
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_row public.ai_subscriptions;
BEGIN
PERFORM public.consume_ton_intent(_intent_id, _telegram_id, 'ai_pro');
SELECT * INTO v_row FROM public.ai_activate_plan(_profile_id, _plan, 0);
RETURN v_row;
END; $$;
CREATE FUNCTION public.ai_get_subscription(_profile_id uuid) RETURNS public.ai_subscriptions
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT * FROM public.ai_subscriptions WHERE profile_id = _profile_id;
$$;
CREATE FUNCTION public.all_prize_broadcast_targets(_limit integer DEFAULT 500, _offset integer DEFAULT 0) RETURNS TABLE(id uuid, telegram_id bigint, first_name text)
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public'
AS $$ SELECT NULL::uuid, NULL::bigint, NULL::text WHERE false $$;
CREATE FUNCTION public.attach_referral_for_telegram(_telegram_id bigint, _code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_ref uuid; v_current uuid;
BEGIN
IF _code IS NULL OR length(trim(_code)) = 0 THEN
RETURN jsonb_build_object('success', false, 'reason', 'no_code');
END IF;
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'reason', 'no_profile'); END IF;
SELECT referred_by INTO v_current FROM public.profiles WHERE id = v_uid;
IF v_current IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'reason', 'already_referred'); END IF;
SELECT id INTO v_ref FROM public.profiles WHERE upper(referral_code) = upper(trim(_code)) LIMIT 1;
IF v_ref IS NULL OR v_ref = v_uid THEN RETURN jsonb_build_object('success', false, 'reason', 'invalid_code'); END IF;
UPDATE public.profiles SET referred_by = v_ref WHERE id = v_uid;
RETURN jsonb_build_object('success', true, 'referrerId', v_ref);
END; $$;
CREATE FUNCTION public.auto_activate_next_character() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_next_id UUID;
BEGIN
IF OLD.is_active = true AND NEW.is_active = false AND NEW.current_hp <= 0 THEN
SELECT id INTO _next_id
FROM public.characters
WHERE id != NEW.id AND is_active = false
ORDER BY random()
LIMIT 1;
IF _next_id IS NOT NULL THEN
UPDATE public.characters
SET is_active = true,
current_hp = max_hp,
defeated_by = NULL,
ton_pool = 0,
updated_at = now()
WHERE id = _next_id;
END IF;
END IF;
RETURN NEW;
END;
$$;
CREATE FUNCTION public.complete_task_for_telegram(_telegram_id bigint, _task_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
v_uid uuid; v_t public.tasks%ROWTYPE; v_p public.profiles%ROWTYPE; v_new boolean := true;
v_ver text; v_n integer;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false); END IF;
SELECT * INTO v_t FROM public.tasks WHERE id = _task_id AND is_active = true;
IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND'); END IF;
v_ver := COALESCE(v_t.verification_type, 'none');
IF v_ver = 'referral_count' THEN
SELECT COUNT(*) INTO v_n FROM public.profiles WHERE referred_by = v_uid;
IF v_n < 3 THEN RETURN jsonb_build_object('success', false, 'error', 'NEED_3_REFERRALS', 'current', v_n, 'required', 3); END IF;
ELSIF v_ver = 'mining_hours' THEN
SELECT COUNT(*) INTO v_n FROM public.mining_sessions WHERE user_id = v_uid AND claimed = true;
IF v_n < 3 THEN RETURN jsonb_build_object('success', false, 'error', 'NEED_3_MINING_SESSIONS', 'current', v_n, 'required', 3); END IF;
ELSIF v_ver = 'server_purchase' THEN
SELECT COUNT(*) INTO v_n FROM public.user_servers WHERE user_id = v_uid;
IF v_n < 1 THEN RETURN jsonb_build_object('success', false, 'error', 'NEED_SERVER_PURCHASE', 'current', v_n, 'required', 1); END IF;
ELSIF v_ver = 'kill_monster' THEN
SELECT COUNT(*) INTO v_n FROM public.attacks WHERE user_id = v_uid AND is_killing_blow = true;
IF v_n < 1 THEN RETURN jsonb_build_object('success', false, 'error', 'NEED_MONSTER_KILL', 'current', v_n, 'required', 1); END IF;
END IF;
INSERT INTO public.user_tasks (user_id, task_id, reward_amount, reward_type)
VALUES (v_uid, _task_id, v_t.reward_amount, v_t.reward_type)
ON CONFLICT (user_id, task_id) DO NOTHING;
IF NOT FOUND THEN v_new := false; END IF;
IF v_new THEN
UPDATE public.profiles SET
siri_balance = siri_balance + CASE WHEN v_t.reward_type = 'siri' THEN v_t.reward_amount ELSE 0 END,
ton_balance  = ton_balance  + CASE WHEN v_t.reward_type = 'ton'  THEN v_t.reward_amount ELSE 0 END,
usdt_balance = usdt_balance + CASE WHEN v_t.reward_type = 'usdt' THEN v_t.reward_amount ELSE 0 END
WHERE id = v_uid;
END IF;
SELECT * INTO v_p FROM public.profiles WHERE id = v_uid;
RETURN jsonb_build_object('success', true, 'alreadyCompleted', NOT v_new,
'rewardAmount', v_t.reward_amount, 'rewardType', v_t.reward_type,
'balances', jsonb_build_object('siri', v_p.siri_balance, 'ton', v_p.ton_balance, 'usdt', v_p.usdt_balance));
END; $$;
CREATE FUNCTION public.consume_ton_intent(_intent_id uuid, _telegram_id bigint, _action text) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_row public.ton_payment_intents%ROWTYPE;
BEGIN
SELECT * INTO v_row FROM public.ton_payment_intents
WHERE id = _intent_id FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'intent_not_found'; END IF;
IF v_row.telegram_id <> _telegram_id THEN RAISE EXCEPTION 'intent_owner_mismatch'; END IF;
IF v_row.action <> _action THEN RAISE EXCEPTION 'intent_action_mismatch'; END IF;
IF v_row.status <> 'confirmed' THEN RAISE EXCEPTION 'intent_not_confirmed'; END IF;
IF v_row.credited_at IS NOT NULL THEN RAISE EXCEPTION 'intent_already_used'; END IF;
UPDATE public.ton_payment_intents SET credited_at = now() WHERE id = _intent_id;
RETURN round(v_row.amount_nano::numeric / 1000000000, 9);
END; $$;
CREATE FUNCTION public.create_smart_offer_for_telegram(_telegram_id bigint, _surface text DEFAULT 'general'::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
v_focus text := CASE WHEN _surface IN ('servers','shop','ai','general') THEN _surface ELSE 'general' END;
v_spent numeric := 0;
v_payments int := 0;
v_bonus numeric;
v_headline text;
v_message text;
v_existing record;
v_profile uuid;
BEGIN
IF _telegram_id IS NULL THEN
RETURN jsonb_build_object('success', false, 'error', 'NO_TELEGRAM_ID');
END IF;
SELECT * INTO v_existing
FROM public.ai_smart_offers
WHERE telegram_id = _telegram_id AND expires_at > now()
ORDER BY created_at DESC
LIMIT 1;
IF v_existing.id IS NOT NULL THEN
RETURN jsonb_build_object('success', true, 'bonus_pct', v_existing.bonus_pct, 'headline', v_existing.headline,
'message', v_existing.message, 'cta', v_existing.cta, 'existing', true);
END IF;
SELECT id INTO v_profile FROM public.profiles WHERE telegram_id = _telegram_id LIMIT 1;
IF v_profile IS NOT NULL THEN
SELECT COALESCE(SUM(amount), 0), COUNT(*) INTO v_spent, v_payments
FROM public.transactions
WHERE user_id = v_profile AND status = 'completed' AND currency = 'ton';
END IF;
v_bonus := LEAST(15, GREATEST(3, ROUND(3 + (v_payments * 1.5) + LEAST(6, v_spent))));
v_headline := CASE v_focus
WHEN 'servers' THEN 'Extra ' || v_bonus || '% off servers'
WHEN 'shop' THEN 'Extra ' || v_bonus || '% off battle gear'
WHEN 'ai' THEN 'Extra ' || v_bonus || '% off AI credits'
ELSE 'Extra ' || v_bonus || '% off today'
END;
v_message := 'Personal bonus unlocked for the next 24 hours. It stacks on top of your member discount.';
INSERT INTO public.ai_smart_offers (telegram_id, bonus_pct, headline, message, cta, focus, context, expires_at)
VALUES (_telegram_id, v_bonus, v_headline, v_message, 'Claim now', v_focus,
jsonb_build_object('spent_ton', v_spent, 'payments', v_payments, 'source', 'rpc'),
now() + interval '24 hours');
RETURN jsonb_build_object('success', true, 'bonus_pct', v_bonus, 'headline', v_headline, 'message', v_message, 'cta', 'Claim now');
END;
$$;
CREATE FUNCTION public.credit_ton_deposit_with_intent(_telegram_id bigint, _intent_id uuid, _wallet_address text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_profile uuid; v_amount numeric; v_tx uuid; v_hash text; v_balance numeric;
BEGIN
SELECT id INTO v_profile FROM public.profiles WHERE telegram_id = _telegram_id LIMIT 1;
IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'no_profile'); END IF;
BEGIN
v_amount := public.consume_ton_intent(_intent_id, _telegram_id, 'deposit');
EXCEPTION WHEN OTHERS THEN
RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
SELECT tx_hash INTO v_hash FROM public.ton_payment_intents WHERE id = _intent_id;
UPDATE public.profiles SET ton_balance = COALESCE(ton_balance, 0) + v_amount
WHERE id = v_profile RETURNING ton_balance INTO v_balance;
INSERT INTO public.transactions (user_id, type, amount, currency, status, wallet_address, tx_hash)
VALUES (v_profile, 'deposit', v_amount, 'ton', 'completed', _wallet_address, v_hash)
RETURNING id INTO v_tx;
RETURN jsonb_build_object('success', true, 'amount', v_amount, 'transactionId', v_tx, 'tonBalance', v_balance);
END; $$;
CREATE FUNCTION public.ensure_monthly_prize() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
IF NEW.reward_balance IS NULL OR NEW.reward_balance < 10000 THEN
NEW.reward_balance := 10000;
END IF;
IF NEW.reward_expires_at IS NULL OR NEW.reward_expires_at <= now() THEN
NEW.reward_expires_at := now() + interval '72 hours';
END IF;
RETURN NEW;
END;
$$;
CREATE FUNCTION public.expire_prize_rewards() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
n integer;
BEGIN
UPDATE public.profiles
SET reward_balance = 0
WHERE reward_balance > 0
AND reward_expires_at IS NOT NULL
AND reward_expires_at <= now();
GET DIAGNOSTICS n = ROW_COUNT;
RETURN n;
END;
$$;
CREATE FUNCTION public.game_crash_cashout(_telegram_id bigint, _bet_id uuid, _at numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_bet game_bets%ROWTYPE;
_crash numeric;
_elapsed double precision;
_allowed numeric;
_mult numeric := 0;
_payout numeric := 0;
_bal numeric;
BEGIN
SELECT * INTO _bet FROM game_bets
WHERE id = _bet_id AND telegram_id = _telegram_id AND status = 'open' AND game_slug = 'crash'
FOR UPDATE;
IF _bet.id IS NULL THEN
RETURN jsonb_build_object('success', false, 'error', 'bet_not_found');
END IF;
_crash := (_bet.meta->>'crash')::numeric;
_elapsed := EXTRACT(EPOCH FROM (now() - _bet.created_at));
_allowed := round((power(1.07::numeric, LEAST(_elapsed, 120)::numeric) * 1.02), 4);
_mult := LEAST(COALESCE(_at, 0), _allowed);
IF _mult >= 1.01 AND _mult < _crash THEN
_payout := round(_bet.stake * _mult, 6);
UPDATE profiles SET ton_balance = ton_balance + _payout WHERE telegram_id = _telegram_id;
ELSE
_mult := 0;
END IF;
UPDATE game_bets
SET status = CASE WHEN _payout > 0 THEN 'won' ELSE 'lost' END,
payout = _payout,
multiplier = _mult,
settled_at = now()
WHERE id = _bet.id;
SELECT ton_balance INTO _bal FROM profiles WHERE telegram_id = _telegram_id;
RETURN jsonb_build_object('success', true, 'multiplier', _mult, 'payout', _payout, 'crash', _crash, 'balance', _bal);
END;
$$;
CREATE FUNCTION public.game_crash_history(_limit integer DEFAULT 12) RETURNS TABLE(round_id bigint, crash_multiplier numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT r.round_id, r.crash_multiplier
FROM public.game_crash_rounds r
ORDER BY r.round_id DESC
LIMIT LEAST(GREATEST(_limit, 1), 50)
$$;
CREATE FUNCTION public.game_crash_pick(_u double precision, _v double precision) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE _c numeric;
BEGIN
IF _u < 0.06 THEN
RETURN 1.00;
ELSIF _u < 0.62 THEN
RETURN round((1.01 + _v * 0.54)::numeric, 2);
END IF;
_c := (0.97 / GREATEST(1.0 - _v, 0.0019))::numeric;
RETURN round(LEAST(500, GREATEST(1.56, _c)), 2);
END;
$$;
CREATE FUNCTION public.game_crash_players(_round bigint, _limit integer DEFAULT 8, _exclude bigint DEFAULT NULL::bigint) RETURNS TABLE(name text, photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT
COALESCE(NULLIF(btrim(p.first_name), ''), NULLIF(btrim(p.username), ''), 'Player') AS name,
p.photo_url
FROM public.profiles p
WHERE p.telegram_id IS NOT NULL
AND (_exclude IS NULL OR p.telegram_id <> _exclude)
AND COALESCE(p.is_banned, false) = false
AND NULLIF(btrim(p.photo_url), '') IS NOT NULL
ORDER BY md5(p.telegram_id::text || '-' || _round::text)
LIMIT LEAST(GREATEST(_limit, 1), 20)
$$;
CREATE FUNCTION public.game_crash_round_result(_round_id bigint) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_crash numeric;
_u double precision;
_v double precision;
BEGIN
SELECT crash_multiplier INTO _crash FROM public.game_crash_rounds WHERE round_id = _round_id;
IF _crash IS NOT NULL THEN RETURN _crash; END IF;
_u := ('x' || substr(md5(_round_id::text || '-nova-crash-v2'), 1, 13))::bit(52)::bigint::double precision / 4503599627370496.0;
_v := ('x' || substr(md5(_round_id::text || '-nova-crash-v2-b'), 1, 13))::bit(52)::bigint::double precision / 4503599627370496.0;
_crash := public.game_crash_pick(_u, _v);
INSERT INTO public.game_crash_rounds (round_id, crash_multiplier)
VALUES (_round_id, _crash)
ON CONFLICT (round_id) DO NOTHING;
SELECT crash_multiplier INTO _crash FROM public.game_crash_rounds WHERE round_id = _round_id;
RETURN _crash;
END;
$$;
CREATE FUNCTION public.game_crash_start(_telegram_id bigint, _stake numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_bal numeric;
_bet_id uuid;
_crash numeric;
BEGIN
IF _stake IS NULL OR _stake <= 0 OR _stake > 100 THEN
RETURN jsonb_build_object('success', false, 'error', 'invalid_stake');
END IF;
SELECT ton_balance INTO _bal FROM profiles WHERE telegram_id = _telegram_id FOR UPDATE;
IF _bal IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'no_profile'); END IF;
IF _bal < _stake THEN RETURN jsonb_build_object('success', false, 'error', 'insufficient_funds'); END IF;
_crash := public.game_crash_pick(random(), random());
UPDATE profiles SET ton_balance = ton_balance - _stake WHERE telegram_id = _telegram_id;
INSERT INTO game_bets (telegram_id, game_slug, stake, meta, status)
VALUES (_telegram_id, 'crash', _stake, jsonb_build_object('crash', _crash), 'open')
RETURNING id INTO _bet_id;
SELECT ton_balance INTO _bal FROM profiles WHERE telegram_id = _telegram_id;
RETURN jsonb_build_object('success', true, 'bet_id', _bet_id, 'balance', _bal);
END;
$$;
CREATE FUNCTION public.game_crash_start(_telegram_id bigint, _stake numeric, _round_id bigint DEFAULT NULL::bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_bal numeric;
_bet_id uuid;
_crash numeric;
_effective_round bigint;
BEGIN
IF _stake IS NULL OR _stake <= 0 OR _stake > 100 THEN
RETURN jsonb_build_object('success', false, 'error', 'invalid_stake');
END IF;
SELECT ton_balance INTO _bal FROM profiles WHERE telegram_id = _telegram_id FOR UPDATE;
IF _bal IS NULL THEN
RETURN jsonb_build_object('success', false, 'error', 'no_profile');
END IF;
IF _bal < _stake THEN
RETURN jsonb_build_object('success', false, 'error', 'insufficient_funds');
END IF;
_effective_round := COALESCE(_round_id, floor(extract(epoch FROM now()) / 15)::bigint);
_crash := public.game_crash_round_result(_effective_round);
UPDATE profiles SET ton_balance = ton_balance - _stake WHERE telegram_id = _telegram_id;
INSERT INTO game_bets (telegram_id, game_slug, stake, meta, status)
VALUES (_telegram_id, 'crash', _stake, jsonb_build_object('crash', _crash, 'round_id', _effective_round), 'open')
RETURNING id INTO _bet_id;
SELECT ton_balance INTO _bal FROM profiles WHERE telegram_id = _telegram_id;
RETURN jsonb_build_object('success', true, 'bet_id', _bet_id, 'balance', _bal, 'round_id', _effective_round);
END;
$$;
CREATE FUNCTION public.game_create_own_profile(_telegram_id bigint, _first_name text, _last_name text, _username text, _photo_url text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
v_id uuid;
v_code text;
BEGIN
IF _telegram_id IS NULL OR _telegram_id = 0 THEN
RETURN NULL;
END IF;
SELECT id INTO v_id
FROM public.profiles
WHERE telegram_id = _telegram_id
LIMIT 1;
IF v_id IS NULL THEN
v_code := upper('SIRI' || _telegram_id::text || to_char(clock_timestamp(), 'SSSSFF3'));
INSERT INTO public.profiles (telegram_id, first_name, last_name, username, photo_url, referral_code, reward_balance, reward_expires_at)
VALUES (
_telegram_id,
coalesce(nullif(_first_name, ''), 'Player'),
coalesce(_last_name, ''),
coalesce(_username, ''),
coalesce(_photo_url, ''),
v_code,
10000,
now() + interval '24 hours'
)
ON CONFLICT DO NOTHING;
END IF;
RETURN public.game_get_own_profile(_telegram_id);
END;
$$;
CREATE FUNCTION public.game_create_transaction(_telegram_id bigint, _type text, _amount numeric, _currency text, _wallet_address text, _tx_hash text DEFAULT NULL::text, _status text DEFAULT 'pending'::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_profile uuid; v_id uuid;
BEGIN
SELECT id INTO v_profile FROM public.profiles WHERE telegram_id = _telegram_id LIMIT 1;
IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'no_profile'); END IF;
IF _type NOT IN ('deposit','withdrawal','wallet_verification') THEN
RETURN jsonb_build_object('success', false, 'error', 'bad_type');
END IF;
IF _amount IS NULL OR _amount <= 0 OR _amount > 1000000 THEN
RETURN jsonb_build_object('success', false, 'error', 'bad_amount');
END IF;
IF _currency NOT IN ('ton','usdt','siri') THEN
RETURN jsonb_build_object('success', false, 'error', 'bad_currency');
END IF;
INSERT INTO public.transactions (user_id, type, amount, currency, status, wallet_address, tx_hash)
VALUES (v_profile, _type, _amount, _currency, 'pending', _wallet_address, _tx_hash)
RETURNING id INTO v_id;
RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;
CREATE FUNCTION public.game_credit_referral(_user_id uuid, _ton_paid numeric, _source text) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_ref uuid; v_reward numeric := 0;
BEGIN
SELECT referred_by INTO v_ref FROM public.profiles WHERE id = _user_id;
IF v_ref IS NULL OR _ton_paid <= 0 THEN RETURN 0; END IF;
v_reward := round(_ton_paid * 0.5, 6);
UPDATE public.profiles SET ton_balance = ton_balance + v_reward WHERE id = v_ref;
INSERT INTO public.referral_rewards (referrer_id, referred_user_id, source_type, ton_amount)
VALUES (v_ref, _user_id, _source, v_reward);
RETURN v_reward;
END; $$;
CREATE FUNCTION public.game_get_own_profile(_telegram_id bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT to_jsonb(t) FROM (
SELECT id, telegram_id, first_name, last_name, username, photo_url, referral_code,
referred_by, siri_balance, ton_balance, usdt_balance, reward_balance, reward_expires_at
FROM public.profiles WHERE telegram_id = _telegram_id LIMIT 1
) t;
$$;