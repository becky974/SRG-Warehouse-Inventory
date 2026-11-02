// Connects the app to your Supabase project.
// Find both values in Supabase: Project Settings → API (or "Connect" → App frameworks).
// The anon key is designed to be public: the database's access rules (supabase/schema.sql)
// are what keep the data private to signed-in staff. Never put the service_role key here.
window.SRG_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT-ID.supabase.co",
  supabaseAnonKey: "YOUR-ANON-KEY",
};
