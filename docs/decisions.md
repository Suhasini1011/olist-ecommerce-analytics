# Decisions log

## 1. Database host: Neon instead of Aiven

**Goal:** Power BI Service (browser only, no Windows, so no gateway) connecting directly to a cloud PostgreSQL database, with scheduled refresh.

**First attempt, Aiven free tier:** Power BI reached the server without a gateway, but failed with
"The remote certificate is invalid according to the validation procedure."
Aiven signs certificates with its own project CA, which Power BI's cloud does not trust, and the
browser offers no way to add a trusted certificate. Without encryption, Aiven rejects the login.

**Fix, Neon free tier:** Neon uses publicly trusted Let's Encrypt (ISRG Root X1) certificates.
Power BI Service connected directly with an encrypted connection and no gateway.

**Cost:** both free tiers, no credit card. Neon Free: 1 GB storage per project.

**Migration:** rebuilt from the repo's scripts (01_create_staging.sql, 02_load_staging.sql),
which confirmed the pipeline is reproducible.

## 2. Loading CSVs with psql \copy instead of the DBeaver import wizard

The DBeaver importer split review comments containing line breaks into extra rows
(158,240 rows instead of 99,224). psql's \copy with FORMAT csv follows the CSV rules and loaded
the correct count. psql comes from Postgres.app, because Homebrew no longer supports Intel Macs.

## 3. Staging keeps the raw data unchanged

All staging columns are TEXT, loaded exactly as in the CSVs. Cleaning and typing happen in the
analytics layer, so every fix is visible in SQL and the raw data can always be checked.