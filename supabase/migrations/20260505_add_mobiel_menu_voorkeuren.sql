-- Add mobile bottom nav preferences to `gebruikers`.
-- Default: 4-item facilitator quick menu.

ALTER TABLE gebruikers
ADD COLUMN IF NOT EXISTS mobiel_menu_voorkeuren TEXT[]
DEFAULT ARRAY['dashboard', 'agenda', 'tickets', 'crm'];

