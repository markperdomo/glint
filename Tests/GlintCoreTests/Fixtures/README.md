# Archive fixtures

These files contain only generated 120 × 80 RGB PNGs, a short text file, and a hidden PNG. No private images are included. They are distributed under the repository's MIT license.

- `solid` / `independent` RAR and 7z files: generated with official RAR 7.23 and 7-Zip 26.03. Exercise decompression, shared streams, Unicode filenames, hidden-file filtering, cache reuse, and concurrent requests.
- `encrypted` RAR and 7z: test password `glint-test`; header encryption verifies failure without an interactive prompt.
- `classic-solid.rar`: generated RAR4 stored-file headers with solid flags. Covers classic RAR parsing and the older solid-header case rejected by libarchive; it does not benchmark compressed RAR4.

To regenerate equivalent fixtures (archive timestamps and compression levels may change bytes):

```sh
python3 Scripts/generate-archive-fixtures.py /tmp/Glint-Archive-Fixtures --rar /path/to/rar --sevenzip /path/to/7zz
cp /tmp/Glint-Archive-Fixtures/*.rar /tmp/Glint-Archive-Fixtures/*.7z Tests/GlintCoreTests/Fixtures/
```

The `--large` option produces separate performance fixtures outside the repository.
