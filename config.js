// Connects the app to your Supabase project.
// Find both values in Supabase: Project Settings → API Keys (the publishable key).
// The publishable key is designed to be public: the database's access rules (supabase/schema.sql)
// are what keep the data private to signed-in staff. Never put the secret / service_role key here.
window.SRG_CONFIG = {
  supabaseUrl: "https://lgfokuzswmocvwztitqt.supabase.co",
  supabaseAnonKey: "sb_publishable_2Y7ifUjIf1xvcsTBWr2QZA_CiF2XHo9",
};
