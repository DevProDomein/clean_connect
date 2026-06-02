-- Glasbewassing op offerte_ruimtes (live tellers + frequentie per sectie)
ALTER TABLE public.offerte_ruimtes
ADD COLUMN IF NOT EXISTS glas_aantal_klein INTEGER NOT NULL DEFAULT 0 CHECK (glas_aantal_klein >= 0),
ADD COLUMN IF NOT EXISTS glas_aantal_middel INTEGER NOT NULL DEFAULT 0 CHECK (glas_aantal_middel >= 0),
ADD COLUMN IF NOT EXISTS glas_aantal_groot INTEGER NOT NULL DEFAULT 0 CHECK (glas_aantal_groot >= 0),
ADD COLUMN IF NOT EXISTS specifieke_frequentie TEXT NOT NULL DEFAULT 'op_afroep';

COMMENT ON COLUMN public.offerte_ruimtes.glas_aantal_klein IS 'Aantal kleine ramen (glasbewassing).';
COMMENT ON COLUMN public.offerte_ruimtes.specifieke_frequentie IS 'Frequentie glas-sectie (bijv. 12_keer_per_jaar, op_afroep).';
