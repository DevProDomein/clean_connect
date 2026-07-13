-- Automatisch opdracht_waarde_ex_btw berekenen voor handmatige/extra opdrachten
-- wanneer het veld nog leeg is (NULL of 0).

CREATE OR REPLACE FUNCTION public.auto_bereken_opdracht_waarde()
RETURNS TRIGGER AS $$
DECLARE
    v_uurtarief NUMERIC;
    v_vaste_prijs NUMERIC;
    v_uren NUMERIC;
BEGIN
    -- Alleen berekenen voor handmatige/extra opdrachten als de waarde nog leeg (null of 0) is
    IF NEW.is_buiten_abonnement = true AND (NEW.opdracht_waarde_ex_btw IS NULL OR NEW.opdracht_waarde_ex_btw = 0) THEN

        -- Haal de tarieven op uit het gekoppelde project
        SELECT
            COALESCE(vastgelegd_uurtarief, uurtarief, regulier_gem_uurtarief, 0),
            COALESCE(tarief_per_beurt, vaste_prijs_per_beurt, 0)
        INTO v_uurtarief, v_vaste_prijs
        FROM public.projecten
        WHERE id = NEW.project_id;

        -- Bepaal de uren van deze opdracht
        v_uren := COALESCE(NEW.benodigde_uren_totaal, NEW.verwachte_uren_totaal, 0);

        -- Berekening uitvoeren op basis van prioriteit
        IF v_vaste_prijs > 0 THEN
            NEW.opdracht_waarde_ex_btw := v_vaste_prijs;
        ELSE
            NEW.opdracht_waarde_ex_btw := ROUND(v_uren * v_uurtarief, 2);
        END IF;

    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_bereken_opdracht_waarde ON public.opdrachten;
CREATE TRIGGER trg_auto_bereken_opdracht_waarde
BEFORE INSERT OR UPDATE ON public.opdrachten
FOR EACH ROW EXECUTE FUNCTION public.auto_bereken_opdracht_waarde();

-- Respecteer expliciete facturatie_status van facilitators bij handmatige opdrachten.
CREATE OR REPLACE FUNCTION public.bepaal_facturatie_status()
RETURNS TRIGGER AS $$
DECLARE
    v_maand_is_voorbij BOOLEAN;
BEGIN
    v_maand_is_voorbij := (DATE_TRUNC('month', NEW.geplande_datum) + INTERVAL '1 month') <= CURRENT_DATE;

    IF NEW.factuur_id IS NOT NULL THEN
        NEW.facturatie_status := 'gefactureerd';

    ELSIF NEW.is_buiten_abonnement = TRUE THEN
        -- Facilitator heeft bij aanmaken expliciet gekozen
        IF TG_OP = 'INSERT' AND NEW.facturatie_status IN ('facturabel', 'niet_facturabel') THEN
            NULL;
        -- Facilitator heeft 'niet facturabel' gekozen: nooit automatisch overschrijven
        ELSIF NEW.facturatie_status = 'niet_facturabel' THEN
            NULL;
        ELSIF NEW.status != 'open' AND v_maand_is_voorbij THEN
            NEW.facturatie_status := 'facturabel';
        ELSE
            NEW.facturatie_status := 'niet_facturabel';
        END IF;

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
