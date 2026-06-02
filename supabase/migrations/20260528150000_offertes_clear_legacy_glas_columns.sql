-- Verwijder spook-data van oude glas-test op offertes (nu in offerte_glasbewassing).
UPDATE public.offertes
SET
  glas_aantal_klein = NULL,
  glas_aantal_middel = NULL,
  glas_aantal_groot = NULL,
  glas_frequentie = NULL,
  glas_uren_per_beurt = NULL
WHERE glas_aantal_klein IS NOT NULL
   OR glas_aantal_middel IS NOT NULL
   OR glas_aantal_groot IS NOT NULL
   OR glas_frequentie IS NOT NULL
   OR glas_uren_per_beurt IS NOT NULL;
