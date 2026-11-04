import React, { useState, useEffect, useMemo } from 'react';
import {
  Car,
  Wrench,
  ClipboardList,
  BookOpen,
  Plus,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  Search,
  Filter,
  Download,
  Upload,
  RotateCcw,
  Edit3,
  Trash2,
  Gauge,
  DollarSign,
  Calendar,
  ChevronRight,
  Check,
  X,
  Info,
  ShieldCheck,
  Sparkles,
  Droplets,
  Clock,
  Tag,
  Package,
  Camera,
  Image as ImageIcon,
  Copy,
  ArrowUpDown,
  Database,
  Store,
  Layers,
  Minus,
  Cloud,
  CloudOff,
  RefreshCw,
  Smartphone,
  QrCode,
  Wifi,
  Share2,
  KeyRound,
  ExternalLink
} from 'lucide-react';

// ==========================================
// SUPABASE CLOUD SYNC CONFIGURATION
// ==========================================
// Option 1: Paste your Supabase Project URL and Anon Key right here when deploying to Vercel/GitHub:
const DEFAULT_SUPABASE_URL = ''; // e.g. 'https://xyzcompany.supabase.co'
const DEFAULT_SUPABASE_ANON_KEY = ''; // e.g. 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
const DEFAULT_GARAGE_SYNC_CODE = 'JETTA-GARAGE-1';

// Option 2: Or leave these blank and paste your URL & Anon Key directly in the app's "Supabase / Phone Sync" modal!
const LOCAL_STORAGE_STATE_KEY = 'garage_command_pro_v3_state';
const LOCAL_STORAGE_CONFIG_KEY = 'garage_command_pro_v3_supabase_cfg';

// Exact SQL script to run once in the Supabase SQL Editor
const SUPABASE_SETUP_SQL = `-- Run this once in your Supabase SQL Editor:
create table if not exists public.garage_state (
  sync_code text primary key,
  payload jsonb not null,
  updated_at timestamptz default now(),
  client_id text
);

alter table public.garage_state enable row level security;

drop policy if exists "Allow anon read/write by sync_code" on public.garage_state;
create policy "Allow anon read/write by sync_code"
  on public.garage_state
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- Enable Realtime on the table:
alter publication supabase_realtime add table public.garage_state;`;

// Dynamic loader for @supabase/supabase-js so Realtime WebSockets + REST work in any browser or build setup
let supabaseSingleton = null;
let supabaseSingletonKey = '';

const getOrCreateSupabaseClient = async (url, anonKey) => {
  const cleanUrl = (url || '').trim().replace(/\/+$/, '');
  const cleanKey = (anonKey || '').trim();
  if (!cleanUrl || !cleanKey) return null;

  const cacheKey = `${cleanUrl}::${cleanKey}`;
  if (supabaseSingleton && supabaseSingletonKey === cacheKey) {
    return supabaseSingleton;
  }

  try {
    // Load @supabase/supabase-js ESM bundle dynamically if not on window
    if (!window.supabaseCreateClient) {
      const mod = await import('https://esm.sh/@supabase/supabase-js@2.45.4');
      window.supabaseCreateClient = mod.createClient;
    }
    supabaseSingleton = window.supabaseCreateClient(cleanUrl, cleanKey, {
      auth: { persistSession: false },
      realtime: { params: { eventsPerSecond: 5 } }
    });
    supabaseSingletonKey = cacheKey;
    return supabaseSingleton;
  } catch (err) {
    console.warn('Dynamic @supabase/supabase-js import fallback to REST:', err);
    return null;
  }
};

// Direct Supabase PostgREST helpers (works even if WebSockets are blocked by a firewall)
const supabaseRestPull = async (url, anonKey, syncCode) => {
  const cleanUrl = url.trim().replace(/\/+$/, '');
  const cleanCode = encodeURIComponent(syncCode.trim().toUpperCase());
  const endpoint = `${cleanUrl}/rest/v1/garage_state?sync_code=eq.${cleanCode}&select=sync_code,payload,updated_at,client_id`;
  const res = await fetch(endpoint, {
    method: 'GET',
    headers: {
      apikey: anonKey.trim(),
      Authorization: `Bearer ${anonKey.trim()}`,
      'Content-Type': 'application/json'
    }
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Supabase Pull HTTP ${res.status}: ${errText}`);
  }
  const rows = await res.json();
  return rows && rows.length > 0 ? rows[0] : null;
};

const supabaseRestPush = async (url, anonKey, syncCode, payloadObj, clientId) => {
  const cleanUrl = url.trim().replace(/\/+$/, '');
  const cleanCode = syncCode.trim().toUpperCase();
  const endpoint = `${cleanUrl}/rest/v1/garage_state?on_conflict=sync_code`;
  const body = {
    sync_code: cleanCode,
    payload: payloadObj,
    updated_at: new Date().toISOString(),
    client_id: clientId
  };
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      apikey: anonKey.trim(),
      Authorization: `Bearer ${anonKey.trim()}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=representation'
    },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Supabase Push HTTP ${res.status}: ${errText}`);
  }
  const rows = await res.json();
  return rows && rows.length > 0 ? rows[0] : body;
};

// Helper to compress photos slightly so they fit comfortably in cloud documents
const compressImageFile = (file, maxWidth = 800, quality = 0.72) => {
  return new Promise((resolve) => {
    if (!file) {
      resolve(null);
      return;
    }
    const reader = new FileReader();
    reader.onload = (event) => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement('canvas');
        let width = img.width;
        let height = img.height;
        if (width > maxWidth) {
          height = Math.round((height * maxWidth) / width);
          width = maxWidth;
        }
        canvas.width = width;
        canvas.height = height;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, width, height);
        resolve(canvas.toDataURL('image/jpeg', quality));
      };
      img.onerror = () => resolve(event.target.result);
      img.src = event.target.result;
    };
    reader.readAsDataURL(file);
  });
};

// ==========================================
// INITIAL DEMO DATA (PRO VERSION)
// ==========================================

const INITIAL_VEHICLES = [
  {
    id: 'v-jetta-2017',
    year: 2017,
    make: 'Volkswagen',
    model: 'Jetta',
    trim: 'TSI 1.8L Turbo (White / Gunmetal)',
    odometer: 168000,
    vinPlate: 'VW-17TSI',
    oilSpec: 'MAG 1 SAE 5W-30 Full Synthetic (5.7 qt, VW 502 00)',
    coolantSpec: 'Peak European Violet G12++/G13 50/50 Prediluted',
    sparkPlugSpec: 'NGK Laser Platinum (5/8" socket, 22 lb-ft)',
    lugTorqueSpec: '89 lb-ft (17mm Lug Bolts)',
    wiperSizes: '24" Driver / 19" Passenger | Tail Light Bulb: 2825',
    notes: 'Spark plugs: 5/8" magnetic socket, 22 lb-ft torque. Tail light bulb: 2825 wedge. Uses Torx T25 for belly pan screws and Triple-Square (XZN) bits for rear caliper carrier bolts & sway bar links.',
    partNumbers: [
      { id: 'pn-1', part: 'Engine Oil Filter Cartridge', number: 'Mann HU 7020 z / OEM 06L115562', vendor: 'FCP Euro / AutoZone' },
      { id: 'pn-2', part: 'Spark Plugs (4x)', number: 'NGK 94833 (PLFER7A8EG)', vendor: 'NGK / Bosch' },
      { id: 'pn-3', part: 'Tail Light Wedge Bulb', number: 'Sylvania 2825 (W5W)', vendor: 'Walmart / AutoZone' },
      { id: 'pn-4', part: 'Cabin Air Filter (Carbon)', number: 'Mann CUK 2939', vendor: 'Amazon / FCP Euro' },
      { id: 'pn-5', part: 'Oil Drain Plug & Crush Washer', number: 'N90813202 (19mm Hex)', vendor: 'OEM VW' }
    ],
    photos: [],
    color: 'from-blue-600 to-indigo-700'
  },
  {
    id: 'v-highlander-2021',
    year: 2021,
    make: 'Toyota',
    model: 'Highlander',
    trim: 'XLE 3.5L V6 AWD',
    odometer: 54200,
    vinPlate: 'TY-21XLE',
    oilSpec: 'SAE 0W-20 Full Synthetic (6.1 qt, ILSAC GF-6A)',
    coolantSpec: 'Toyota Super Long Life Pink 50/50',
    sparkPlugSpec: 'Denso Iridium Long Life (14mm thin-wall socket, 15 lb-ft)',
    lugTorqueSpec: '80 lb-ft (21mm Lug Nuts)',
    wiperSizes: '26" Driver / 20" Passenger / 12" Rear',
    notes: 'Uses 64mm 14-flute cartridge oil filter housing wrench. Lug nut torque: 80 lb-ft (21mm socket). Replace aluminum drain plug crush washer every oil change.',
    partNumbers: [
      { id: 'pn-6', part: 'Oil Filter Cartridge Element', number: 'Toyota OEM 04152-YZZA1', vendor: 'Toyota Dealership / Walmart' },
      { id: 'pn-7', part: 'Drain Plug Crush Gasket', number: 'Toyota 90430-12031', vendor: 'OEM Toyota' },
      { id: 'pn-8', part: 'Iridium Spark Plugs (6x)', number: 'Denso FK20HBR8', vendor: 'RockAuto / Denso' },
      { id: 'pn-9', part: 'Engine Air Filter', number: 'Toyota 17801-0P100', vendor: 'OEM Toyota' }
    ],
    photos: [],
    color: 'from-emerald-600 to-teal-700'
  }
];

const INITIAL_SHELF = [
  {
    id: 's-mag1-oil',
    name: 'MAG 1 SAE 5W-30 Full Synthetic Euro Oil',
    category: 'Fluids',
    vehicleId: 'v-jetta-2017',
    partNumber: 'MAG1-62096',
    quantity: 6,
    minQuantity: 6,
    unit: 'quarts',
    unitCost: 6.49,
    notes: 'FMX European Formula for 2017 Jetta 1.8T (takes 5.7 qt per change)'
  },
  {
    id: 's-mann-filter',
    name: 'Mann Oil Filter (VW 1.8T)',
    category: 'Filters',
    vehicleId: 'v-jetta-2017',
    partNumber: 'Mann HU 7020 z',
    quantity: 1,
    minQuantity: 1,
    unit: 'filter',
    unitCost: 11.99,
    notes: 'Includes O-ring gasket'
  },
  {
    id: 's-peak-coolant',
    name: 'Peak OET European Violet G12++/G13 50/50 Coolant',
    category: 'Fluids',
    vehicleId: 'v-jetta-2017',
    partNumber: 'PEAK-PEVB53',
    quantity: 1,
    minQuantity: 1,
    unit: 'gallon jug',
    unitCost: 18.99,
    notes: 'Half jug remaining from last top-off'
  },
  {
    id: 's-2825-bulb',
    name: '2825 Miniature Wedge Bulb (Tail Light)',
    category: 'Bulbs & Electrical',
    vehicleId: 'v-jetta-2017',
    partNumber: 'Sylvania 2825 LL',
    quantity: 1,
    minQuantity: 1,
    unit: 'bulb',
    unitCost: 3.25,
    notes: '1 spare bulb left from 2-pack'
  },
  {
    id: 's-ngk-plugs',
    name: 'NGK Laser Platinum Spark Plugs (VW 1.8T)',
    category: 'Ignition',
    vehicleId: 'v-jetta-2017',
    partNumber: 'NGK 94833',
    quantity: 0,
    minQuantity: 4,
    unit: 'plugs',
    unitCost: 13.99,
    notes: 'Used all 4 on recent tune-up'
  },
  {
    id: 's-toyota-filter',
    name: 'Toyota OEM Oil Filter Cartridge (04152-YZZA1)',
    category: 'Filters',
    vehicleId: 'v-highlander-2021',
    partNumber: '04152-YZZA1',
    quantity: 2,
    minQuantity: 1,
    unit: 'filters',
    unitCost: 6.50,
    notes: 'Includes filter element & housing O-rings'
  },
  {
    id: 's-0w20-oil',
    name: '0W-20 Full Synthetic Motor Oil',
    category: 'Fluids',
    vehicleId: 'v-highlander-2021',
    partNumber: 'Mobil1-0W20',
    quantity: 3,
    minQuantity: 6,
    unit: 'quarts',
    unitCost: 5.99,
    notes: 'Need 3 more quarts before next Highlander oil change (6.1 qt capacity)'
  },
  {
    id: 's-dot4-fluid',
    name: 'DOT 4 Synthetic Brake Fluid',
    category: 'Fluids',
    vehicleId: 'ALL',
    partNumber: 'Pentosin Super DOT 4',
    quantity: 1,
    minQuantity: 2,
    unit: 'bottles (500ml)',
    unitCost: 12.99,
    notes: 'Unopened bottle on top shelf'
  },
  {
    id: 's-brake-cleaner',
    name: 'Non-Chlorinated Brake Parts Cleaner',
    category: 'Shop Supplies',
    vehicleId: 'ALL',
    partNumber: 'CRC-05088',
    quantity: 2,
    minQuantity: 1,
    unit: 'cans',
    unitCost: 5.49,
    notes: 'Essential for brake & oil jobs'
  }
];

const INITIAL_TOOLS = [
  // Sockets & Bits
  { id: 't-metric-sockets', name: 'Metric Socket Set (8mm - 19mm)', category: 'Sockets & Bits', owned: true, loanerAvailable: false, estBuyPrice: 45, notes: '6-point standard and deep sockets' },
  { id: 't-spark-58', name: '5/8" Magnetic Spark Plug Socket', category: 'Sockets & Bits', owned: true, loanerAvailable: false, estBuyPrice: 12, notes: 'Fits 2017 VW Jetta 1.8T & most domestic/Euro plugs' },
  { id: 't-spark-14mm', name: '14mm Thin-Wall Spark Plug Socket', category: 'Sockets & Bits', owned: false, loanerAvailable: false, estBuyPrice: 14, notes: 'Needed for Toyota 3.5L V6 & modern tight plug wells' },
  { id: 't-torx-set', name: 'Torx Bit Socket Set (T15 - T55)', category: 'Sockets & Bits', owned: true, loanerAvailable: false, estBuyPrice: 28, notes: 'Crucial for VW belly pan (T25), airbox & PCV screws' },
  { id: 't-triple-square', name: 'Triple-Square (XZN) Bit Set (M6 - M16)', category: 'Sockets & Bits', owned: false, loanerAvailable: true, estBuyPrice: 26, notes: 'Required for VW rear caliper carriers (M14) & sway bar links' },
  { id: 't-hex-allen', name: 'Metric Hex / Allen Bit Socket Set (4mm - 12mm)', category: 'Sockets & Bits', owned: true, loanerAvailable: false, estBuyPrice: 22, notes: 'For caliper guide pins & transmission level plugs' },
  { id: 't-lug-sockets', name: '17mm & 21mm Thin-Wall Deep Impact Sockets', category: 'Sockets & Bits', owned: true, loanerAvailable: false, estBuyPrice: 19, notes: '17mm for VW Jetta lug bolts; 21mm for Toyota Highlander lug nuts' },

  // Wrenches & Ratchets
  { id: 't-ratchet-38', name: '3/8" Drive Ratchet & Extensions', category: 'Wrenches & Ratchets', owned: true, loanerAvailable: false, estBuyPrice: 35, notes: 'Includes 3", 6", and 10" extension bars' },
  { id: 't-torque-38', name: 'Torque Wrench (3/8" Drive, 10-80 lb-ft)', category: 'Wrenches & Ratchets', owned: true, loanerAvailable: true, estBuyPrice: 45, notes: 'Ideal for spark plugs (22 lb-ft) & drain plugs' },
  { id: 't-torque-12', name: 'Torque Wrench (1/2" Drive, 30-250 lb-ft)', category: 'Wrenches & Ratchets', owned: true, loanerAvailable: true, estBuyPrice: 60, notes: 'For lug bolts (89 lb-ft VW / 80 lb-ft Toyota) & suspension' },
  { id: 't-combo-wrenches', name: 'Metric Combination Wrench Set (8mm - 19mm)', category: 'Wrenches & Ratchets', owned: true, loanerAvailable: false, estBuyPrice: 38, notes: 'Open and box-end metric wrenches' },
  { id: 't-flare-wrenches', name: '10mm & 11mm Flare Nut (Line) Wrench Set', category: 'Wrenches & Ratchets', owned: false, loanerAvailable: false, estBuyPrice: 18, notes: 'Prevents rounding soft brake caliper bleeder nipples' },
  { id: 't-breaker-bar', name: '1/2" Drive 24" Breaker Bar', category: 'Wrenches & Ratchets', owned: true, loanerAvailable: false, estBuyPrice: 25, notes: 'High leverage for lug nuts and carrier bolts' },

  // Specialty & Diagnostics
  { id: 't-caliper-compressor', name: 'Brake Caliper Piston Wind-Back Kit', category: 'Specialty & Diagnostics', owned: false, loanerAvailable: true, estBuyPrice: 32, notes: 'Free Loan-A-Tool at AutoZone/Advance! Rotates & presses VW rear pistons' },
  { id: 't-toyota-filter-cup', name: 'Toyota 64mm 14-Flute Oil Filter Socket', category: 'Specialty & Diagnostics', owned: false, loanerAvailable: false, estBuyPrice: 15, notes: 'Heavy-duty aluminum cup wrench for Toyota 3.5L V6 filter housing' },
  { id: 't-serpentine-tool', name: 'Long-Reach Serpentine Belt Tensioner Tool', category: 'Specialty & Diagnostics', owned: false, loanerAvailable: true, estBuyPrice: 29, notes: 'Loan-A-Tool eligible; reaches narrow transverse belt tensioners' },
  { id: 't-brake-bleeder', name: 'One-Person Vacuum Brake Bleeder Kit', category: 'Specialty & Diagnostics', owned: false, loanerAvailable: true, estBuyPrice: 34, notes: 'For solo brake fluid flushes' },
  { id: 't-fluid-pump', name: 'Fluid Transfer Pump & Fill Adapter', category: 'Specialty & Diagnostics', owned: false, loanerAvailable: false, estBuyPrice: 18, notes: 'Pumps ATF/gear oil upward into transmission fill ports' },
  { id: 't-wheel-hanger', name: 'M14x1.5 Wheel Hanger Alignment Pin', category: 'Specialty & Diagnostics', owned: true, loanerAvailable: false, estBuyPrice: 11, notes: 'Holds heavy VW wheels on hub while threading lug bolts' },
  { id: 't-obd2-scanner', name: 'OBDII Diagnostic Scanner & EPB Tool', category: 'Specialty & Diagnostics', owned: true, loanerAvailable: true, estBuyPrice: 65, notes: 'Reads CEL codes, ATF temp & retracts Electronic Parking Brakes' },
  { id: 't-multimeter', name: 'Digital Multimeter & 12V Battery Tester', category: 'Specialty & Diagnostics', owned: true, loanerAvailable: true, estBuyPrice: 25, notes: 'Tests resting voltage (12.6V) and alternator output (14.2V)' },

  // Lifting & Garage
  { id: 't-jack-stands', name: 'Hydraulic Floor Jack & 3-Ton Jack Stands', category: 'Lifting & Garage', owned: true, loanerAvailable: false, estBuyPrice: 165, notes: 'Always use jack stands + wheel chocks' },
  { id: 't-drain-pan-funnel', name: 'Oil Drain Pan & Spill-Free Funnel Set', category: 'Lifting & Garage', owned: true, loanerAvailable: false, estBuyPrice: 20, notes: '15-quart catch pan + clean oil funnel' },
  { id: 't-filter-pliers', name: 'Adjustable Oil Filter Wrench / Pliers', category: 'Lifting & Garage', owned: true, loanerAvailable: false, estBuyPrice: 14, notes: 'For spin-on and cartridge housings' },
  { id: 't-gloves-glasses', name: 'Nitrile Gloves & Safety Glasses', category: 'Lifting & Garage', owned: true, loanerAvailable: false, estBuyPrice: 12, notes: 'Personal protective equipment' },

  // Pliers & Drivers
  { id: 't-screwdrivers', name: 'Phillips & Flathead Screwdriver Set', category: 'Pliers & Drivers', owned: true, loanerAvailable: false, estBuyPrice: 20, notes: 'Assorted sizes' },
  { id: 't-trim-tools', name: 'Nylon Trim & Panel Removal Tool Set', category: 'Pliers & Drivers', owned: true, loanerAvailable: false, estBuyPrice: 11, notes: 'Non-marring pry tools for tail light access panels & clips' },
  { id: 't-hose-clamp-pliers', name: 'Spring Hose Clamp Pliers & Pick Set', category: 'Pliers & Drivers', owned: true, loanerAvailable: false, estBuyPrice: 18, notes: 'For intake boots, radiator hoses, and PCV breather clips' }
];

const INITIAL_GUIDES = [
  {
    id: 'g-1-oil-vw',
    title: '1. Engine Oil & Filter Change (VW 1.8L TSI)',
    vehicleId: 'v-jetta-2017',
    category: 'Fluids',
    intervalMiles: 5000,
    intervalMonths: 6,
    difficulty: 'Easy',
    estimatedTime: '35 mins',
    estimatedDiyCost: 45,
    estimatedShopCost: 115,
    requiredTools: [
      '3/8" Drive Ratchet & Extensions',
      'Metric Socket Set (8mm - 19mm)',
      'Torx Bit Socket Set (T15 - T55)',
      'Torque Wrench (3/8" Drive, 10-80 lb-ft)',
      'Adjustable Oil Filter Wrench / Pliers',
      'Oil Drain Pan & Spill-Free Funnel Set',
      'Hydraulic Floor Jack & 3-Ton Jack Stands'
    ],
    requiredParts: [
      { name: 'MAG 1 SAE 5W-30 Full Synthetic Euro Oil', qty: 6 },
      { name: 'Mann Oil Filter (VW 1.8T)', qty: 1 }
    ],
    specsAndAdvice: 'Capacity: 5.7 Quarts of MAG 1 SAE 5W-30 Full Synthetic (VW 502 00). Remove lower belly pan using Torx T25 bit. Drain plug uses 19mm socket torqued to 22 lb-ft (30 Nm) with a fresh crush washer. Lubricate new Mann filter O-ring before tightening to 18 lb-ft.'
  },
  {
    id: 'g-1b-oil-toyota',
    title: '1B. Engine Oil & Cartridge Filter Change (Highlander 3.5L V6)',
    vehicleId: 'v-highlander-2021',
    category: 'Fluids',
    intervalMiles: 5000,
    intervalMonths: 6,
    difficulty: 'Easy',
    estimatedTime: '40 mins',
    estimatedDiyCost: 44,
    estimatedShopCost: 120,
    requiredTools: [
      '3/8" Drive Ratchet & Extensions',
      'Metric Socket Set (8mm - 19mm)',
      'Toyota 64mm 14-Flute Oil Filter Socket',
      'Torque Wrench (3/8" Drive, 10-80 lb-ft)',
      'Oil Drain Pan & Spill-Free Funnel Set',
      'Hydraulic Floor Jack & 3-Ton Jack Stands'
    ],
    requiredParts: [
      { name: '0W-20 Full Synthetic Motor Oil', qty: 6 },
      { name: 'Toyota OEM Oil Filter Cartridge (04152-YZZA1)', qty: 1 }
    ],
    specsAndAdvice: 'Capacity: 6.1 Quarts SAE 0W-20 Full Synthetic. Requires a 64mm 14-flute cup socket to remove the Toyota cartridge oil filter housing without cracking it. Drain plug is 14mm torqued to 30 lb-ft; filter housing torques to 18 lb-ft.'
  },
  {
    id: 'g-2-plugs-vw',
    title: '2. Spark Plug Replacement (VW 1.8T — 5/8" Socket)',
    vehicleId: 'v-jetta-2017',
    category: 'Maintenance',
    intervalMiles: 40000,
    intervalMonths: 48,
    difficulty: 'Moderate',
    estimatedTime: '45 mins',
    estimatedDiyCost: 56,
    estimatedShopCost: 260,
    requiredTools: [
      '3/8" Drive Ratchet & Extensions',
      '5/8" Magnetic Spark Plug Socket',
      'Torque Wrench (3/8" Drive, 10-80 lb-ft)',
      'Metric Socket Set (8mm - 19mm)',
      'Torx Bit Socket Set (T15 - T55)'
    ],
    requiredParts: [
      { name: 'NGK Laser Platinum Spark Plugs (VW 1.8T)', qty: 4 }
    ],
    specsAndAdvice: 'VW Jetta 1.8T uses a 5/8" Magnetic Spark Plug Socket with a 6" extension. Torque Spec: 22 lb-ft (30 Nm) on a cold engine! (Note: Toyota Highlander 3.5L V6 uses a 14mm thin-wall socket at 15 lb-ft). Remove 10mm coil harness ground nuts first and pull ignition coils straight up.'
  },
  {
    id: 'g-3-front-brakes',
    title: '3. Front Brake Pads & Rotors Service',
    vehicleId: 'ALL',
    category: 'Tires/Brakes',
    intervalMiles: 45000,
    intervalMonths: 48,
    difficulty: 'Moderate',
    estimatedTime: '75 mins',
    estimatedDiyCost: 135,
    estimatedShopCost: 440,
    requiredTools: [
      'Hydraulic Floor Jack & 3-Ton Jack Stands',
      '17mm & 21mm Thin-Wall Deep Impact Sockets',
      '1/2" Drive 24" Breaker Bar',
      'Torque Wrench (1/2" Drive, 30-250 lb-ft)',
      'Metric Socket Set (8mm - 19mm)',
      'Metric Hex / Allen Bit Socket Set (4mm - 12mm)'
    ],
    requiredParts: [
      { name: 'Non-Chlorinated Brake Parts Cleaner', qty: 1 }
    ],
    specsAndAdvice: 'Front caliper pistons press straight in (use an old brake pad and C-clamp or piston spreader). Clean rotor friction surfaces with Brake Parts Cleaner, grease slide pins with silicone paste, and torque caliper carrier bolts to spec. Lug torque: 89 lb-ft (VW) / 80 lb-ft (Toyota).'
  },
  {
    id: 'g-4-rear-brakes',
    title: '4. Rear Brake Pads & Rotors (Piston Wind-Back / EPB)',
    vehicleId: 'ALL',
    category: 'Tires/Brakes',
    intervalMiles: 50000,
    intervalMonths: 48,
    difficulty: 'Advanced',
    estimatedTime: '90 mins',
    estimatedDiyCost: 145,
    estimatedShopCost: 490,
    requiredTools: [
      'Hydraulic Floor Jack & 3-Ton Jack Stands',
      '1/2" Drive 24" Breaker Bar',
      'Torque Wrench (1/2" Drive, 30-250 lb-ft)',
      'Metric Socket Set (8mm - 19mm)',
      'Triple-Square (XZN) Bit Set (M6 - M16)',
      'Brake Caliper Piston Wind-Back Kit',
      'OBDII Diagnostic Scanner & EPB Tool'
    ],
    requiredParts: [
      { name: 'Non-Chlorinated Brake Parts Cleaner', qty: 1 }
    ],
    specsAndAdvice: 'VW Jetta mechanical rear calipers MUST be rotated clockwise while pressing in using a Brake Caliper Piston Wind-Back Kit (free rental at AutoZone) and require an M14 Triple-Square bit for the carrier. Toyota Highlander uses an Electronic Parking Brake (put into EPB Service Mode via OBD tool or dash sequence before pressing piston).'
  },
  {
    id: 'g-5-brake-flush',
    title: '5. Brake Fluid Flush / Bleed (DOT 4 / DOT 3)',
    vehicleId: 'ALL',
    category: 'Fluids',
    intervalMiles: 30000,
    intervalMonths: 24,
    difficulty: 'Moderate',
    estimatedTime: '60 mins',
    estimatedDiyCost: 26,
    estimatedShopCost: 165,
    requiredTools: [
      'Hydraulic Floor Jack & 3-Ton Jack Stands',
      '10mm & 11mm Flare Nut (Line) Wrench Set',
      'One-Person Vacuum Brake Bleeder Kit',
      'Nitrile Gloves & Safety Glasses'
    ],
    requiredParts: [
      { name: 'DOT 4 Synthetic Brake Fluid', qty: 2 }
    ],
    specsAndAdvice: 'Flush every 2–3 years / 30k miles to prevent moisture corrosion in ABS valves. Bleed sequence: Rear Right -> Rear Left -> Front Right -> Front Left. Always use a 10mm/11mm Flare Nut Wrench on bleeder screws and never let the master cylinder reservoir run dry!'
  },
  {
    id: 'g-6-coolant',
    title: '6. Coolant Flush / Drain & Top-Off (Euro Violet / Toyota Pink)',
    vehicleId: 'ALL',
    category: 'Fluids',
    intervalMiles: 30000,
    intervalMonths: 24,
    difficulty: 'Easy',
    estimatedTime: '25 mins',
    estimatedDiyCost: 19,
    estimatedShopCost: 135,
    requiredTools: [
      'Oil Drain Pan & Spill-Free Funnel Set',
      'Spring Hose Clamp Pliers & Pick Set',
      'Nitrile Gloves & Safety Glasses'
    ],
    requiredParts: [
      { name: 'Peak OET European Violet G12++/G13 50/50 Coolant', qty: 1 }
    ],
    specsAndAdvice: 'VW Jetta uses Peak European Violet G12++/G13 50/50 Prediluted. Highlander uses Toyota Super Long Life Pink 50/50. NEVER open a hot pressurized expansion cap! Fill to the cold MAX seam line and inspect water pump housing for seepage.'
  },
  {
    id: 'g-7-trans-fluid',
    title: '7. Transmission / Transaxle Fluid Drain & Fill',
    vehicleId: 'ALL',
    category: 'Fluids',
    intervalMiles: 60000,
    intervalMonths: 60,
    difficulty: 'Advanced',
    estimatedTime: '90 mins',
    estimatedDiyCost: 85,
    estimatedShopCost: 380,
    requiredTools: [
      'Hydraulic Floor Jack & 3-Ton Jack Stands',
      'Metric Hex / Allen Bit Socket Set (4mm - 12mm)',
      'Fluid Transfer Pump & Fill Adapter',
      'OBDII Diagnostic Scanner & EPB Tool',
      'Torque Wrench (3/8" Drive, 10-80 lb-ft)',
      'Oil Drain Pan & Spill-Free Funnel Set'
    ],
    requiredParts: [],
    specsAndAdvice: 'Critical at 60,000 miles! Always crack open the FILL plug BEFORE removing the drain plug. Vehicle must be dead level on 4 jack stands. Use OBDII scanner to monitor live ATF temperature (35°C–45°C) when setting final overflow level.'
  },
  {
    id: 'g-8-serpentine',
    title: '8. Serpentine / Accessory Belt Inspection & Swap',
    vehicleId: 'ALL',
    category: 'Maintenance',
    intervalMiles: 60000,
    intervalMonths: 60,
    difficulty: 'Moderate',
    estimatedTime: '45 mins',
    estimatedDiyCost: 32,
    estimatedShopCost: 195,
    requiredTools: [
      'Long-Reach Serpentine Belt Tensioner Tool',
      'Metric Combination Wrench Set (8mm - 19mm)',
      '3/8" Drive Ratchet & Extensions',
      'Nitrile Gloves & Safety Glasses'
    ],
    requiredParts: [],
    specsAndAdvice: 'Snap a photo of the belt routing diagram before releasing tension! Use a Long-Reach Serpentine Belt Tensioner Tool (or 16mm wrench on VW tensioner lug) to rotate tensioner clockwise and slide belt off alternator pulley.'
  },
  {
    id: 'g-9-pcv',
    title: '9. PCV Valve / Crankcase Breather Oil Separator Service',
    vehicleId: 'v-jetta-2017',
    category: 'Maintenance',
    intervalMiles: 60000,
    intervalMonths: 60,
    difficulty: 'Moderate',
    estimatedTime: '45 mins',
    estimatedDiyCost: 68,
    estimatedShopCost: 290,
    requiredTools: [
      'Torx Bit Socket Set (T15 - T55)',
      'Spring Hose Clamp Pliers & Pick Set',
      '3/8" Drive Ratchet & Extensions',
      'Torque Wrench (3/8" Drive, 10-80 lb-ft)'
    ],
    requiredParts: [],
    specsAndAdvice: 'High-mileage turbo engines suffer rough idle, whistling, or rear main seal leaks when the PCV diaphragm tears. On VW 1.8T, remove upper timing cover and Torx T30 fasteners in a crisscross pattern; torque new separator to 9 lb-ft.'
  },
  {
    id: 'g-10-suspension',
    title: '10. Suspension Strut / Sway Bar End Links Inspection & Swap',
    vehicleId: 'ALL',
    category: 'Repair',
    intervalMiles: 75000,
    intervalMonths: 72,
    difficulty: 'Moderate',
    estimatedTime: '60 mins',
    estimatedDiyCost: 65,
    estimatedShopCost: 310,
    requiredTools: [
      'Hydraulic Floor Jack & 3-Ton Jack Stands',
      'Triple-Square (XZN) Bit Set (M6 - M16)',
      'Metric Combination Wrench Set (8mm - 19mm)',
      'Torque Wrench (1/2" Drive, 30-250 lb-ft)',
      '1/2" Drive 24" Breaker Bar'
    ],
    requiredParts: [],
    specsAndAdvice: 'Front-end clunking over small bumps past 100k miles is almost always worn sway bar end links. Hold the center ball stud with a Triple-Square (M6/M8 on VW) or Hex key while turning the 18mm nut with a box wrench.'
  },
  {
    id: 'g-11-tire-rotation',
    title: '11. Tire Rotation & Precision Lug Torque Check',
    vehicleId: 'ALL',
    category: 'Tires/Brakes',
    intervalMiles: 5000,
    intervalMonths: 6,
    difficulty: 'Easy',
    estimatedTime: '30 mins',
    estimatedDiyCost: 0,
    estimatedShopCost: 40,
    requiredTools: [
      'Hydraulic Floor Jack & 3-Ton Jack Stands',
      '17mm & 21mm Thin-Wall Deep Impact Sockets',
      'Torque Wrench (1/2" Drive, 30-250 lb-ft)',
      'M14x1.5 Wheel Hanger Alignment Pin',
      '1/2" Drive 24" Breaker Bar'
    ],
    requiredParts: [],
    specsAndAdvice: 'Rotate every 5,000 miles with oil change. Thread the M14x1.5 Wheel Hanger Pin into a VW hub hole so the wheel slides on effortlessly. Torque in a star pattern: 89 lb-ft (17mm socket) for VW Jetta; 80 lb-ft (21mm socket) for Toyota Highlander.'
  },
  {
    id: 'g-12-taillight',
    title: '12. Tail Light / Exterior Bulb Replacement (2825 Wedge)',
    vehicleId: 'v-jetta-2017',
    category: 'Repair',
    intervalMiles: 50000,
    intervalMonths: 48,
    difficulty: 'Easy',
    estimatedTime: '15 mins',
    estimatedDiyCost: 4,
    estimatedShopCost: 65,
    requiredTools: [
      'Nylon Trim & Panel Removal Tool Set',
      'Phillips & Flathead Screwdriver Set',
      'Nitrile Gloves & Safety Glasses'
    ],
    requiredParts: [
      { name: '2825 Miniature Wedge Bulb (Tail Light)', qty: 1 }
    ],
    specsAndAdvice: 'Bulb Spec: 2825 (W5W) Miniature Wedge Bulb. Pop trunk carpet access trim panel using a nylon trim tool, unclip bulb tray, and push in new 2825 bulb wearing clean nitrile gloves so skin oils do not shorten bulb life.'
  },
  {
    id: 'g-13-air-filters',
    title: '13. Engine & Cabin Air Filter Swap',
    vehicleId: 'ALL',
    category: 'Maintenance',
    intervalMiles: 15000,
    intervalMonths: 12,
    difficulty: 'Easy',
    estimatedTime: '15 mins',
    estimatedDiyCost: 34,
    estimatedShopCost: 110,
    requiredTools: [
      'Phillips & Flathead Screwdriver Set',
      'Torx Bit Socket Set (T15 - T55)',
      'Nylon Trim & Panel Removal Tool Set'
    ],
    requiredParts: [],
    specsAndAdvice: 'Cabin filter sits behind lower passenger glovebox panel; check AIR FLOW arrow direction before sliding new activated-carbon filter in. Engine air box uses Torx T25 screws (VW) or 2 metal flip clips (Toyota).'
  },
  {
    id: 'g-14-battery',
    title: '14. 12V Battery Load Test & Replacement',
    vehicleId: 'ALL',
    category: 'Repair',
    intervalMiles: 45000,
    intervalMonths: 48,
    difficulty: 'Easy',
    estimatedTime: '25 mins',
    estimatedDiyCost: 165,
    estimatedShopCost: 280,
    requiredTools: [
      '3/8" Drive Ratchet & Extensions',
      'Metric Socket Set (8mm - 19mm)',
      'Digital Multimeter & 12V Battery Tester',
      'Nitrile Gloves & Safety Glasses'
    ],
    requiredParts: [],
    specsAndAdvice: 'Always disconnect the Negative (-) black terminal first (10mm nut) and reconnect it last. Resting healthy voltage: 12.6V+; running alternator voltage: 13.8V–14.4V. Hold-down bracket bolt at base of tray uses a 13mm socket + 10" extension.'
  }
];

const INITIAL_LOGS = [
  {
    id: 'log-1',
    vehicleId: 'v-jetta-2017',
    guideId: 'g-1-oil-vw',
    date: '2026-09-18',
    odometer: 166500,
    serviceType: '1. Engine Oil & Filter Change (VW 1.8L TSI)',
    category: 'Fluids',
    performedBy: 'DIY',
    cost: 41.50,
    estimatedShopSavings: 73.50,
    partsUsed: '5.7 qt MAG 1 SAE 5W-30 Full Synthetic Euro + Mann HU 7020 z Filter',
    notes: 'Drained cleanly, replaced crush washer, torqued drain plug to 22 lb-ft. Next oil service due at 171,500 mi.',
    receiptPhoto: null
  },
  {
    id: 'log-2',
    vehicleId: 'v-jetta-2017',
    guideId: 'g-2-plugs-vw',
    date: '2026-08-05',
    odometer: 164800,
    serviceType: '2. Spark Plug Replacement (VW 1.8T — 5/8" Socket)',
    category: 'Maintenance',
    performedBy: 'DIY',
    cost: 54.99,
    estimatedShopSavings: 205.00,
    partsUsed: '4x NGK Laser Platinum Spark Plugs (94833)',
    notes: 'Used 5/8" magnetic spark plug socket and 3/8" torque wrench set to 22 lb-ft. Smooth idle restored.',
    receiptPhoto: null
  },
  {
    id: 'log-3',
    vehicleId: 'v-jetta-2017',
    guideId: 'g-12-taillight',
    date: '2026-07-12',
    odometer: 163900,
    serviceType: '12. Tail Light / Exterior Bulb Replacement (2825 Wedge)',
    category: 'Repair',
    performedBy: 'DIY',
    cost: 6.49,
    estimatedShopSavings: 58.50,
    partsUsed: 'Sylvania 2825 Long Life Wedge Bulb (kept 1 spare on shelf)',
    notes: 'Replaced burnt tail light 2825 bulb; dash warning light cleared immediately.',
    receiptPhoto: null
  },
  {
    id: 'log-4',
    vehicleId: 'v-jetta-2017',
    guideId: 'g-6-coolant',
    date: '2026-06-20',
    odometer: 162400,
    serviceType: '6. Coolant Flush / Drain & Top-Off (Euro Violet / Toyota Pink)',
    category: 'Fluids',
    performedBy: 'DIY',
    cost: 18.99,
    estimatedShopSavings: 45.00,
    partsUsed: 'Peak OET European Violet G12++/G13 50/50 Prediluted',
    notes: 'Topped expansion reservoir up to MAX cold line. Stored remaining jug on Garage Shelf.',
    receiptPhoto: null
  },
  {
    id: 'log-5',
    vehicleId: 'v-highlander-2021',
    guideId: 'g-1b-oil-toyota',
    date: '2026-05-14',
    odometer: 49800,
    serviceType: '1B. Engine Oil & Cartridge Filter Change (Highlander 3.5L V6)',
    category: 'Fluids',
    performedBy: 'Shop',
    cost: 118.00,
    estimatedShopSavings: 0,
    partsUsed: 'Toyota 0W-20 Synthetic + OEM 04152-YZZA1 Filter Element',
    notes: 'Done at shop at 49,800 mi (Due soon at 54,800 mi!). Need 64mm 14-flute filter socket for next DIY change.',
    receiptPhoto: null
  }
];

const TOOL_CATEGORIES = [
  'Sockets & Bits',
  'Wrenches & Ratchets',
  'Specialty & Diagnostics',
  'Lifting & Garage',
  'Pliers & Drivers'
];

const SERVICE_CATEGORIES = [
  'Maintenance',
  'Fluids',
  'Tires/Brakes',
  'Repair',
  'Upgrade/Other'
];

const SHELF_CATEGORIES = [
  'Fluids',
  'Filters',
  'Ignition',
  'Bulbs & Electrical',
  'Brakes & Suspension',
  'Shop Supplies'
];

// ==========================================
// MAIN APPLICATION COMPONENT
// ==========================================

export default function App() {
  // --- Load Saved Local Cache on Startup (Offline-First) ---
  const savedLocalState = useMemo(() => {
    try {
      const raw = localStorage.getItem(LOCAL_STORAGE_STATE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  }, []);

  const savedSupabaseCfg = useMemo(() => {
    try {
      const raw = localStorage.getItem(LOCAL_STORAGE_CONFIG_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  }, []);

  // --- Persistent State Setup ---
  const [vehicles, setVehicles] = useState(savedLocalState?.vehicles || INITIAL_VEHICLES);
  const [selectedVehicleId, setSelectedVehicleId] = useState(
    savedLocalState?.selectedVehicleId || INITIAL_VEHICLES[0].id
  );
  const [tools, setTools] = useState(savedLocalState?.tools || INITIAL_TOOLS);
  const [shelf, setShelf] = useState(savedLocalState?.shelf || INITIAL_SHELF);
  const [guides, setGuides] = useState(savedLocalState?.guides || INITIAL_GUIDES);
  const [logs, setLogs] = useState(savedLocalState?.logs || INITIAL_LOGS);

  // --- Supabase Cloud Real-Time Sync State ---
  const [supabaseUrl, setSupabaseUrl] = useState(
    savedSupabaseCfg?.supabaseUrl || DEFAULT_SUPABASE_URL
  );
  const [supabaseAnonKey, setSupabaseAnonKey] = useState(
    savedSupabaseCfg?.supabaseAnonKey || DEFAULT_SUPABASE_ANON_KEY
  );
  const [syncRoomCode, setSyncRoomCode] = useState(
    savedSupabaseCfg?.syncRoomCode || DEFAULT_GARAGE_SYNC_CODE
  );
  const [clientId] = useState(
    () => savedSupabaseCfg?.clientId || `dev-${Math.random().toString(36).slice(2, 10)}`
  );

  const isSupabaseConfigured = Boolean(supabaseUrl.trim() && supabaseAnonKey.trim());
  const [cloudStatus, setCloudStatus] = useState(
    isSupabaseConfigured ? 'connecting' : 'local-only'
  ); // 'connecting' | 'synced' | 'syncing' | 'error' | 'local-only'
  const [cloudErrorMsg, setCloudErrorMsg] = useState('');
  const [lastSyncedAt, setLastSyncedAt] = useState(null);
  const [isPhoneModalOpen, setIsPhoneModalOpen] = useState(false);

  // Refs to prevent echo loops during real-time multi-device sync
  const isApplyingRemoteUpdate = React.useRef(false);
  const hasLoadedInitialCloud = React.useRef(false);
  const lastSyncedPayloadHash = React.useRef('');

  // Always save state to browser localStorage immediately (Offline-First safety net)
  useEffect(() => {
    try {
      localStorage.setItem(
        LOCAL_STORAGE_STATE_KEY,
        JSON.stringify({
          vehicles,
          selectedVehicleId,
          tools,
          shelf,
          guides,
          logs,
          savedAt: new Date().toISOString()
        })
      );
    } catch (e) {
      console.warn('Local storage save warning:', e);
    }
  }, [vehicles, selectedVehicleId, tools, shelf, guides, logs]);

  // Persist Supabase Config in localStorage
  useEffect(() => {
    try {
      localStorage.setItem(
        LOCAL_STORAGE_CONFIG_KEY,
        JSON.stringify({
          supabaseUrl,
          supabaseAnonKey,
          syncRoomCode,
          clientId
        })
      );
    } catch (e) {
      console.warn('Could not save Supabase config:', e);
    }
  }, [supabaseUrl, supabaseAnonKey, syncRoomCode, clientId]);

  // Helper to apply incoming remote payload safely
  const applyRemotePayload = React.useCallback((payload, timestampLabel) => {
    if (!payload || typeof payload !== 'object') return;
    const incomingHash = JSON.stringify(payload);
    if (incomingHash === lastSyncedPayloadHash.current) return;

    lastSyncedPayloadHash.current = incomingHash;
    isApplyingRemoteUpdate.current = true;

    if (Array.isArray(payload.vehicles) && payload.vehicles.length > 0) {
      setVehicles(payload.vehicles);
    }
    if (payload.selectedVehicleId) {
      setSelectedVehicleId(payload.selectedVehicleId);
    }
    if (Array.isArray(payload.tools)) setTools(payload.tools);
    if (Array.isArray(payload.shelf)) setShelf(payload.shelf);
    if (Array.isArray(payload.guides)) setGuides(payload.guides);
    if (Array.isArray(payload.logs)) setLogs(payload.logs);

    setCloudStatus('synced');
    setCloudErrorMsg('');
    setLastSyncedAt(
      timestampLabel
        ? new Date(timestampLabel).toLocaleTimeString()
        : new Date().toLocaleTimeString()
    );

    setTimeout(() => {
      isApplyingRemoteUpdate.current = false;
    }, 150);
  }, []);

  // Manual Pull from Supabase
  const handleManualPullFromSupabase = React.useCallback(
    async (silent = false) => {
      if (!supabaseUrl.trim() || !supabaseAnonKey.trim()) {
        setCloudStatus('local-only');
        return false;
      }
      const cleanRoom = (syncRoomCode || 'DEFAULT-GARAGE').trim().toUpperCase();
      setCloudStatus('syncing');
      try {
        const row = await supabaseRestPull(supabaseUrl, supabaseAnonKey, cleanRoom);
        if (row && row.payload) {
          applyRemotePayload(row.payload, row.updated_at);
          hasLoadedInitialCloud.current = true;
          if (!silent) {
            showToast(`Pulled latest garage state from Supabase (${cleanRoom})!`);
          }
          return true;
        } else {
          // Row doesn't exist yet -> create initial row on Supabase
          const currentPayload = {
            vehicles,
            selectedVehicleId,
            tools,
            shelf,
            guides,
            logs
          };
          lastSyncedPayloadHash.current = JSON.stringify(currentPayload);
          await supabaseRestPush(
            supabaseUrl,
            supabaseAnonKey,
            cleanRoom,
            currentPayload,
            clientId
          );
          hasLoadedInitialCloud.current = true;
          setCloudStatus('synced');
          setCloudErrorMsg('');
          setLastSyncedAt(new Date().toLocaleTimeString());
          if (!silent) {
            showToast(`Initialized new Supabase room "${cleanRoom}"!`);
          }
          return true;
        }
      } catch (err) {
        console.error('Supabase Pull Error:', err);
        setCloudStatus('error');
        setCloudErrorMsg(err.message || 'Failed to connect to Supabase');
        if (!silent) {
          showToast(
            'Supabase Error: Make sure you ran the SQL setup script in your Supabase project.',
            'error'
          );
        }
        return false;
      }
    },
    [
      supabaseUrl,
      supabaseAnonKey,
      syncRoomCode,
      vehicles,
      selectedVehicleId,
      tools,
      shelf,
      guides,
      logs,
      clientId,
      applyRemotePayload
    ]
  );

  // Manual Push to Supabase
  const handleManualPushToSupabase = React.useCallback(
    async (silent = false) => {
      if (!supabaseUrl.trim() || !supabaseAnonKey.trim()) {
        setCloudStatus('local-only');
        return false;
      }
      const cleanRoom = (syncRoomCode || 'DEFAULT-GARAGE').trim().toUpperCase();
      const currentPayload = {
        vehicles,
        selectedVehicleId,
        tools,
        shelf,
        guides,
        logs
      };
      setCloudStatus('syncing');
      try {
        lastSyncedPayloadHash.current = JSON.stringify(currentPayload);
        await supabaseRestPush(
          supabaseUrl,
          supabaseAnonKey,
          cleanRoom,
          currentPayload,
          clientId
        );
        hasLoadedInitialCloud.current = true;
        setCloudStatus('synced');
        setCloudErrorMsg('');
        setLastSyncedAt(new Date().toLocaleTimeString());
        if (!silent) {
          showToast(`Pushed garage data to Supabase (${cleanRoom})!`);
        }
        return true;
      } catch (err) {
        console.error('Supabase Push Error:', err);
        setCloudStatus('error');
        setCloudErrorMsg(err.message || 'Failed to push to Supabase');
        if (!silent) {
          showToast('Supabase Push failed — check your URL, Anon Key & SQL table.', 'error');
        }
        return false;
      }
    },
    [
      supabaseUrl,
      supabaseAnonKey,
      syncRoomCode,
      vehicles,
      selectedVehicleId,
      tools,
      shelf,
      guides,
      logs,
      clientId
    ]
  );

  // 1. Connect to Supabase & Subscribe to Realtime Postgres Changes + Background Poll Fallback
  useEffect(() => {
    if (!supabaseUrl.trim() || !supabaseAnonKey.trim()) {
      setCloudStatus('local-only');
      setCloudErrorMsg('');
      hasLoadedInitialCloud.current = false;
      return;
    }

    let isMounted = true;
    let realtimeChannel = null;
    let supabaseClientInstance = null;
    const cleanRoom = (syncRoomCode || 'DEFAULT-GARAGE').trim().toUpperCase();

    // Perform initial pull or seed room
    handleManualPullFromSupabase(true);

    // Setup Supabase Realtime WebSocket subscription
    getOrCreateSupabaseClient(supabaseUrl, supabaseAnonKey).then((client) => {
      if (!isMounted || !client) return;
      supabaseClientInstance = client;
      realtimeChannel = client
        .channel(`garage-room-${cleanRoom}`)
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'garage_state',
            filter: `sync_code=eq.${cleanRoom}`
          },
          (changeEvent) => {
            const newRow = changeEvent.new;
            if (newRow && newRow.payload && newRow.client_id !== clientId) {
              applyRemotePayload(newRow.payload, newRow.updated_at);
            }
          }
        )
        .subscribe();
    });

    // Lightweight 12-second background check in case mobile browser suspends WebSockets
    const pollInterval = setInterval(async () => {
      if (!isMounted || isApplyingRemoteUpdate.current) return;
      try {
        const row = await supabaseRestPull(supabaseUrl, supabaseAnonKey, cleanRoom);
        if (row && row.payload && row.client_id !== clientId) {
          applyRemotePayload(row.payload, row.updated_at);
        }
      } catch (e) {
        // Ignore transient offline errors during background poll
      }
    }, 12000);

    return () => {
      isMounted = false;
      clearInterval(pollInterval);
      if (supabaseClientInstance && realtimeChannel) {
        supabaseClientInstance.removeChannel(realtimeChannel);
      }
    };
  }, [supabaseUrl, supabaseAnonKey, syncRoomCode, clientId]);

  // 2. Automatically Push Local State Edits to Supabase
  useEffect(() => {
    if (
      !supabaseUrl.trim() ||
      !supabaseAnonKey.trim() ||
      !hasLoadedInitialCloud.current ||
      isApplyingRemoteUpdate.current
    ) {
      return;
    }

    const currentPayload = {
      vehicles,
      selectedVehicleId,
      tools,
      shelf,
      guides,
      logs
    };
    const payloadHash = JSON.stringify(currentPayload);
    if (payloadHash === lastSyncedPayloadHash.current) {
      return;
    }

    const cleanRoom = (syncRoomCode || 'DEFAULT-GARAGE').trim().toUpperCase();
    setCloudStatus('syncing');

    const debounceTimer = setTimeout(async () => {
      try {
        lastSyncedPayloadHash.current = payloadHash;
        await supabaseRestPush(
          supabaseUrl,
          supabaseAnonKey,
          cleanRoom,
          currentPayload,
          clientId
        );
        setCloudStatus('synced');
        setCloudErrorMsg('');
        setLastSyncedAt(new Date().toLocaleTimeString());
      } catch (err) {
        console.error('Auto-push to Supabase failed:', err);
        setCloudStatus('error');
        setCloudErrorMsg(err.message || 'Auto-sync error');
      }
    }, 400);

    return () => clearTimeout(debounceTimer);
  }, [
    vehicles,
    selectedVehicleId,
    tools,
    shelf,
    guides,
    logs,
    supabaseUrl,
    supabaseAnonKey,
    syncRoomCode,
    clientId
  ]);

  // --- Navigation & UI State ---
  const [activeTab, setActiveTab] = useState('dashboard'); // 'dashboard' | 'guides' | 'shelf' | 'tools' | 'garage'
  const [toast, setToast] = useState(null);

  // Filters & Sorting
  const [logSearch, setLogSearch] = useState('');
  const [logCategoryFilter, setLogCategoryFilter] = useState('ALL');

  const [guideFilter, setGuideFilter] = useState('VEHICLE'); // 'VEHICLE' | 'ALL' | 'READY' | 'MISSING' | 'OVERDUE'
  const [guideSort, setGuideSort] = useState('URGENCY'); // 'URGENCY' | 'READINESS' | 'CATEGORY'
  const [guideSearch, setGuideSearch] = useState('');

  const [shelfSearch, setShelfSearch] = useState('');
  const [shelfFilter, setShelfFilter] = useState('ALL'); // 'ALL' | 'VEHICLE' | 'LOW_STOCK'

  const [toolSearch, setToolSearch] = useState('');
  const [toolOwnershipFilter, setToolOwnershipFilter] = useState('ALL'); // 'ALL' | 'OWNED' | 'MISSING' | 'LOANER'
  const [toolCategoryFilter, setToolCategoryFilter] = useState('ALL');

  // Modals
  const [isVehicleModalOpen, setIsVehicleModalOpen] = useState(false);
  const [editingVehicle, setEditingVehicle] = useState(null);

  const [isOdometerModalOpen, setIsOdometerModalOpen] = useState(false);
  const [tempOdometer, setTempOdometer] = useState('');

  const [isLogModalOpen, setIsLogModalOpen] = useState(false);
  const [editingLog, setEditingLog] = useState(null);

  const [isGuideModalOpen, setIsGuideModalOpen] = useState(false);
  const [isToolModalOpen, setIsToolModalOpen] = useState(false);
  const [isShelfModalOpen, setIsShelfModalOpen] = useState(false);
  const [editingShelfItem, setEditingShelfItem] = useState(null);

  const [isBackupModalOpen, setIsBackupModalOpen] = useState(false);
  const [confirmResetOpen, setConfirmResetOpen] = useState(false);
  const [previewPhoto, setPreviewPhoto] = useState(null);

  // Toast helper
  const showToast = (message, type = 'success') => {
    setToast({ message, type });
    setTimeout(() => {
      setToast((prev) => (prev?.message === message ? null : prev));
    }, 3600);
  };

  // --- Derived Active Vehicle ---
  const activeVehicle = useMemo(() => {
    return vehicles.find((v) => v.id === selectedVehicleId) || vehicles[0] || null;
  }, [vehicles, selectedVehicleId]);

  // --- 1. Tool Readiness & Loaner Calculator ---
  const evaluateToolReadiness = useMemo(() => {
    const toolMap = new Map();
    tools.forEach((t) => {
      toolMap.set(t.name.toLowerCase().trim(), t);
    });

    return (requiredToolNames = []) => {
      const details = requiredToolNames.map((reqName) => {
        const match = toolMap.get(reqName.toLowerCase().trim());
        return {
          name: reqName,
          toolId: match ? match.id : null,
          owned: match ? Boolean(match.owned) : false,
          loanerAvailable: match ? Boolean(match.loanerAvailable) : false,
          estBuyPrice: match ? Number(match.estBuyPrice || 20) : 20,
          category: match ? match.category : 'Specialty & Diagnostics'
        };
      });
      const missingTools = details.filter((d) => !d.owned);
      const missingCount = missingTools.length;
      const loanerCount = missingTools.filter((d) => d.loanerAvailable).length;
      const missingBuyCost = missingTools.reduce((sum, d) => sum + d.estBuyPrice, 0);
      const missingNonLoanerCost = missingTools
        .filter((d) => !d.loanerAvailable)
        .reduce((sum, d) => sum + d.estBuyPrice, 0);

      return {
        isReady: missingCount === 0,
        missingCount,
        loanerCount,
        missingBuyCost,
        missingNonLoanerCost,
        ownedCount: details.length - missingCount,
        totalCount: details.length,
        details
      };
    };
  }, [tools]);

  // --- 2. Shelf Consumables Readiness Helper ---
  const evaluatePartsReadiness = useMemo(() => {
    return (requiredParts = [], vehicleId) => {
      if (!requiredParts || requiredParts.length === 0) {
        return {
          hasRequirements: false,
          isReady: true,
          missingPartsCount: 0,
          details: []
        };
      }

      const details = requiredParts.map((req) => {
        const match = shelf.find(
          (s) =>
            s.name.toLowerCase().trim() === req.name.toLowerCase().trim() ||
            s.name.toLowerCase().includes(req.name.toLowerCase().slice(0, 14))
        );
        const availableQty = match ? Number(match.quantity) : 0;
        const neededQty = Number(req.qty) || 1;
        const enough = availableQty >= neededQty;

        return {
          name: req.name,
          shelfId: match ? match.id : null,
          neededQty,
          availableQty,
          unit: match ? match.unit : 'units',
          enough
        };
      });

      const missingPartsCount = details.filter((d) => !d.enough).length;
      return {
        hasRequirements: true,
        isReady: missingPartsCount === 0,
        missingPartsCount,
        details
      };
    };
  }, [shelf]);

  // --- 3. Dynamic "Next Due" Mileage Countdown & Urgency Helper ---
  const evaluateGuideDueStatus = (guide, vehicle) => {
    if (!vehicle) {
      return {
        status: 'unknown',
        urgencyScore: 4,
        label: 'No Vehicle Selected',
        progressPercent: 0
      };
    }

    const matchingLogs = logs
      .filter(
        (l) =>
          l.vehicleId === vehicle.id &&
          (l.guideId === guide.id ||
            l.serviceType.toLowerCase().includes(guide.title.toLowerCase().slice(3, 18).trim()))
      )
      .sort((a, b) => b.odometer - a.odometer);

    if (matchingLogs.length === 0) {
      return {
        status: 'never',
        urgencyScore: 2, // High attention
        label: 'No prior log — Check / Due Now',
        subLabel: `Recommended every ${Number(guide.intervalMiles).toLocaleString()} mi`,
        lastOdometer: null,
        nextDueMileage: vehicle.odometer,
        lastDate: null,
        milesRemaining: 0,
        progressPercent: 100
      };
    }

    const lastLog = matchingLogs[0];
    const interval = Number(guide.intervalMiles) || 10000;
    const nextDueMileage = Number(lastLog.odometer) + interval;
    const milesSince = Math.max(0, Number(vehicle.odometer) - Number(lastLog.odometer));
    const milesRemaining = nextDueMileage - Number(vehicle.odometer);
    const progressPercent = Math.min(100, Math.max(5, Math.round((milesSince / interval) * 100)));

    if (milesRemaining < 0) {
      return {
        status: 'overdue',
        urgencyScore: 1, // Highest urgency
        label: `OVERDUE by ${Math.abs(milesRemaining).toLocaleString()} mi`,
        subLabel: `Due at ${nextDueMileage.toLocaleString()} mi`,
        lastOdometer: lastLog.odometer,
        nextDueMileage,
        lastDate: lastLog.date,
        milesRemaining,
        progressPercent: 100
      };
    } else if (milesRemaining <= 1000) {
      return {
        status: 'due-soon',
        urgencyScore: 2, // Second urgency
        label: `DUE SOON: ${milesRemaining.toLocaleString()} mi left`,
        subLabel: `Due at ${nextDueMileage.toLocaleString()} mi`,
        lastOdometer: lastLog.odometer,
        nextDueMileage,
        lastDate: lastLog.date,
        milesRemaining,
        progressPercent
      };
    } else {
      return {
        status: 'good',
        urgencyScore: 3, // On track
        label: `${milesRemaining.toLocaleString()} mi remaining`,
        subLabel: `Next due at ${nextDueMileage.toLocaleString()} mi`,
        lastOdometer: lastLog.odometer,
        nextDueMileage,
        lastDate: lastLog.date,
        milesRemaining,
        progressPercent
      };
    }
  };

  // --- KPIs for Active Vehicle ---
  const vehicleStats = useMemo(() => {
    if (!activeVehicle) {
      return { totalSpend: 0, diySavings: 0, totalServices: 0, diyCount: 0, dueAlerts: [], lowStockCount: 0 };
    }
    const vLogs = logs.filter((l) => l.vehicleId === activeVehicle.id);
    const totalSpend = vLogs.reduce((acc, l) => acc + (Number(l.cost) || 0), 0);
    const diySavings = vLogs.reduce(
      (acc, l) => acc + (l.performedBy === 'DIY' ? Number(l.estimatedShopSavings) || 0 : 0),
      0
    );
    const diyCount = vLogs.filter((l) => l.performedBy === 'DIY').length;

    const applicableGuides = guides.filter(
      (g) => g.vehicleId === activeVehicle.id || g.vehicleId === 'ALL'
    );
    const evaluatedGuides = applicableGuides
      .map((g) => ({
        guide: g,
        dueInfo: evaluateGuideDueStatus(g, activeVehicle),
        readiness: evaluateToolReadiness(g.requiredTools),
        partsReadiness: evaluatePartsReadiness(g.requiredParts, activeVehicle.id)
      }))
      .sort((a, b) => a.dueInfo.urgencyScore - b.dueInfo.urgencyScore);

    const lowStockCount = shelf.filter(
      (s) =>
        (s.vehicleId === activeVehicle.id || s.vehicleId === 'ALL') &&
        Number(s.quantity) < Number(s.minQuantity)
    ).length;

    return {
      totalSpend,
      diySavings,
      totalServices: vLogs.length,
      diyCount,
      evaluatedGuides,
      lowStockCount
    };
  }, [activeVehicle, logs, guides, shelf, evaluateToolReadiness, evaluatePartsReadiness]);

  // --- Filtered Logs ---
  const filteredLogs = useMemo(() => {
    return logs
      .filter((l) => (activeVehicle ? l.vehicleId === activeVehicle.id : true))
      .filter((l) => (logCategoryFilter === 'ALL' ? true : l.category === logCategoryFilter))
      .filter((l) => {
        if (!logSearch.trim()) return true;
        const q = logSearch.toLowerCase();
        return (
          l.serviceType.toLowerCase().includes(q) ||
          (l.partsUsed && l.partsUsed.toLowerCase().includes(q)) ||
          (l.notes && l.notes.toLowerCase().includes(q))
        );
      })
      .sort((a, b) => new Date(b.date) - new Date(a.date) || b.odometer - a.odometer);
  }, [logs, activeVehicle, logCategoryFilter, logSearch]);

  // --- Filtered & Sorted Guides ---
  const filteredGuides = useMemo(() => {
    const list = guides
      .filter((g) => {
        const isVehicleMatch = !activeVehicle || g.vehicleId === activeVehicle.id || g.vehicleId === 'ALL';
        if (guideFilter === 'VEHICLE') return isVehicleMatch;
        if (guideFilter === 'READY') return isVehicleMatch && evaluateToolReadiness(g.requiredTools).isReady;
        if (guideFilter === 'MISSING') return isVehicleMatch && !evaluateToolReadiness(g.requiredTools).isReady;
        if (guideFilter === 'OVERDUE') {
          const d = evaluateGuideDueStatus(g, activeVehicle);
          return isVehicleMatch && (d.status === 'overdue' || d.status === 'due-soon' || d.status === 'never');
        }
        return true;
      })
      .filter((g) => {
        if (!guideSearch.trim()) return true;
        const q = guideSearch.toLowerCase();
        return (
          g.title.toLowerCase().includes(q) ||
          g.specsAndAdvice.toLowerCase().includes(q) ||
          g.requiredTools.some((t) => t.toLowerCase().includes(q))
        );
      });

    return [...list].sort((a, b) => {
      if (guideSort === 'URGENCY') {
        const dueA = evaluateGuideDueStatus(a, activeVehicle);
        const dueB = evaluateGuideDueStatus(b, activeVehicle);
        if (dueA.urgencyScore !== dueB.urgencyScore) {
          return dueA.urgencyScore - dueB.urgencyScore;
        }
        return (dueA.milesRemaining ?? 99999) - (dueB.milesRemaining ?? 99999);
      }
      if (guideSort === 'READINESS') {
        const rA = evaluateToolReadiness(a.requiredTools);
        const rB = evaluateToolReadiness(b.requiredTools);
        return rA.missingCount - rB.missingCount;
      }
      return a.category.localeCompare(b.category);
    });
  }, [guides, guideFilter, guideSort, guideSearch, activeVehicle, evaluateToolReadiness, logs]);

  // --- Filtered Shelf Items ---
  const filteredShelf = useMemo(() => {
    return shelf
      .filter((item) => {
        if (shelfFilter === 'VEHICLE' && activeVehicle) {
          return item.vehicleId === activeVehicle.id || item.vehicleId === 'ALL';
        }
        if (shelfFilter === 'LOW_STOCK') {
          return Number(item.quantity) < Number(item.minQuantity);
        }
        return true;
      })
      .filter((item) => {
        if (!shelfSearch.trim()) return true;
        const q = shelfSearch.toLowerCase();
        return (
          item.name.toLowerCase().includes(q) ||
          (item.partNumber && item.partNumber.toLowerCase().includes(q)) ||
          item.category.toLowerCase().includes(q) ||
          (item.notes && item.notes.toLowerCase().includes(q))
        );
      });
  }, [shelf, shelfFilter, shelfSearch, activeVehicle]);

  // --- Filtered Tools ---
  const filteredTools = useMemo(() => {
    return tools
      .filter((t) => (toolCategoryFilter === 'ALL' ? true : t.category === toolCategoryFilter))
      .filter((t) => {
        if (toolOwnershipFilter === 'OWNED') return t.owned;
        if (toolOwnershipFilter === 'MISSING') return !t.owned;
        if (toolOwnershipFilter === 'LOANER') return t.loanerAvailable;
        return true;
      })
      .filter((t) => {
        if (!toolSearch.trim()) return true;
        const q = toolSearch.toLowerCase();
        return (
          t.name.toLowerCase().includes(q) ||
          t.category.toLowerCase().includes(q) ||
          (t.notes && t.notes.toLowerCase().includes(q))
        );
      });
  }, [tools, toolCategoryFilter, toolOwnershipFilter, toolSearch]);

  // ==========================================
  // ACTION HANDLERS
  // ==========================================

  // Toggle or add a tool as owned right from a Service Guide or Tool Chest
  const handleToggleToolByName = (toolName) => {
    const existing = tools.find((t) => t.name.toLowerCase().trim() === toolName.toLowerCase().trim());
    if (existing) {
      const nextOwned = !existing.owned;
      setTools((prev) =>
        prev.map((t) => (t.id === existing.id ? { ...t, owned: nextOwned } : t))
      );
      showToast(
        nextOwned
          ? `Marked "${existing.name}" as Owned in your Tool Chest!`
          : `Marked "${existing.name}" as Missing.`
      );
    } else {
      const newTool = {
        id: `t-custom-${Date.now()}`,
        name: toolName,
        category: 'Specialty & Diagnostics',
        owned: true,
        loanerAvailable: false,
        estBuyPrice: 20,
        notes: 'Added directly from Service Guide requirement'
      };
      setTools((prev) => [newTool, ...prev]);
      showToast(`Added "${toolName}" to your Tool Chest!`);
    }
  };

  // Update Shelf Item Quantity (+ / -)
  const handleAdjustShelfQty = (id, delta) => {
    setShelf((prev) =>
      prev.map((item) => {
        if (item.id !== id) return item;
        const nextQty = Math.max(0, Number(item.quantity) + delta);
        return { ...item, quantity: nextQty };
      })
    );
  };

  // Open Add/Edit Vehicle Modal
  const openAddVehicleModal = () => {
    setEditingVehicle(null);
    setIsVehicleModalOpen(true);
  };

  const openEditVehicleModal = (vehicle) => {
    setEditingVehicle(vehicle);
    setIsVehicleModalOpen(true);
  };

  const handleDeleteVehicle = (vehicleId) => {
    if (vehicles.length <= 1) {
      showToast('Keep at least one vehicle in your garage.', 'error');
      return;
    }
    const target = vehicles.find((v) => v.id === vehicleId);
    const remaining = vehicles.filter((v) => v.id !== vehicleId);
    setVehicles(remaining);
    if (selectedVehicleId === vehicleId) {
      setSelectedVehicleId(remaining[0].id);
    }
    showToast(`Removed ${target?.year} ${target?.make} ${target?.model} from Garage.`);
  };

  // Quick Odometer Update
  const handleQuickOdometerSave = (e) => {
    e.preventDefault();
    const parsed = parseInt(tempOdometer, 10);
    if (isNaN(parsed) || parsed < 0) {
      showToast('Please enter a valid odometer reading.', 'error');
      return;
    }
    setVehicles((prev) =>
      prev.map((v) => (v.id === activeVehicle.id ? { ...v, odometer: parsed } : v))
    );
    setIsOdometerModalOpen(false);
    showToast(`Updated ${activeVehicle.model} odometer to ${parsed.toLocaleString()} miles.`);
  };

  // One-Click "Complete & Log This Job" from a Service Guide
  const handleLogFromGuide = (guide) => {
    const partsString =
      guide.requiredParts && guide.requiredParts.length > 0
        ? guide.requiredParts.map((p) => `${p.qty}x ${p.name}`).join(', ')
        : '';

    setEditingLog({
      isPrefill: true,
      vehicleId: activeVehicle ? activeVehicle.id : vehicles[0]?.id,
      guideId: guide.id,
      requiredPartsToDeduct: guide.requiredParts || [],
      date: new Date().toISOString().split('T')[0],
      odometer: activeVehicle ? activeVehicle.odometer : 0,
      serviceType: guide.title,
      category: guide.category || 'Maintenance',
      performedBy: 'DIY',
      cost: guide.estimatedDiyCost || '',
      estimatedShopSavings: Math.max(0, (guide.estimatedShopCost || 0) - (guide.estimatedDiyCost || 0)),
      partsUsed: partsString,
      notes: `Completed DIY Service Guide. ${guide.specsAndAdvice.slice(0, 110)}...`,
      receiptPhoto: null
    });
    setIsLogModalOpen(true);
  };

  // Export Service History to CSV
  const handleExportCSV = () => {
    const headers = [
      'Date',
      'Vehicle',
      'Odometer',
      'Service Type',
      'Category',
      'Performed By',
      'Cost ($)',
      'Est DIY Savings ($)',
      'Parts / Fluids Used',
      'Notes'
    ];
    const rows = logs.map((l) => {
      const v = vehicles.find((veh) => veh.id === l.vehicleId);
      const vName = v ? `${v.year} ${v.make} ${v.model}` : 'Unknown Vehicle';
      return [
        l.date,
        `"${vName.replace(/"/g, '""')}"`,
        l.odometer,
        `"${(l.serviceType || '').replace(/"/g, '""')}"`,
        l.category,
        l.performedBy,
        Number(l.cost || 0).toFixed(2),
        Number(l.estimatedShopSavings || 0).toFixed(2),
        `"${(l.partsUsed || '').replace(/"/g, '""')}"`,
        `"${(l.notes || '').replace(/"/g, '""')}"`
      ].join(',');
    });
    const csvContent = 'data:text/csv;charset=utf-8,' + [headers.join(','), ...rows].join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement('a');
    link.setAttribute('href', encodedUri);
    link.setAttribute('download', `GarageCommandPro_Ledger_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    showToast('Exported service & expense ledger to CSV!');
  };

  // Export Full System JSON Backup
  const handleExportFullJSON = () => {
    const payload = {
      app: 'GarageCommand Pro',
      version: 2,
      exportedAt: new Date().toISOString(),
      vehicles,
      selectedVehicleId,
      tools,
      shelf,
      guides,
      logs
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `GarageCommandPro_FullBackup_${new Date().toISOString().slice(0, 10)}.json`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    showToast('Downloaded full JSON system backup!');
  };

  // Import Full System JSON Backup
  const handleImportFullJSON = (file) => {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const parsed = JSON.parse(e.target.result);
        if (!parsed.vehicles || !parsed.tools || !parsed.logs) {
          showToast('Invalid backup file format.', 'error');
          return;
        }
        setVehicles(parsed.vehicles);
        setSelectedVehicleId(parsed.selectedVehicleId || parsed.vehicles[0]?.id);
        setTools(parsed.tools);
        if (parsed.shelf) setShelf(parsed.shelf);
        if (parsed.guides) setGuides(parsed.guides);
        setLogs(parsed.logs);
        setIsBackupModalOpen(false);
        showToast('Restored full GarageCommand Pro backup successfully!');
      } catch (err) {
        console.error(err);
        showToast('Could not parse JSON backup file.', 'error');
      }
    };
    reader.readAsText(file);
  };

  // Reset Demo Data
  const handleResetDemoData = () => {
    setVehicles(INITIAL_VEHICLES);
    setSelectedVehicleId(INITIAL_VEHICLES[0].id);
    setTools(INITIAL_TOOLS);
    setShelf(INITIAL_SHELF);
    setGuides(INITIAL_GUIDES);
    setLogs(INITIAL_LOGS);
    setConfirmResetOpen(false);
    showToast('Restored default demo vehicles, shelf inventory, tools, and 14+ guides.');
  };

  const ownedToolsCount = tools.filter((t) => t.owned).length;
  const totalShelfItems = shelf.reduce((acc, s) => acc + (Number(s.quantity) > 0 ? 1 : 0), 0);

  return (
    <div className="min-h-screen pb-20 md:pb-8 bg-slate-950 text-slate-100 flex flex-col font-sans selection:bg-emerald-500/30 selection:text-emerald-200">
      {/* Toast Notification */}
      {toast && (
        <div className="fixed bottom-20 md:bottom-5 right-4 left-4 sm:left-auto z-50 flex items-center justify-between sm:justify-start gap-3 px-4 py-3 rounded-xl shadow-2xl border backdrop-blur-md transition-all duration-300 bg-slate-900/95 border-emerald-500/40 text-slate-100">
          <div className="flex items-center gap-2.5">
            {toast.type === 'error' ? (
              <AlertTriangle className="w-5 h-5 text-amber-400 shrink-0" />
            ) : (
              <CheckCircle2 className="w-5 h-5 text-emerald-400 shrink-0" />
            )}
            <span className="text-sm font-medium">{toast.message}</span>
          </div>
          <button
            onClick={() => setToast(null)}
            className="text-slate-400 hover:text-slate-200 p-1"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      {/* Photo Lightbox Modal */}
      {previewPhoto && (
        <div
          onClick={() => setPreviewPhoto(null)}
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/90 backdrop-blur-md p-4"
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="bg-slate-900 border border-slate-800 rounded-2xl max-w-2xl w-full p-4 space-y-3 shadow-2xl"
          >
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-bold text-white">{previewPhoto.label || 'Photo Reference'}</h4>
              <button
                onClick={() => setPreviewPhoto(null)}
                className="p-1 text-slate-400 hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            <img
              src={previewPhoto.dataUrl}
              alt={previewPhoto.label || 'Attachment'}
              className="w-full max-h-[70vh] object-contain rounded-xl bg-slate-950"
            />
          </div>
        </div>
      )}

      {/* ==========================================
          TOP COMMAND HEADER
      ========================================== */}
      <header className="sticky top-0 z-30 bg-slate-900/90 backdrop-blur-md border-b border-slate-800">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
          <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
            {/* Brand Logo */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-500 to-teal-600 flex items-center justify-center shadow-lg shadow-emerald-950/50 border border-emerald-400/30">
                  <Wrench className="w-5 h-5 text-slate-950 stroke-[2.5]" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h1 className="text-lg font-bold tracking-tight text-white">
                      Garage<span className="text-emerald-400">Command</span>{' '}
                      <span className="text-xs font-extrabold uppercase px-1.5 py-0.5 rounded bg-emerald-500 text-slate-950">
                        PRO
                      </span>
                    </h1>
                    <span className="hidden sm:inline-block text-[11px] font-semibold uppercase tracking-wider px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                      Tools • Shelf • Live Countdowns
                    </span>
                  </div>
                  <p className="text-xs text-slate-400 hidden sm:block">
                    Vehicle Service Ledger, Consumables Shelf & Live DIY Tool Readiness
                  </p>
                </div>
              </div>

              {/* Mobile Top Right Quick Actions */}
              <div className="flex md:hidden items-center gap-1.5">
                <button
                  onClick={() => setIsPhoneModalOpen(true)}
                  className={`inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-semibold border transition ${
                    cloudStatus === 'synced'
                      ? 'bg-emerald-500/15 border-emerald-500/40 text-emerald-300'
                      : cloudStatus === 'syncing' || cloudStatus === 'connecting'
                      ? 'bg-amber-500/15 border-amber-500/40 text-amber-300'
                      : cloudStatus === 'error'
                      ? 'bg-rose-500/15 border-rose-500/40 text-rose-300'
                      : 'bg-slate-800 border-slate-700 text-slate-300'
                  }`}
                >
                  <Smartphone className="w-3.5 h-3.5" />
                  {cloudStatus === 'synced'
                    ? 'Supabase Live'
                    : cloudStatus === 'error'
                    ? 'Sync Error'
                    : 'Supabase Setup'}
                </button>
                <button
                  onClick={openAddVehicleModal}
                  className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-bold bg-emerald-500 text-slate-950 hover:bg-emerald-400 transition"
                >
                  <Plus className="w-3.5 h-3.5 stroke-[2.5]" />
                  Car
                </button>
              </div>
            </div>

            {/* Active Vehicle Selector & Garage Actions */}
            <div className="flex flex-wrap items-center gap-2 sm:gap-2.5">
              {/* Live Supabase Cloud Sync Status & Phone Setup Pill */}
              <button
                onClick={() => setIsPhoneModalOpen(true)}
                title="Click to configure your Supabase URL & Anon Key for Phone & Desktop Cloud Sync"
                className={`hidden md:inline-flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-semibold border transition cursor-pointer ${
                  cloudStatus === 'synced'
                    ? 'bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-300 border-emerald-500/30'
                    : cloudStatus === 'syncing' || cloudStatus === 'connecting'
                    ? 'bg-amber-500/10 text-amber-300 border-amber-500/30'
                    : cloudStatus === 'error'
                    ? 'bg-rose-500/10 text-rose-300 border-rose-500/40'
                    : 'bg-slate-800 hover:bg-slate-700 text-slate-300 border-slate-700'
                }`}
              >
                {cloudStatus === 'synced' ? (
                  <>
                    <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                    <Cloud className="w-3.5 h-3.5 text-emerald-400" />
                    <span>Supabase Live</span>
                  </>
                ) : cloudStatus === 'syncing' || cloudStatus === 'connecting' ? (
                  <>
                    <RefreshCw className="w-3.5 h-3.5 text-amber-400 animate-spin" />
                    <span>Syncing Supabase...</span>
                  </>
                ) : cloudStatus === 'error' ? (
                  <>
                    <AlertTriangle className="w-3.5 h-3.5 text-rose-400" />
                    <span>Supabase Error</span>
                  </>
                ) : (
                  <>
                    <Database className="w-3.5 h-3.5 text-emerald-400" />
                    <span>Connect Supabase</span>
                  </>
                )}
                <span className="px-1.5 py-0.5 rounded bg-slate-950/80 text-[10px] font-mono text-slate-300 border border-slate-800">
                  <Smartphone className="w-3 h-3 inline mr-0.5 -mt-0.5 text-emerald-400" />
                  Phone Sync
                </span>
              </button>

              {/* Vehicle Switcher Dropdown */}
              <div className="relative flex items-center bg-slate-950 border border-slate-800 rounded-xl p-1 flex-1 sm:flex-initial">
                <Car className="w-4 h-4 text-emerald-400 ml-2.5 mr-2 shrink-0" />
                <select
                  aria-label="Select Active Vehicle"
                  value={selectedVehicleId}
                  onChange={(e) => setSelectedVehicleId(e.target.value)}
                  className="bg-transparent text-sm font-semibold text-slate-100 pr-7 py-1.5 focus:outline-none cursor-pointer w-full"
                >
                  {vehicles.map((v) => (
                    <option key={v.id} value={v.id} className="bg-slate-900 text-slate-100">
                      {v.year} {v.make} {v.model} ({Number(v.odometer).toLocaleString()} mi)
                    </option>
                  ))}
                </select>
              </div>

              {/* Backup / Restore Button */}
              <button
                onClick={() => setIsBackupModalOpen(true)}
                title="JSON Backup & Restore"
                className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 transition"
              >
                <Database className="w-3.5 h-3.5 text-emerald-400" />
                <span className="hidden lg:inline">Backup</span>
              </button>

              {/* Add New Vehicle Button */}
              <button
                onClick={openAddVehicleModal}
                className="hidden md:inline-flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-emerald-400 border border-slate-700 hover:border-emerald-500/40 transition"
              >
                <Plus className="w-4 h-4" />
                Add Vehicle
              </button>

              {/* Log Service Primary CTA */}
              <button
                onClick={() => {
                  setEditingLog(null);
                  setIsLogModalOpen(true);
                }}
                className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-lg shadow-emerald-950/50 transition cursor-pointer"
              >
                <Plus className="w-4 h-4 stroke-[2.5]" />
                Log Service
              </button>
            </div>
          </div>

          {/* Desktop Navigation Tabs (Hidden on small mobile screens in favor of thumb-friendly bottom bar) */}
          <nav className="hidden md:flex items-center gap-1 sm:gap-2 mt-3 pt-2 border-t border-slate-800/80 overflow-x-auto no-scrollbar">
            <button
              onClick={() => setActiveTab('dashboard')}
              className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition whitespace-nowrap ${
                activeTab === 'dashboard'
                  ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
              }`}
            >
              <ClipboardList className="w-4 h-4" />
              Service & Expense Ledger
            </button>

            <button
              onClick={() => setActiveTab('guides')}
              className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition whitespace-nowrap ${
                activeTab === 'guides'
                  ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
              }`}
            >
              <BookOpen className="w-4 h-4" />
              DIY Guides & Readiness
              <span className="px-1.5 py-0.5 text-[11px] rounded-full bg-slate-800 text-slate-300">
                {guides.filter((g) => !activeVehicle || g.vehicleId === activeVehicle.id || g.vehicleId === 'ALL').length}
              </span>
            </button>

            <button
              onClick={() => setActiveTab('shelf')}
              className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition whitespace-nowrap ${
                activeTab === 'shelf'
                  ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
              }`}
            >
              <Package className="w-4 h-4" />
              Garage Shelf (Parts & Fluids)
              <span className="px-1.5 py-0.5 text-[11px] rounded-full bg-blue-500/20 text-blue-300 font-semibold">
                {totalShelfItems} in stock
              </span>
            </button>

            <button
              onClick={() => setActiveTab('tools')}
              className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition whitespace-nowrap ${
                activeTab === 'tools'
                  ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
              }`}
            >
              <Wrench className="w-4 h-4" />
              My Tool Chest
              <span className="px-1.5 py-0.5 text-[11px] rounded-full bg-emerald-500/20 text-emerald-300 font-semibold">
                {ownedToolsCount}/{tools.length}
              </span>
            </button>

            <button
              onClick={() => setActiveTab('garage')}
              className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition whitespace-nowrap ${
                activeTab === 'garage'
                  ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
              }`}
            >
              <Car className="w-4 h-4" />
              My Garage & Part #s ({vehicles.length})
            </button>
          </nav>
        </div>
      </header>

      {/* ==========================================
          ACTIVE VEHICLE BANNER & SPEC STRIP
      ========================================== */}
      {activeVehicle && (
        <div className="bg-slate-900/60 border-b border-slate-800/80">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
            <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3">
              {/* Vehicle Identity & Quick Specs */}
              <div className="flex flex-wrap items-center gap-2.5">
                <div className="flex items-center gap-2">
                  <span className="inline-block w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
                  <h2 className="text-base sm:text-lg font-bold text-white">
                    {activeVehicle.year} {activeVehicle.make} {activeVehicle.model}
                  </h2>
                  <span className="text-xs font-medium px-2.5 py-0.5 rounded-md bg-slate-800 text-slate-300 border border-slate-700">
                    {activeVehicle.trim}
                  </span>
                </div>

                <div className="flex flex-wrap items-center gap-2 text-xs text-slate-300">
                  {activeVehicle.oilSpec && (
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-950/90 border border-slate-800">
                      <Droplets className="w-3.5 h-3.5 text-amber-400" />
                      <strong className="text-slate-400">Oil:</strong> {activeVehicle.oilSpec}
                    </span>
                  )}
                  {activeVehicle.coolantSpec && (
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-950/90 border border-slate-800">
                      <Sparkles className="w-3.5 h-3.5 text-purple-400" />
                      <strong className="text-slate-400">Coolant:</strong> {activeVehicle.coolantSpec}
                    </span>
                  )}
                  {activeVehicle.lugTorqueSpec && (
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-950/90 border border-slate-800">
                      <Wrench className="w-3.5 h-3.5 text-emerald-400" />
                      <strong className="text-slate-400">Lugs:</strong> {activeVehicle.lugTorqueSpec}
                    </span>
                  )}
                </div>
              </div>

              {/* Odometer & Edit Vehicle Controls */}
              <div className="flex items-center gap-2 self-start lg:self-auto shrink-0">
                <div className="flex items-center gap-2 bg-slate-950 border border-slate-800 px-3 py-1.5 rounded-xl">
                  <Gauge className="w-4 h-4 text-emerald-400" />
                  <span className="text-xs text-slate-400">Odometer:</span>
                  <span className="text-sm font-mono font-bold text-white">
                    {Number(activeVehicle.odometer).toLocaleString()} mi
                  </span>
                  <button
                    onClick={() => {
                      setTempOdometer(String(activeVehicle.odometer));
                      setIsOdometerModalOpen(true);
                    }}
                    title="Update Odometer"
                    className="ml-1 text-xs text-emerald-400 hover:text-emerald-300 underline font-medium cursor-pointer"
                  >
                    Update
                  </button>
                </div>

                <button
                  onClick={() => openEditVehicleModal(activeVehicle)}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium bg-slate-800/80 hover:bg-slate-800 text-slate-200 border border-slate-700 transition cursor-pointer"
                >
                  <Edit3 className="w-3.5 h-3.5" />
                  Specs & Part #s
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ==========================================
          MAIN WORKSPACE CONTENT
      ========================================== */}
      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-6">
        {/* ------------------------------------------
            TAB 1: DASHBOARD & SERVICE / EXPENSE LEDGER
        ------------------------------------------ */}
        {activeTab === 'dashboard' && activeVehicle && (
          <div className="space-y-6">
            {/* KPI Summary Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              {/* Total Maintenance Spend */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-sm">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Total Logged Spend
                  </span>
                  <div className="p-2 rounded-lg bg-blue-500/10 text-blue-400">
                    <DollarSign className="w-4 h-4" />
                  </div>
                </div>
                <p className="text-2xl font-bold text-white mt-2">
                  ${vehicleStats.totalSpend.toFixed(2)}
                </p>
                <p className="text-xs text-slate-400 mt-1">
                  Across {vehicleStats.totalServices} logged service records
                </p>
              </div>

              {/* Estimated DIY Savings */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-sm">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Est. DIY Labor Saved
                  </span>
                  <div className="p-2 rounded-lg bg-emerald-500/10 text-emerald-400">
                    <ShieldCheck className="w-4 h-4" />
                  </div>
                </div>
                <p className="text-2xl font-bold text-emerald-400 mt-2">
                  +${vehicleStats.diySavings.toFixed(2)}
                </p>
                <p className="text-xs text-slate-400 mt-1">
                  {vehicleStats.diyCount} of {vehicleStats.totalServices} services performed DIY
                </p>
              </div>

              {/* Garage Shelf Stock */}
              <div
                onClick={() => setActiveTab('shelf')}
                className="bg-slate-900 border border-slate-800 hover:border-slate-700 rounded-2xl p-4 shadow-sm cursor-pointer transition group"
              >
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Garage Parts Shelf
                  </span>
                  <div className="p-2 rounded-lg bg-cyan-500/10 text-cyan-400 group-hover:scale-105 transition">
                    <Package className="w-4 h-4" />
                  </div>
                </div>
                <p className="text-2xl font-bold text-white mt-2">
                  {totalShelfItems}{' '}
                  <span className="text-sm font-normal text-slate-400">Items In Stock</span>
                </p>
                <p className="text-xs text-cyan-400 mt-1 flex items-center gap-1">
                  {vehicleStats.lowStockCount > 0
                    ? `${vehicleStats.lowStockCount} item(s) low on stock`
                    : 'All key fluids & filters stocked'}{' '}
                  <ChevronRight className="w-3.5 h-3.5" />
                </p>
              </div>

              {/* Tool Chest Readiness */}
              <div
                onClick={() => setActiveTab('tools')}
                className="bg-slate-900 border border-slate-800 hover:border-slate-700 rounded-2xl p-4 shadow-sm cursor-pointer transition group"
              >
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Garage Tool Chest
                  </span>
                  <div className="p-2 rounded-lg bg-amber-500/10 text-amber-400 group-hover:scale-105 transition">
                    <Wrench className="w-4 h-4" />
                  </div>
                </div>
                <p className="text-2xl font-bold text-white mt-2">
                  {ownedToolsCount}{' '}
                  <span className="text-sm font-normal text-slate-400">/ {tools.length} Owned</span>
                </p>
                <p className="text-xs text-emerald-400 mt-1 flex items-center gap-1">
                  Check tools & free loaner options <ChevronRight className="w-3.5 h-3.5" />
                </p>
              </div>
            </div>

            {/* Main Grid: Left 2 Cols = Ledger, Right Col = Live Countdown & Part #s */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              {/* Left 2 Columns: Service & Expense History Table */}
              <div className="lg:col-span-2 bg-slate-900 border border-slate-800 rounded-2xl overflow-hidden flex flex-col">
                <div className="p-4 sm:p-5 border-b border-slate-800 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                  <div>
                    <h3 className="text-base font-bold text-white flex items-center gap-2">
                      <ClipboardList className="w-4 h-4 text-emerald-400" />
                      Service & Expense Log ({filteredLogs.length})
                    </h3>
                    <p className="text-xs text-slate-400">
                      Complete maintenance history, fluid specs used, and costs for {activeVehicle.year} {activeVehicle.model}
                    </p>
                  </div>

                  <div className="flex flex-wrap items-center gap-2">
                    <button
                      onClick={handleExportCSV}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 transition cursor-pointer"
                    >
                      <Download className="w-3.5 h-3.5" />
                      CSV
                    </button>
                    <button
                      onClick={() => setIsBackupModalOpen(true)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium bg-slate-800 hover:bg-slate-700 text-emerald-300 border border-slate-700 transition cursor-pointer"
                    >
                      <Database className="w-3.5 h-3.5" />
                      JSON Backup
                    </button>
                    <button
                      onClick={() => {
                        setEditingLog(null);
                        setIsLogModalOpen(true);
                      }}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold bg-emerald-500 hover:bg-emerald-400 text-slate-950 transition cursor-pointer"
                    >
                      <Plus className="w-3.5 h-3.5 stroke-[2.5]" />
                      Add Entry
                    </button>
                  </div>
                </div>

                {/* Search & Category Filter Bar */}
                <div className="px-4 sm:px-5 py-3 bg-slate-950/50 border-b border-slate-800 flex flex-col sm:flex-row gap-2.5">
                  <div className="relative flex-1">
                    <Search className="w-4 h-4 text-slate-500 absolute left-3 top-1/2 -translate-y-1/2" />
                    <input
                      type="text"
                      value={logSearch}
                      onChange={(e) => setLogSearch(e.target.value)}
                      placeholder="Search service, fluid (e.g. MAG 1 5W-30, 2825 bulb, NGK plugs)..."
                      className="w-full bg-slate-900 border border-slate-800 rounded-xl pl-9 pr-3 py-1.5 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-emerald-500"
                    />
                  </div>
                  <select
                    aria-label="Filter by Service Category"
                    value={logCategoryFilter}
                    onChange={(e) => setLogCategoryFilter(e.target.value)}
                    className="bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-emerald-500"
                  >
                    <option value="ALL">All Categories</option>
                    {SERVICE_CATEGORIES.map((cat) => (
                      <option key={cat} value={cat}>
                        {cat}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Log Entries List */}
                <div className="divide-y divide-slate-800/70">
                  {filteredLogs.length === 0 ? (
                    <div className="p-10 text-center">
                      <ClipboardList className="w-8 h-8 text-slate-600 mx-auto mb-2" />
                      <p className="text-sm font-medium text-slate-300">No service records match your filter</p>
                      <p className="text-xs text-slate-500 mt-1">
                        Click &ldquo;Add Entry&rdquo; or use the One-Click Complete button inside any DIY Service Guide.
                      </p>
                    </div>
                  ) : (
                    filteredLogs.map((log) => (
                      <div
                        key={log.id}
                        className="p-4 sm:px-5 hover:bg-slate-800/30 transition flex flex-col sm:flex-row sm:items-center justify-between gap-3"
                      >
                        <div className="space-y-1 flex-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="text-sm font-bold text-white">{log.serviceType}</span>
                            <span
                              className={`text-[11px] font-semibold px-2 py-0.5 rounded-full border ${
                                log.performedBy === 'DIY'
                                  ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                                  : 'bg-blue-500/10 text-blue-400 border-blue-500/30'
                              }`}
                            >
                              {log.performedBy}
                            </span>
                            <span className="text-[11px] px-2 py-0.5 rounded-md bg-slate-800 text-slate-300">
                              {log.category}
                            </span>
                            {log.receiptPhoto && (
                              <button
                                onClick={() =>
                                  setPreviewPhoto({
                                    label: `${log.serviceType} (${log.date})`,
                                    dataUrl: log.receiptPhoto
                                  })
                                }
                                className="inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-md bg-purple-500/15 text-purple-300 border border-purple-500/30 hover:bg-purple-500/25"
                              >
                                <ImageIcon className="w-3 h-3" />
                                View Receipt Photo
                              </button>
                            )}
                          </div>

                          <div className="flex flex-wrap items-center gap-3 text-xs text-slate-400">
                            <span className="inline-flex items-center gap-1">
                              <Calendar className="w-3.5 h-3.5 text-slate-500" />
                              {log.date}
                            </span>
                            <span className="inline-flex items-center gap-1 font-mono text-slate-300">
                              <Gauge className="w-3.5 h-3.5 text-slate-500" />
                              {Number(log.odometer).toLocaleString()} mi
                            </span>
                            {log.partsUsed && (
                              <span className="text-emerald-300/90 font-medium">
                                • Parts/Fluids: {log.partsUsed}
                              </span>
                            )}
                          </div>

                          {log.notes && (
                            <p className="text-xs text-slate-400 pt-0.5 leading-relaxed">{log.notes}</p>
                          )}
                        </div>

                        <div className="flex sm:flex-col items-center sm:items-end justify-between sm:justify-center gap-2 shrink-0 border-t sm:border-t-0 border-slate-800 pt-2 sm:pt-0">
                          <div className="text-right">
                            <span className="text-base font-bold text-white">
                              ${Number(log.cost || 0).toFixed(2)}
                            </span>
                            {log.performedBy === 'DIY' && Number(log.estimatedShopSavings) > 0 && (
                              <p className="text-[11px] text-emerald-400">
                                Saved ~${Number(log.estimatedShopSavings).toFixed(0)} vs shop
                              </p>
                            )}
                          </div>

                          <div className="flex items-center gap-1">
                            <button
                              onClick={() => {
                                setEditingLog(log);
                                setIsLogModalOpen(true);
                              }}
                              title="Edit Record"
                              className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
                            >
                              <Edit3 className="w-3.5 h-3.5" />
                            </button>
                            <button
                              onClick={() => {
                                setLogs((prev) => prev.filter((item) => item.id !== log.id));
                                showToast('Deleted service record.');
                              }}
                              title="Delete Record"
                              className="p-1.5 rounded-lg text-slate-400 hover:text-rose-400 hover:bg-slate-800 transition"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </div>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>

              {/* Right Column: Live Mileage Countdowns & Store Aisle Part Numbers */}
              <div className="space-y-6">
                {/* Live Next-Due Mileage Countdown Card */}
                <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 sm:p-5 space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <h3 className="text-sm font-bold text-white flex items-center gap-2">
                        <Gauge className="w-4 h-4 text-emerald-400" />
                        Live Service Mileage Countdowns
                      </h3>
                      <p className="text-xs text-slate-400">
                        Compared against {Number(activeVehicle.odometer).toLocaleString()} mi odometer
                      </p>
                    </div>
                    <button
                      onClick={() => setActiveTab('guides')}
                      className="text-xs font-semibold text-emerald-400 hover:text-emerald-300"
                    >
                      All 14+ Guides
                    </button>
                  </div>

                  <div className="space-y-3">
                    {vehicleStats.evaluatedGuides.slice(0, 6).map(({ guide, dueInfo, readiness, partsReadiness }) => (
                      <div
                        key={guide.id}
                        className="p-3 rounded-xl bg-slate-950/90 border border-slate-800/90 space-y-2"
                      >
                        <div className="flex items-start justify-between gap-2">
                          <h4 className="text-xs font-bold text-slate-100 leading-snug">
                            {guide.title}
                          </h4>
                          <span
                            className={`text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0 ${
                              dueInfo.status === 'overdue'
                                ? 'bg-rose-500/20 text-rose-300 border border-rose-500/40'
                                : dueInfo.status === 'due-soon'
                                ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                                : dueInfo.status === 'good'
                                ? 'bg-emerald-500/15 text-emerald-300 border border-emerald-500/30'
                                : 'bg-slate-800 text-slate-300'
                            }`}
                          >
                            {dueInfo.label}
                          </span>
                        </div>

                        {/* Visual Progress Bar */}
                        <div className="w-full h-1.5 bg-slate-800 rounded-full overflow-hidden">
                          <div
                            style={{ width: `${dueInfo.progressPercent}%` }}
                            className={`h-full rounded-full transition-all ${
                              dueInfo.status === 'overdue'
                                ? 'bg-rose-500'
                                : dueInfo.status === 'due-soon'
                                ? 'bg-amber-400'
                                : 'bg-emerald-500'
                            }`}
                          />
                        </div>

                        <div className="flex flex-wrap items-center justify-between gap-2 text-[11px] pt-0.5">
                          <div className="flex items-center gap-2">
                            {readiness.isReady ? (
                              <span className="inline-flex items-center gap-1 text-emerald-400 font-semibold">
                                <CheckCircle2 className="w-3 h-3" />
                                Tools Ready
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1 text-amber-400 font-semibold">
                                <AlertTriangle className="w-3 h-3" />
                                {readiness.missingCount} tool{readiness.missingCount > 1 ? 's' : ''} missing
                              </span>
                            )}

                            {partsReadiness.hasRequirements && (
                              <span
                                className={`inline-flex items-center gap-1 font-medium ${
                                  partsReadiness.isReady ? 'text-cyan-400' : 'text-slate-400'
                                }`}
                              >
                                • {partsReadiness.isReady ? 'Parts on Shelf' : 'Need Parts'}
                              </span>
                            )}
                          </div>

                          <button
                            onClick={() => handleLogFromGuide(guide)}
                            className="text-emerald-400 hover:text-emerald-300 font-semibold underline cursor-pointer"
                          >
                            Complete Job
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Store-Aisle Quick Part Numbers & Specs Reference */}
                <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 sm:p-5 space-y-3">
                  <div className="flex items-center justify-between">
                    <div>
                      <h3 className="text-sm font-bold text-white flex items-center gap-2">
                        <Tag className="w-4 h-4 text-emerald-400" />
                        Store-Aisle Part Numbers & Specs
                      </h3>
                      <p className="text-xs text-slate-400">
                        Click any part number to copy
                      </p>
                    </div>
                    <button
                      onClick={() => openEditVehicleModal(activeVehicle)}
                      className="text-xs text-emerald-400 hover:text-emerald-300 font-medium"
                    >
                      + Edit / Add
                    </button>
                  </div>

                  {/* Clickable Part Numbers List */}
                  <div className="space-y-1.5">
                    {(activeVehicle.partNumbers || []).map((pn) => (
                      <div
                        key={pn.id}
                        onClick={() => {
                          navigator.clipboard?.writeText(pn.number);
                          showToast(`Copied "${pn.number}" to clipboard!`);
                        }}
                        title="Click to copy part number"
                        className="p-2.5 rounded-xl bg-slate-950 hover:bg-slate-950/60 border border-slate-800/90 hover:border-emerald-500/40 flex items-center justify-between gap-2 cursor-pointer transition group"
                      >
                        <div>
                          <span className="text-xs font-semibold text-slate-200 block">
                            {pn.part}
                          </span>
                          <span className="text-[11px] text-slate-500">{pn.vendor}</span>
                        </div>
                        <div className="flex items-center gap-1.5 bg-slate-900 px-2.5 py-1 rounded-lg border border-slate-800 group-hover:border-emerald-500/40">
                          <span className="text-xs font-mono font-bold text-emerald-400">
                            {pn.number}
                          </span>
                          <Copy className="w-3 h-3 text-slate-500 group-hover:text-emerald-400" />
                        </div>
                      </div>
                    ))}
                  </div>

                  {activeVehicle.notes && (
                    <div className="p-3 rounded-xl bg-slate-950 border border-slate-800/90 text-xs text-slate-300 leading-relaxed">
                      <strong className="text-slate-100 block mb-1">Fastener & Torque Cheat Sheet:</strong>
                      {activeVehicle.notes}
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ------------------------------------------
            TAB 2: SMART DIY SERVICE GUIDES (14+ GUIDES, DUAL CHECK & LOANER CALCULATOR)
        ------------------------------------------ */}
        {activeTab === 'guides' && (
          <div className="space-y-6">
            {/* Header & Controls */}
            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 sm:p-5 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
              <div>
                <h2 className="text-lg font-bold text-white flex items-center gap-2">
                  <BookOpen className="w-5 h-5 text-emerald-400" />
                  Smart DIY Service Guides — Live Mileage, Tool & Shelf Readiness
                </h2>
                <p className="text-xs sm:text-sm text-slate-400 mt-0.5">
                  Cross-checks your <strong className="text-slate-200">Tool Chest</strong> (including Free Loan-A-Tool rentals) and your <strong className="text-slate-200">Garage Shelf</strong> parts before you start.
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <button
                  onClick={() => setIsGuideModalOpen(true)}
                  className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-lg shadow-emerald-950/40 transition cursor-pointer"
                >
                  <Plus className="w-4 h-4 stroke-[2.5]" />
                  Add Custom Service Guide
                </button>
              </div>
            </div>

            {/* Filter, Sort & Search Bar */}
            <div className="flex flex-col lg:flex-row items-stretch lg:items-center justify-between gap-3">
              <div className="flex flex-wrap items-center gap-1.5 bg-slate-900 p-1.5 rounded-xl border border-slate-800">
                <button
                  onClick={() => setGuideFilter('VEHICLE')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    guideFilter === 'VEHICLE'
                      ? 'bg-emerald-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  For {activeVehicle ? `${activeVehicle.year} ${activeVehicle.model}` : 'Selected Vehicle'}
                </button>
                <button
                  onClick={() => setGuideFilter('OVERDUE')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    guideFilter === 'OVERDUE'
                      ? 'bg-rose-500 text-white'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Due Soon / Overdue
                </button>
                <button
                  onClick={() => setGuideFilter('READY')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    guideFilter === 'READY'
                      ? 'bg-emerald-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Ready to DIY (Tools Owned)
                </button>
                <button
                  onClick={() => setGuideFilter('MISSING')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    guideFilter === 'MISSING'
                      ? 'bg-amber-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Missing Tools
                </button>
                <button
                  onClick={() => setGuideFilter('ALL')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    guideFilter === 'ALL'
                      ? 'bg-slate-700 text-white'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  All Guides ({guides.length})
                </button>
              </div>

              <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2">
                <div className="flex items-center gap-1.5 bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5">
                  <ArrowUpDown className="w-3.5 h-3.5 text-emerald-400" />
                  <span className="text-xs text-slate-400">Sort:</span>
                  <select
                    aria-label="Sort Guides"
                    value={guideSort}
                    onChange={(e) => setGuideSort(e.target.value)}
                    className="bg-transparent text-xs font-semibold text-white focus:outline-none"
                  >
                    <option value="URGENCY" className="bg-slate-900">Urgency (Overdue First)</option>
                    <option value="READINESS" className="bg-slate-900">Tool Readiness</option>
                    <option value="CATEGORY" className="bg-slate-900">Service Category</option>
                  </select>
                </div>

                <div className="relative w-full sm:w-64">
                  <Search className="w-4 h-4 text-slate-500 absolute left-3 top-1/2 -translate-y-1/2" />
                  <input
                    type="text"
                    value={guideSearch}
                    onChange={(e) => setGuideSearch(e.target.value)}
                    placeholder="Search 5/8 socket, Triple-Square, PCV..."
                    className="w-full bg-slate-900 border border-slate-800 rounded-xl pl-9 pr-3 py-2 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-emerald-500"
                  />
                </div>
              </div>
            </div>

            {/* Service Guide Cards Grid */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
              {filteredGuides.map((guide) => {
                const readiness = evaluateToolReadiness(guide.requiredTools);
                const partsReadiness = evaluatePartsReadiness(
                  guide.requiredParts,
                  activeVehicle?.id
                );
                const dueInfo = evaluateGuideDueStatus(guide, activeVehicle);
                const guideVehicle = vehicles.find((v) => v.id === guide.vehicleId);

                return (
                  <div
                    key={guide.id}
                    className={`bg-slate-900 rounded-2xl border transition flex flex-col justify-between overflow-hidden ${
                      readiness.isReady
                        ? 'border-slate-800 hover:border-emerald-500/40'
                        : 'border-slate-800 hover:border-amber-500/40'
                    }`}
                  >
                    <div>
                      {/* Top Readiness & Live Countdown Header */}
                      <div
                        className={`px-5 py-2.5 border-b flex flex-wrap items-center justify-between gap-2 ${
                          readiness.isReady
                            ? 'bg-emerald-500/10 border-emerald-500/20'
                            : 'bg-amber-500/10 border-amber-500/20'
                        }`}
                      >
                        <div className="flex flex-wrap items-center gap-2">
                          {readiness.isReady ? (
                            <span className="inline-flex items-center gap-1.5 text-xs font-bold text-emerald-400">
                              <CheckCircle2 className="w-4 h-4" />
                              TOOLS READY ({readiness.totalCount}/{readiness.totalCount})
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1.5 text-xs font-bold text-amber-400">
                              <AlertTriangle className="w-4 h-4" />
                              MISSING {readiness.missingCount} TOOL{readiness.missingCount > 1 ? 'S' : ''}
                              {readiness.loanerCount > 0 && (
                                <span className="text-[10px] px-2 py-0.5 rounded-full bg-purple-500/20 text-purple-300 border border-purple-500/30">
                                  {readiness.loanerCount} Free Loan-A-Tool
                                </span>
                              )}
                            </span>
                          )}
                        </div>

                        {/* Mileage Countdown Badge */}
                        <span
                          className={`text-[11px] font-bold px-2.5 py-0.5 rounded-full ${
                            dueInfo.status === 'overdue'
                              ? 'bg-rose-500/20 text-rose-300 border border-rose-500/40'
                              : dueInfo.status === 'due-soon'
                              ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                              : dueInfo.status === 'good'
                              ? 'bg-slate-900/90 text-emerald-400 border border-emerald-500/30'
                              : 'bg-slate-900/80 text-slate-300 border border-slate-700'
                          }`}
                        >
                          {dueInfo.label}
                        </span>
                      </div>

                      {/* Card Body */}
                      <div className="p-5 space-y-4">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <div className="flex flex-wrap items-center gap-2 mb-1">
                              <span className="text-[11px] font-semibold uppercase tracking-wider px-2 py-0.5 rounded bg-slate-800 text-slate-300">
                                {guideVehicle
                                  ? `${guideVehicle.year} ${guideVehicle.make} ${guideVehicle.model}`
                                  : 'Universal / All Vehicles'}
                              </span>
                              <span className="text-[11px] px-2 py-0.5 rounded bg-slate-800/80 text-slate-400">
                                Every {Number(guide.intervalMiles).toLocaleString()} mi / {guide.intervalMonths} mos
                              </span>
                            </div>
                            <h3 className="text-base font-bold text-white">{guide.title}</h3>
                          </div>

                          <div className="text-right shrink-0">
                            <span className="text-xs font-bold text-emerald-400 block">
                              DIY ~${guide.estimatedDiyCost}
                            </span>
                            <span className="text-[11px] text-slate-500 line-through">
                              Shop ~${guide.estimatedShopCost}
                            </span>
                          </div>
                        </div>

                        {/* Live Mileage Progress Bar */}
                        <div className="p-3 rounded-xl bg-slate-950 border border-slate-800/90 space-y-1.5">
                          <div className="flex items-center justify-between text-[11px]">
                            <span className="text-slate-400">
                              {dueInfo.lastOdometer
                                ? `Last logged at ${Number(dueInfo.lastOdometer).toLocaleString()} mi (${dueInfo.lastDate})`
                                : 'No prior log for this vehicle yet'}
                            </span>
                            <span className="font-mono font-semibold text-slate-300">
                              {dueInfo.subLabel}
                            </span>
                          </div>
                          <div className="w-full h-2 bg-slate-800 rounded-full overflow-hidden">
                            <div
                              style={{ width: `${dueInfo.progressPercent}%` }}
                              className={`h-full rounded-full transition-all ${
                                dueInfo.status === 'overdue'
                                  ? 'bg-rose-500'
                                  : dueInfo.status === 'due-soon'
                                  ? 'bg-amber-400'
                                  : 'bg-emerald-500'
                              }`}
                            />
                          </div>
                        </div>

                        {/* Metadata Pills */}
                        <div className="flex flex-wrap items-center gap-2 text-xs text-slate-400">
                          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-slate-950 border border-slate-800">
                            <Clock className="w-3.5 h-3.5 text-slate-500" />
                            Time: <strong className="text-slate-200">{guide.estimatedTime}</strong>
                          </span>
                          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-slate-950 border border-slate-800">
                            <Gauge className="w-3.5 h-3.5 text-slate-500" />
                            Difficulty: <strong className="text-slate-200">{guide.difficulty}</strong>
                          </span>
                          {!readiness.isReady && (
                            <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-purple-500/10 border border-purple-500/30 text-purple-300">
                              <Store className="w-3.5 h-3.5" />
                              Buy missing: ~${readiness.missingBuyCost} (or ${readiness.missingNonLoanerCost} w/ Free Loaner)
                            </span>
                          )}
                        </div>

                        {/* Specs & Pro Advice Box */}
                        <div className="p-3.5 rounded-xl bg-slate-950 border border-slate-800/90 space-y-1">
                          <span className="text-[11px] font-bold uppercase tracking-wider text-emerald-400 flex items-center gap-1.5">
                            <Sparkles className="w-3.5 h-3.5" />
                            Recommended Specs, Torque & Pro Advice
                          </span>
                          <p className="text-xs text-slate-300 leading-relaxed">{guide.specsAndAdvice}</p>
                        </div>

                        {/* Shelf Parts & Consumables Readiness Check */}
                        {partsReadiness.hasRequirements && (
                          <div className="space-y-1.5">
                            <span className="text-xs font-bold text-slate-200 flex items-center gap-1.5">
                              <Package className="w-3.5 h-3.5 text-cyan-400" />
                              Garage Shelf Parts Check:
                            </span>
                            <div className="flex flex-wrap gap-1.5">
                              {partsReadiness.details.map((part, pIdx) => (
                                <span
                                  key={pIdx}
                                  onClick={() => setActiveTab('shelf')}
                                  className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium border cursor-pointer ${
                                    part.enough
                                      ? 'bg-cyan-500/10 border-cyan-500/30 text-cyan-300'
                                      : 'bg-amber-500/10 border-amber-500/40 text-amber-300'
                                  }`}
                                >
                                  {part.enough ? (
                                    <Check className="w-3.5 h-3.5 text-cyan-400" />
                                  ) : (
                                    <AlertTriangle className="w-3.5 h-3.5 text-amber-400" />
                                  )}
                                  {part.neededQty}x {part.name} (On Shelf: {part.availableQty})
                                </span>
                              ))}
                            </div>
                          </div>
                        )}

                        {/* Interactive Required Tools Checklist */}
                        <div className="space-y-2">
                          <span className="text-xs font-bold text-slate-200 flex items-center gap-1.5">
                            <Wrench className="w-3.5 h-3.5 text-emerald-400" />
                            Required Tools Checklist (Click any tool to toggle Owned status):
                          </span>

                          <div className="flex flex-wrap gap-1.5">
                            {readiness.details.map((toolItem, idx) => (
                              <button
                                key={idx}
                                onClick={() => handleToggleToolByName(toolItem.name)}
                                title={
                                  toolItem.owned
                                    ? 'You own this tool! Click to toggle.'
                                    : 'Missing from your Tool Chest! Click to mark as Owned.'
                                }
                                className={`group inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-medium border transition cursor-pointer ${
                                  toolItem.owned
                                    ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-300 hover:bg-emerald-500/20'
                                    : 'bg-rose-500/10 border-rose-500/40 text-rose-300 hover:bg-rose-500/20'
                                }`}
                              >
                                {toolItem.owned ? (
                                  <Check className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                                ) : (
                                  <XCircle className="w-3.5 h-3.5 text-rose-400 shrink-0" />
                                )}
                                <span>{toolItem.name}</span>
                                {!toolItem.owned && toolItem.loanerAvailable && (
                                  <span className="px-1.5 py-0.5 text-[10px] rounded bg-purple-500/30 text-purple-200 font-semibold">
                                    Free Loaner Available
                                  </span>
                                )}
                                {!toolItem.owned && (
                                  <span className="ml-0.5 px-1.5 py-0.5 text-[10px] rounded bg-rose-500/30 text-rose-100 font-semibold group-hover:bg-emerald-500 group-hover:text-slate-950 transition">
                                    + Own (${toolItem.estBuyPrice})
                                  </span>
                                )}
                              </button>
                            ))}
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Card Footer Actions */}
                    <div className="px-5 py-3 bg-slate-950/70 border-t border-slate-800/80 flex items-center justify-between gap-2">
                      <span className="text-xs text-slate-400">
                        Est. DIY Labor Savings:{' '}
                        <strong className="text-emerald-400">
                          +${Math.max(0, (guide.estimatedShopCost || 0) - (guide.estimatedDiyCost || 0))}
                        </strong>
                      </span>

                      <div className="flex items-center gap-2">
                        {guide.id.startsWith('g-custom-') && (
                          <button
                            onClick={() => {
                              setGuides((prev) => prev.filter((item) => item.id !== guide.id));
                              showToast('Deleted custom service guide.');
                            }}
                            className="p-1.5 rounded-lg text-slate-500 hover:text-rose-400 transition"
                            title="Delete Custom Guide"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        )}
                        <button
                          onClick={() => handleLogFromGuide(guide)}
                          className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-md shadow-emerald-950/50 transition cursor-pointer"
                        >
                          <CheckCircle2 className="w-3.5 h-3.5 stroke-[2.5]" />
                          Complete & Log This Job
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* ------------------------------------------
            TAB 3: GARAGE SHELF (CONSUMABLES & PARTS INVENTORY)
        ------------------------------------------ */}
        {activeTab === 'shelf' && (
          <div className="space-y-6">
            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
              <div>
                <h2 className="text-lg font-bold text-white flex items-center gap-2">
                  <Package className="w-5 h-5 text-cyan-400" />
                  Garage Shelf — Spare Parts, Fluids & Consumables Inventory
                </h2>
                <p className="text-xs sm:text-sm text-slate-400 mt-0.5">
                  Track oil quarts, filters, 2825 bulbs, and coolant sitting on your shelf. Items automatically cross-check with DIY Guides and can be auto-deducted when you complete a job!
                </p>
              </div>

              <button
                onClick={() => {
                  setEditingShelfItem(null);
                  setIsShelfModalOpen(true);
                }}
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-lg shadow-emerald-950/40 transition cursor-pointer self-start lg:self-auto"
              >
                <Plus className="w-4 h-4 stroke-[2.5]" />
                Add Shelf Item
              </button>
            </div>

            {/* Filter & Search Bar */}
            <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
              <div className="flex flex-wrap items-center gap-1.5 bg-slate-900 p-1.5 rounded-xl border border-slate-800">
                <button
                  onClick={() => setShelfFilter('ALL')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    shelfFilter === 'ALL'
                      ? 'bg-slate-700 text-white'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  All Shelf Items ({shelf.length})
                </button>
                <button
                  onClick={() => setShelfFilter('VEHICLE')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    shelfFilter === 'VEHICLE'
                      ? 'bg-emerald-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  For {activeVehicle ? `${activeVehicle.year} ${activeVehicle.model}` : 'Selected Vehicle'}
                </button>
                <button
                  onClick={() => setShelfFilter('LOW_STOCK')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    shelfFilter === 'LOW_STOCK'
                      ? 'bg-amber-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Low / Out of Stock ({shelf.filter((s) => Number(s.quantity) < Number(s.minQuantity)).length})
                </button>
              </div>

              <div className="relative w-full sm:w-72">
                <Search className="w-4 h-4 text-slate-500 absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  value={shelfSearch}
                  onChange={(e) => setShelfSearch(e.target.value)}
                  placeholder="Search MAG 1, 2825 bulb, filter..."
                  className="w-full bg-slate-900 border border-slate-800 rounded-xl pl-9 pr-3 py-2 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-emerald-500"
                />
              </div>
            </div>

            {/* Shelf Items Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {filteredShelf.map((item) => {
                const isLow = Number(item.quantity) < Number(item.minQuantity);
                const itemVehicle = vehicles.find((v) => v.id === item.vehicleId);

                return (
                  <div
                    key={item.id}
                    className={`bg-slate-900 rounded-2xl border p-4 flex flex-col justify-between gap-4 transition ${
                      isLow
                        ? 'border-amber-500/40 bg-amber-500/5'
                        : 'border-slate-800 hover:border-cyan-500/40'
                    }`}
                  >
                    <div className="space-y-2">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-[10px] font-semibold uppercase tracking-wider px-2 py-0.5 rounded bg-slate-800 text-slate-300">
                          {item.category}
                        </span>
                        <span className="text-[10px] px-2 py-0.5 rounded bg-slate-800/80 text-slate-400">
                          {itemVehicle
                            ? `${itemVehicle.year} ${itemVehicle.model}`
                            : 'Universal'}
                        </span>
                      </div>

                      <h3 className="text-sm font-bold text-white">{item.name}</h3>

                      {item.partNumber && (
                        <div className="inline-flex items-center gap-1.5 text-xs font-mono text-cyan-400 bg-slate-950 px-2 py-0.5 rounded border border-slate-800">
                          <span>Part #: {item.partNumber}</span>
                        </div>
                      )}

                      {item.notes && <p className="text-xs text-slate-400">{item.notes}</p>}
                    </div>

                    <div className="pt-3 border-t border-slate-800/80 flex items-center justify-between gap-2">
                      <div>
                        <div className="flex items-baseline gap-1.5">
                          <span
                            className={`text-xl font-bold font-mono ${
                              isLow ? 'text-amber-400' : 'text-emerald-400'
                            }`}
                          >
                            {item.quantity}
                          </span>
                          <span className="text-xs text-slate-400">{item.unit}</span>
                        </div>
                        <span className="text-[10px] text-slate-500 block">
                          Target min: {item.minQuantity} • ~${Number(item.unitCost || 0).toFixed(2)}/ea
                        </span>
                      </div>

                      <div className="flex items-center gap-1.5">
                        <button
                          onClick={() => handleAdjustShelfQty(item.id, -1)}
                          className="p-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 transition cursor-pointer"
                          title="Decrease Quantity"
                        >
                          <Minus className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => handleAdjustShelfQty(item.id, 1)}
                          className="p-1.5 rounded-lg bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 border border-emerald-500/30 transition cursor-pointer"
                          title="Increase Quantity"
                        >
                          <Plus className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => {
                            setEditingShelfItem(item);
                            setIsShelfModalOpen(true);
                          }}
                          className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
                          title="Edit Item"
                        >
                          <Edit3 className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => {
                            setShelf((prev) => prev.filter((s) => s.id !== item.id));
                            showToast(`Removed "${item.name}" from Shelf.`);
                          }}
                          className="p-1.5 rounded-lg text-slate-400 hover:text-rose-400 hover:bg-slate-800 transition"
                          title="Delete Item"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* ------------------------------------------
            TAB 4: MY TOOL CHEST (GARAGE INVENTORY & LOANER CALCULATOR)
        ------------------------------------------ */}
        {activeTab === 'tools' && (
          <div className="space-y-6">
            {/* Tool Chest Header Banner */}
            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
              <div>
                <h2 className="text-lg font-bold text-white flex items-center gap-2">
                  <Wrench className="w-5 h-5 text-emerald-400" />
                  My Garage Tool Chest ({ownedToolsCount} Owned / {tools.length - ownedToolsCount} Missing)
                </h2>
                <p className="text-xs sm:text-sm text-slate-400 mt-0.5">
                  Click any tool card to toggle ownership. Specialty tools marked <strong className="text-purple-300">Free Loan-A-Tool Available</strong> can be borrowed for free at AutoZone / Advance Auto Parts.
                </p>
              </div>

              <div className="flex items-center gap-3">
                <button
                  onClick={() => setIsToolModalOpen(true)}
                  className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-lg shadow-emerald-950/40 transition cursor-pointer"
                >
                  <Plus className="w-4 h-4 stroke-[2.5]" />
                  Add Custom Tool
                </button>
              </div>
            </div>

            {/* Filters & Search */}
            <div className="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3">
              <div className="flex flex-wrap items-center gap-1.5 bg-slate-900 p-1.5 rounded-xl border border-slate-800">
                <button
                  onClick={() => setToolOwnershipFilter('ALL')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    toolOwnershipFilter === 'ALL'
                      ? 'bg-slate-700 text-white'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  All Tools ({tools.length})
                </button>
                <button
                  onClick={() => setToolOwnershipFilter('OWNED')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    toolOwnershipFilter === 'OWNED'
                      ? 'bg-emerald-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Owned ({ownedToolsCount})
                </button>
                <button
                  onClick={() => setToolOwnershipFilter('MISSING')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    toolOwnershipFilter === 'MISSING'
                      ? 'bg-amber-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Missing / Wishlist ({tools.length - ownedToolsCount})
                </button>
                <button
                  onClick={() => setToolOwnershipFilter('LOANER')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                    toolOwnershipFilter === 'LOANER'
                      ? 'bg-purple-500 text-white'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Free Loan-A-Tool Eligible ({tools.filter((t) => t.loanerAvailable).length})
                </button>
              </div>

              <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2">
                <select
                  aria-label="Filter by Tool Category"
                  value={toolCategoryFilter}
                  onChange={(e) => setToolCategoryFilter(e.target.value)}
                  className="bg-slate-900 border border-slate-800 rounded-xl px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-emerald-500"
                >
                  <option value="ALL">All Tool Categories</option>
                  {TOOL_CATEGORIES.map((cat) => (
                    <option key={cat} value={cat}>
                      {cat}
                    </option>
                  ))}
                </select>

                <div className="relative w-full sm:w-64">
                  <Search className="w-4 h-4 text-slate-500 absolute left-3 top-1/2 -translate-y-1/2" />
                  <input
                    type="text"
                    value={toolSearch}
                    onChange={(e) => setToolSearch(e.target.value)}
                    placeholder="Search 5/8 socket, Triple-Square..."
                    className="w-full bg-slate-900 border border-slate-800 rounded-xl pl-9 pr-3 py-2 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-emerald-500"
                  />
                </div>
              </div>
            </div>

            {/* Tool Cards Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {filteredTools.map((tool) => {
                const usedInGuidesCount = guides.filter((g) =>
                  g.requiredTools.some((req) => req.toLowerCase().trim() === tool.name.toLowerCase().trim())
                ).length;

                return (
                  <div
                    key={tool.id}
                    onClick={() => handleToggleToolByName(tool.name)}
                    className={`p-4 rounded-2xl border transition cursor-pointer flex items-start justify-between gap-3 ${
                      tool.owned
                        ? 'bg-slate-900 border-emerald-500/30 hover:border-emerald-500/60'
                        : 'bg-slate-900/60 border-slate-800 hover:border-amber-500/40'
                    }`}
                  >
                    <div className="space-y-1.5">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <span className="text-[10px] font-semibold uppercase tracking-wider px-2 py-0.5 rounded bg-slate-800 text-slate-400">
                          {tool.category}
                        </span>
                        {usedInGuidesCount > 0 && (
                          <span className="text-[10px] px-2 py-0.5 rounded bg-blue-500/10 text-blue-400">
                            Used in {usedInGuidesCount} guide{usedInGuidesCount > 1 ? 's' : ''}
                          </span>
                        )}
                        {tool.loanerAvailable && (
                          <span className="text-[10px] font-semibold px-2 py-0.5 rounded bg-purple-500/15 text-purple-300 border border-purple-500/30">
                            Free Loan-A-Tool
                          </span>
                        )}
                      </div>

                      <h3 className="text-sm font-bold text-white">{tool.name}</h3>
                      {tool.notes && <p className="text-xs text-slate-400">{tool.notes}</p>}
                    </div>

                    <div className="flex flex-col items-end gap-1.5 shrink-0">
                      <div
                        className={`px-2.5 py-1 rounded-lg text-xs font-bold flex items-center gap-1 transition ${
                          tool.owned
                            ? 'bg-emerald-500 text-slate-950'
                            : 'bg-slate-800 text-slate-400 border border-slate-700'
                        }`}
                      >
                        {tool.owned ? (
                          <>
                            <Check className="w-3.5 h-3.5 stroke-[3]" /> Owned
                          </>
                        ) : (
                          <span>Missing (~${tool.estBuyPrice || 20})</span>
                        )}
                      </div>

                      {tool.id.startsWith('t-custom-') && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setTools((prev) => prev.filter((item) => item.id !== tool.id));
                            showToast(`Removed "${tool.name}" from Tool Chest.`);
                          }}
                          className="text-slate-500 hover:text-rose-400 p-1"
                          title="Delete Custom Tool"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* ------------------------------------------
            TAB 5: MY GARAGE & PART NUMBERS / PHOTO REFERENCE
        ------------------------------------------ */}
        {activeTab === 'garage' && (
          <div className="space-y-6">
            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div>
                <h2 className="text-lg font-bold text-white flex items-center gap-2">
                  <Car className="w-5 h-5 text-emerald-400" />
                  My Garage Vehicles, Store-Aisle Part Numbers & Photo Reference ({vehicles.length})
                </h2>
                <p className="text-xs sm:text-sm text-slate-400 mt-0.5">
                  Manage your fleet, store clickable OEM/aftermarket part numbers, attach part label photos, or back up your garage.
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <button
                  onClick={() => setIsBackupModalOpen(true)}
                  className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium bg-slate-800 hover:bg-slate-700 text-emerald-300 border border-slate-700 transition cursor-pointer"
                >
                  <Database className="w-3.5 h-3.5" />
                  Backup / Restore JSON
                </button>
                <button
                  onClick={() => setConfirmResetOpen(true)}
                  className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition cursor-pointer"
                >
                  <RotateCcw className="w-3.5 h-3.5" />
                  Reset Demo Data
                </button>
                <button
                  onClick={openAddVehicleModal}
                  className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-lg shadow-emerald-950/40 transition cursor-pointer"
                >
                  <Plus className="w-4 h-4 stroke-[2.5]" />
                  Add New Vehicle
                </button>
              </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {vehicles.map((veh) => {
                const isSelected = veh.id === selectedVehicleId;
                const vLogs = logs.filter((l) => l.vehicleId === veh.id);
                const vSpend = vLogs.reduce((sum, l) => sum + (Number(l.cost) || 0), 0);

                return (
                  <div
                    key={veh.id}
                    className={`bg-slate-900 rounded-2xl border p-5 flex flex-col justify-between gap-4 transition ${
                      isSelected
                        ? 'border-emerald-500/60 ring-1 ring-emerald-500/30'
                        : 'border-slate-800 hover:border-slate-700'
                    }`}
                  >
                    <div className="space-y-4">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <div className="flex items-center gap-2">
                            <h3 className="text-lg font-bold text-white">
                              {veh.year} {veh.make} {veh.model}
                            </h3>
                            {isSelected && (
                              <span className="text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                                Active Vehicle
                              </span>
                            )}
                          </div>
                          <p className="text-xs text-slate-400">{veh.trim}</p>
                        </div>

                        <div className="text-right font-mono">
                          <span className="text-base font-bold text-white block">
                            {Number(veh.odometer).toLocaleString()} mi
                          </span>
                          <span className="text-[11px] text-slate-400">
                            {vLogs.length} records • ${vSpend.toFixed(2)} spent
                          </span>
                        </div>
                      </div>

                      {/* Core Fluid & Torque Specs Grid */}
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 text-xs">
                        <div className="p-2.5 rounded-xl bg-slate-950 border border-slate-800">
                          <span className="text-slate-500 block text-[11px]">Engine Oil Spec</span>
                          <span className="text-slate-200 font-medium">{veh.oilSpec || 'Not specified'}</span>
                        </div>
                        <div className="p-2.5 rounded-xl bg-slate-950 border border-slate-800">
                          <span className="text-slate-500 block text-[11px]">Coolant Spec</span>
                          <span className="text-slate-200 font-medium">{veh.coolantSpec || 'Not specified'}</span>
                        </div>
                        <div className="p-2.5 rounded-xl bg-slate-950 border border-slate-800">
                          <span className="text-slate-500 block text-[11px]">Spark Plugs & Torque</span>
                          <span className="text-slate-200 font-medium">{veh.sparkPlugSpec || 'Not specified'}</span>
                        </div>
                        <div className="p-2.5 rounded-xl bg-slate-950 border border-slate-800">
                          <span className="text-slate-500 block text-[11px]">Wheel Lug Torque</span>
                          <span className="text-slate-200 font-medium">{veh.lugTorqueSpec || 'Not specified'}</span>
                        </div>
                      </div>

                      {/* Part Numbers List */}
                      {veh.partNumbers && veh.partNumbers.length > 0 && (
                        <div className="space-y-1.5">
                          <span className="text-xs font-bold text-slate-300 flex items-center gap-1.5">
                            <Tag className="w-3.5 h-3.5 text-emerald-400" />
                            Saved OEM & Aftermarket Part Numbers (Click to Copy):
                          </span>
                          <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                            {veh.partNumbers.map((pn) => (
                              <div
                                key={pn.id}
                                onClick={() => {
                                  navigator.clipboard?.writeText(pn.number);
                                  showToast(`Copied "${pn.number}"!`);
                                }}
                                className="p-2 rounded-lg bg-slate-950 border border-slate-800 hover:border-emerald-500/40 flex items-center justify-between gap-2 cursor-pointer text-xs"
                              >
                                <span className="text-slate-300 truncate">{pn.part}</span>
                                <span className="font-mono font-bold text-emerald-400 shrink-0">
                                  {pn.number}
                                </span>
                              </div>
                            ))}
                          </div>
                        </div>
                      )}

                      {/* Attached Reference Photos */}
                      {veh.photos && veh.photos.length > 0 && (
                        <div className="space-y-1.5">
                          <span className="text-xs font-bold text-slate-300 flex items-center gap-1.5">
                            <Camera className="w-3.5 h-3.5 text-purple-400" />
                            Saved Part Label / Receipt Photos:
                          </span>
                          <div className="flex flex-wrap gap-2">
                            {veh.photos.map((ph) => (
                              <button
                                key={ph.id}
                                onClick={() => setPreviewPhoto(ph)}
                                className="group relative w-16 h-16 rounded-lg overflow-hidden border border-slate-700 hover:border-emerald-400"
                              >
                                <img
                                  src={ph.dataUrl}
                                  alt={ph.label}
                                  className="w-full h-full object-cover"
                                />
                              </button>
                            ))}
                          </div>
                        </div>
                      )}

                      {veh.notes && (
                        <p className="text-xs text-slate-300 bg-slate-950/70 p-3 rounded-xl border border-slate-800/80">
                          <strong className="text-slate-100">Mechanic Notes: </strong>
                          {veh.notes}
                        </p>
                      )}
                    </div>

                    <div className="flex flex-wrap items-center justify-between gap-2 pt-3 border-t border-slate-800">
                      <div className="flex items-center gap-2">
                        {!isSelected && (
                          <button
                            onClick={() => {
                              setSelectedVehicleId(veh.id);
                              showToast(`Switched active vehicle to ${veh.year} ${veh.make} ${veh.model}`);
                            }}
                            className="px-3 py-1.5 rounded-xl text-xs font-bold bg-emerald-500 text-slate-950 hover:bg-emerald-400 transition cursor-pointer"
                          >
                            Select Active
                          </button>
                        )}
                        <button
                          onClick={() => openEditVehicleModal(veh)}
                          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 transition cursor-pointer"
                        >
                          <Edit3 className="w-3.5 h-3.5" />
                          Edit Specs, Part #s & Photos
                        </button>
                      </div>

                      {vehicles.length > 1 && (
                        <button
                          onClick={() => handleDeleteVehicle(veh.id)}
                          className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-xl text-xs text-rose-400 hover:bg-rose-500/10 transition cursor-pointer"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                          Remove
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </main>

      {/* ==========================================
          MODALS
      ========================================== */}

      {/* 1. ADD / EDIT VEHICLE MODAL (WITH PART NUMBERS & PHOTO ATTACHMENTS) */}
      {isVehicleModalOpen && (
        <VehicleModal
          vehicle={editingVehicle}
          onClose={() => setIsVehicleModalOpen(false)}
          onSave={(vehicleData) => {
            if (editingVehicle) {
              setVehicles((prev) =>
                prev.map((v) => (v.id === editingVehicle.id ? { ...v, ...vehicleData } : v))
              );
              showToast(`Updated ${vehicleData.year} ${vehicleData.make} ${vehicleData.model}!`);
            } else {
              const newVehicle = {
                ...vehicleData,
                id: `v-${Date.now()}`,
                color: 'from-emerald-600 to-cyan-700'
              };
              setVehicles((prev) => [...prev, newVehicle]);
              setSelectedVehicleId(newVehicle.id);
              showToast(`Added ${newVehicle.year} ${newVehicle.make} ${newVehicle.model} to your Garage!`);
            }
            setIsVehicleModalOpen(false);
          }}
        />
      )}

      {/* 2. QUICK ODOMETER UPDATE MODAL */}
      {isOdometerModalOpen && activeVehicle && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-sm w-full p-5 shadow-2xl space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Gauge className="w-5 h-5 text-emerald-400" />
                Update Odometer Reading
              </h3>
              <button
                onClick={() => setIsOdometerModalOpen(false)}
                className="text-slate-400 hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            <p className="text-xs text-slate-400">
              Enter current mileage for your <strong className="text-slate-200">{activeVehicle.year} {activeVehicle.make} {activeVehicle.model}</strong>. All service countdown bars will recalculate immediately:
            </p>
            <form onSubmit={handleQuickOdometerSave} className="space-y-4">
              <input
                type="number"
                required
                min="0"
                value={tempOdometer}
                onChange={(e) => setTempOdometer(e.target.value)}
                className="w-full bg-slate-950 border border-slate-700 rounded-xl px-3.5 py-2.5 text-base font-mono font-bold text-white focus:outline-none focus:border-emerald-500"
              />
              <div className="flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setIsOdometerModalOpen(false)}
                  className="px-4 py-2 rounded-xl text-xs font-medium bg-slate-800 text-slate-300 hover:bg-slate-700"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 rounded-xl text-xs font-bold bg-emerald-500 text-slate-950 hover:bg-emerald-400"
                >
                  Save Mileage
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* 3. LOG SERVICE / EXPENSE MODAL (WITH AUTO SHELF DEDUCTION & RECEIPT PHOTO) */}
      {isLogModalOpen && (
        <LogServiceModal
          initialData={editingLog}
          vehicles={vehicles}
          activeVehicleId={selectedVehicleId}
          guides={guides}
          shelf={shelf}
          onClose={() => {
            setIsLogModalOpen(false);
            setEditingLog(null);
          }}
          onSave={(logData, deductFromShelf, partsToDeduct) => {
            if (editingLog && !editingLog.isPrefill) {
              setLogs((prev) =>
                prev.map((item) => (item.id === editingLog.id ? { ...item, ...logData } : item))
              );
              showToast('Updated service record!');
            } else {
              const newEntry = {
                ...logData,
                id: `log-${Date.now()}`
              };
              setLogs((prev) => [newEntry, ...prev]);

              // Deduct used consumables from Garage Shelf if checked
              if (deductFromShelf && partsToDeduct && partsToDeduct.length > 0) {
                setShelf((prevShelf) =>
                  prevShelf.map((shelfItem) => {
                    const matchedReq = partsToDeduct.find(
                      (req) =>
                        shelfItem.name.toLowerCase().trim() === req.name.toLowerCase().trim() ||
                        shelfItem.name.toLowerCase().includes(req.name.toLowerCase().slice(0, 14))
                    );
                    if (!matchedReq) return shelfItem;
                    const nextQty = Math.max(0, Number(shelfItem.quantity) - Number(matchedReq.qty || 1));
                    return { ...shelfItem, quantity: nextQty };
                  })
                );
                showToast('Logged service & deducted used parts from your Garage Shelf!');
              } else {
                showToast('Logged service & expense record!');
              }
            }

            // Bump vehicle odometer if logged service odometer is higher
            const targetVehicle = vehicles.find((v) => v.id === logData.vehicleId);
            if (targetVehicle && Number(logData.odometer) > Number(targetVehicle.odometer)) {
              setVehicles((prev) =>
                prev.map((v) =>
                  v.id === targetVehicle.id ? { ...v, odometer: Number(logData.odometer) } : v
                )
              );
            }

            setIsLogModalOpen(false);
            setEditingLog(null);
          }}
        />
      )}

      {/* 4. ADD CUSTOM SERVICE GUIDE MODAL */}
      {isGuideModalOpen && (
        <AddGuideModal
          vehicles={vehicles}
          activeVehicleId={selectedVehicleId}
          tools={tools}
          shelf={shelf}
          onClose={() => setIsGuideModalOpen(false)}
          onSave={(newGuide) => {
            const guideObj = {
              ...newGuide,
              id: `g-custom-${Date.now()}`
            };
            setGuides((prev) => [guideObj, ...prev]);
            newGuide.requiredTools.forEach((reqName) => {
              const exists = tools.some(
                (t) => t.name.toLowerCase().trim() === reqName.toLowerCase().trim()
              );
              if (!exists) {
                setTools((prev) => [
                  ...prev,
                  {
                    id: `t-custom-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
                    name: reqName,
                    category: 'Specialty & Diagnostics',
                    owned: false,
                    loanerAvailable: false,
                    estBuyPrice: 20,
                    notes: `Required for ${newGuide.title}`
                  }
                ]);
              }
            });
            setIsGuideModalOpen(false);
            showToast(`Created custom service guide "${newGuide.title}"!`);
          }}
        />
      )}

      {/* 5. ADD / EDIT GARAGE SHELF ITEM MODAL */}
      {isShelfModalOpen && (
        <ShelfItemModal
          item={editingShelfItem}
          vehicles={vehicles}
          activeVehicleId={selectedVehicleId}
          onClose={() => {
            setIsShelfModalOpen(false);
            setEditingShelfItem(null);
          }}
          onSave={(itemData) => {
            if (editingShelfItem) {
              setShelf((prev) =>
                prev.map((s) => (s.id === editingShelfItem.id ? { ...s, ...itemData } : s))
              );
              showToast(`Updated "${itemData.name}" on Garage Shelf!`);
            } else {
              setShelf((prev) => [
                {
                  ...itemData,
                  id: `s-custom-${Date.now()}`
                },
                ...prev
              ]);
              showToast(`Added "${itemData.name}" to Garage Shelf!`);
            }
            setIsShelfModalOpen(false);
            setEditingShelfItem(null);
          }}
        />
      )}

      {/* 6. ADD CUSTOM TOOL MODAL */}
      {isToolModalOpen && (
        <AddToolModal
          onClose={() => setIsToolModalOpen(false)}
          onSave={(toolData) => {
            const newTool = {
              ...toolData,
              id: `t-custom-${Date.now()}`
            };
            setTools((prev) => [newTool, ...prev]);
            setIsToolModalOpen(false);
            showToast(`Added "${newTool.name}" to your Tool Chest!`);
          }}
        />
      )}

      {/* 7. SYSTEM JSON BACKUP & RESTORE MODAL */}
      {isBackupModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-5 sm:p-6 shadow-2xl space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-slate-800">
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Database className="w-5 h-5 text-emerald-400" />
                Full System Backup & Restore (JSON)
              </h3>
              <button
                onClick={() => setIsBackupModalOpen(false)}
                className="text-slate-400 hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <p className="text-xs text-slate-300 leading-relaxed">
              Export your entire garage—including all vehicles, part numbers, photos, custom tools, shelf consumables, and service logs—to a single JSON file, or restore from a previous backup.
            </p>

            <div className="space-y-3 pt-1">
              <button
                onClick={handleExportFullJSON}
                className="w-full py-2.5 px-4 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 flex items-center justify-center gap-2 transition cursor-pointer"
              >
                <Download className="w-4 h-4" />
                Download Full Garage Backup (.JSON)
              </button>

              <label className="w-full py-2.5 px-4 rounded-xl text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 flex items-center justify-center gap-2 transition cursor-pointer">
                <Upload className="w-4 h-4 text-emerald-400" />
                Restore from JSON Backup File
                <input
                  type="file"
                  accept=".json,application/json"
                  onChange={(e) => handleImportFullJSON(e.target.files?.[0])}
                  className="hidden"
                />
              </label>
            </div>

            <div className="flex justify-end pt-2 border-t border-slate-800">
              <button
                onClick={() => setIsBackupModalOpen(false)}
                className="px-4 py-1.5 rounded-xl text-xs font-medium bg-slate-800 text-slate-300 hover:bg-slate-700"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 8. CONFIRM RESET DEMO DATA MODAL */}
      {confirmResetOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-5 shadow-2xl space-y-4">
            <div className="flex items-center gap-2 text-amber-400">
              <AlertTriangle className="w-5 h-5" />
              <h3 className="text-base font-bold text-white">Reset to Default Demo Data?</h3>
            </div>
            <p className="text-xs text-slate-300 leading-relaxed">
              This will restore the default vehicles (2017 VW Jetta TSI & 2021 Toyota Highlander), sample service history, shelf stock, and 14+ DIY service guides.
            </p>
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setConfirmResetOpen(false)}
                className="px-4 py-2 rounded-xl text-xs font-medium bg-slate-800 text-slate-300 hover:bg-slate-700"
              >
                Cancel
              </button>
              <button
                onClick={handleResetDemoData}
                className="px-4 py-2 rounded-xl text-xs font-bold bg-amber-500 text-slate-950 hover:bg-amber-400"
              >
                Yes, Reset Demo Data
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 9. SUPABASE CLOUD SYNC & PHONE INSTALL MODAL */}
      {isPhoneModalOpen && (
        <PhoneSyncModal
          supabaseUrl={supabaseUrl}
          supabaseAnonKey={supabaseAnonKey}
          syncRoomCode={syncRoomCode}
          onSaveConfig={(newUrl, newKey, newCode) => {
            setSupabaseUrl(newUrl.trim());
            setSupabaseAnonKey(newKey.trim());
            setSyncRoomCode(newCode.trim().toUpperCase() || 'JETTA-GARAGE-1');
            showToast('Saved Supabase Cloud Sync settings!');
          }}
          onDisconnectSupabase={() => {
            setSupabaseUrl('');
            setSupabaseAnonKey('');
            setCloudStatus('local-only');
            setCloudErrorMsg('');
            showToast('Switched to Local-Only Storage mode.');
          }}
          onManualPull={() => handleManualPullFromSupabase(false)}
          onManualPush={() => handleManualPushToSupabase(false)}
          cloudStatus={cloudStatus}
          cloudErrorMsg={cloudErrorMsg}
          lastSyncedAt={lastSyncedAt}
          clientId={clientId}
          onClose={() => setIsPhoneModalOpen(false)}
          onOpenBackup={() => {
            setIsPhoneModalOpen(false);
            setIsBackupModalOpen(true);
          }}
        />
      )}

      {/* ==========================================
          MOBILE BOTTOM NAVIGATION BAR (THUMB-FRIENDLY GARAGE MODE)
      ========================================== */}
      <nav className="md:hidden fixed bottom-0 inset-x-0 z-40 bg-slate-900/95 backdrop-blur-lg border-t border-slate-800 px-2 py-1.5 flex items-center justify-around shadow-2xl">
        <button
          onClick={() => setActiveTab('dashboard')}
          className={`flex flex-col items-center justify-center py-1 px-2.5 rounded-xl transition ${
            activeTab === 'dashboard' ? 'text-emerald-400' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <ClipboardList className="w-5 h-5" />
          <span className="text-[10px] font-semibold mt-0.5">Ledger</span>
        </button>

        <button
          onClick={() => setActiveTab('guides')}
          className={`flex flex-col items-center justify-center py-1 px-2.5 rounded-xl transition relative ${
            activeTab === 'guides' ? 'text-emerald-400' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <BookOpen className="w-5 h-5" />
          <span className="text-[10px] font-semibold mt-0.5">Guides</span>
        </button>

        <button
          onClick={() => setActiveTab('tools')}
          className={`flex flex-col items-center justify-center py-1 px-2.5 rounded-xl transition ${
            activeTab === 'tools' ? 'text-emerald-400' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <Wrench className="w-5 h-5" />
          <span className="text-[10px] font-semibold mt-0.5">
            Tools ({ownedToolsCount})
          </span>
        </button>

        <button
          onClick={() => setActiveTab('shelf')}
          className={`flex flex-col items-center justify-center py-1 px-2.5 rounded-xl transition ${
            activeTab === 'shelf' ? 'text-emerald-400' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <Package className="w-5 h-5" />
          <span className="text-[10px] font-semibold mt-0.5">
            Shelf ({totalShelfItems})
          </span>
        </button>

        <button
          onClick={() => setActiveTab('garage')}
          className={`flex flex-col items-center justify-center py-1 px-2.5 rounded-xl transition ${
            activeTab === 'garage' ? 'text-emerald-400' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <Car className="w-5 h-5" />
          <span className="text-[10px] font-semibold mt-0.5">Garage</span>
        </button>
      </nav>
    </div>
  );
}

// ==========================================
// SUB-COMPONENT: SUPABASE CLOUD SYNC & PHONE SETUP MODAL
// ==========================================

function PhoneSyncModal({
  supabaseUrl,
  supabaseAnonKey,
  syncRoomCode,
  onSaveConfig,
  onDisconnectSupabase,
  onManualPull,
  onManualPush,
  cloudStatus,
  cloudErrorMsg,
  lastSyncedAt,
  clientId,
  onClose,
  onOpenBackup
}) {
  const [urlInput, setUrlInput] = useState(supabaseUrl || '');
  const [keyInput, setKeyInput] = useState(supabaseAnonKey || '');
  const [codeInput, setCodeInput] = useState(syncRoomCode || 'JETTA-GARAGE-1');
  const [showSql, setShowSql] = useState(false);
  const [copiedSql, setCopiedSql] = useState(false);
  const [copiedCode, setCopiedCode] = useState(false);

  const handleSave = (e) => {
    e.preventDefault();
    const cleanedCode = codeInput.trim().toUpperCase().replace(/[^A-Z0-9_-]/g, '-');
    setCodeInput(cleanedCode || 'JETTA-GARAGE-1');
    onSaveConfig(urlInput, keyInput, cleanedCode || 'JETTA-GARAGE-1');
  };

  const handleCopySql = () => {
    navigator.clipboard?.writeText(SUPABASE_SETUP_SQL);
    setCopiedSql(true);
    setTimeout(() => setCopiedSql(false), 2500);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/85 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-2xl w-full p-5 sm:p-6 shadow-2xl my-8 space-y-5 max-h-[92vh] overflow-y-auto">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800">
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-xl bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
              <Database className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base sm:text-lg font-bold text-white">
                Supabase Real-Time Cloud Sync & Phone Setup
              </h3>
              <p className="text-xs text-slate-400">
                Plug in your own free Supabase URL & Anon Key so your phone and computer stay in lockstep
              </p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Status Bar */}
        <div className="p-3.5 rounded-2xl bg-slate-950 border border-slate-800 flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            {cloudStatus === 'synced' ? (
              <span className="inline-flex items-center gap-1.5 text-xs font-bold text-emerald-400">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
                Connected to Supabase • Live Sync Active
              </span>
            ) : cloudStatus === 'syncing' || cloudStatus === 'connecting' ? (
              <span className="inline-flex items-center gap-1.5 text-xs font-bold text-amber-400">
                <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                Syncing with Supabase...
              </span>
            ) : cloudStatus === 'error' ? (
              <span className="inline-flex items-center gap-1.5 text-xs font-bold text-rose-400">
                <AlertTriangle className="w-4 h-4" />
                Connection Error (Check URL, Key & SQL Table)
              </span>
            ) : (
              <span className="inline-flex items-center gap-1.5 text-xs font-bold text-slate-300">
                <CloudOff className="w-4 h-4 text-slate-400" />
                Local Browser Storage Mode (Paste Supabase Keys Below to Enable Cloud Sync)
              </span>
            )}
          </div>

          <div className="flex items-center gap-2">
            {lastSyncedAt && (
              <span className="text-[11px] text-slate-400 font-mono">
                Synced: {lastSyncedAt}
              </span>
            )}
            {supabaseUrl && supabaseAnonKey && (
              <>
                <button
                  type="button"
                  onClick={onManualPull}
                  className="px-2.5 py-1 rounded-lg text-[11px] font-semibold bg-slate-800 hover:bg-slate-700 text-emerald-300 border border-slate-700 cursor-pointer"
                >
                  Pull Now
                </button>
                <button
                  type="button"
                  onClick={onManualPush}
                  className="px-2.5 py-1 rounded-lg text-[11px] font-semibold bg-slate-800 hover:bg-slate-700 text-cyan-300 border border-slate-700 cursor-pointer"
                >
                  Push Now
                </button>
              </>
            )}
          </div>
        </div>

        {cloudErrorMsg && (
          <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/30 text-xs text-rose-200 font-mono break-all">
            {cloudErrorMsg}
          </div>
        )}

        {/* Step 1: 1-Click SQL Setup Script */}
        <div className="p-4 rounded-2xl bg-slate-950 border border-slate-800 space-y-2.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <span className="text-xs font-bold text-emerald-400 uppercase tracking-wider block">
                Step 1: Create the Table in Your Supabase Project (One-Time)
              </span>
              <p className="text-xs text-slate-400">
                In your Supabase Dashboard, open <strong>SQL Editor</strong>, paste this script, and click <strong>Run</strong>.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setShowSql(!showSql)}
                className="px-2.5 py-1.5 rounded-xl text-xs font-medium bg-slate-900 hover:bg-slate-800 text-slate-300 border border-slate-700 cursor-pointer"
              >
                {showSql ? 'Hide SQL' : 'View SQL'}
              </button>
              <button
                type="button"
                onClick={handleCopySql}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 border border-emerald-500/40 cursor-pointer"
              >
                <Copy className="w-3.5 h-3.5" />
                {copiedSql ? 'Copied SQL to Clipboard!' : 'Copy SQL Setup Script'}
              </button>
            </div>
          </div>

          {showSql && (
            <pre className="p-3 rounded-xl bg-slate-900 border border-slate-800 text-[11px] font-mono text-emerald-300 overflow-x-auto leading-relaxed">
              {SUPABASE_SETUP_SQL}
            </pre>
          )}
        </div>

        {/* Step 2: Paste Supabase Project URL, Anon Key & Garage Sync Code */}
        <form onSubmit={handleSave} className="p-4 rounded-2xl bg-slate-950 border border-slate-800 space-y-3.5">
          <span className="text-xs font-bold text-emerald-400 uppercase tracking-wider block">
            Step 2: Enter Your Supabase Credentials & Garage Sync Code
          </span>
          <p className="text-xs text-slate-400">
            Found in Supabase under <strong>Project Settings → API</strong>. Saved securely in your browser&apos;s local storage (or hardcode them at the top of <code className="text-slate-200">App.jsx</code>).
          </p>

          <div className="space-y-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Supabase Project URL
              </label>
              <input
                type="url"
                placeholder="https://your-project-id.supabase.co"
                value={urlInput}
                onChange={(e) => setUrlInput(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs font-mono text-white focus:outline-none focus:border-emerald-500"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Supabase Anon / Public API Key
              </label>
              <input
                type="password"
                placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
                value={keyInput}
                onChange={(e) => setKeyInput(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs font-mono text-white focus:outline-none focus:border-emerald-500"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Shared Garage Sync Code (Use this same code on your Phone & Computer)
              </label>
              <div className="flex gap-2">
                <div className="relative flex-1">
                  <KeyRound className="w-4 h-4 text-emerald-400 absolute left-3 top-1/2 -translate-y-1/2" />
                  <input
                    type="text"
                    required
                    value={codeInput}
                    onChange={(e) => setCodeInput(e.target.value.toUpperCase())}
                    placeholder="JETTA-GARAGE-1"
                    className="w-full bg-slate-900 border border-slate-700 rounded-xl pl-9 pr-3 py-2 text-xs font-mono font-bold text-emerald-300 focus:outline-none focus:border-emerald-500"
                  />
                </div>
                <button
                  type="button"
                  onClick={() => {
                    navigator.clipboard?.writeText(codeInput);
                    setCopiedCode(true);
                    setTimeout(() => setCopiedCode(false), 2000);
                  }}
                  className="px-3 py-2 rounded-xl text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 cursor-pointer flex items-center gap-1"
                >
                  <Copy className="w-3.5 h-3.5" />
                  {copiedCode ? 'Copied' : 'Copy Code'}
                </button>
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 pt-2">
            {supabaseUrl && (
              <button
                type="button"
                onClick={onDisconnectSupabase}
                className="text-xs text-rose-400 hover:text-rose-300 underline cursor-pointer"
              >
                Disconnect Supabase (Use Local-Only)
              </button>
            )}
            <button
              type="submit"
              className="ml-auto px-5 py-2 rounded-xl text-xs font-bold bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-lg shadow-emerald-950/50 transition cursor-pointer"
            >
              Save & Connect Supabase
            </button>
          </div>
        </form>

        {/* Step 3: Install on Phone Home Screen */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
          <div className="p-3.5 rounded-xl bg-slate-950 border border-slate-800 space-y-1">
            <strong className="text-white block">Android / Galaxy Home Screen App</strong>
            <p className="text-slate-400 leading-relaxed">
              Open your deployed URL in Chrome → Tap <strong>⋮</strong> → <strong>Add to Home screen</strong> → Enter your Supabase URL, Key & Sync Code (<code className="text-emerald-400">{codeInput}</code>).
            </p>
          </div>
          <div className="p-3.5 rounded-xl bg-slate-950 border border-slate-800 space-y-1">
            <strong className="text-white block">iPhone / iOS Safari Home Screen</strong>
            <p className="text-slate-400 leading-relaxed">
              Open in Safari → Tap <strong>Share</strong> → <strong>Add to Home Screen</strong> → Enter the same Supabase credentials & Sync Code (<code className="text-emerald-400">{codeInput}</code>).
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-slate-800">
          <button
            type="button"
            onClick={onOpenBackup}
            className="text-xs text-slate-400 hover:text-emerald-400 underline cursor-pointer"
          >
            Or export/import a manual JSON Backup file ({clientId})
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-1.5 rounded-xl text-xs font-semibold bg-slate-800 text-slate-200 hover:bg-slate-700 cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}

// ==========================================
// SUB-COMPONENT: ADD / EDIT VEHICLE MODAL
// ==========================================

function VehicleModal({ vehicle, onClose, onSave }) {
  const [year, setYear] = useState(vehicle?.year || new Date().getFullYear());
  const [make, setMake] = useState(vehicle?.make || '');
  const [model, setModel] = useState(vehicle?.model || '');
  const [trim, setTrim] = useState(vehicle?.trim || '');
  const [odometer, setOdometer] = useState(vehicle?.odometer ?? '');
  const [vinPlate, setVinPlate] = useState(vehicle?.vinPlate || '');
  const [oilSpec, setOilSpec] = useState(vehicle?.oilSpec || '');
  const [coolantSpec, setCoolantSpec] = useState(vehicle?.coolantSpec || '');
  const [sparkPlugSpec, setSparkPlugSpec] = useState(vehicle?.sparkPlugSpec || '');
  const [lugTorqueSpec, setLugTorqueSpec] = useState(vehicle?.lugTorqueSpec || '');
  const [wiperSizes, setWiperSizes] = useState(vehicle?.wiperSizes || '');
  const [notes, setNotes] = useState(vehicle?.notes || '');
  const [partNumbers, setPartNumbers] = useState(vehicle?.partNumbers || []);
  const [photos, setPhotos] = useState(vehicle?.photos || []);

  // New Part Number inputs
  const [newPartLabel, setNewPartLabel] = useState('');
  const [newPartNum, setNewPartNum] = useState('');
  const [newPartVendor, setNewPartVendor] = useState('');

  const handleAddPartNumber = () => {
    if (!newPartLabel.trim() || !newPartNum.trim()) return;
    setPartNumbers((prev) => [
      ...prev,
      {
        id: `pn-${Date.now()}`,
        part: newPartLabel.trim(),
        number: newPartNum.trim(),
        vendor: newPartVendor.trim() || 'OEM / Aftermarket'
      }
    ]);
    setNewPartLabel('');
    setNewPartNum('');
    setNewPartVendor('');
  };

  const handlePhotoUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const compressedDataUrl = await compressImageFile(file);
    if (compressedDataUrl) {
      setPhotos((prev) => [
        ...prev,
        {
          id: `ph-${Date.now()}`,
          label: file.name,
          dataUrl: compressedDataUrl
        }
      ]);
    }
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!make.trim() || !model.trim()) return;
    onSave({
      year: Number(year) || 2020,
      make: make.trim(),
      model: model.trim(),
      trim: trim.trim() || 'Base',
      odometer: Number(odometer) || 0,
      vinPlate: vinPlate.trim(),
      oilSpec: oilSpec.trim(),
      coolantSpec: coolantSpec.trim(),
      sparkPlugSpec: sparkPlugSpec.trim(),
      lugTorqueSpec: lugTorqueSpec.trim(),
      wiperSizes: wiperSizes.trim(),
      notes: notes.trim(),
      partNumbers,
      photos
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-2xl w-full p-5 sm:p-6 shadow-2xl my-8 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800">
          <h3 className="text-base sm:text-lg font-bold text-white flex items-center gap-2">
            <Car className="w-5 h-5 text-emerald-400" />
            {vehicle ? `Edit ${vehicle.year} ${vehicle.make} ${vehicle.model}` : 'Add New Vehicle to Garage'}
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 mt-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Year *</label>
              <input
                type="number"
                required
                min="1950"
                max="2030"
                value={year}
                onChange={(e) => setYear(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-emerald-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Make *</label>
              <input
                type="text"
                required
                placeholder="e.g. Volkswagen, Toyota"
                value={make}
                onChange={(e) => setMake(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-emerald-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Model *</label>
              <input
                type="text"
                required
                placeholder="e.g. Jetta, Highlander"
                value={model}
                onChange={(e) => setModel(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-emerald-500"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Trim / Engine</label>
              <input
                type="text"
                placeholder="e.g. TSI 1.8L Turbo"
                value={trim}
                onChange={(e) => setTrim(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-emerald-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Current Odometer (mi) *</label>
              <input
                type="number"
                required
                min="0"
                value={odometer}
                onChange={(e) => setOdometer(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white focus:outline-none focus:border-emerald-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">License Plate / VIN</label>
              <input
                type="text"
                value={vinPlate}
                onChange={(e) => setVinPlate(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white focus:outline-none focus:border-emerald-500"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2 border-t border-slate-800/80">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Engine Oil Spec & Capacity</label>
              <input
                type="text"
                placeholder="e.g. MAG 1 SAE 5W-30 Full Synthetic (5.7 qt)"
                value={oilSpec}
                onChange={(e) => setOilSpec(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Coolant / Antifreeze Spec</label>
              <input
                type="text"
                placeholder="e.g. Peak European Violet G12++/G13 50/50"
                value={coolantSpec}
                onChange={(e) => setCoolantSpec(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Spark Plug Socket & Torque</label>
              <input
                type="text"
                placeholder='e.g. NGK Laser Platinum (5/8" socket, 22 lb-ft)'
                value={sparkPlugSpec}
                onChange={(e) => setSparkPlugSpec(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Wheel Lug Torque & Socket</label>
              <input
                type="text"
                placeholder="e.g. 89 lb-ft (17mm Lug Bolts)"
                value={lugTorqueSpec}
                onChange={(e) => setLugTorqueSpec(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
          </div>

          {/* Store-Aisle Part Numbers Builder */}
          <div className="pt-2 border-t border-slate-800/80 space-y-2">
            <label className="block text-xs font-bold text-emerald-400">
              Store-Aisle OEM & Aftermarket Part Numbers
            </label>
            <div className="space-y-1.5 max-h-32 overflow-y-auto">
              {partNumbers.map((pn) => (
                <div
                  key={pn.id}
                  className="flex items-center justify-between px-3 py-1.5 rounded-lg bg-slate-950 border border-slate-800 text-xs"
                >
                  <span>
                    <strong className="text-slate-200">{pn.part}:</strong>{' '}
                    <span className="font-mono text-emerald-400">{pn.number}</span>{' '}
                    <span className="text-slate-500">({pn.vendor})</span>
                  </span>
                  <button
                    type="button"
                    onClick={() => setPartNumbers((prev) => prev.filter((item) => item.id !== pn.id))}
                    className="text-slate-500 hover:text-rose-400"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                </div>
              ))}
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-7 gap-2">
              <input
                type="text"
                placeholder="Part (e.g. Oil Filter)"
                value={newPartLabel}
                onChange={(e) => setNewPartLabel(e.target.value)}
                className="sm:col-span-2 bg-slate-950 border border-slate-800 rounded-xl px-2.5 py-1.5 text-xs text-white"
              />
              <input
                type="text"
                placeholder="Part # (e.g. Mann HU 7020 z)"
                value={newPartNum}
                onChange={(e) => setNewPartNum(e.target.value)}
                className="sm:col-span-2 bg-slate-950 border border-slate-800 rounded-xl px-2.5 py-1.5 text-xs font-mono text-white"
              />
              <input
                type="text"
                placeholder="Brand / Store"
                value={newPartVendor}
                onChange={(e) => setNewPartVendor(e.target.value)}
                className="sm:col-span-2 bg-slate-950 border border-slate-800 rounded-xl px-2.5 py-1.5 text-xs text-white"
              />
              <button
                type="button"
                onClick={handleAddPartNumber}
                className="px-3 py-1.5 rounded-xl text-xs font-bold bg-slate-800 hover:bg-slate-700 text-emerald-400"
              >
                + Add
              </button>
            </div>
          </div>

          {/* Photo Reference Upload */}
          <div className="pt-2 border-t border-slate-800/80 space-y-2">
            <div className="flex items-center justify-between">
              <label className="block text-xs font-medium text-slate-300">
                Attach Part Box / Label / VIN Sticker Photos
              </label>
              <label className="inline-flex items-center gap-1.5 px-3 py-1 rounded-lg text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-purple-300 cursor-pointer">
                <Camera className="w-3.5 h-3.5" />
                Upload Photo
                <input type="file" accept="image/*" onChange={handlePhotoUpload} className="hidden" />
              </label>
            </div>
            {photos.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {photos.map((ph) => (
                  <div key={ph.id} className="relative w-14 h-14 rounded-lg overflow-hidden border border-slate-700">
                    <img src={ph.dataUrl} alt={ph.label} className="w-full h-full object-cover" />
                    <button
                      type="button"
                      onClick={() => setPhotos((prev) => prev.filter((item) => item.id !== ph.id))}
                      className="absolute top-0.5 right-0.5 bg-slate-950/80 text-rose-400 rounded-full p-0.5"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">
              Mechanic Notes (Fasteners, bulb sizes, torque specs)
            </label>
            <textarea
              rows={2}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="flex justify-end gap-2 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-xs font-medium bg-slate-800 text-slate-300 hover:bg-slate-700"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-5 py-2 rounded-xl text-xs font-bold bg-emerald-500 text-slate-950 hover:bg-emerald-400"
            >
              {vehicle ? 'Save Vehicle Changes' : 'Add Vehicle to Garage'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ==========================================
// SUB-COMPONENT: LOG SERVICE / EXPENSE MODAL
// ==========================================

function LogServiceModal({ initialData, vehicles, activeVehicleId, guides, shelf, onClose, onSave }) {
  const [vehicleId, setVehicleId] = useState(initialData?.vehicleId || activeVehicleId);
  const [guideId, setGuideId] = useState(initialData?.guideId || '');
  const [date, setDate] = useState(initialData?.date || new Date().toISOString().split('T')[0]);
  const [odometer, setOdometer] = useState(() => {
    if (initialData?.odometer !== undefined) return initialData.odometer;
    const v = vehicles.find((veh) => veh.id === (initialData?.vehicleId || activeVehicleId));
    return v ? v.odometer : 0;
  });
  const [serviceType, setServiceType] = useState(initialData?.serviceType || '');
  const [category, setCategory] = useState(initialData?.category || 'Maintenance');
  const [performedBy, setPerformedBy] = useState(initialData?.performedBy || 'DIY');
  const [cost, setCost] = useState(initialData?.cost ?? '');
  const [estimatedShopSavings, setEstimatedShopSavings] = useState(
    initialData?.estimatedShopSavings ?? 65
  );
  const [partsUsed, setPartsUsed] = useState(initialData?.partsUsed || '');
  const [notes, setNotes] = useState(initialData?.notes || '');
  const [receiptPhoto, setReceiptPhoto] = useState(initialData?.receiptPhoto || null);
  const [deductFromShelf, setDeductFromShelf] = useState(true);
  const [requiredPartsToDeduct, setRequiredPartsToDeduct] = useState(
    initialData?.requiredPartsToDeduct || []
  );

  const handleSelectGuideTemplate = (selectedGuideId) => {
    setGuideId(selectedGuideId);
    const found = guides.find((g) => g.id === selectedGuideId);
    if (found) {
      setServiceType(found.title);
      setCategory(found.category || 'Maintenance');
      setCost(found.estimatedDiyCost || '');
      setEstimatedShopSavings(
        Math.max(0, (found.estimatedShopCost || 0) - (found.estimatedDiyCost || 0))
      );
      setRequiredPartsToDeduct(found.requiredParts || []);
      if (found.requiredParts && found.requiredParts.length > 0) {
        setPartsUsed(found.requiredParts.map((p) => `${p.qty}x ${p.name}`).join(', '));
      }
    } else {
      setRequiredPartsToDeduct([]);
    }
  };

  const handleReceiptPhotoChange = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const compressedDataUrl = await compressImageFile(file);
    if (compressedDataUrl) {
      setReceiptPhoto(compressedDataUrl);
    }
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!serviceType.trim()) return;
    onSave(
      {
        vehicleId,
        guideId: guideId || null,
        date,
        odometer: Number(odometer) || 0,
        serviceType: serviceType.trim(),
        category,
        performedBy,
        cost: Number(cost) || 0,
        estimatedShopSavings: performedBy === 'DIY' ? Number(estimatedShopSavings) || 0 : 0,
        partsUsed: partsUsed.trim(),
        notes: notes.trim(),
        receiptPhoto
      },
      deductFromShelf,
      requiredPartsToDeduct
    );
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-xl w-full p-5 sm:p-6 shadow-2xl my-8">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800">
          <h3 className="text-base sm:text-lg font-bold text-white flex items-center gap-2">
            <ClipboardList className="w-5 h-5 text-emerald-400" />
            {initialData && !initialData.isPrefill ? 'Edit Service Record' : 'Complete & Log Vehicle Service'}
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 mt-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Vehicle *</label>
              <select
                value={vehicleId}
                onChange={(e) => {
                  setVehicleId(e.target.value);
                  const veh = vehicles.find((v) => v.id === e.target.value);
                  if (veh) setOdometer(veh.odometer);
                }}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                {vehicles.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.year} {v.make} {v.model}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Pre-Fill from DIY Guide
              </label>
              <select
                value={guideId}
                onChange={(e) => handleSelectGuideTemplate(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-emerald-300"
              >
                <option value="">-- Custom Service Entry --</option>
                {guides
                  .filter((g) => g.vehicleId === vehicleId || g.vehicleId === 'ALL')
                  .map((g) => (
                    <option key={g.id} value={g.id}>
                      {g.title}
                    </option>
                  ))}
              </select>
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">
              Service Title / Description *
            </label>
            <input
              type="text"
              required
              value={serviceType}
              onChange={(e) => setServiceType(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Date *</label>
              <input
                type="date"
                required
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Odometer (mi) *</label>
              <input
                type="number"
                required
                min="0"
                value={odometer}
                onChange={(e) => setOdometer(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Category</label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                {SERVICE_CATEGORIES.map((cat) => (
                  <option key={cat} value={cat}>
                    {cat}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Performed By</label>
              <div className="grid grid-cols-2 gap-1.5 bg-slate-950 p-1 rounded-xl border border-slate-800">
                <button
                  type="button"
                  onClick={() => setPerformedBy('DIY')}
                  className={`py-1.5 rounded-lg text-xs font-bold transition ${
                    performedBy === 'DIY'
                      ? 'bg-emerald-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  DIY
                </button>
                <button
                  type="button"
                  onClick={() => setPerformedBy('Shop')}
                  className={`py-1.5 rounded-lg text-xs font-bold transition ${
                    performedBy === 'Shop'
                      ? 'bg-blue-500 text-slate-950'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Shop
                </button>
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Total Cost ($) *</label>
              <input
                type="number"
                step="0.01"
                required
                min="0"
                placeholder="42.50"
                value={cost}
                onChange={(e) => setCost(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white"
              />
            </div>

            {performedBy === 'DIY' && (
              <div>
                <label className="block text-xs font-medium text-emerald-400 mb-1">
                  Est. Shop Labor Saved ($)
                </label>
                <input
                  type="number"
                  step="1"
                  min="0"
                  value={estimatedShopSavings}
                  onChange={(e) => setEstimatedShopSavings(e.target.value)}
                  className="w-full bg-slate-950 border border-emerald-500/30 rounded-xl px-3 py-2 text-xs font-mono text-emerald-300"
                />
              </div>
            )}
          </div>

          {/* Automatic Shelf Deduction Option */}
          {requiredPartsToDeduct && requiredPartsToDeduct.length > 0 && (
            <div className="p-3 rounded-xl bg-cyan-500/10 border border-cyan-500/30 flex items-start gap-2.5">
              <input
                type="checkbox"
                id="deductShelfCheck"
                checked={deductFromShelf}
                onChange={(e) => setDeductFromShelf(e.target.checked)}
                className="mt-0.5 rounded accent-emerald-500"
              />
              <label htmlFor="deductShelfCheck" className="text-xs text-cyan-200 cursor-pointer">
                <strong className="block text-cyan-300">
                  Auto-Deduct Consumables from Garage Shelf Inventory
                </strong>
                Deducts:{' '}
                {requiredPartsToDeduct.map((p) => `${p.qty}x ${p.name}`).join(', ')}
              </label>
            </div>
          )}

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">
              Parts & Fluids Used
            </label>
            <input
              type="text"
              placeholder="e.g. MAG 1 5W-30 Full Synthetic, Mann HU 7020 z Filter"
              value={partsUsed}
              onChange={(e) => setPartsUsed(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="flex items-center justify-between gap-2">
            <label className="text-xs font-medium text-slate-300">
              Receipt / Part Box Photo (Optional)
            </label>
            <label className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-purple-300 cursor-pointer">
              <Camera className="w-3.5 h-3.5" />
              {receiptPhoto ? 'Change Photo' : 'Attach Photo'}
              <input type="file" accept="image/*" onChange={handleReceiptPhotoChange} className="hidden" />
            </label>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Service Notes</label>
            <textarea
              rows={2}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="flex justify-end gap-2 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-xs font-medium bg-slate-800 text-slate-300 hover:bg-slate-700"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-5 py-2 rounded-xl text-xs font-bold bg-emerald-500 text-slate-950 hover:bg-emerald-400"
            >
              Save Service Record
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ==========================================
// SUB-COMPONENT: ADD / EDIT GARAGE SHELF MODAL
// ==========================================

function ShelfItemModal({ item, vehicles, activeVehicleId, onClose, onSave }) {
  const [name, setName] = useState(item?.name || '');
  const [category, setCategory] = useState(item?.category || SHELF_CATEGORIES[0]);
  const [vehicleId, setVehicleId] = useState(item?.vehicleId || activeVehicleId || 'ALL');
  const [partNumber, setPartNumber] = useState(item?.partNumber || '');
  const [quantity, setQuantity] = useState(item?.quantity ?? 1);
  const [minQuantity, setMinQuantity] = useState(item?.minQuantity ?? 1);
  const [unit, setUnit] = useState(item?.unit || 'units');
  const [unitCost, setUnitCost] = useState(item?.unitCost ?? '');
  const [notes, setNotes] = useState(item?.notes || '');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!name.trim()) return;
    onSave({
      name: name.trim(),
      category,
      vehicleId,
      partNumber: partNumber.trim(),
      quantity: Number(quantity) || 0,
      minQuantity: Number(minQuantity) || 1,
      unit: unit.trim() || 'units',
      unitCost: Number(unitCost) || 0,
      notes: notes.trim()
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-5 shadow-2xl space-y-4">
        <div className="flex items-center justify-between pb-2 border-b border-slate-800">
          <h3 className="text-base font-bold text-white flex items-center gap-2">
            <Package className="w-5 h-5 text-cyan-400" />
            {item ? 'Edit Garage Shelf Item' : 'Add Part / Fluid to Garage Shelf'}
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-3.5">
          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">
              Part / Fluid Name *
            </label>
            <input
              type="text"
              required
              placeholder="e.g. MAG 1 SAE 5W-30 Full Synthetic or 2825 Bulb"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Category</label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                {SHELF_CATEGORIES.map((cat) => (
                  <option key={cat} value={cat}>
                    {cat}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">For Vehicle</label>
              <select
                value={vehicleId}
                onChange={(e) => setVehicleId(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                <option value="ALL">Universal / All</option>
                {vehicles.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.year} {v.model}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-2.5">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Qty on Shelf</label>
              <input
                type="number"
                min="0"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Min Target</label>
              <input
                type="number"
                min="0"
                value={minQuantity}
                onChange={(e) => setMinQuantity(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Unit</label>
              <input
                type="text"
                placeholder="quarts, bulbs"
                value={unit}
                onChange={(e) => setUnit(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Part Number</label>
              <input
                type="text"
                placeholder="e.g. Mann HU 7020 z"
                value={partNumber}
                onChange={(e) => setPartNumber(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Unit Cost ($)</label>
              <input
                type="number"
                step="0.01"
                placeholder="6.49"
                value={unitCost}
                onChange={(e) => setUnitCost(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Notes</label>
            <input
              type="text"
              placeholder="Shelf location or specs"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-xs font-medium bg-slate-800 text-slate-300"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-5 py-2 rounded-xl text-xs font-bold bg-emerald-500 text-slate-950"
            >
              Save Shelf Item
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ==========================================
// SUB-COMPONENT: ADD CUSTOM SERVICE GUIDE MODAL
// ==========================================

function AddGuideModal({ vehicles, activeVehicleId, tools, onClose, onSave }) {
  const [title, setTitle] = useState('');
  const [vehicleId, setVehicleId] = useState(activeVehicleId || 'ALL');
  const [category, setCategory] = useState('Maintenance');
  const [intervalMiles, setIntervalMiles] = useState(30000);
  const [intervalMonths, setIntervalMonths] = useState(24);
  const [difficulty, setDifficulty] = useState('Moderate');
  const [estimatedTime, setEstimatedTime] = useState('45 mins');
  const [estimatedDiyCost, setEstimatedDiyCost] = useState(45);
  const [estimatedShopCost, setEstimatedShopCost] = useState(160);
  const [specsAndAdvice, setSpecsAndAdvice] = useState('');
  const [selectedTools, setSelectedTools] = useState([
    '3/8" Drive Ratchet & Extensions',
    'Metric Socket Set (8mm - 19mm)'
  ]);
  const [customToolInput, setCustomToolInput] = useState('');

  const toggleSelectedTool = (toolName) => {
    setSelectedTools((prev) =>
      prev.includes(toolName) ? prev.filter((t) => t !== toolName) : [...prev, toolName]
    );
  };

  const handleAddCustomToolRequirement = () => {
    const trimmed = customToolInput.trim();
    if (!trimmed) return;
    if (!selectedTools.includes(trimmed)) {
      setSelectedTools((prev) => [...prev, trimmed]);
    }
    setCustomToolInput('');
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!title.trim()) return;
    onSave({
      title: title.trim(),
      vehicleId,
      category,
      intervalMiles: Number(intervalMiles) || 15000,
      intervalMonths: Number(intervalMonths) || 12,
      difficulty,
      estimatedTime: estimatedTime.trim() || '30 mins',
      estimatedDiyCost: Number(estimatedDiyCost) || 0,
      estimatedShopCost: Number(estimatedShopCost) || 0,
      requiredTools: selectedTools,
      requiredParts: [],
      specsAndAdvice:
        specsAndAdvice.trim() || 'Follow factory torque specifications and safety procedures.'
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-2xl w-full p-5 sm:p-6 shadow-2xl my-8">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800">
          <h3 className="text-base sm:text-lg font-bold text-white flex items-center gap-2">
            <BookOpen className="w-5 h-5 text-emerald-400" />
            Create Custom DIY Service Guide & Tool Checklist
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 mt-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Service Job Title *
              </label>
              <input
                type="text"
                required
                placeholder="e.g. Haldex / AWD Rear Differential Fluid Service"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Applies To</label>
              <select
                value={vehicleId}
                onChange={(e) => setVehicleId(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                <option value="ALL">Universal (All Garage Vehicles)</option>
                {vehicles.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.year} {v.make} {v.model}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Interval (Miles)</label>
              <input
                type="number"
                value={intervalMiles}
                onChange={(e) => setIntervalMiles(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Interval (Months)</label>
              <input
                type="number"
                value={intervalMonths}
                onChange={(e) => setIntervalMonths(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Difficulty</label>
              <select
                value={difficulty}
                onChange={(e) => setDifficulty(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                <option value="Easy">Easy</option>
                <option value="Moderate">Moderate</option>
                <option value="Advanced">Advanced</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Est. DIY Time</label>
              <input
                type="text"
                value={estimatedTime}
                onChange={(e) => setEstimatedTime(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Est. DIY Parts Cost ($)
              </label>
              <input
                type="number"
                value={estimatedDiyCost}
                onChange={(e) => setEstimatedDiyCost(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Est. Shop Price ($)
              </label>
              <input
                type="number"
                value={estimatedShopCost}
                onChange={(e) => setEstimatedShopCost(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">
              Recommended Advice, Fluid Specs & Torque Specs *
            </label>
            <textarea
              rows={2}
              required
              placeholder="e.g. Torque drain plug to 22 lb-ft. Use 5/8 magnetic socket..."
              value={specsAndAdvice}
              onChange={(e) => setSpecsAndAdvice(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          {/* Tool Selector */}
          <div className="space-y-2">
            <label className="block text-xs font-medium text-slate-300">
              Select Required Tools ({selectedTools.length} selected)
            </label>
            <div className="max-h-36 overflow-y-auto p-2.5 rounded-xl bg-slate-950 border border-slate-800 flex flex-wrap gap-1.5">
              {tools.map((t) => {
                const isSelected = selectedTools.includes(t.name);
                return (
                  <button
                    type="button"
                    key={t.id}
                    onClick={() => toggleSelectedTool(t.name)}
                    className={`px-2.5 py-1 rounded-lg text-xs font-medium border transition ${
                      isSelected
                        ? 'bg-emerald-500/20 border-emerald-500 text-emerald-300'
                        : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-white'
                    }`}
                  >
                    {isSelected ? '✓ ' : '+ '}
                    {t.name}
                  </button>
                );
              })}
            </div>

            <div className="flex gap-2 pt-1">
              <input
                type="text"
                placeholder="Or type a new specialty tool name and click Add..."
                value={customToolInput}
                onChange={(e) => setCustomToolInput(e.target.value)}
                className="flex-1 bg-slate-950 border border-slate-800 rounded-xl px-3 py-1.5 text-xs text-white"
              />
              <button
                type="button"
                onClick={handleAddCustomToolRequirement}
                className="px-3 py-1.5 rounded-xl text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-emerald-400"
              >
                + Add Tool Requirement
              </button>
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-xs font-medium bg-slate-800 text-slate-300"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-5 py-2 rounded-xl text-xs font-bold bg-emerald-500 text-slate-950"
            >
              Save Service Guide
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ==========================================
// SUB-COMPONENT: ADD CUSTOM TOOL MODAL
// ==========================================

function AddToolModal({ onClose, onSave }) {
  const [name, setName] = useState('');
  const [category, setCategory] = useState(TOOL_CATEGORIES[0]);
  const [owned, setOwned] = useState(true);
  const [loanerAvailable, setLoanerAvailable] = useState(false);
  const [estBuyPrice, setEstBuyPrice] = useState(25);
  const [notes, setNotes] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!name.trim()) return;
    onSave({
      name: name.trim(),
      category,
      owned,
      loanerAvailable,
      estBuyPrice: Number(estBuyPrice) || 20,
      notes: notes.trim()
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-5 shadow-2xl space-y-4">
        <div className="flex items-center justify-between pb-2 border-b border-slate-800">
          <h3 className="text-base font-bold text-white flex items-center gap-2">
            <Wrench className="w-5 h-5 text-emerald-400" />
            Add Tool to Garage Inventory
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">
              Tool Name / Size *
            </label>
            <input
              type="text"
              required
              placeholder='e.g. 14mm Thin-Wall Spark Plug Socket or Triple-Square Set'
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Category</label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                {TOOL_CATEGORIES.map((cat) => (
                  <option key={cat} value={cat}>
                    {cat}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Est. Buy Price ($)</label>
              <input
                type="number"
                min="0"
                value={estBuyPrice}
                onChange={(e) => setEstBuyPrice(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs font-mono text-white"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Ownership Status</label>
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setOwned(true)}
                className={`py-2 rounded-xl text-xs font-bold border transition ${
                  owned
                    ? 'bg-emerald-500/20 border-emerald-500 text-emerald-300'
                    : 'bg-slate-950 border-slate-800 text-slate-400'
                }`}
              >
                ✓ I Own This Tool
              </button>
              <button
                type="button"
                onClick={() => setOwned(false)}
                className={`py-2 rounded-xl text-xs font-bold border transition ${
                  !owned
                    ? 'bg-amber-500/20 border-amber-500 text-amber-300'
                    : 'bg-slate-950 border-slate-800 text-slate-400'
                }`}
              >
                Wishlist / Missing
              </button>
            </div>
          </div>

          <div className="flex items-center gap-2 p-2.5 rounded-xl bg-purple-500/10 border border-purple-500/30">
            <input
              type="checkbox"
              id="loanerCheck"
              checked={loanerAvailable}
              onChange={(e) => setLoanerAvailable(e.target.checked)}
              className="rounded accent-purple-500"
            />
            <label htmlFor="loanerCheck" className="text-xs text-purple-200 cursor-pointer">
              Eligible for Free Store Loan-A-Tool Rental (AutoZone / Advance Auto)
            </label>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Notes</label>
            <input
              type="text"
              placeholder="e.g. 3/8 drive, kept in top drawer"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>

          <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-xs font-medium bg-slate-800 text-slate-300"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-5 py-2 rounded-xl text-xs font-bold bg-emerald-500 text-slate-950"
            >
              Add Tool
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
