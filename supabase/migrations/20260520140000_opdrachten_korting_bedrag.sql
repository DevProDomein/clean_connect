-- Korting/credit op opdracht-niveau (extra werk / handmatige opdrachten).
alter table if exists public.opdrachten
  add column if not exists korting_bedrag numeric(14,2) not null default 0;

comment on column public.opdrachten.korting_bedrag is
  'Ex btw: aftrek op facturabele waarde voor extra werk (o.a. handmatige opdrachten).';
