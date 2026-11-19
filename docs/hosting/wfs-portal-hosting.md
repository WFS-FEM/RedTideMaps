# WFS-Portal hosting: staged decision

Date: 19 Nov 2026. Resolves decision D1 ("Hosting: undecided until a constraint forces it") in
`docs/issue23_portal-bundle/issue23-portal-bundle-plan.md`.

This file is self-contained so it can move to `WFS-FEM/WFS-Portal` with the rest of the planning
history. A shorter version for collaborators is at
<https://claude.ai/artifact/6HDZ6qhjUzFMX2Q6hhqkmS>.

**How the figures were sourced.** The Posit, UF Research Computing, and other vendor pages could
not be opened from the session that wrote this file. Every price and limit below comes from
search-result summaries of the cited pages. Section 9 lists what must be confirmed on the live
pages before money or dates are committed.

## 1. Decision

WFS-Portal starts on the **Free plan of Posit Connect Cloud**, built so that it can move without
code changes. It moves to a dedicated host only when a trigger in section 5 is met. UF PubApps is
the first choice for that dedicated host.

| Stage | Host | Cost | Purpose |
|---|---|---|---|
| 0 | none | $0 | Confirm plan terms, repo visibility, attribution, account ownership (section 2) |
| 1 | Posit Connect Cloud, Free | $0 | Red Tide Maps live; republished from the WFS-FEM repo on each monthly update |
| 1.5 | Same host; data in object storage and GitHub Releases | $0 up to 10 GB on Cloudflare R2 | Ecospace layers as Parquet and COG, read on demand; downloads as pre-built files |
| 2 | UF PubApps (needs a HiPerGator group) | about $300/yr | 2 vCPU, 16 GB RAM, always on, `*.rc.ufl.edu` URL, data beside HiPerGator |

### Choosing now versus waiting

Reasons to start now:

- The app is about 40 MB (9.7 MB bundle plus about 29 MB of pre-rendered PNGs per product) with
  `shiny` as its only runtime dependency, so a free plan carries it and nothing is locked in.
- Collaborators can see and comment on a live app.
- It forces the open decisions that are cheap now and costly later: the PNG cache, the deploy
  path, and the update workflow.
- UF procurement and a HiPerGator group have lead time; asking now costs nothing.

Reasons to wait: the Ecospace data shape is unknown, so a paid or self-administered host chosen
today could be the wrong size. The staged plan avoids this by spending nothing until the data
exists.

Waiting does not resolve the real unknown, which is the size and format of the Ecospace outputs.

## 2. Stage 0: before the first deploy

- [ ] Read <https://connect.posit.cloud/plans> and confirm two Free plan points: whether it
      publishes from a private repository, and whether monthly active hours are enforced.
      Plan for the stricter reading (public repo, 20 active hours per month).
- [ ] Decide whether `WFS-FEM/WFS-Portal` can be public.
- [ ] Confirm the attribution wording with FWC-FWRI and the USF Optical Oceanography Laboratory,
      and supply the funding acknowledgment line. With a public repo and a public app this gates
      stage 1 (issue-23 plan, "Still open").
- [ ] A WFS-FEM organization owner installs the Posit Connect Cloud GitHub App on the
      organization. Create the Connect Cloud account under a lab or project email, not a personal
      login, and record who holds it.
- [ ] Ask whether the Chagaris lab has a HiPerGator group (message below). Do **not** start the
      PubApps trial yet: it is a one-time 3-month trial, best kept until Ecospace data exists.

Message to send:

> David, a quick question for planning where the WFS-Portal Shiny app is hosted long term. Does
> the lab have a HiPerGator group (UF Research Computing allocation)? UF RC's PubApps service
> hosts public Shiny apps for HiPerGator groups at about $300 per year, and it is our first choice
> if the Ecospace outputs outgrow the free host we are starting on. No action needed now beyond a
> yes or no.

## 3. Stage 1: Posit Connect Cloud Free, built to move

### Deploy path

1. A GitHub Actions workflow in WFS-Portal assembles the deployable folder: the app, the data
   bundle at the pinned RedTideMaps commit, and the pre-rendered PNG cache.
2. It commits that folder to a `deploy` branch.
3. Connect Cloud tracks `deploy` and republishes on push.

This settles the open PNG-cache question in the issue-23 plan: the cache is **built in CI and
never tracked on `main`**. `main` holds no binaries, and a restyle does not rewrite 30 MB of
history there.

Fallback if branch tracking proves unreliable: the same workflow publishes with
`rsconnect::deployApp()` (recent rsconnect releases support Connect Cloud, including `appId=`),
with a Connect Cloud token stored as a repository secret.

### Portability pieces (all in WFS-Portal)

| Piece | Why |
|---|---|
| `manifest.json` from `rsconnect::writeManifest()` | Connect Cloud needs a manifest or an `renv.lock`. The manifest alone is enough, so "renv deferred" (D1) stands. |
| `Dockerfile` plus a CI job that builds the image and checks the app starts | Keeps the PubApps (Podman), Jetstream2, and VM routes working while unused. |
| One data-root setting, an environment variable next to `WFS_PORTAL_CONFIG`, read by the loader | Data can move from the repo to a mounted volume or object storage without touching modules. |
| A GitHub Pages landing page under WFS-FEM that links to the live app | Papers, reports, and partners cite an org-owned address, so a host move never breaks a link. |

No host-specific code enters the app. Host differences live in the workflow, the Dockerfile, and
environment variables.

### Templates (untested)

These were written without access to the WFS-Portal repository and have **not been run**. Script
names come from the issue-23 plan. Test each in WFS-Portal before relying on it.

Deploy workflow, `.github/workflows/deploy.yaml`:

```yaml
name: deploy
on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.5.1"
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
      - name: Prerender PNG cache
        run: Rscript scripts/prerender.R
      - name: Write manifest (after prerender, so it lists the cache)
        run: Rscript -e 'rsconnect::writeManifest()'
      - name: Publish deploy branch
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git checkout -B deploy
          git add -f cache manifest.json
          git commit -m "deploy: $(date -u +%F)"
          git push --force origin deploy
```

Notes on the workflow:

- `deploy` is `main` plus one bot commit, replaced on each run, so cache history does not
  accumulate. Whether Connect Cloud republishes cleanly after a force-push is unconfirmed; if it
  does not, commit on top of the existing `deploy` branch instead.
- `rsconnect` is in `Suggests`, so `setup-r-dependencies` installs it.

Dockerfile:

```dockerfile
FROM rocker/r-ver:4.5.1
RUN R -q -e 'install.packages("shiny")'
WORKDIR /app
COPY . /app
ENV WFS_PORTAL_CONFIG=portal
EXPOSE 3838
CMD ["R", "-q", "-e", "shiny::runApp('/app', host = '0.0.0.0', port = 3838)"]
```

Notes on the Dockerfile:

- Build it from the assembled folder (after the prerender step), so the image carries the cache.
- If any module draws plots at run time, confirm the image has a working PNG device
  (`capabilities("png")`), or add `ragg` and its system libraries.

Smoke test for CI, after `docker build -t wfs-portal .`:

```bash
docker run -d --name wfs -p 3838:3838 wfs-portal
```

```bash
curl --fail --retry 10 --retry-delay 3 --retry-connrefused http://localhost:3838/
```

### Monthly update

1. Run the pipeline and commit in RedTideMaps. The manual look at the `Hulls:` line stays.
2. In WFS-Portal, fetch the bundle at the new pinned commit and commit it (`scripts/fetch_bundle.R`).
3. Trigger the deploy workflow by hand.
4. Check active hours and memory on the Connect Cloud usage page.

Steps 2 and 3 can later be merged into one workflow. Step 1 stays semi-automatic while the hull
check needs a person.

## 4. Speed and data size

The data layout affects speed more than the choice of server. The server matters for memory per
session, cold starts after idle sleep, and whether data is local or fetched over the network.

### Sizing sketch for Ecospace layers

On the current 5-arcminute grid over the current month range:

- 78 x 66 = 5,148 cells
- 5,148 x 504 months = 2,594,592 values per layer
- at 4 bytes per value: 10.4 MB per layer, uncompressed
- 80 layers: about 830 MB per variable per model run

The layer count of 80 is illustrative, not the model's functional group count. Land cells and
compression reduce these figures; more variables, runs, or months raise them. Replace the sketch
with the real run metadata (the open item "Ecospace bundle volume and transport" in the issue-23
plan). The sketch points to gigabytes, not terabytes, which stage 1.5 can carry.

### Layout for Ecospace outputs (stage 1.5)

- Tables and time series (biomass, catch, mortality rates) as Parquet, queried with `arrow` or
  `duckdb`, so the app reads only the rows a user selects.
- Maps as cloud-optimized GeoTIFF, or pre-rendered PNGs as the red tide product does now.
- Downloads as pre-built files served from storage (Cloudflare R2, or GitHub Releases at under
  2 GiB per file), not assembled inside a user session.
- Versioned data releases on Zenodo, which gives each release a DOI.
- Dense layers do not go in text CSV. The issue-23 plan already notes they "reach hundreds of MB
  as text".

This changes D13 ("no raster, terra, sf ... in the app") only if maps are read from COG at run
time. Pre-rendered PNGs and Parquet tables keep the app's dependency list short.

## 5. Move triggers

Any one of these moves the portal off the Free plan. The first step is usually stage 1.5 or a
paid Connect Cloud plan, not a new host.

- Active hours or memory limits are reached in two consecutive months.
- App data no longer fits GitHub's limits (100 MiB per file, about 1 GB per repository).
- A user session needs more memory than the plan allows.
- Cold starts draw complaints, or the app must be always on.
- A funder or partner requires an institutional address.

## 6. Stage 2 options

| Option | Cost | Upkeep | Notes |
|---|---|---|---|
| UF PubApps | about $300/yr for 2 vCPU, 16 GB RAM; extra storage $140 to $300 per TB-year | Moderate: Podman containers under systemd, reached by SSH from HiPerGator | Needs a HiPerGator group. Public `*.rc.ufl.edu` URL with TLS and a dev twin. Data on /blue or /orange. Free one-time 3-month trial. |
| NSF Jetstream2 via ACCESS | Free allocation by proposal | High: own VM, periodic renewal | Supports always-on gateways and persistent IPs. Shiny use and long-running public apps on a free allocation not confirmed. |
| Cloud VM (AWS Lightsail, DigitalOcean) | $24 to $48/mo for 4 to 8 GB RAM | High: patching, TLS, uptime | Shiny Server Open Source or ShinyProxy. UF cloud purchases go through UFIT. |
| Connect Cloud paid | Basic $19/mo; Enhanced $59/mo | None | Enhanced adds a custom domain with TLS. Works with stage 1.5 data layout. |
| NOAA Fisheries Posit Connect | none to the project | none to the project | NMFS staff accounts only. Possible only if a NOAA co-investigator owns the deployment. |

PubApps deployment sketch: GitHub Actions builds the image from section 3 and pushes it to GHCR;
the PubApps instance runs it with Podman under systemd and pulls updates on a timer.

## 7. Options ruled out

| Option | Reason |
|---|---|
| shinyapps.io | Being retired into Connect Cloud (active until 2026-12-31; free accounts migrate from 2027-01-28). |
| Shinylive on GitHub Pages | All data downloads to the browser; Pages sites are capped at 1 GB. Fine for Red Tide Maps alone, not for Ecospace. |
| Hugging Face Spaces | Free tier status uncertain in 2026. |
| FSU and USF research computing | No Shiny hosting service found. |
| Licensed Posit Connect, self-hosted | Priced for enterprises; far more than one public app needs. |

GCOOS ERDDAP and GRIIDC do not host apps but are candidates for archiving and serving the model
outputs.

## 8. Ownership

- Code: `WFS-FEM/WFS-Portal`.
- Deploys: GitHub Actions in that repo; Connect Cloud connected through the organization's
  GitHub App installation.
- Hosting account: a lab or project identity, with the holder recorded in the WFS-Portal README.
- Public address: the WFS-FEM GitHub Pages landing page.

## 9. To confirm on the live pages

- **Connect Cloud Free plan**: public-repository requirement; 20 active hours per month and
  whether enforced; 4 GB memory and 2 CPU. Published figures date from the December 2024 beta.
- **Connect Cloud**: idle sleep and cold-start time (one forum report of 10 to 30 s); behavior
  after a force-push to the tracked branch.
- **UF PubApps**: current price; disk (40 GB local, with 1 TB data storage on one page); extra
  storage at $140 or $300 per TB-year; whether collaborators outside UF can sign in to restricted
  apps.
- **Jetstream2**: whether a free ACCESS allocation covers a long-running public Shiny app.
- **Cloud VM prices**: taken from third-party listings.
- **Ecospace outputs**: layer count, variables, runs, month range, precision.

## 10. Sources

Posit Connect Cloud

- Plans: <https://docs.posit.co/connect-cloud/user/account/plans.html>
- Usage and credits: <https://docs.posit.co/connect-cloud/user/usage.html>
- Publishing limits: <https://docs.posit.co/connect-cloud/user/publish/>
- Republish on push: <https://docs.posit.co/connect-cloud/user/publish/republish.html>
- R dependencies (manifest or renv.lock): <https://docs.posit.co/connect-cloud/how-to/r/dependencies.html>
- Beta announcement with plan figures: <https://docs.posit.co/connect-cloud/whats-new/posts/2024-12-01-connect-cloud-beta.html>
- Custom domains: <https://docs.posit.co/connect-cloud/whats-new/posts/2026-01-02-custom-domains-now-supported.html>
- shinyapps.io migration: <https://docs.posit.co/connect-cloud/user/shinyapps-migration.html>
- rsconnect release notes: <https://rstudio.github.io/rsconnect/news/index.html>

UF Research Computing

- Web hosting (PubApps): <https://docs.rc.ufl.edu/services/web_hosting>
- Shiny guide: <https://docs.rc.ufl.edu/services/web_hosting/shiny>
- Price list: <https://www.rc.ufl.edu/get-started/price-list/>
- Trial allocation: <https://docs.rc.ufl.edu/resources/trial>
- UFIT public cloud: <https://it.ufl.edu/hosting/services/public-cloud>

Other hosts

- Jetstream2: <https://kb.iu.edu/d/bfde>
- NOAA Fisheries Posit Connect: <https://nmfs-opensci.github.io/nmfs-connect>
- FSU RCC Open OnDemand: <https://docs.rcc.fsu.edu/hpc/ood>
- USF CIRCE: <https://wiki.rc.usf.edu/index.php/Connecting_To_CIRCE>
- AWS Lightsail bundles: <https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-bundles.html>
- Hugging Face Spaces: <https://huggingface.co/docs/hub/en/spaces-overview>

Data and storage

- GitHub large files: <https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github>
- GitHub Pages limits: <https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits>
- GitHub Releases: <https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases>
- Cloudflare R2 pricing: <https://developers.cloudflare.com/r2/pricing>
- Zenodo versioning: <https://zenodo.org/help/versioning>
- GCOOS ERDDAP data provider form: <https://gcoos5.geos.tamu.edu/erddap/dataProviderForm.html>
- GRIIDC model data guidance: <https://griidc.org/media/model_data_guidance.pdf>

Project

- App and data sizes, decisions D1, D2, D13, D18: `docs/issue23_portal-bundle/issue23-portal-bundle-plan.md`
