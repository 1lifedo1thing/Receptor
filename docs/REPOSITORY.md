# Cydia repository maintenance

This directory is a flat APT repository, published by GitHub Pages from `main:/docs`.

- Cydia source: `http://jajaengland.github.io/Receptor/`
- APT source line: `deb http://jajaengland.github.io/Receptor/ ./`
- Package pool: `debs/`
- Package indexes: `Packages`, `Packages.gz`, `Packages.bz2`
- Release metadata: `Release`

Build the new package, then regenerate all indexes and hashes:

```sh
bash scripts/build-wsl.sh
python3 scripts/update-repository.py packages/com.receptor.downloadmanager_1.0.0_iphoneos-arm.deb
python3 tests/check_repository.py
```

For a new version, update `control`, supply that version's package path, update the website's version/download details, and commit the rebuilt repository files together. The generator indexes all `.deb` files in `docs/debs`. It includes MD5, SHA1 and SHA256 package checksums and matching Release checksums for every index. It uses gzip and bzip2 for compatibility with older Cydia clients. GitHub Pages must have HTTPS enforcement disabled to serve HTTP to legacy devices. The repository has no Release signature; package-manager versions that require signed repositories may display a trust warning or require explicit configuration. Do not commit private signing keys or GitHub credentials.

Enable Pages with the `main` branch and `/docs` folder. The `.nojekyll` file preserves the repository files without Jekyll processing. To check a deployed update, fetch the live Packages index and package file and compare their SHA256 hashes with this checkout.
