-- Offerte-totalen: vloer (ruimte/diensten) + glasbewassing
--
-- De oorspronkelijke herbereken-functie staat alleen op de remote Supabase-database
-- (niet in eerdere repo-migraties). Deze migratie levert:
--   1) Een ontdek-query (onderaan als comment)
--   2) public.herbereken_offerte_totalen — inclusief SUM uit offerte_glasbewassing
--   3) Triggers op offerte_ruimte_diensten, offerte_ruimtes en offerte_glasbewassing
--
-- Als je remote al een andere functienaam hebt: voer eerst de ontdek-query uit en
-- pas de naam hieronder aan, of kopieer alleen het glas-blok naar je bestaande functie.

-- Kwartier afronden (zelfde idee als Dart _urenAfgerondOpKwartier)
CREATE OR REPLACE FUNCTION public.offerte_uren_afgerond_op_kwartier(p_minuten NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_minuten, 0) <= 0 THEN 0::NUMERIC
    ELSE (ROUND((p_minuten / 60.0) * 4) / 4.0)::NUMERIC
  END;
$$;

-- Hoofd-rekenmachine: vloer + glas → offertes
CREATE OR REPLACE FUNCTION public.herbereken_offerte_totalen(p_offerte_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offerte_id UUID := p_offerte_id;
  v_contract_type TEXT;
  v_vaste_override NUMERIC(12, 2);

  v_vloeren_prijs NUMERIC(12, 2) := 0;
  v_vloeren_minuten NUMERIC(12, 2) := 0;

  v_glas_prijs NUMERIC(12, 2) := 0;
  v_glas_minuten NUMERIC(12, 2) := 0;

  v_eind_prijs NUMERIC(12, 2) := 0;
  v_eind_minuten NUMERIC(12, 2) := 0;

  v_reg_min NUMERIC := 0;
  v_freq_min NUMERIC := 0;
  v_per_min NUMERIC := 0;

  v_reg_uren NUMERIC := 0;
  v_freq_uren NUMERIC := 0;
  v_per_uren NUMERIC := 0;

  v_btw NUMERIC(12, 2);
  v_is_losse_klus BOOLEAN;
BEGIN
  IF v_offerte_id IS NULL THEN
    RETURN;
  END IF;

  SELECT
    LOWER(COALESCE(o.contract_type, 'vast')),
    COALESCE(o.vaste_prijs_override, 0)
  INTO
    v_contract_type,
    v_vaste_override
  FROM public.offertes o
  WHERE o.id = v_offerte_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_is_losse_klus := v_contract_type IN ('incidenteel', 'eenmalig');

  IF v_vaste_override > 0 THEN
    UPDATE public.offertes
    SET
      totaal_prijs_ex_btw = v_vaste_override,
      maandprijs_ex_btw = CASE WHEN v_is_losse_klus THEN 0 ELSE v_vaste_override END,
      maand_btw_bedrag = CASE WHEN v_is_losse_klus THEN 0 ELSE v_vaste_override * 0.21 END,
      maandprijs_inc_btw = CASE WHEN v_is_losse_klus THEN 0 ELSE v_vaste_override * 1.21 END
    WHERE id = v_offerte_id;
    RETURN;
  END IF;

  -- Vloer: som van reeds berekende regels (per dienst)
  SELECT
    COALESCE(SUM(d.berekende_prijs), 0),
    COALESCE(SUM(d.berekende_minuten), 0)
  INTO v_vloeren_prijs, v_vloeren_minuten
  FROM public.offerte_ruimte_diensten d
  INNER JOIN public.offerte_ruimtes r ON r.id = d.offerte_ruimte_id
  WHERE r.offerte_id = v_offerte_id;

  -- Fallback: ruimte-subtotalen als diensten nog geen berekende_prijs hebben
  IF v_vloeren_prijs = 0 AND v_vloeren_minuten = 0 THEN
    SELECT
      COALESCE(SUM(
        COALESCE(r.subtotaal_prijs_regulier, 0)
        + COALESCE(r.subtotaal_prijs_frequent, 0)
        + COALESCE(r.subtotaal_prijs_periodiek, 0)
      ), 0),
      COALESCE(SUM(
        COALESCE(r.subtotaal_minuten_regulier, 0)
        + COALESCE(r.subtotaal_minuten_frequent, 0)
        + COALESCE(r.subtotaal_minuten_periodiek, 0)
      ), 0)
    INTO v_vloeren_prijs, v_vloeren_minuten
    FROM public.offerte_ruimtes r
    WHERE r.offerte_id = v_offerte_id;
  END IF;

  -- Glas: som uit offerte_glasbewassing (berekende_prijs = maand of beurt, sync via app)
  SELECT
    COALESCE(SUM(g.berekende_prijs), 0),
    COALESCE(SUM(g.berekende_minuten), 0)
  INTO v_glas_prijs, v_glas_minuten
  FROM public.offerte_glasbewassing g
  WHERE g.offerte_id = v_offerte_id;

  v_eind_prijs := v_vloeren_prijs + v_glas_prijs;
  v_eind_minuten := v_vloeren_minuten + v_glas_minuten;

  -- Uren per beurt (voor PDF / weergave) uit ruimte-subtotalen
  SELECT
    COALESCE(SUM(r.subtotaal_minuten_regulier), 0),
    COALESCE(SUM(r.subtotaal_minuten_frequent), 0),
    COALESCE(SUM(r.subtotaal_minuten_periodiek), 0)
  INTO v_reg_min, v_freq_min, v_per_min
  FROM public.offerte_ruimtes r
  WHERE r.offerte_id = v_offerte_id;

  v_reg_uren := public.offerte_uren_afgerond_op_kwartier(v_reg_min);
  v_freq_uren := public.offerte_uren_afgerond_op_kwartier(v_freq_min);
  v_per_uren := public.offerte_uren_afgerond_op_kwartier(v_per_min);

  v_btw := ROUND((v_eind_prijs * 0.21)::NUMERIC, 2);

  UPDATE public.offertes
  SET
    regulier_uren_per_beurt_afgerond = v_reg_uren,
    frequent_uren_per_beurt_afgerond = v_freq_uren,
    periodiek_uren_per_beurt_afgerond = v_per_uren,
    totaal_prijs_ex_btw = CASE
      WHEN v_is_losse_klus THEN v_eind_prijs
      ELSE v_eind_prijs
    END,
    maandprijs_ex_btw = CASE
      WHEN v_is_losse_klus THEN 0
      ELSE v_eind_prijs
    END,
    maand_btw_bedrag = CASE
      WHEN v_is_losse_klus THEN 0
      ELSE v_btw
    END,
    maandprijs_inc_btw = CASE
      WHEN v_is_losse_klus THEN 0
      ELSE v_eind_prijs + v_btw
    END
  WHERE id = v_offerte_id;
END;
$$;

COMMENT ON FUNCTION public.herbereken_offerte_totalen(UUID) IS
  'Herberekent offerte-totalen: vloer (offerte_ruimte_diensten / ruimte-subtotalen) + glas (offerte_glasbewassing).';

-- Helper: offerte_id uit ruimte/dienst
CREATE OR REPLACE FUNCTION public.trg_herbereken_offerte_totalen_van_ruimte()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offerte_id UUID;
BEGIN
  SELECT r.offerte_id
  INTO v_offerte_id
  FROM public.offerte_ruimtes r
  WHERE r.id = COALESCE(NEW.offerte_ruimte_id, OLD.offerte_ruimte_id);

  IF v_offerte_id IS NOT NULL THEN
    PERFORM public.herbereken_offerte_totalen(v_offerte_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_herbereken_offerte_totalen_van_ruimte_rij()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offerte_id UUID := COALESCE(NEW.offerte_id, OLD.offerte_id);
BEGIN
  IF v_offerte_id IS NOT NULL THEN
    PERFORM public.herbereken_offerte_totalen(v_offerte_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_herbereken_offerte_totalen_van_glas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offerte_id UUID := COALESCE(NEW.offerte_id, OLD.offerte_id);
BEGIN
  IF v_offerte_id IS NOT NULL THEN
    PERFORM public.herbereken_offerte_totalen(v_offerte_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_offerte_ruimte_dienst_totalen ON public.offerte_ruimte_diensten;
CREATE TRIGGER trg_offerte_ruimte_dienst_totalen
  AFTER INSERT OR UPDATE OR DELETE ON public.offerte_ruimte_diensten
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_herbereken_offerte_totalen_van_ruimte();

DROP TRIGGER IF EXISTS trg_offerte_ruimte_totalen ON public.offerte_ruimtes;
CREATE TRIGGER trg_offerte_ruimte_totalen
  AFTER INSERT OR UPDATE OR DELETE ON public.offerte_ruimtes
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_herbereken_offerte_totalen_van_ruimte_rij();

DROP TRIGGER IF EXISTS trg_offerte_glasbewassing_totalen ON public.offerte_glasbewassing;
CREATE TRIGGER trg_offerte_glasbewassing_totalen
  AFTER INSERT OR UPDATE OR DELETE ON public.offerte_glasbewassing
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_herbereken_offerte_totalen_van_glas();

-- Eenmalig: bestaande offertes met glasregels herberekenen
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT offerte_id AS oid
    FROM public.offerte_glasbewassing
    WHERE offerte_id IS NOT NULL
  LOOP
    PERFORM public.herbereken_offerte_totalen(r.oid);
  END LOOP;
END;
$$;

-- Ontdek bestaande remote functie (plak in SQL Editor vóór deploy):
-- SELECT n.nspname AS schema, p.proname AS functie, pg_get_functiondef(p.oid) AS definitie
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND (
--     p.prosrc ILIKE '%maandprijs_ex_btw%'
--     OR p.prosrc ILIKE '%offerte_ruimte_diensten%'
--     OR p.prosrc ILIKE '%bereken_offerte%'
--   )
-- ORDER BY p.proname;
