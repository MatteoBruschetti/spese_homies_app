/// <reference types="vite/client" />
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://tjssmfntbuxubytujcdj.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_9tyzODAB4aq65qOdH3t2Sw_B1QmlSE6';

// Use defaults to avoid load errors, but prefer env variables
export const supabase = createClient(supabaseUrl, supabaseAnonKey);

if (!import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_ANON_KEY) {
  console.info('Using default Supabase keys. Set VITE_SUPABASE_URL/KEY in Secrets for custom projects.');
}

export interface Expense {
  id: string;
  amount: number;
  category: string;
  created_by: string;
  created_at: string;
  notes?: string;
}

export interface Settlement {
  id: string;
  amount: number;
  settled_at: string;
  settled_by: string;
}
