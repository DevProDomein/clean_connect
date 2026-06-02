-- Glasregels: eigen naam + meerdere moederbestek-diensten per regel.

ALTER TABLE public.offerte_glasbewassing
ADD COLUMN IF NOT EXISTS naam TEXT;

ALTER TABLE public.offerte_glasbewassing
ADD COLUMN IF NOT EXISTS moeder_bestek_ids UUID[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.offerte_glasbewassing.naam IS
  'Door gebruiker gekozen weergavenaam van deze glasregel.';

COMMENT ON COLUMN public.offerte_glasbewassing.moeder_bestek_ids IS
  'Geselecteerde glas-diensten uit moeder_bestek (is_glasbewassing).';
