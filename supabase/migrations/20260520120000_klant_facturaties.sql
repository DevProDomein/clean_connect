-- Maandfacturatie-status per klant (bedrijf) voor Generator facturatie-overzicht.
create table if not exists public.klant_facturaties (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references public.bedrijven (id) on delete cascade,
  maand_sleutel text not null check (maand_sleutel ~ '^\d{4}-\d{2}$'),
  berekend_abonnement numeric(14,2) not null default 0,
  berekend_incidenteel numeric(14,2) not null default 0,
  berekend_extra numeric(14,2) not null default 0,
  totaal_ex_btw numeric(14,2) not null default 0,
  status text not null default 'concept'
    check (status in ('concept', 'gefactureerd', 'betaald')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (bedrijf_id, maand_sleutel)
);

create index if not exists klant_facturaties_maand_sleutel_idx
  on public.klant_facturaties (maand_sleutel);

alter table public.klant_facturaties enable row level security;

-- Pas aan naar jullie bestaande admin-RLS-patroon indien nodig.
create policy "klant_facturaties_select_authenticated"
  on public.klant_facturaties for select
  to authenticated
  using (true);

create policy "klant_facturaties_write_authenticated"
  on public.klant_facturaties for insert
  to authenticated
  with check (true);

create policy "klant_facturaties_update_authenticated"
  on public.klant_facturaties for update
  to authenticated
  using (true)
  with check (true);
