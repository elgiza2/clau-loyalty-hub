export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      ai_subscriptions: {
        Row: {
          created_at: string
          expires_at: string | null
          id: string
          images_used: number
          period_start: string
          plan: string
          profile_id: string
          status: string
          updated_at: string
          videos_used: number
        }
        Insert: {
          created_at?: string
          expires_at?: string | null
          id?: string
          images_used?: number
          period_start?: string
          plan?: string
          profile_id: string
          status?: string
          updated_at?: string
          videos_used?: number
        }
        Update: {
          created_at?: string
          expires_at?: string | null
          id?: string
          images_used?: number
          period_start?: string
          plan?: string
          profile_id?: string
          status?: string
          updated_at?: string
          videos_used?: number
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      __exec_sql: { Args: { sql: string }; Returns: undefined }
      ad_watch_claim:
        | { Args: { _telegram_id: number }; Returns: Json }
        | { Args: { _telegram_id: number; _tier?: string }; Returns: Json }
      ad_watch_get_progress: { Args: { _telegram_id: number }; Returns: Json }
      ad_watch_increment: {
        Args: { _telegram_id: number; _tier?: string }
        Returns: Json
      }
      admin_activate_character_for_telegram: {
        Args: { _character_id: string; _telegram_id: number }
        Returns: Json
      }
      admin_activate_reward_for_telegram: {
        Args: { _reward_amount: number; _telegram_id: number }
        Returns: Json
      }
      admin_broadcast_notification_for_telegram: {
        Args: { _message: string; _telegram_id: number; _title: string }
        Returns: Json
      }
      admin_cleanup_expired_rewards: { Args: never; Returns: Json }
      admin_create_character_for_telegram:
        | {
            Args: {
              _image_url: string
              _max_hp: number
              _name: string
              _telegram_id: number
            }
            Returns: Json
          }
        | {
            Args: {
              _image_url: string
              _max_hp: number
              _name: string
              _telegram_id: number
            }
            Returns: Json
          }
      admin_create_server_for_telegram:
        | {
            Args: {
              _attack_boost: number
              _image_url: string
              _mining_boost: number
              _name: string
              _price_ton: number
              _rarity: string
              _telegram_id: number
              _ton_mining_rate: number
              _usdt_mining_rate: number
            }
            Returns: Json
          }
        | {
            Args: {
              _attack_boost: number
              _image_url: string
              _mining_boost: number
              _name: string
              _price_ton: number
              _rarity: string
              _telegram_id: number
              _ton_mining_rate: number
              _usdt_mining_rate: number
            }
            Returns: Json
          }
      admin_delete_task_for_telegram: {
        Args: { _task_id: string; _telegram_id: number }
        Returns: Json
      }
      admin_get_dashboard_for_telegram: {
        Args: { _telegram_id: number }
        Returns: Json
      }
      admin_pin_task_for_telegram: {
        Args: { _is_pinned: boolean; _task_id: string; _telegram_id: number }
        Returns: Json
      }
      admin_set_welcome_image_for_telegram: {
        Args: { _telegram_id: number; _url: string }
        Returns: Json
      }
      admin_toggle_ban_for_telegram: {
        Args: { _is_banned: boolean; _profile_id: string; _telegram_id: number }
        Returns: Json
      }
      admin_toggle_task_for_telegram: {
        Args: { _is_active: boolean; _task_id: string; _telegram_id: number }
        Returns: Json
      }
      admin_upsert_task_for_telegram: {
        Args: {
          _link: string
          _reward_amount: number
          _reward_type: string
          _task_id: string
          _task_type: string
          _telegram_id: number
          _title: string
        }
        Returns: Json
      }
      ai_activate_plan: {
        Args: { _plan: string; _price: number; _profile_id: string }
        Returns: {
          created_at: string
          expires_at: string | null
          id: string
          images_used: number
          period_start: string
          plan: string
          profile_id: string
          status: string
          updated_at: string
          videos_used: number
        }
        SetofOptions: {
          from: "*"
          to: "ai_subscriptions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ai_activate_plan_with_intent: {
        Args: {
          _intent_id: string
          _plan: string
          _profile_id: string
          _telegram_id: number
        }
        Returns: {
          created_at: string
          expires_at: string | null
          id: string
          images_used: number
          period_start: string
          plan: string
          profile_id: string
          status: string
          updated_at: string
          videos_used: number
        }
        SetofOptions: {
          from: "*"
          to: "ai_subscriptions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ai_get_subscription: {
        Args: { _profile_id: string }
        Returns: {
          created_at: string
          expires_at: string | null
          id: string
          images_used: number
          period_start: string
          plan: string
          profile_id: string
          status: string
          updated_at: string
          videos_used: number
        }
        SetofOptions: {
          from: "*"
          to: "ai_subscriptions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      all_prize_broadcast_targets: {
        Args: { _limit?: number; _offset?: number }
        Returns: {
          first_name: string
          id: string
          telegram_id: number
        }[]
      }
      attach_referral_for_telegram: {
        Args: { _code: string; _telegram_id: number }
        Returns: Json
      }
      complete_task_for_telegram: {
        Args: { _task_id: string; _telegram_id: number }
        Returns: Json
      }
      consume_ton_intent: {
        Args: { _action: string; _intent_id: string; _telegram_id: number }
        Returns: number
      }
      create_smart_offer_for_telegram: {
        Args: { _surface?: string; _telegram_id: number }
        Returns: Json
      }
      credit_ton_deposit_with_intent: {
        Args: {
          _intent_id: string
          _telegram_id: number
          _wallet_address?: string
        }
        Returns: Json
      }
      expire_prize_rewards: { Args: never; Returns: number }
      game_crash_cashout: {
        Args: { _at: number; _bet_id: string; _telegram_id: number }
        Returns: Json
      }
      game_crash_history: {
        Args: { _limit?: number }
        Returns: {
          crash_multiplier: number
          round_id: number
        }[]
      }
      game_crash_pick: { Args: { _u: number; _v: number }; Returns: number }
      game_crash_players: {
        Args: { _exclude?: number; _limit?: number; _round: number }
        Returns: {
          name: string
          photo_url: string
        }[]
      }
      game_crash_round_result: { Args: { _round_id: number }; Returns: number }
      game_crash_start:
        | { Args: { _stake: number; _telegram_id: number }; Returns: Json }
        | {
            Args: { _round_id?: number; _stake: number; _telegram_id: number }
            Returns: Json
          }
      game_create_own_profile: {
        Args: {
          _first_name: string
          _last_name: string
          _photo_url: string
          _telegram_id: number
          _username: string
        }
        Returns: Json
      }
      game_create_transaction: {
        Args: {
          _amount: number
          _currency: string
          _status?: string
          _telegram_id: number
          _tx_hash?: string
          _type: string
          _wallet_address: string
        }
        Returns: Json
      }
      game_credit_referral: {
        Args: { _source: string; _ton_paid: number; _user_id: string }
        Returns: number
      }
      game_get_own_profile: { Args: { _telegram_id: number }; Returns: Json }
    }
    Enums: {
      app_role: "admin" | "user"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "user"],
    },
  },
} as const
