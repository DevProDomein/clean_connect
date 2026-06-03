-- Facturatie: blokkeer dubbel genereren via maand_sleutel op facturen.
ALTER TABLE public.facturen
ADD COLUMN IF NOT EXISTS maand_sleutel text;

COMMENT ON COLUMN public.facturen.maand_sleutel IS
  'YYYY-MM sleutel voor maandfacturatie (generator-slot).';

CREATE INDEX IF NOT EXISTS facturen_maand_sleutel_idx
  ON public.facturen (maand_sleutel);

