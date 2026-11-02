# SRG Warehouse Stock

A phone-friendly stock app for the SRG warehouse: photograph stock, give each item a
bin location, and book stock in, out to venues, or count it at stocktake. Every movement
is logged with who did it and when, and the stock list and log export to CSV.

Staff sign in with an email and password. No Claude account is needed.

## How it's built

| Part | What it does | Where |
|---|---|---|
| Website | The app itself: plain HTML, no build step | `index.html`, `config.js`, `icons/`, `vendor/` |
| Supabase | Database, staff logins and photo storage | `supabase/schema.sql` |
| Netlify (or Vercel) | Hosts the website, redeploys when GitHub changes | (connected to this repo) |

Quantities can only change through the `book_stock` database function. It locks the item while
it updates, so two people booking the same item at once can't overwrite each other, and it
blocks booking out more than is on hand. The movement log can't be edited from the app.

## One-time setup (about 20 minutes)

### 1. Create the Supabase project
1. Sign up at [supabase.com](https://supabase.com) with an SRG email (the free plan is enough to start).
2. **New project** → name it `srg-warehouse`, choose region **Sydney**, set a strong database password and save it somewhere safe.

### 2. Set up the database
1. In the project, open **SQL Editor** → **New query**.
2. Paste in the whole of `supabase/schema.sql` from this repo and click **Run**. It should finish with "Success".

### 3. Lock down sign-ups
1. **Authentication** → **Sign In / Providers** → turn **off** "Allow new users to sign up".
   Only people you add can then get in.
2. Under **Email**, turn **off** "Confirm email" (you're creating the accounts yourself).

### 4. Connect the app to Supabase
1. **Project Settings** → **API** (or the **Connect** button). Copy the **Project URL** and the **anon public** key.
2. In GitHub, edit `config.js` and replace the two placeholder values. Commit the change.
   The anon key is meant to be public; the database rules keep the data private.
   Never paste the `service_role` key into this file.

### 5. Put the website live on Netlify
1. Sign up at [netlify.com](https://www.netlify.com) and choose **Add new site** → **Import an existing project** → **GitHub**.
2. Pick the `SRG-Warehouse-Inventory` repo and the `master` branch. Leave the build command empty and set the publish directory to `/`.
3. **Deploy**. Netlify gives you a link like `srg-warehouse.netlify.app`. You can rename it in **Site configuration**,
   or point a company address such as `stock.srghospitality.com.au` at it under **Domain management**.

Every change pushed to `master` goes live automatically within a minute.

### 6. Add staff
1. Supabase → **Authentication** → **Users** → **Add user** → **Create new user**.
2. Enter their email and a starting password, tick **Auto Confirm User**, and create.
3. Send them the website link and their password. The first time they sign in, the app asks for their name,
   which then appears in the stock log.

To reset a forgotten password: open the user in **Authentication → Users** and set a new one.
To remove someone: delete them there. Their past bookings stay in the log under their name.

### Install on phones
Open the website, then:
- **iPhone (Safari):** Share → **Add to Home Screen**
- **Android (Chrome):** menu ⋮ → **Add to Home screen** / **Install app**

It then opens full-screen like an app, and the **Take photo** button uses the phone camera.

## Changing the venue list
Venues are listed near the top of the script in `index.html` (`VENUES_OPEN` and `VENUES_SOON`).
Edit the names, commit, and Netlify redeploys. Past bookings keep the venue name they were saved with.

## Costs and limits
Supabase's free plan covers 500 MB of data and 1 GB of photo storage. The app shrinks photos to about
200–400 KB each, so that's a few thousand photos. Free projects pause after a week with no use; any visit
wakes them, and the Pro plan (about US$25/month) removes the pause and raises the limits.
Netlify's free plan is plenty for a website this size.

## Files
- `index.html` – the app
- `config.js` – which Supabase project to use
- `supabase/schema.sql` – tables, access rules, the `book_stock` function and the photo bucket
- `vendor/supabase-2.45.4.min.js` – Supabase's JavaScript client, kept here so the app doesn't depend on a CDN
- `manifest.webmanifest`, `icons/` – home-screen app name and icon
- `prototype/claude-artifact.html` – the original prototype that runs inside Claude
  (live at https://claude.ai/artifact/9GEMvnaS92BVBgTgA78YYc; needs a Claude login)
