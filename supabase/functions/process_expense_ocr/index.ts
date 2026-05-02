// Supabase Edge Function: process_expense_ocr
// Accepts POST: { invoice_id: "uuid", file_url: "string" }
// Simulates enterprise OCR + confidence scoring and updates `inkoopfacturen`.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.2";

type Body = {
  invoice_id?: string;
  file_url?: string;
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return json(500, { error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" });
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }

  const invoiceId = (body.invoice_id ?? "").trim();
  const fileUrl = (body.file_url ?? "").trim();
  if (!invoiceId || !fileUrl) {
    return json(400, { error: "invoice_id and file_url are required" });
  }

  // Mark processing.
  {
    const { error } = await supabase
      .from("inkoopfacturen")
      .update({ ocr_verwerkings_status: "processing" })
      .eq("id", invoiceId);
    if (error) return json(500, { error: error.message });
  }

  // Simulate enterprise AI (Mindee/DocumentAI).
  await delay(3000);

  const mock = {
    vendor_name: "Sligro B.V.",
    kvk: "12345678",
    iban: "NL99INGB0001234567",
    invoice_number: "INV-2026-999",
    date: "2026-04-16",
    total_ex: 100.0,
    vat: 21.0,
    total_inc: 121.0,
  };

  const confidence = {
    factuur_nummer_leverancier: 99.5,
    totaal_inc_btw: 98.0,
    factuur_datum: 60.5,
  };

  // Update invoice with extracted fields.
  {
    const { error } = await supabase
      .from("inkoopfacturen")
      .update({
        totaal_ex_btw: mock.total_ex,
        totaal_btw: mock.vat,
        totaal_inc_btw: mock.total_inc,
        factuur_nummer_leverancier: mock.invoice_number,
        factuur_datum: mock.date,
        herkende_kvk: mock.kvk,
        herkende_iban: mock.iban,
        ocr_raw_data: { file_url: fileUrl, provider: "mock_ai", extracted: mock },
        ocr_confidence_scores: confidence,
        ocr_verwerkings_status: "completed",
      })
      .eq("id", invoiceId);
    if (error) return json(500, { error: error.message });
  }

  // Notify the uploader (best-effort).
  try {
    const { data: invRow } = await supabase
      .from("inkoopfacturen")
      .select("id, aangemaakt_door_id, gebruiker_id, user_id")
      .eq("id", invoiceId)
      .maybeSingle();

    const uploaderId =
      (invRow as any)?.aangemaakt_door_id ??
      (invRow as any)?.gebruiker_id ??
      (invRow as any)?.user_id ??
      null;

    if (uploaderId) {
      await supabase.from("in_app_notificaties").insert({
        gebruiker_id: uploaderId,
        bericht: "Je bon is geanalyseerd en staat klaar voor controle!",
        type: "inkoop_ocr_voltooid",
        gelezen: false,
        data: { invoice_id: invoiceId },
      });
    }
  } catch {
    // Ignore notification errors to keep OCR pipeline resilient.
  }

  return json(200, { ok: true, invoice_id: invoiceId });
});

