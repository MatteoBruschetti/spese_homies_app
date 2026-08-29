<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://ai.google.dev/static/site-assets/images/share-ais-513315318.png" />
</div>

# Run and deploy your AI Studio app

This contains everything you need to run your app locally.

View your app in AI Studio: https://ai.studio/apps/ad1b82de-b33d-4c8e-83d3-450ae8f9eebe

## Run Locally

**Prerequisites:**  Node.js

1. Install dependencies:
   `npm install`
2. Create a `.env.local` file in the project root with your Supabase credentials
   (see [Environment variables](#environment-variables) below)
3. Run the app:
   `npm run dev`

## Environment variables

`.env.local` is git-ignored and never committed. Create it locally with:

```sh
VITE_SUPABASE_URL="https://<your-project>.supabase.co"
VITE_SUPABASE_ANON_KEY="<your-publishable-anon-key>"
```

| Variable | Required | Notes |
| --- | --- | --- |
| `VITE_SUPABASE_URL` | yes | Supabase project URL. |
| `VITE_SUPABASE_ANON_KEY` | yes | Publishable anon key. |

Both are `VITE_`-prefixed, so Vite embeds them in the client bundle by design —
only ever put publishable values here. Secrets (service-role keys, database
passwords, third-party API keys) must never be exposed to the client: keep them
server-side, in Supabase Edge Functions or your hosting provider's secret store.
