-- Verwijderen van tracker bij intrekken conceptfactuur (Flutter).
create policy "klant_facturaties_delete_authenticated"
  on public.klant_facturaties for delete
  to authenticated
  using (true);
