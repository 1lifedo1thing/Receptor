# Cydia repository maintenance

This directory is the legacy Receptor flat APT repository, published by GitHub Pages from `main:/docs`. The main source for Receptor and future tweaks is now **https://jajaengland.github.io/**, maintained in [jajaengland/jajaengland.github.io](https://github.com/jajaengland/jajaengland.github.io). This legacy source remains available so existing installs and binary-embedded depiction links keep working.

- Cydia source: `https://jajaengland.github.io/Receptor/`
- APT source line: `deb https://jajaengland.github.io/Receptor/ ./`
- Package pool: `debs/`
- Package indexes: `Packages`, `Packages.gz`, `Packages.bz2`
- Release metadata: `Release`

Build the new package, then regenerate all indexes and hashes:

```sh
bash scripts/build-wsl.sh
python3 scripts/update-repository.py
python3 tests/check_repository.py
```

For a new version, update `control`, supply that version's package path, update the website's version/download details, and commit the rebuilt repository files together. The generator indexes all `.deb` files in `docs/debs`. It includes MD5, SHA1 and SHA256 package checksums and matching Release checksums for every index. It uses gzip and bzip2 for compatibility with older Cydia clients. The repository has no Release signature; package-manager versions that require signed repositories may display a trust warning or require explicit configuration. Do not commit private signing keys or GitHub credentials.

GitHub rejected disabling HTTPS enforcement for this default `github.io` site. HTTP requests redirect to HTTPS; the owner chose to keep HTTPS hosting for now. Legacy clients without compatible TLS or trust roots may fail to refresh this source. Plain HTTP would require a suitable custom domain or an alternative host. The 1.0.0 package's HTTP Depiction URL redirects to the live HTTPS page; its binary and package checksums have been preserved after initial publication.

Enable Pages with the `main` branch and `/docs` folder. The `.nojekyll` file preserves the repository files without Jekyll processing. To check a deployed update, fetch the live Packages index and package file and compare their SHA256 hashes with this checkout.

When releasing a future Receptor version, also import its built `.deb` into the general repository using that repository's `scripts/update-repository.py /path/to/package.deb`, run `scripts/verify.py`, and push its update. Other tweaks can be imported through the same generic workflow without editing Receptor's source project. Keep already released package bytes immutable.
