-- Glasbewassing-module: losse regels per offerte + projectgeneratie bij getekend.

-- 1. Moeder bestek: vlag voor glas-diensten in de modal
ALTER TABLE public.moeder_bestek
ADD COLUMN IF NOT EXISTS is_glasbewassing BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.moeder_bestek.is_glasbewassing IS
  'True = dienst verschijnt in de Glasbewassing-modal (niet als gewone ruimte).';

-- Bestaande glas-diensten markeren (pas aan indien nodig)
UPDATE public.moeder_bestek
SET is_glasbewassing = TRUE
WHERE LOWER(COALESCE(ruimte, '')) LIKE '%glas%'
   OR LOWER(COALESCE(volledige_naam, '')) LIKE '%glasbewassing%';

-- 2. Tabel offerte_glasbewassing
CREATE TABLE IF NOT EXISTS public.offerte_glasbewassing (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offerte_id UUID NOT NULL REFERENCES public.offertes(id) ON DELETE CASCADE,
  moeder_bestek_id UUID REFERENCES public.moeder_bestek(id) ON DELETE SET NULL,
  omschrijving TEXT,
  frequentie TEXT NOT NULL DEFAULT 'op_afroep',
  aantal_klein INTEGER NOT NULL DEFAULT 0 CHECK (aantal_klein >= 0),
  aantal_middel INTEGER NOT NULL DEFAULT 0 CHECK (aantal_middel >= 0),
  aantal_groot INTEGER NOT NULL DEFAULT 0 CHECK (aantal_groot >= 0),
  berekende_minuten NUMERIC(10, 2),
  berekende_prijs NUMERIC(12, 2),
  sort_volgorde INTEGER NOT NULL DEFAULT 0,
  aangemaakt_op TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  bijgewerkt_op TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_offerte_glasbewassing_offerte
  ON public.offerte_glasbewassing(offerte_id);

CREATE INDEX IF NOT EXISTS idx_offerte_glasbewassing_moeder
  ON public.offerte_glasbewassing(moeder_bestek_id);

-- 3. Projecten: koppeling glas-regel (idempotent projectgeneratie)
ALTER TABLE public.projecten
ADD COLUMN IF NOT EXISTS is_glas_project BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.projecten
ADD COLUMN IF NOT EXISTS glas_moeder_bestek_id UUID REFERENCES public.moeder_bestek(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_projecten_offerte_glas_moeder
  ON public.projecten(offerte_id, glas_moeder_bestek_id)
  WHERE is_glas_project = TRUE AND offerte_id IS NOT NULL AND glas_moeder_bestek_id IS NOT NULL;

-- 4. RLS (zelfde patroon als offerte_ruimtes: ingelogde gebruikers)
ALTER TABLE public.offerte_glasbewassing ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS offerte_glasbewassing_all_authenticated ON public.offerte_glasbewassing;
CREATE POLICY offerte_glasbewassing_all_authenticated ON public.offerte_glasbewassing
  FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

-- 5. Hulp: aantal opdrachten per glas-frequentie
CREATE OR REPLACE FUNCTION public.glas_frequentie_naar_aantal_opdrachten(p_freq TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_freq
    WHEN '12_keer_per_jaar' THEN 12
    WHEN '6_keer_per_jaar' THEN 6
    WHEN '4_keer_per_jaar' THEN 4
    WHEN '2_keer_per_jaar' THEN 2
    WHEN '1_keer_per_jaar' THEN 1
    ELSE 0
  END;
$$;

-- 6. Project + opdrachten genereren per unieke moeder_bestek op de offerte
CREATE OR REPLACE FUNCTION public.genereer_glasbewassing_projecten(p_offerte_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offerte RECORD;
  v_regel RECORD;
  v_mb RECORD;
  v_project_id UUID;
  v_suffix INT := 0;
  v_project_naam TEXT;
  v_basis_uren NUMERIC;
  v_aantal_opdrachten INT;
  v_i INT;
  v_offerte_nr TEXT;
BEGIN
  SELECT * INTO v_offerte FROM public.offertes WHERE id = p_offerte_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_offerte_nr := COALESCE(NULLIF(TRIM(v_offerte.offerte_nummer), ''), LEFT(p_offerte_id::TEXT, 8));

  FOR v_regel IN
    SELECT DISTINCT ON (g.moeder_bestek_id)
      g.*,
      g.moeder_bestek_id AS mb_id
    FROM public.offerte_glasbewassing g
    WHERE g.offerte_id = p_offerte_id
      AND g.moeder_bestek_id IS NOT NULL
    ORDER BY g.moeder_bestek_id, g.sort_volgorde, g.aangemaakt_op
  LOOP
    IF EXISTS (
      SELECT 1 FROM public.projecten p
      WHERE p.offerte_id = p_offerte_id
        AND p.is_glas_project = TRUE
        AND p.glas_moeder_bestek_id = v_regel.moeder_bestek_id
    ) THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_mb FROM public.moeder_bestek WHERE id = v_regel.moeder_bestek_id;

    v_suffix := v_suffix + 1;
    v_project_naam := COALESCE(
      NULLIF(TRIM(v_mb.volledige_naam), ''),
      NULLIF(TRIM(v_regel.omschrijving), ''),
      'Glasbewassing'
    );

    v_basis_uren := GREATEST(
      COALESCE(v_regel.berekende_minuten, 0) / 60.0,
      0.25
    );

    INSERT INTO public.projecten (
      offerte_id,
      bedrijf_id,
      project_naam,
      werk_regio,
      frequentie_type,
      periodieke_frequentie,
      status,
      is_glas_project,
      glas_moeder_bestek_id,
      basis_uren_per_opdracht,
      facilitator_id,
      klant_id,
      uitvoer_adres_volledig,
      contract_startdatum
    ) VALUES (
      p_offerte_id,
      v_offerte.bedrijf_id,
      v_offerte_nr || '-G' || v_suffix::TEXT || ' (' || v_project_naam || ')',
      v_offerte.werk_regio,
      CASE
        WHEN v_regel.frequentie = 'op_afroep' THEN 'incidenteel'
        ELSE 'periodiek'
      END,
      CASE
        WHEN v_regel.frequentie = 'op_afroep' THEN NULL
        ELSE v_regel.frequentie
      END,
      'actief',
      TRUE,
      v_regel.moeder_bestek_id,
      v_basis_uren,
      v_offerte.facilitator_id,
      v_offerte.klant_id,
      COALESCE(
        v_offerte.uitvoer_adres_volledig,
        TRIM(CONCAT_WS(', ',
          v_offerte.uitvoer_adres_straat_huisnr,
          v_offerte.uitvoer_adres_postcode,
          v_offerte.uitvoer_adres_stad
        ))
      ),
      COALESCE(v_offerte.contract_startdatum, CURRENT_DATE)
    )
    RETURNING id INTO v_project_id;

    v_aantal_opdrachten := public.glas_frequentie_naar_aantal_opdrachten(v_regel.frequentie);

    FOR v_i IN 1..v_aantal_opdrachten LOOP
      INSERT INTO public.opdrachten (
        project_id,
        bedrijfsnaam,
        werk_regio,
        status,
        benodigde_uren_totaal,
        verwachte_uren_totaal,
        frequentie_type,
        is_buiten_abonnement
      ) VALUES (
        v_project_id,
        COALESCE(v_offerte.bedrijfsnaam_klant, 'Glasbewassing'),
        v_offerte.werk_regio,
        'open',
        v_basis_uren,
        v_basis_uren,
        CASE
          WHEN v_regel.frequentie = 'op_afroep' THEN 'incidenteel'
          ELSE 'periodiek'
        END,
        FALSE
      );
    END LOOP;
  END LOOP;
END;
$$;

-- 7. Trigger bij status getekend
CREATE OR REPLACE FUNCTION public.trg_offerte_glas_projecten_bij_getekend()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('signed', 'getekend')
     AND (OLD.status IS DISTINCT FROM NEW.status)
     AND (OLD.status IS NULL OR OLD.status NOT IN ('signed', 'getekend'))
  THEN
    PERFORM public.genereer_glasbewassing_projecten(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_offerte_glas_projecten ON public.offertes;
CREATE TRIGGER trg_offerte_glas_projecten
  AFTER UPDATE OF status ON public.offertes
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_offerte_glas_projecten_bij_getekend();

COMMENT ON FUNCTION public.genereer_glasbewassing_projecten IS
  'Maakt per unieke glas-moeder_bestek een -G project met open opdrachten (frequentie → aantal).';
