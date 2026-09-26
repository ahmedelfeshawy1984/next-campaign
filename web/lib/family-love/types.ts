export type RelationType =
  | 'mother'
  | 'father'
  | 'spouse'
  | 'grandmother'
  | 'grandfather'
  | 'sibling'
  | 'other';

export type DeviceKind = 'parent' | 'child';

export type OccurrenceStatus = 'pending' | 'in_progress' | 'done' | 'skipped';

export type SubscriptionStatus = 'trialing' | 'active' | 'past_due' | 'expired' | 'cancelled';

export type SubscriptionPlatform = 'android_play' | 'web';

export type MessageEventKey = 'location_share' | 'sos_call_me' | 'battery_low' | 'no_signal';

export interface Station {
  order_index: number;
  title: string;
  icon: string | null;
}

export interface BoardTask {
  task_id: string;
  title: string;
  occurrence_id: string;
  current_station_index: number;
  status: OccurrenceStatus;
  stations: Station[];
}

export interface Entitlement {
  status: SubscriptionStatus;
  trial_ends_at: string;
  current_period_end: string | null;
  platform: SubscriptionPlatform | null;
}

export interface ChildProfile {
  id: string;
  family_circle_id: string;
  display_name: string;
  avatar_url: string | null;
}

export interface FamilyMember {
  id: string;
  family_circle_id: string;
  account_id: string;
  relation_type: RelationType;
  display_name: string | null;
  is_owner: boolean;
}
