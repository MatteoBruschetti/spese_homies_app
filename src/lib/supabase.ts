/// <reference types="vite/client" />
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://tjssmfntbuxubytujcdj.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_9tyzODAB4aq65qOdH3t2Sw_B1QmlSE6';

const DEVICE_TOKEN_KEY = 'device_token';

/**
 * Il token che autorizza questo dispositivo. Non sta nel bundle ne' nel repo:
 * arriva una volta sola nel frammento della URL di attivazione (`#t=<64 hex>`)
 * e da li' finisce in localStorage.
 *
 * Il frammento non viene mai inviato al server, quindi non compare nei log di
 * Vercel ne' nell'header Referer. Lo rimuoviamo comunque subito dalla barra
 * degli indirizzi, cosi' il token non resta nella cronologia del browser.
 *
 * localStorage e' la fonte durevole e non il frammento perche' manifest.json
 * dichiara `start_url: "/"`: lanciando la web app dalla schermata Home il
 * frammento andrebbe perso, mentre localStorage sopravvive.
 */
function readDeviceToken(): string | null {
  const fromHash = window.location.hash.match(/[#&]t=([0-9a-f]{64})/i)?.[1];
  if (fromHash) {
    try {
      localStorage.setItem(DEVICE_TOKEN_KEY, fromHash);
    } catch {
      // Storage negato (navigazione privata): il token vale per questa sessione.
    }
    history.replaceState(null, '', window.location.pathname + window.location.search);
    return fromHash;
  }
  try {
    return localStorage.getItem(DEVICE_TOKEN_KEY);
  } catch {
    return null;
  }
}

export const deviceToken = readDeviceToken();

/** Formato del token: i due UUID concatenati generati da `devices`. */
export const DEVICE_TOKEN_RE = /^[0-9a-f]{64}$/i;

/**
 * Attivazione manuale. Serve soprattutto su iOS: una web app aggiunta alla
 * schermata Home ha un contenitore di storage separato da Safari e non ha barra
 * degli indirizzi, quindi il link di attivazione non e' apribile da dentro.
 * Accetta sia il token nudo sia il link di attivazione completo.
 */
export function saveDeviceToken(input: string): boolean {
  const token = input.trim().replace(/^.*[#&]t=/, '');
  if (!DEVICE_TOKEN_RE.test(token)) return false;
  try {
    localStorage.setItem(DEVICE_TOKEN_KEY, token);
  } catch {
    return false;
  }
  return true;
}

// Use defaults to avoid load errors, but prefer env variables
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  global: {
    headers: deviceToken ? { 'x-device-token': deviceToken } : {},
  },
});

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
