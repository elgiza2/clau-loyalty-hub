SET check_function_bodies = false;
CREATE FUNCTION public.request_withdrawal_for_telegram(_telegram_id bigint, _amount numeric, _currency text, _wallet_address text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_profile uuid; v_balance numeric; v_verified boolean; v_pending int; v_id uuid;
BEGIN
  SELECT id INTO v_profile FROM public.profiles WHERE telegram_id = _telegram_id LIMIT 1;
  IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'no_profile'); END IF;
  IF _currency NOT IN ('ton','usdt') THEN RETURN jsonb_build_object('success', false, 'error', 'bad_currency'); END IF;
  IF _amount IS NULL OR _amount <= 0 OR _amount > 1000000 THEN
RETURN jsonb_build_object('success', false, 'error', 'bad_amount');
  END IF;
  IF _wallet_address IS NULL OR length(_wallet_address) < 10 THEN
RETURN jsonb_build_object('success', false, 'error', 'no_wallet');
  END IF;
  v_verified := public.game_is_wallet_verified(_telegram_id);
  IF NOT v_verified THEN RETURN jsonb_build_object('success', false, 'error', 'wallet_not_verified'); END IF;
  SELECT CASE WHEN _currency = 'ton' THEN COALESCE(ton_balance, 0) ELSE COALESCE(usdt_balance, 0) END
  INTO v_balance FROM public.profiles WHERE id = v_profile FOR UPDATE;
  IF v_balance < _amount THEN
RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance', 'balance', v_balance);
  END IF;
  SELECT count(*) INTO v_pending FROM public.transactions
  WHERE user_id = v_profile AND type = 'withdrawal' AND currency = _currency AND status = 'pending';
  IF v_pending > 0 THEN RETURN jsonb_build_object('success', false, 'error', 'pending_request_exists'); END IF;
  INSERT INTO public.transactions (user_id, type, amount, currency, status, wallet_address)
  VALUES (v_profile, 'withdrawal', _amount, _currency, 'pending', _wallet_address)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('success', true, 'id', v_id);
END; $$;

CREATE FUNCTION public.set_ton_payment_intent_updated_at() RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.staking_claim_for_telegram(_telegram_id bigint, _stake_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _pid uuid;
  _stake public.stakes;
  _yield numeric;
BEGIN
  SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
  IF _pid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
  SELECT * INTO _stake FROM public.stakes WHERE id = _stake_id AND profile_id = _pid AND status = 'active' FOR UPDATE;
  IF _stake.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'stake_not_found'); END IF;
  _yield := public.staking_pending_yield(_stake);
  IF _yield <= 0 THEN RETURN jsonb_build_object('success', false, 'error', 'nothing_to_claim'); END IF;
  IF _stake.currency = 'ton' THEN
UPDATE public.profiles SET ton_balance = COALESCE(ton_balance,0) + _yield WHERE id = _pid;
  ELSE
UPDATE public.profiles SET siri_balance = COALESCE(siri_balance,0) + _yield WHERE id = _pid;
  END IF;
  UPDATE public.stakes
  SET last_claim_at = LEAST(now(), ends_at), claimed_yield = claimed_yield + _yield
  WHERE id = _stake.id;
  RETURN jsonb_build_object('success', true, 'claimed', _yield, 'currency', _stake.currency);
END;
$$;

CREATE FUNCTION public.staking_create_for_telegram(_telegram_id bigint, _plan_id uuid, _amount numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _pid uuid;
  _plan public.staking_plans;
  _bal numeric;
  _stake_id uuid;
  _multiplier numeric := 1;
  _credited_amount numeric;
BEGIN
  SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
  IF _pid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
  SELECT * INTO _plan FROM public.staking_plans WHERE id = _plan_id AND is_active;
  IF _plan.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'plan_not_found'); END IF;
  IF _amount IS NULL OR _amount <= 0 OR _amount < _plan.min_amount THEN
RETURN jsonb_build_object('success', false, 'error', 'amount_too_low');
  END IF;
  IF _plan.max_amount IS NOT NULL AND _amount > _plan.max_amount THEN
RETURN jsonb_build_object('success', false, 'error', 'amount_too_high');
  END IF;
  IF _plan.currency = 'ton' THEN
SELECT COALESCE(ton_balance,0) INTO _bal FROM public.profiles WHERE id = _pid FOR UPDATE;
  ELSE
SELECT COALESCE(siri_balance,0) INTO _bal FROM public.profiles WHERE id = _pid FOR UPDATE;
  END IF;
  IF _bal < _amount THEN RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance'); END IF;
  IF _plan.currency = 'ton' THEN
SELECT COALESCE(o.multiplier, 1) INTO _multiplier
FROM public.staking_personal_offers o
WHERE o.profile_id = _pid AND o.currency = 'ton' AND o.is_active AND now() >= o.starts_at AND now() < o.expires_at
ORDER BY o.expires_at DESC
LIMIT 1;
_multiplier := COALESCE(_multiplier, 1);
  END IF;
  _credited_amount := _amount * _multiplier;
  IF _plan.currency = 'ton' THEN
UPDATE public.profiles SET ton_balance = COALESCE(ton_balance,0) - _amount WHERE id = _pid;
  ELSE
UPDATE public.profiles SET siri_balance = COALESCE(siri_balance,0) - _amount WHERE id = _pid;
  END IF;
  INSERT INTO public.stakes (profile_id, plan_id, currency, amount, funded_amount, apr, duration_days, early_exit_fee_pct, ends_at)
  VALUES (_pid, _plan.id, _plan.currency, _credited_amount, _amount, _plan.apr, _plan.duration_days, _plan.early_exit_fee_pct,
      now() + (_plan.duration_days || ' days')::interval)
  RETURNING id INTO _stake_id;
  RETURN jsonb_build_object('success', true, 'stake_id', _stake_id, 'funded_amount', _amount, 'credited_amount', _credited_amount, 'multiplier', _multiplier);
END;
$$;

CREATE FUNCTION public.staking_get_overview_for_telegram(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _pid uuid;
  _offer jsonb;
BEGIN
  SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
  SELECT jsonb_build_object('active', true, 'multiplier', o.multiplier, 'starts_at', o.starts_at, 'expires_at', o.expires_at, 'currency', o.currency) INTO _offer
  FROM public.staking_personal_offers o
  WHERE o.profile_id = _pid AND o.currency = 'ton' AND o.is_active AND now() >= o.starts_at AND now() < o.expires_at
  ORDER BY o.expires_at DESC
  LIMIT 1;
  RETURN jsonb_build_object(
'success', true,
'plans', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.sort_order) FROM public.staking_plans p WHERE p.is_active), '[]'::jsonb),
'stakes', COALESCE((
  SELECT jsonb_agg(to_jsonb(s) || jsonb_build_object('pending_yield', public.staking_pending_yield(s), 'plan_name', pl.name) ORDER BY s.created_at DESC)
  FROM public.stakes s
  JOIN public.staking_plans pl ON pl.id = s.plan_id
  WHERE s.profile_id = _pid
), '[]'::jsonb),
'balances', (SELECT jsonb_build_object('ton', COALESCE(ton_balance,0), 'siri', COALESCE(siri_balance,0)) FROM public.profiles WHERE id = _pid),
'personal_offer', _offer
  );
END;
$$;

CREATE TABLE public.stakes (
id uuid DEFAULT gen_random_uuid() NOT NULL,
profile_id uuid NOT NULL,
plan_id uuid NOT NULL,
currency text NOT NULL,
amount numeric NOT NULL,
apr numeric NOT NULL,
duration_days integer NOT NULL,
early_exit_fee_pct numeric DEFAULT 20 NOT NULL,
started_at timestamp with time zone DEFAULT now() NOT NULL,
ends_at timestamp with time zone NOT NULL,
last_claim_at timestamp with time zone DEFAULT now() NOT NULL,
claimed_yield numeric DEFAULT 0 NOT NULL,
status text DEFAULT 'active'::text NOT NULL,
closed_at timestamp with time zone,
created_at timestamp with time zone DEFAULT now() NOT NULL,
updated_at timestamp with time zone DEFAULT now() NOT NULL,
funded_amount numeric NOT NULL,
CONSTRAINT stakes_amount_check CHECK ((amount > (0)::numeric)),
CONSTRAINT stakes_status_check CHECK ((status = ANY (ARRAY['active'::text, 'closed'::text, 'early_closed'::text])))
);

CREATE FUNCTION public.staking_pending_yield(_stake public.stakes) RETURNS numeric
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
  SELECT GREATEST(0, _stake.amount * (_stake.apr / 100.0)
* (EXTRACT(EPOCH FROM (LEAST(now(), _stake.ends_at) - _stake.last_claim_at)) / 86400.0) / 365.0);
$$;

CREATE FUNCTION public.staking_unstake_for_telegram(_telegram_id bigint, _stake_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _pid uuid;
  _stake public.stakes;
  _yield numeric;
  _fee numeric := 0;
  _payout numeric;
  _principal numeric;
  _early boolean;
BEGIN
  SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
  IF _pid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
  SELECT * INTO _stake FROM public.stakes WHERE id = _stake_id AND profile_id = _pid AND status = 'active' FOR UPDATE;
  IF _stake.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'stake_not_found'); END IF;
  _early := now() < _stake.ends_at;
  _yield := public.staking_pending_yield(_stake);
  _principal := CASE WHEN _early THEN _stake.funded_amount ELSE _stake.amount END;
  IF _early THEN
_yield := 0;
_fee := _principal * (_stake.early_exit_fee_pct / 100.0);
  END IF;
  _payout := _principal - _fee + _yield;
  IF _stake.currency = 'ton' THEN
UPDATE public.profiles SET ton_balance = COALESCE(ton_balance,0) + _payout WHERE id = _pid;
  ELSE
UPDATE public.profiles SET siri_balance = COALESCE(siri_balance,0) + _payout WHERE id = _pid;
  END IF;
  UPDATE public.stakes
  SET status = CASE WHEN _early THEN 'early_closed' ELSE 'closed' END,
  closed_at = now(),
  last_claim_at = LEAST(now(), ends_at),
  claimed_yield = claimed_yield + _yield
  WHERE id = _stake.id;
  RETURN jsonb_build_object('success', true, 'payout', _payout, 'fee', _fee, 'yield', _yield, 'early', _early, 'currency', _stake.currency);
END;
$$;

CREATE FUNCTION public.start_mining_for_telegram(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_exists uuid; v_boost numeric := 1; v_ton numeric := 0; v_usdt numeric := 0; v_ends timestamptz; v_id uuid;
BEGIN
  v_uid := public.game_profile_id(_telegram_id);
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'isMining', false); END IF;
  SELECT id INTO v_exists FROM public.mining_sessions
   WHERE user_id = v_uid AND claimed = false AND ends_at > now() LIMIT 1;
  IF v_exists IS NOT NULL THEN
RETURN public.sync_mining_for_telegram(_telegram_id);
  END IF;
  SELECT COALESCE(1 + SUM(s.mining_boost - 1), 1), COALESCE(SUM(s.ton_mining_rate), 0), COALESCE(SUM(s.usdt_mining_rate), 0)
INTO v_boost, v_ton, v_usdt
FROM public.user_servers us JOIN public.servers s ON s.id = us.server_id
   WHERE us.user_id = v_uid;
  v_ends := now() + interval '8 hours';
  INSERT INTO public.mining_sessions (user_id, ends_at, siri_reward, ton_reward, usdt_reward)
  VALUES (v_uid, v_ends, round(500 * COALESCE(v_boost,1), 4), round(COALESCE(v_ton,0), 6), round(COALESCE(v_usdt,0), 6))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('success', true, 'isMining', true, 'endsAt', v_ends, 'sessionId', v_id);
END; $$;

CREATE FUNCTION public.sync_mining_for_telegram(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_s public.mining_sessions%ROWTYPE; v_p public.profiles%ROWTYPE;
BEGIN
  v_uid := public.game_profile_id(_telegram_id);
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'isMining', false); END IF;
  SELECT * INTO v_s FROM public.mining_sessions
   WHERE user_id = v_uid AND claimed = false ORDER BY started_at DESC LIMIT 1;
  IF FOUND AND v_s.ends_at <= now() THEN
UPDATE public.mining_sessions SET claimed = true WHERE id = v_s.id;
UPDATE public.profiles
   SET siri_balance = siri_balance + v_s.siri_reward,
       ton_balance = ton_balance + v_s.ton_reward,
       usdt_balance = usdt_balance + v_s.usdt_reward
 WHERE id = v_uid RETURNING * INTO v_p;
RETURN jsonb_build_object('success', true, 'isMining', false, 'claimed', true,
  'siriReward', v_s.siri_reward, 'tonReward', v_s.ton_reward, 'usdtReward', v_s.usdt_reward,
  'balances', jsonb_build_object('siri', v_p.siri_balance, 'ton', v_p.ton_balance, 'usdt', v_p.usdt_balance));
  END IF;
  SELECT * INTO v_p FROM public.profiles WHERE id = v_uid;
  IF v_s.id IS NOT NULL THEN
RETURN jsonb_build_object('success', true, 'isMining', true, 'endsAt', v_s.ends_at, 'sessionId', v_s.id,
  'balances', jsonb_build_object('siri', v_p.siri_balance, 'ton', v_p.ton_balance, 'usdt', v_p.usdt_balance));
  END IF;
  RETURN jsonb_build_object('success', true, 'isMining', false,
'balances', jsonb_build_object('siri', v_p.siri_balance, 'ton', v_p.ton_balance, 'usdt', v_p.usdt_balance));
END; $$;

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.verify_wallet_with_intent(_telegram_id bigint, _intent_id uuid, _wallet_address text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_profile uuid; v_amount numeric; v_hash text;
BEGIN
  SELECT id INTO v_profile FROM public.profiles WHERE telegram_id = _telegram_id LIMIT 1;
  IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'no_profile'); END IF;
  BEGIN
v_amount := public.consume_ton_intent(_intent_id, _telegram_id, 'wallet_verification');
  EXCEPTION WHEN OTHERS THEN
RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
  SELECT tx_hash INTO v_hash FROM public.ton_payment_intents WHERE id = _intent_id;
  INSERT INTO public.transactions (user_id, type, amount, currency, status, wallet_address, tx_hash)
  VALUES (v_profile, 'wallet_verification', v_amount, 'ton', 'completed', _wallet_address, v_hash);
  RETURN jsonb_build_object('success', true, 'verified', true);
END; $$;

CREATE TABLE public.ad_watch_progress (user_id uuid NOT NULL, ads_watched integer DEFAULT 0 NOT NULL, total_claims integer DEFAULT 0 NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, ads_watched_b integer DEFAULT 0 NOT NULL, total_claims_b integer DEFAULT 0 NOT NULL);
CREATE TABLE public.ai_generations (id uuid DEFAULT gen_random_uuid() NOT NULL, profile_id uuid NOT NULL, kind text NOT NULL, model text NOT NULL, prompt text NOT NULL, url text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.ai_smart_offers (id uuid DEFAULT gen_random_uuid() NOT NULL, telegram_id bigint NOT NULL, bonus_pct numeric DEFAULT 0 NOT NULL, headline text DEFAULT ''::text NOT NULL, message text DEFAULT ''::text NOT NULL, cta text DEFAULT ''::text NOT NULL, focus text DEFAULT 'general'::text NOT NULL, context jsonb DEFAULT '{}'::jsonb NOT NULL, expires_at timestamp with time zone DEFAULT (now() + '24:00:00'::interval) NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.attacks (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, character_id uuid NOT NULL, damage integer NOT NULL, ton_spent numeric(20,8) DEFAULT 0, is_killing_blow boolean DEFAULT false, created_at timestamp with time zone DEFAULT now() NOT NULL, attack_type text DEFAULT 'free'::text NOT NULL, metadata jsonb DEFAULT '{}'::jsonb NOT NULL);
CREATE TABLE public.auto_notification_log (profile_id uuid NOT NULL, topic text DEFAULT 'mining'::text NOT NULL, last_sent_at timestamp with time zone DEFAULT now() NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.battle_inventory (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, category text NOT NULL, package_key text NOT NULL, package_name text NOT NULL, quantity integer DEFAULT 0 NOT NULL, total_purchased integer DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL,
CONSTRAINT battle_inventory_category_check CHECK ((category = ANY (ARRAY['attack'::text, 'power'::text, 'boost'::text, 'spell'::text]))),
CONSTRAINT battle_inventory_quantity_check CHECK ((quantity >= 0)),
CONSTRAINT battle_inventory_total_purchased_check CHECK ((total_purchased >= 0)));
CREATE TABLE public.characters (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, image_url text NOT NULL, max_hp integer DEFAULT 10000 NOT NULL, current_hp integer DEFAULT 10000 NOT NULL, ton_pool numeric(20,8) DEFAULT 0, is_active boolean DEFAULT true, defeated_by uuid, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.crash_notification_log (profile_id uuid NOT NULL, last_sent_at timestamp with time zone DEFAULT now() NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.game_bets (id uuid DEFAULT gen_random_uuid() NOT NULL, telegram_id bigint NOT NULL, game_slug text NOT NULL, stake numeric NOT NULL, payout numeric DEFAULT 0 NOT NULL, status text DEFAULT 'open'::text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, settled_at timestamp with time zone, multiplier numeric DEFAULT 0 NOT NULL, meta jsonb DEFAULT '{}'::jsonb NOT NULL, CONSTRAINT game_bets_stake_check CHECK ((stake > (0)::numeric)));
CREATE TABLE public.game_crash_rounds (round_id bigint NOT NULL, crash_multiplier numeric NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, CONSTRAINT game_crash_rounds_crash_multiplier_check CHECK ((crash_multiplier >= (1)::numeric)));
CREATE TABLE public.game_notifications (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid, title text NOT NULL, message text DEFAULT ''::text NOT NULL, is_read boolean DEFAULT false NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.mining_reminders (profile_id uuid NOT NULL, last_sent_at timestamp with time zone DEFAULT now() NOT NULL, sent_count integer DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.mining_sessions (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, started_at timestamp with time zone DEFAULT now() NOT NULL, ends_at timestamp with time zone NOT NULL, reward_amount numeric(20,4) DEFAULT 100, claimed boolean DEFAULT false, created_at timestamp with time zone DEFAULT now() NOT NULL, siri_reward numeric DEFAULT 0 NOT NULL, ton_reward numeric DEFAULT 0 NOT NULL, usdt_reward numeric DEFAULT 0 NOT NULL);
CREATE TABLE public.prize_broadcast_log (profile_id uuid NOT NULL, sent_at timestamp with time zone DEFAULT now() NOT NULL, delivered boolean DEFAULT true NOT NULL);
CREATE TABLE public.profiles (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid, telegram_id bigint NOT NULL, first_name text DEFAULT ''::text NOT NULL, last_name text DEFAULT ''::text, username text DEFAULT ''::text, photo_url text DEFAULT ''::text, siri_balance numeric(20,4) DEFAULT 0, ton_balance numeric(20,8) DEFAULT 0, usdt_balance numeric(20,4) DEFAULT 0, referral_code text, referred_by uuid, is_banned boolean DEFAULT false, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, reward_balance numeric DEFAULT 10000, reward_expires_at timestamp with time zone DEFAULT (now() + '72:00:00'::interval), wallet_address text);
CREATE TABLE public.pvp_character_owned (id uuid DEFAULT gen_random_uuid() NOT NULL, profile_id uuid NOT NULL, character_key text NOT NULL, equipped boolean DEFAULT false NOT NULL, ton_paid numeric DEFAULT 0 NOT NULL, tx_hash text, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.pvp_characters (id uuid DEFAULT gen_random_uuid() NOT NULL, key text NOT NULL, name text NOT NULL, title text DEFAULT ''::text NOT NULL, rarity text DEFAULT 'common'::text NOT NULL, price_ton numeric DEFAULT 0 NOT NULL, speed_mod numeric DEFAULT 1 NOT NULL, hp_mod numeric DEFAULT 1 NOT NULL, color text DEFAULT '#ffffff'::text NOT NULL, sort_order integer DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.pvp_match_players (id uuid DEFAULT gen_random_uuid() NOT NULL, match_id uuid NOT NULL, profile_id uuid, telegram_id bigint, username text DEFAULT 'Player'::text NOT NULL, photo_url text, slot integer DEFAULT 0 NOT NULL, is_bot boolean DEFAULT false NOT NULL, weapon_key text DEFAULT 'pistol'::text NOT NULL, kills integer DEFAULT 0 NOT NULL, deaths integer DEFAULT 0 NOT NULL, score integer DEFAULT 0 NOT NULL, alive boolean DEFAULT true NOT NULL, joined_at timestamp with time zone DEFAULT now() NOT NULL, character_key text DEFAULT 'striker'::text NOT NULL);
ALTER TABLE ONLY public.pvp_match_players REPLICA IDENTITY FULL;
CREATE TABLE public.pvp_matches (id uuid DEFAULT gen_random_uuid() NOT NULL, mode text DEFAULT 'duo'::text NOT NULL, max_players integer DEFAULT 4 NOT NULL, status text DEFAULT 'waiting'::text NOT NULL, arena_seed integer DEFAULT floor((random() * (100000)::double precision)) NOT NULL, prize_ton numeric DEFAULT 0.02 NOT NULL, started_at timestamp with time zone, ends_at timestamp with time zone, winner_profile_id uuid, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE ONLY public.pvp_matches REPLICA IDENTITY FULL;
CREATE TABLE public.pvp_stats (profile_id uuid NOT NULL, matches integer DEFAULT 0 NOT NULL, wins integer DEFAULT 0 NOT NULL, kills integer DEFAULT 0 NOT NULL, deaths integer DEFAULT 0 NOT NULL, rating integer DEFAULT 1000 NOT NULL, ton_earned numeric DEFAULT 0 NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.pvp_weapon_owned (id uuid DEFAULT gen_random_uuid() NOT NULL, profile_id uuid NOT NULL, weapon_key text NOT NULL, ton_paid numeric DEFAULT 0 NOT NULL, tx_hash text, created_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.pvp_weapons (key text NOT NULL, name text NOT NULL, rarity text DEFAULT 'common'::text NOT NULL, damage integer DEFAULT 10 NOT NULL, fire_rate_ms integer DEFAULT 300 NOT NULL, bullet_speed integer DEFAULT 420 NOT NULL, spread numeric DEFAULT 0 NOT NULL, pellets integer DEFAULT 1 NOT NULL, range_px integer DEFAULT 600 NOT NULL, price_ton numeric DEFAULT 0 NOT NULL, is_default boolean DEFAULT false NOT NULL, color text DEFAULT '#7dd3fc'::text NOT NULL, sort_order integer DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.referral_rewards (id uuid DEFAULT gen_random_uuid() NOT NULL, referrer_id uuid NOT NULL, referred_user_id uuid NOT NULL, source_type text NOT NULL, source_id uuid, ton_amount numeric DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.servers (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, image_url text NOT NULL, price_ton numeric(20,8) NOT NULL, rarity text DEFAULT 'common'::text NOT NULL, mining_boost integer DEFAULT 0, attack_boost integer DEFAULT 0, ton_mining_rate numeric(20,8) DEFAULT 0, usdt_mining_rate numeric(20,8) DEFAULT 0, is_active boolean DEFAULT true, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.staking_personal_offers (id uuid DEFAULT gen_random_uuid() NOT NULL, profile_id uuid NOT NULL, currency text DEFAULT 'ton'::text NOT NULL, multiplier numeric DEFAULT 2 NOT NULL, starts_at timestamp with time zone DEFAULT now() NOT NULL, expires_at timestamp with time zone NOT NULL, is_active boolean DEFAULT true NOT NULL, message_sent_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.staking_plans (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, currency text NOT NULL, duration_days integer NOT NULL, apr numeric NOT NULL, min_amount numeric DEFAULT 0 NOT NULL, max_amount numeric, early_exit_fee_pct numeric DEFAULT 20 NOT NULL, is_active boolean DEFAULT true NOT NULL, sort_order integer DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL,
CONSTRAINT staking_plans_apr_check CHECK ((apr >= (0)::numeric)),
CONSTRAINT staking_plans_currency_check CHECK ((currency = ANY (ARRAY['ton'::text, 'siri'::text]))),
CONSTRAINT staking_plans_duration_days_check CHECK ((duration_days > 0)));
CREATE TABLE public.star_payments (id uuid DEFAULT gen_random_uuid() NOT NULL, profile_id uuid, telegram_id bigint, product text NOT NULL, stars integer NOT NULL, payload text NOT NULL, status text DEFAULT 'pending'::text NOT NULL, charge_id text, meta jsonb DEFAULT '{}'::jsonb NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, paid_at timestamp with time zone);
CREATE TABLE public.tasks (id uuid DEFAULT gen_random_uuid() NOT NULL, title text NOT NULL, description text DEFAULT ''::text, reward_amount numeric(20,4) NOT NULL, reward_type text DEFAULT 'siri'::text NOT NULL, task_type text DEFAULT 'social'::text NOT NULL, link text DEFAULT ''::text, is_active boolean DEFAULT true, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, verification_type text DEFAULT 'none'::text NOT NULL, is_pinned boolean DEFAULT false NOT NULL, image_url text);
CREATE TABLE public.telegram_admins (telegram_id bigint NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, welcome_image_url text);
CREATE TABLE public.telegram_notifications (id uuid DEFAULT gen_random_uuid() NOT NULL, profile_id uuid NOT NULL, notification_type text NOT NULL, title text NOT NULL, message text NOT NULL, metadata jsonb DEFAULT '{}'::jsonb NOT NULL, status text DEFAULT 'pending'::text NOT NULL, scheduled_for timestamp with time zone DEFAULT now() NOT NULL, sent_at timestamp with time zone, error_message text, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL,
CONSTRAINT telegram_notifications_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text]))));
CREATE TABLE public.telegram_task_drafts (telegram_id bigint NOT NULL, draft jsonb DEFAULT '{}'::jsonb NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.ton_payment_intents (id uuid DEFAULT gen_random_uuid() NOT NULL, telegram_id bigint NOT NULL, action text NOT NULL, amount_nano bigint NOT NULL, wallet_address text, memo text NOT NULL, metadata jsonb DEFAULT '{}'::jsonb NOT NULL, status text DEFAULT 'created'::text NOT NULL, boc text, tx_hash text, failure_reason text, expires_at timestamp with time zone DEFAULT (now() + '00:15:00'::interval) NOT NULL, confirmed_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, base_amount_nano bigint, discount_pct numeric DEFAULT 0 NOT NULL, discount_reason text, credited_at timestamp with time zone,
CONSTRAINT ton_payment_intents_action_valid CHECK ((action = ANY (ARRAY['deposit'::text, 'wallet_verification'::text, 'server'::text, 'server_purchase'::text, 'custom_server'::text, 'battle_item'::text, 'battle_purchase'::text, 'ai_pro'::text, 'nft_purchase'::text]))),
CONSTRAINT ton_payment_intents_amount_positive CHECK ((amount_nano > 0)),
CONSTRAINT ton_payment_intents_status_valid CHECK ((status = ANY (ARRAY['created'::text, 'submitted'::text, 'confirmed'::text, 'failed'::text, 'expired'::text]))));
CREATE TABLE public.transactions (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, type text NOT NULL, currency text DEFAULT 'ton'::text NOT NULL, amount numeric(20,8) NOT NULL, status text DEFAULT 'pending'::text NOT NULL, tx_hash text DEFAULT ''::text, wallet_address text DEFAULT ''::text, metadata jsonb DEFAULT '{}'::jsonb, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, verification_status text DEFAULT 'unverified'::text NOT NULL);
CREATE TABLE public.user_nfts (id uuid DEFAULT gen_random_uuid() NOT NULL, telegram_id bigint NOT NULL, profile_id uuid, name text DEFAULT 'Custom NFT'::text NOT NULL, image_url text NOT NULL, storage_path text, rarity text DEFAULT 'custom'::text NOT NULL, price_ton numeric DEFAULT 1 NOT NULL, tx_hash text, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.user_roles (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, role public.app_role NOT NULL);
CREATE TABLE public.user_servers (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, server_id uuid NOT NULL, purchased_at timestamp with time zone DEFAULT now() NOT NULL, ton_paid numeric(20,8) NOT NULL);
CREATE TABLE public.user_tasks (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, task_id uuid NOT NULL, completed_at timestamp with time zone DEFAULT now() NOT NULL);
