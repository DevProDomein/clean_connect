-- 1. Voeg Artikel-koppeling toe aan Projecten
ALTER TABLE public.projecten
ADD COLUMN IF NOT EXISTS standaard_artikel_code TEXT;

-- 2. Voeg het 'Slot'-veld toe aan de Factuurregels
ALTER TABLE public.factuur_regels
ADD COLUMN IF NOT EXISTS gekoppelde_opdrachten_info TEXT;

-- 3. DE VERNIEUWDE WAAKHOND (TRIGGER) VOOR FACTURATIE STATUS
CREATE OR REPLACE FUNCTION public.bepaal_facturatie_status()
RETURNS TRIGGER AS $$
DECLARE
    v_maand_is_voorbij BOOLEAN;
BEGIN
    -- Bereken of de maand van de geplande datum in het verleden ligt
    v_maand_is_voorbij := (DATE_TRUNC('month', NEW.geplande_datum) + INTERVAL '1 month') <= CURRENT_DATE;

    -- REGEL 1: Heeft hij al een factuur_id? Dan is hij 100% zeker gefactureerd.
    IF NEW.factuur_id IS NOT NULL THEN
        NEW.facturatie_status := 'gefactureerd';

    -- REGEL 2: Het is extra werk (buiten abonnement)
    ELSIF NEW.is_buiten_abonnement = TRUE THEN
        IF NEW.status != 'open' AND v_maand_is_voorbij THEN
            NEW.facturatie_status := 'facturabel';
        ELSE
            NEW.facturatie_status := 'niet_facturabel';
        END IF;

    -- REGEL 3: Regulier abonnement (wordt via offerte/maandprijs gefactureerd)
    ELSE
        NEW.facturatie_status := 'niet_facturabel';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

DROP TRIGGER IF EXISTS trg_bepaal_facturatie_status ON public.opdrachten;
CREATE TRIGGER trg_bepaal_facturatie_status
BEFORE INSERT OR UPDATE OF is_buiten_abonnement, factuur_id, status, geplande_datum ON public.opdrachten
FOR EACH ROW
EXECUTE FUNCTION public.bepaal_facturatie_status();

-- 4. DE GROTE SCHOONMAAK (Retroactief alles rechtzetten volgens de nieuwe regels)
UPDATE public.opdrachten o
SET is_buiten_abonnement = TRUE
FROM public.projecten p
WHERE o.project_id = p.id AND p.offerte_id IS NULL;

UPDATE public.opdrachten SET geplande_datum = geplande_datum WHERE factuur_id IS NULL;
