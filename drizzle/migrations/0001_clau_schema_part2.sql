SET check_function_bodies = false;
CREATE FUNCTION public.game_is_wallet_verified(_telegram_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT EXISTS (
SELECT 1 FROM public.transactions t
JOIN public.profiles p ON p.id = t.user_id
WHERE p.telegram_id = _telegram_id
AND t.type = 'wallet_verification' AND t.status = 'completed'
);
$$;
CREATE FUNCTION public.game_place_bet_for_telegram(_telegram_id bigint, _game_slug text, _stake numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_bal numeric;
_bet_id uuid;
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
UPDATE profiles SET ton_balance = ton_balance - _stake WHERE telegram_id = _telegram_id;
INSERT INTO game_bets (telegram_id, game_slug, stake)
VALUES (_telegram_id, _game_slug, _stake)
RETURNING id INTO _bet_id;
RETURN jsonb_build_object('success', true, 'bet_id', _bet_id, 'balance', _bal - _stake);
END;
$$;
CREATE FUNCTION public.game_play_round(_telegram_id bigint, _game_slug text, _stake numeric, _params jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_bal numeric;
_mult numeric := 0;
_payout numeric := 0;
_outcome jsonb := '{}'::jsonb;
_r double precision;
_r2 double precision;
_target numeric;
_roll numeric;
_pick text;
_pocket int;
_color text;
_syms int[];
_mtab numeric[] := ARRAY[3,4,5,8,12,20,40,100];
_bet_id uuid;
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
IF _game_slug = 'coinflip' THEN
_pick := COALESCE(_params->>'side', 'heads');
_r := random();
_outcome := jsonb_build_object('side', CASE WHEN _r < 0.5 THEN 'heads' ELSE 'tails' END);
IF (_outcome->>'side') = _pick THEN _mult := 1.96; END IF;
ELSIF _game_slug = 'dice' THEN
_target := COALESCE((_params->>'target')::numeric, 50);
IF _target < 2 OR _target > 95 THEN
RETURN jsonb_build_object('success', false, 'error', 'invalid_target');
END IF;
_roll := round((random() * 100)::numeric, 2);
_outcome := jsonb_build_object('roll', _roll, 'target', _target);
IF _roll < _target THEN _mult := round(96 / _target, 4); END IF;
ELSIF _game_slug = 'roulette' THEN
_pick := COALESCE(_params->>'color', 'red');
_pocket := floor(random() * 37)::int;
_color := CASE WHEN _pocket = 0 THEN 'green'
WHEN _pocket % 2 = 1 THEN 'red' ELSE 'black' END;
_outcome := jsonb_build_object('pocket', _pocket, 'color', _color);
IF _pick = _color THEN
_mult := CASE WHEN _color = 'green' THEN 14 ELSE 1.94 END;
END IF;
ELSIF _game_slug = 'slots' THEN
_syms := ARRAY[
floor(random() * 8)::int,
floor(random() * 8)::int,
floor(random() * 8)::int
];
_outcome := jsonb_build_object('reels', to_jsonb(_syms));
IF _syms[1] = _syms[2] AND _syms[2] = _syms[3] THEN
_mult := _mtab[_syms[1] + 1];
ELSIF _syms[1] = _syms[2] OR _syms[2] = _syms[3] OR _syms[1] = _syms[3] THEN
_mult := 1.8;
END IF;
ELSIF _game_slug = 'wheel' THEN
_r := random();
_mult := CASE
WHEN _r < 0.40 THEN 0
WHEN _r < 0.70 THEN 1.2
WHEN _r < 0.88 THEN 1.8
WHEN _r < 0.97 THEN 3
WHEN _r < 0.995 THEN 8
ELSE 25 END;
_outcome := jsonb_build_object('segment', _mult);
ELSE
RETURN jsonb_build_object('success', false, 'error', 'unknown_game');
END IF;
_payout := round(_stake * _mult, 6);
UPDATE profiles
SET ton_balance = ton_balance - _stake + _payout
WHERE telegram_id = _telegram_id;
INSERT INTO game_bets (telegram_id, game_slug, stake, payout, multiplier, meta, status, settled_at)
VALUES (_telegram_id, _game_slug, _stake, _payout, _mult, _outcome,
CASE WHEN _payout > 0 THEN 'won' ELSE 'lost' END, now())
RETURNING id INTO _bet_id;
SELECT ton_balance INTO _bal FROM profiles WHERE telegram_id = _telegram_id;
RETURN jsonb_build_object(
'success', true,
'bet_id', _bet_id,
'multiplier', _mult,
'payout', _payout,
'outcome', _outcome,
'balance', _bal
);
END;
$$;
CREATE FUNCTION public.game_profile_id(_telegram_id bigint) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT id FROM public.profiles WHERE telegram_id = _telegram_id AND is_banned = false LIMIT 1;
$$;
CREATE FUNCTION public.game_public_profiles(_ids uuid[]) RETURNS TABLE(id uuid, username text, first_name text, photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT p.id, p.username, p.first_name, p.photo_url
FROM public.profiles p
WHERE p.id = ANY(coalesce(_ids, '{}'::uuid[]))
LIMIT 500;
$$;
CREATE FUNCTION public.game_settle_bet_for_telegram(_telegram_id bigint, _bet_id uuid, _won boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_bet game_bets%ROWTYPE;
_payout numeric := 0;
_bal numeric;
BEGIN
SELECT * INTO _bet FROM game_bets
WHERE id = _bet_id AND telegram_id = _telegram_id AND status = 'open'
FOR UPDATE;
IF _bet.id IS NULL THEN
RETURN jsonb_build_object('success', false, 'error', 'bet_not_found');
END IF;
IF _won THEN
_payout := round(_bet.stake * 1.8, 6);
UPDATE profiles SET ton_balance = ton_balance + _payout WHERE telegram_id = _telegram_id;
END IF;
UPDATE game_bets
SET status = CASE WHEN _won THEN 'won' ELSE 'lost' END,
payout = _payout,
settled_at = now()
WHERE id = _bet.id;
SELECT ton_balance INTO _bal FROM profiles WHERE telegram_id = _telegram_id;
RETURN jsonb_build_object('success', true, 'payout', _payout, 'balance', _bal);
END;
$$;
CREATE FUNCTION public.game_touch_updated_at() RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;
CREATE FUNCTION public.get_battle_inventory_for_telegram(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', b.id, 'category', b.category, 'package_key', b.package_key,
'package_name', b.package_name, 'quantity', b.quantity, 'total_purchased', b.total_purchased, 'updated_at', b.updated_at))
FROM public.battle_inventory b WHERE b.user_id = v_uid AND b.quantity > 0), '[]'::jsonb);
END; $$;
CREATE FUNCTION public.get_payment_discount_for_telegram(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
v_spent numeric := 0;
v_count integer := 0;
v_tier text := 'none';
v_label text := 'Newcomer';
v_pct numeric := 0;
v_first boolean := false;
v_next_pct numeric := NULL;
v_next_at numeric := NULL;
v_ai record;
v_ai_pct numeric := 0;
BEGIN
SELECT COALESCE(SUM(COALESCE(base_amount_nano, amount_nano)) / 1e9, 0), COUNT(*)
INTO v_spent, v_count
FROM public.ton_payment_intents
WHERE telegram_id = _telegram_id AND status = 'confirmed';
IF v_spent >= 100 THEN
v_tier := 'diamond'; v_label := 'Diamond'; v_pct := 25;
ELSIF v_spent >= 40 THEN
v_tier := 'gold'; v_label := 'Gold'; v_pct := 15; v_next_pct := 25; v_next_at := 100;
ELSIF v_spent >= 15 THEN
v_tier := 'silver'; v_label := 'Silver'; v_pct := 10; v_next_pct := 15; v_next_at := 40;
ELSIF v_spent >= 5 THEN
v_tier := 'bronze'; v_label := 'Bronze'; v_pct := 5; v_next_pct := 10; v_next_at := 15;
ELSE
v_tier := 'none'; v_label := 'Newcomer'; v_pct := 0; v_next_pct := 5; v_next_at := 5;
END IF;
IF v_count = 0 THEN
v_first := true;
v_pct := GREATEST(v_pct, 20);
END IF;
SELECT * INTO v_ai
FROM public.ai_smart_offers
WHERE telegram_id = _telegram_id AND expires_at > now()
ORDER BY created_at DESC
LIMIT 1;
IF v_ai.id IS NOT NULL THEN
v_ai_pct := LEAST(GREATEST(COALESCE(v_ai.bonus_pct, 0), 0), 15);
END IF;
v_pct := LEAST(v_pct + v_ai_pct, 50);
RETURN jsonb_build_object(
'total_spent_ton', ROUND(v_spent, 4),
'payments', v_count,
'tier', v_tier,
'tier_label', v_label,
'discount_pct', v_pct,
'first_purchase', v_first,
'ai_bonus_pct', v_ai_pct,
'ai_headline', COALESCE(v_ai.headline, ''),
'ai_message', COALESCE(v_ai.message, ''),
'ai_cta', COALESCE(v_ai.cta, ''),
'ai_expires_at', v_ai.expires_at,
'next_tier_pct', v_next_pct,
'next_tier_ton', v_next_at,
'remaining_to_next_ton', CASE WHEN v_next_at IS NULL THEN NULL ELSE GREATEST(ROUND(v_next_at - v_spent, 4), 0) END
);
END;
$$;
CREATE FUNCTION public.get_referral_summary_for_telegram(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('count', 0, 'ton_earned', 0, 'users', '[]'::jsonb, 'rewards', '[]'::jsonb); END IF;
RETURN jsonb_build_object(
'count', (SELECT count(*) FROM public.profiles WHERE referred_by = v_uid),
'ton_earned', COALESCE((SELECT sum(ton_amount) FROM public.referral_rewards WHERE referrer_id = v_uid), 0),
'users', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'username', p.username, 'photo_url', p.photo_url, 'joined_at', p.created_at) ORDER BY p.created_at DESC)
FROM public.profiles p WHERE p.referred_by = v_uid), '[]'::jsonb),
'rewards', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'source_type', r.source_type, 'ton_amount', r.ton_amount, 'created_at', r.created_at, 'referred_user_id', r.referred_user_id) ORDER BY r.created_at DESC)
FROM public.referral_rewards r WHERE r.referrer_id = v_uid), '[]'::jsonb));
END; $$;
CREATE FUNCTION public.get_server_time() RETURNS timestamp with time zone
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT now();
$$;
CREATE FUNCTION public.grant_prize_to_all() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public'
AS $$ SELECT jsonb_build_object('granted', 0, 'disabled', true) $$;
CREATE FUNCTION public.grant_referral_reward(_buyer_profile_id uuid, _source_type text, _source_id uuid, _ton_amount numeric) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_referrer_id UUID;
_reward NUMERIC := ROUND(GREATEST(COALESCE(_ton_amount, 0), 0) * 0.5, 4);
BEGIN
IF _reward <= 0 THEN
RETURN 0;
END IF;
SELECT referred_by INTO _referrer_id
FROM public.profiles
WHERE id = _buyer_profile_id;
IF _referrer_id IS NULL THEN
RETURN 0;
END IF;
INSERT INTO public.referral_rewards (referrer_id, referred_user_id, source_type, source_id, ton_amount)
VALUES (_referrer_id, _buyer_profile_id, _source_type, _source_id, _reward);
UPDATE public.profiles
SET ton_balance = COALESCE(ton_balance, 0) + _reward
WHERE id = _referrer_id;
PERFORM public.queue_telegram_notification(
_referrer_id,
'referral_reward',
'Referral Reward',
'You received ' || _reward || ' TON from a referral purchase.',
jsonb_build_object(
'source_type', _source_type,
'source_id', _source_id,
'amount', _reward,
'buyer_profile_id', _buyer_profile_id
)
);
RETURN _reward;
END;
$$;
CREATE FUNCTION public.grant_welcome_prize(_telegram_id bigint) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public'
AS $$ SELECT jsonb_build_object('granted', false, 'disabled', true) $$;
CREATE FUNCTION public.has_role(_user_id uuid, _role public.app_role) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT EXISTS (
SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role
)
$$;
CREATE FUNCTION public.is_telegram_admin(_telegram_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT EXISTS (SELECT 1 FROM public.telegram_admins WHERE telegram_id = _telegram_id);
$$;
CREATE FUNCTION public.next_prize_broadcast_targets(_limit integer) RETURNS TABLE(id uuid, telegram_id bigint, first_name text)
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public'
AS $$ SELECT NULL::uuid, NULL::bigint, NULL::text WHERE false $$;
CREATE FUNCTION public.perform_attack_for_telegram(_telegram_id bigint, _attack_type text DEFAULT 'free'::text, _package_key text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
v_uid uuid; v_c public.characters%ROWTYPE; v_free int; v_dmg bigint; v_boost numeric := 1;
v_ton numeric := 0; v_kill boolean := false; v_qty int;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'no_profile'); END IF;
SELECT * INTO v_c FROM public.characters WHERE is_active = true ORDER BY updated_at DESC LIMIT 1 FOR UPDATE;
IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'no_boss'); END IF;
SELECT COALESCE(1 + SUM(s.attack_boost - 1), 1) INTO v_boost
FROM public.user_servers us JOIN public.servers s ON s.id = us.server_id WHERE us.user_id = v_uid;
SELECT count(*) INTO v_free FROM public.attacks
WHERE user_id = v_uid AND attack_type = 'free' AND created_at >= date_trunc('day', now());
IF _attack_type = 'free' OR _package_key IS NULL THEN
IF v_free >= 3 THEN RETURN jsonb_build_object('success', false, 'error', 'no_free_attacks'); END IF;
v_dmg := GREATEST(1, floor(100 * COALESCE(v_boost, 1)))::bigint;
ELSE
SELECT quantity INTO v_qty FROM public.battle_inventory WHERE user_id = v_uid AND package_key = _package_key FOR UPDATE;
IF COALESCE(v_qty, 0) <= 0 THEN RETURN jsonb_build_object('success', false, 'error', 'no_items'); END IF;
UPDATE public.battle_inventory SET quantity = quantity - 1 WHERE user_id = v_uid AND package_key = _package_key;
v_dmg := GREATEST(1, floor(1000 * COALESCE(v_boost, 1)))::bigint;
END IF;
IF v_dmg >= v_c.current_hp THEN
v_dmg := v_c.current_hp; v_kill := true;
v_ton := round(v_c.ton_pool * 0.3, 6);
ELSE
v_ton := round(v_c.ton_pool * (v_dmg::numeric / GREATEST(v_c.max_hp, 1)) * 0.5, 6);
END IF;
UPDATE public.characters
SET current_hp = GREATEST(0, current_hp - v_dmg),
ton_pool = GREATEST(0, ton_pool - v_ton),
is_active = CASE WHEN current_hp - v_dmg <= 0 THEN false ELSE is_active END
WHERE id = v_c.id RETURNING * INTO v_c;
INSERT INTO public.attacks (user_id, character_id, damage, attack_type, package_key, ton_reward, is_killing_blow)
VALUES (v_uid, v_c.id, v_dmg, CASE WHEN _package_key IS NULL THEN 'free' ELSE _attack_type END, _package_key, v_ton, v_kill);
IF v_ton > 0 THEN
UPDATE public.profiles SET ton_balance = ton_balance + v_ton WHERE id = v_uid;
END IF;
SELECT count(*) INTO v_free FROM public.attacks
WHERE user_id = v_uid AND attack_type = 'free' AND created_at >= date_trunc('day', now());
RETURN jsonb_build_object('success', true, 'damage', v_dmg,
'character', jsonb_build_object('id', v_c.id, 'name', v_c.name, 'current_hp', v_c.current_hp,
'max_hp', v_c.max_hp, 'ton_pool', v_c.ton_pool, 'is_active', v_c.is_active),
'inventory', public.get_battle_inventory_for_telegram(_telegram_id),
'freeAttacksRemaining', GREATEST(0, 3 - v_free));
END; $$;
CREATE FUNCTION public.purchase_battle_item_for_telegram(_telegram_id bigint, _category text, _package_key text, _package_name text, _quantity integer, _ton_paid numeric, _wallet_address text DEFAULT NULL::text, _tx_hash text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_tx uuid; v_ref numeric := 0;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false); END IF;
INSERT INTO public.battle_inventory (user_id, category, package_key, package_name, quantity, total_purchased)
VALUES (v_uid, _category, _package_key, _package_name, _quantity, _quantity)
ON CONFLICT (user_id, package_key) DO UPDATE
SET quantity = public.battle_inventory.quantity + EXCLUDED.quantity,
total_purchased = public.battle_inventory.total_purchased + EXCLUDED.quantity,
package_name = EXCLUDED.package_name,
category = EXCLUDED.category;
INSERT INTO public.transactions (user_id, type, amount, currency, status, wallet_address, tx_hash, metadata)
VALUES (v_uid, 'battle_purchase', _ton_paid, 'ton', 'completed', _wallet_address, _tx_hash,
jsonb_build_object('package_key', _package_key, 'quantity', _quantity))
RETURNING id INTO v_tx;
UPDATE public.characters SET ton_pool = ton_pool + round(_ton_paid * 0.25, 6) WHERE is_active = true;
v_ref := public.game_credit_referral(v_uid, _ton_paid, 'battle_purchase');
RETURN jsonb_build_object('success', true, 'transactionId', v_tx, 'referralReward', v_ref,
'inventory', public.get_battle_inventory_for_telegram(_telegram_id));
END; $$;
CREATE FUNCTION public.purchase_battle_item_with_balance(_telegram_id bigint, _category text, _package_key text, _package_name text, _quantity integer, _price numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_user_id uuid;
_balance numeric;
_tx_id uuid;
BEGIN
SELECT id, ton_balance INTO _user_id, _balance FROM public.profiles WHERE telegram_id = _telegram_id;
IF _user_id IS NULL THEN
RETURN jsonb_build_object('success', false, 'error', 'user_not_found');
END IF;
IF _balance < _price THEN
RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance');
END IF;
UPDATE public.profiles SET ton_balance = ton_balance - _price, updated_at = now() WHERE id = _user_id;
INSERT INTO public.battle_inventory (user_id, category, package_key, package_name, quantity, total_purchased)
VALUES (_user_id, _category, _package_key, _package_name, _quantity, _quantity)
ON CONFLICT (user_id, category, package_key) DO UPDATE
SET quantity = battle_inventory.quantity + EXCLUDED.quantity,
total_purchased = battle_inventory.total_purchased + EXCLUDED.total_purchased;
INSERT INTO public.transactions (user_id, type, amount, status, metadata)
VALUES (_user_id, 'battle_purchase', _price, 'completed',
jsonb_build_object('paid_with', 'balance', 'package_key', _package_key, 'package_name', _package_name, 'quantity', _quantity))
RETURNING id INTO _tx_id;
RETURN jsonb_build_object('success', true, 'transactionId', _tx_id);
END;
$$;
CREATE FUNCTION public.purchase_battle_item_with_intent(_telegram_id bigint, _category text, _package_key text, _package_name text, _quantity integer, _intent_id uuid, _wallet_address text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_ton numeric;
BEGIN
v_ton := public.consume_ton_intent(_intent_id, _telegram_id, 'battle_item');
RETURN public.purchase_battle_item_for_telegram(_telegram_id, _category, _package_key, _package_name,
_quantity, v_ton, _wallet_address, _intent_id::text);
END; $$;
CREATE FUNCTION public.purchase_server_for_telegram(_telegram_id bigint, _server_id uuid, _ton_paid numeric, _wallet_address text DEFAULT NULL::text, _tx_hash text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_tx uuid; v_ref numeric := 0;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false); END IF;
INSERT INTO public.user_servers (user_id, server_id, ton_paid) VALUES (v_uid, _server_id, _ton_paid);
INSERT INTO public.transactions (user_id, type, amount, currency, status, wallet_address, tx_hash, metadata)
VALUES (v_uid, 'server_purchase', _ton_paid, 'ton', 'completed', _wallet_address, _tx_hash, jsonb_build_object('server_id', _server_id))
RETURNING id INTO v_tx;
UPDATE public.characters SET ton_pool = ton_pool + round(_ton_paid * 0.25, 6) WHERE is_active = true;
v_ref := public.game_credit_referral(v_uid, _ton_paid, 'server_purchase');
RETURN jsonb_build_object('success', true, 'transactionId', v_tx, 'referralReward', v_ref);
END; $$;
CREATE FUNCTION public.purchase_server_with_balance(_telegram_id bigint, _server_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_price numeric; v_bal numeric; v_tx uuid; v_ref numeric := 0;
BEGIN
v_uid := public.game_profile_id(_telegram_id);
IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
SELECT price_ton INTO v_price FROM public.servers WHERE id = _server_id AND is_active = true;
IF v_price IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'server_not_found'); END IF;
SELECT COALESCE(ton_balance, 0) INTO v_bal FROM public.profiles WHERE id = v_uid FOR UPDATE;
IF v_bal < v_price THEN
RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance');
END IF;
UPDATE public.profiles SET ton_balance = COALESCE(ton_balance, 0) - v_price, updated_at = now() WHERE id = v_uid;
INSERT INTO public.user_servers (user_id, server_id, ton_paid) VALUES (v_uid, _server_id, v_price);
INSERT INTO public.transactions (user_id, type, amount, currency, status, metadata)
VALUES (v_uid, 'server_purchase', v_price, 'ton', 'completed',
jsonb_build_object('server_id', _server_id, 'paid_with', 'balance'))
RETURNING id INTO v_tx;
UPDATE public.characters SET ton_pool = ton_pool + round(v_price * 0.25, 6) WHERE is_active = true;
v_ref := public.game_credit_referral(v_uid, v_price, 'server_purchase');
RETURN jsonb_build_object('success', true, 'transactionId', v_tx, 'referralReward', v_ref, 'price', v_price);
END; $$;
CREATE FUNCTION public.purchase_server_with_intent(_telegram_id bigint, _server_id uuid, _intent_id uuid, _wallet_address text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_ton numeric;
BEGIN
v_ton := public.consume_ton_intent(_intent_id, _telegram_id, 'server');
RETURN public.purchase_server_for_telegram(_telegram_id, _server_id, v_ton, _wallet_address, _intent_id::text);
END; $$;
CREATE FUNCTION public.pvp_add_bots(_match_id uuid, _count integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_slot int; i int; v_names text[] := ARRAY['Wraith','Vortex','Nomad','Sentinel','Havoc','Cipher'];
BEGIN
SELECT COALESCE(max(slot) + 1, 0) INTO v_slot FROM public.pvp_match_players WHERE match_id = _match_id;
FOR i IN 0.._count - 1 LOOP
INSERT INTO public.pvp_match_players (match_id, username, slot, is_bot, weapon_key)
VALUES (_match_id, v_names[1 + ((v_slot + i) % array_length(v_names,1))] , v_slot + i, true,
(ARRAY['pistol','smg','shotgun','rifle'])[1 + floor(random()*4)::int])
ON CONFLICT DO NOTHING;
END LOOP;
UPDATE public.pvp_matches SET status = 'live', started_at = now(), ends_at = now() + interval '90 seconds', updated_at = now()
WHERE id = _match_id AND status = 'waiting';
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.pvp_buy_character(_telegram_id bigint, _character_key text, _ton_paid numeric, _tx_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_pid uuid;
_price numeric;
BEGIN
SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
IF _pid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
SELECT price_ton INTO _price FROM public.pvp_characters WHERE key = _character_key;
IF _price IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'character_not_found'); END IF;
IF _ton_paid < _price THEN RETURN jsonb_build_object('success', false, 'error', 'insufficient_payment'); END IF;
INSERT INTO public.pvp_character_owned (profile_id, character_key, ton_paid, tx_hash)
VALUES (_pid, _character_key, _ton_paid, _tx_hash)
ON CONFLICT (profile_id, character_key) DO NOTHING;
RETURN jsonb_build_object('success', true);
END;
$$;
CREATE FUNCTION public.pvp_buy_weapon(_telegram_id bigint, _weapon_key text, _ton_paid numeric, _tx_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_profile uuid; v_price numeric;
BEGIN
v_profile := public.game_profile_id(_telegram_id);
IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
SELECT price_ton INTO v_price FROM public.pvp_weapons WHERE key = _weapon_key;
IF v_price IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'weapon_not_found'); END IF;
IF _ton_paid + 0.0000001 < v_price THEN RETURN jsonb_build_object('success', false, 'error', 'underpaid'); END IF;
INSERT INTO public.pvp_weapon_owned (profile_id, weapon_key, ton_paid, tx_hash)
VALUES (v_profile, _weapon_key, _ton_paid, _tx_hash)
ON CONFLICT (profile_id, weapon_key) DO NOTHING;
RETURN jsonb_build_object('success', true, 'weapon_key', _weapon_key);
END; $$;
CREATE FUNCTION public.pvp_equip_character(_telegram_id bigint, _character_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_pid uuid;
_price numeric;
BEGIN
SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
IF _pid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
SELECT price_ton INTO _price FROM public.pvp_characters WHERE key = _character_key;
IF _price IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'character_not_found'); END IF;
IF _price > 0 AND NOT EXISTS (
SELECT 1 FROM public.pvp_character_owned WHERE profile_id = _pid AND character_key = _character_key
) THEN
RETURN jsonb_build_object('success', false, 'error', 'not_owned');
END IF;
UPDATE public.pvp_character_owned SET equipped = false WHERE profile_id = _pid;
INSERT INTO public.pvp_character_owned (profile_id, character_key, equipped)
VALUES (_pid, _character_key, true)
ON CONFLICT (profile_id, character_key) DO UPDATE SET equipped = true;
RETURN jsonb_build_object('success', true);
END;
$$;
CREATE FUNCTION public.pvp_find_or_create_match(_telegram_id bigint, _mode text DEFAULT 'squad'::text, _weapon_key text DEFAULT 'pistol'::text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
v_profile uuid;
v_match public.pvp_matches;
v_max int;
v_slot int;
v_count int;
v_username text;
v_photo text;
v_owned boolean;
BEGIN
v_profile := public.game_profile_id(_telegram_id);
IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
SELECT COALESCE(username, first_name, 'Player'), photo_url INTO v_username, v_photo
FROM public.profiles WHERE id = v_profile;
SELECT (is_default OR EXISTS (SELECT 1 FROM public.pvp_weapon_owned o WHERE o.profile_id = v_profile AND o.weapon_key = w.key))
INTO v_owned FROM public.pvp_weapons w WHERE w.key = _weapon_key;
IF v_owned IS NOT TRUE THEN _weapon_key := 'pistol'; END IF;
v_max := CASE WHEN _mode = 'duel' THEN 2 ELSE 4 END;
DELETE FROM public.pvp_match_players p
USING public.pvp_matches m
WHERE p.match_id = m.id AND p.profile_id = v_profile AND m.status <> 'finished';
SELECT m.* INTO v_match FROM public.pvp_matches m
WHERE m.status = 'waiting' AND m.mode = _mode
AND m.created_at > now() - interval '2 minutes'
AND (SELECT count(*) FROM public.pvp_match_players p WHERE p.match_id = m.id) < m.max_players
ORDER BY m.created_at ASC LIMIT 1
FOR UPDATE SKIP LOCKED;
IF v_match.id IS NULL THEN
INSERT INTO public.pvp_matches (mode, max_players, prize_ton)
VALUES (_mode, v_max, CASE WHEN _mode = 'duel' THEN 0.015 ELSE 0.03 END)
RETURNING * INTO v_match;
END IF;
SELECT COALESCE(max(slot) + 1, 0), count(*) INTO v_slot, v_count
FROM public.pvp_match_players WHERE match_id = v_match.id;
INSERT INTO public.pvp_match_players (match_id, profile_id, telegram_id, username, photo_url, slot, weapon_key)
VALUES (v_match.id, v_profile, _telegram_id, v_username, v_photo, v_slot, _weapon_key);
RETURN jsonb_build_object(
'success', true,
'match_id', v_match.id,
'mode', v_match.mode,
'max_players', v_match.max_players,
'arena_seed', v_match.arena_seed,
'prize_ton', v_match.prize_ton,
'slot', v_slot,
'profile_id', v_profile,
'weapon_key', _weapon_key
);
END; $$;
CREATE FUNCTION public.pvp_finish_match(_telegram_id bigint, _match_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
v_profile uuid; v_match public.pvp_matches; v_winner public.pvp_match_players;
v_me public.pvp_match_players; v_reward numeric := 0;
BEGIN
v_profile := public.game_profile_id(_telegram_id);
IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
SELECT * INTO v_match FROM public.pvp_matches WHERE id = _match_id FOR UPDATE;
IF v_match.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'match_not_found'); END IF;
SELECT * INTO v_me FROM public.pvp_match_players WHERE match_id = _match_id AND profile_id = v_profile;
IF v_me.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_in_match'); END IF;
IF v_match.status <> 'finished' THEN
SELECT * INTO v_winner FROM public.pvp_match_players
WHERE match_id = _match_id ORDER BY score DESC, kills DESC, deaths ASC LIMIT 1;
UPDATE public.pvp_matches
SET status = 'finished', winner_profile_id = v_winner.profile_id, updated_at = now()
WHERE id = _match_id;
ELSE
SELECT * INTO v_winner FROM public.pvp_match_players
WHERE match_id = _match_id ORDER BY score DESC, kills DESC, deaths ASC LIMIT 1;
END IF;
IF v_winner.profile_id = v_profile THEN v_reward := v_match.prize_ton; END IF;
INSERT INTO public.pvp_stats (profile_id, matches, wins, kills, deaths, rating, ton_earned, updated_at)
VALUES (v_profile, 1, CASE WHEN v_reward > 0 THEN 1 ELSE 0 END, v_me.kills, v_me.deaths,
1000 + CASE WHEN v_reward > 0 THEN 25 ELSE -10 END, v_reward, now())
ON CONFLICT (profile_id) DO UPDATE SET
matches = public.pvp_stats.matches + 1,
wins = public.pvp_stats.wins + CASE WHEN v_reward > 0 THEN 1 ELSE 0 END,
kills = public.pvp_stats.kills + v_me.kills,
deaths = public.pvp_stats.deaths + v_me.deaths,
rating = GREATEST(0, public.pvp_stats.rating + CASE WHEN v_reward > 0 THEN 25 ELSE -10 END),
ton_earned = public.pvp_stats.ton_earned + v_reward,
updated_at = now();
UPDATE public.profiles
SET ton_balance = COALESCE(ton_balance, 0) + v_reward,
siri_balance = COALESCE(siri_balance, 0) + (v_me.kills * 250)
WHERE id = v_profile;
RETURN jsonb_build_object(
'success', true,
'won', (v_winner.profile_id = v_profile),
'ton_reward', v_reward,
'siri_reward', v_me.kills * 250,
'winner', v_winner.username,
'kills', v_me.kills,
'deaths', v_me.deaths,
'score', v_me.score
);
END; $$;
CREATE FUNCTION public.pvp_get_characters(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_pid uuid;
_res jsonb;
BEGIN
SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
SELECT jsonb_agg(to_jsonb(t) ORDER BY t.sort_order) INTO _res
FROM (
SELECT c.key, c.name, c.title, c.rarity, c.price_ton, c.speed_mod, c.hp_mod, c.color, c.sort_order,
(c.price_ton = 0 OR o.id IS NOT NULL) AS owned,
COALESCE(o.equipped, false) AS equipped
FROM public.pvp_characters c
LEFT JOIN public.pvp_character_owned o ON o.character_key = c.key AND o.profile_id = _pid
) t;
RETURN COALESCE(_res, '[]'::jsonb);
END;
$$;
CREATE FUNCTION public.pvp_get_loadout(_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_profile uuid; v_res jsonb;
BEGIN
v_profile := public.game_profile_id(_telegram_id);
SELECT jsonb_agg(jsonb_build_object(
'key', w.key, 'name', w.name, 'rarity', w.rarity, 'damage', w.damage,
'fire_rate_ms', w.fire_rate_ms, 'bullet_speed', w.bullet_speed, 'spread', w.spread,
'pellets', w.pellets, 'range_px', w.range_px, 'price_ton', w.price_ton,
'color', w.color, 'sort_order', w.sort_order,
'owned', (w.is_default OR EXISTS (SELECT 1 FROM public.pvp_weapon_owned o WHERE o.profile_id = v_profile AND o.weapon_key = w.key))
) ORDER BY w.sort_order) INTO v_res FROM public.pvp_weapons w;
RETURN COALESCE(v_res, '[]'::jsonb);
END; $$;
CREATE FUNCTION public.pvp_leaderboard(_limit integer DEFAULT 20) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
SELECT COALESCE(p.username, p.first_name, 'Player') AS username, p.photo_url,
s.wins, s.kills, s.rating, s.ton_earned
FROM public.pvp_stats s JOIN public.profiles p ON p.id = s.profile_id
ORDER BY s.rating DESC, s.wins DESC LIMIT _limit
) x;
$$;
CREATE FUNCTION public.pvp_report_frag(_telegram_id bigint, _match_id uuid, _kills integer, _deaths integer, _score integer, _alive boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_profile uuid;
BEGIN
v_profile := public.game_profile_id(_telegram_id);
IF v_profile IS NULL THEN RETURN jsonb_build_object('success', false); END IF;
UPDATE public.pvp_match_players
SET kills = GREATEST(kills, _kills), deaths = GREATEST(deaths, _deaths),
score = GREATEST(score, _score), alive = _alive
WHERE match_id = _match_id AND profile_id = v_profile;
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.pvp_set_match_character(_telegram_id bigint, _match_id uuid, _character_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_pid uuid;
BEGIN
SELECT id INTO _pid FROM public.profiles WHERE telegram_id = _telegram_id;
IF _pid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'profile_not_found'); END IF;
UPDATE public.pvp_match_players SET character_key = _character_key
WHERE match_id = _match_id AND profile_id = _pid;
RETURN jsonb_build_object('success', true);
END;
$$;
CREATE FUNCTION public.pvp_start_match(_match_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
UPDATE public.pvp_matches
SET status = 'live', started_at = now(), ends_at = now() + interval '90 seconds', updated_at = now()
WHERE id = _match_id AND status = 'waiting';
RETURN jsonb_build_object('success', true);
END; $$;
CREATE FUNCTION public.queue_telegram_notification(_profile_id uuid, _notification_type text, _title text, _message text, _metadata jsonb DEFAULT '{}'::jsonb, _scheduled_for timestamp with time zone DEFAULT now()) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
_notification_id UUID;
BEGIN
INSERT INTO public.telegram_notifications (profile_id, notification_type, title, message, metadata, scheduled_for)
VALUES (_profile_id, _notification_type, _title, _message, COALESCE(_metadata, '{}'::jsonb), COALESCE(_scheduled_for, now()))
RETURNING id INTO _notification_id;
RETURN _notification_id;
END;
$$;