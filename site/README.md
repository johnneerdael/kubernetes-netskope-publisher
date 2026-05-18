# kubernetes-netskope-publisher — docs site

Hexo + Cactus source for the public docs site at
https://johnneerdael.github.io/kubernetes-netskope-publisher/.

The same `gh-pages` branch also hosts the Helm chart repository
(`index.yaml` + chart tarballs are served alongside the docs).

## Local development

```bash
cd site
npm ci            # one-time
npx hexo server   # http://localhost:4000/kubernetes-netskope-publisher/
```

Edit Markdown under `source/`; the dev server hot-reloads.

## Build

```bash
npx hexo clean && npx hexo generate
```

Output lives in `site/public/`.

## Deploy

Deploy is automatic on push to `main` via `.github/workflows/pages.yml`.
The workflow builds and pushes `site/public/` to `gh-pages` with
`keep_files: true`, preserving the Helm repo files placed there by
`release.yml`.

## Files

- `_config.yml` — site config (URL, theme, version)
- `_config.cactus.yml` — Cactus theme overrides (dark colorscheme, nav)
- `source/` — Markdown content
- `package.json` — pinned plugin versions

See `CONTRIBUTING.md` for content conventions.
