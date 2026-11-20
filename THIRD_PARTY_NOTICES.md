# Third-party notices

The installed OpenCode runtime is a pinned Android bundle from
[Spectra010s/opencode-termux](https://github.com/Spectra010s/opencode-termux),
release tag `v2.3.2`, archive SHA-256:

`6d32b72efae7ecb6b78a5e023a8af471ea9118a6faa741fbcde9d1dfa88bd12d`

That project is distributed under the MIT License:

MIT License

Copyright (c) 2026 Oh-My-Litecode Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

The bundle also contains OpenCode from
[anomalyco/opencode](https://github.com/anomalyco/opencode), which is
distributed under the MIT License:

MIT License

Copyright (c) 2025 opencode

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Other runtime dependencies retain their own licenses and notices.

The Android/Bionic build pipeline in this repository includes build and compatibility
scripts derived from [Spectra010s/opencode-termux](https://github.com/Spectra010s/opencode-termux),
which is also distributed under the MIT License. Those scripts are maintained and
executed by this repository's own GitHub Actions workflows; no prebuilt runtime
release from that project is required by the build pipeline.

The build fetches OpenCode source from
[anomalyco/opencode](https://github.com/anomalyco/opencode) at the exact commit
recorded in `tools/supply-chain-lock.json`. OpenTUI and bun-pty sources are also
pinned to immutable commits in that lock file. Their original licenses and
notices remain applicable. The published runtime report and source lock accompany
each release for provenance.
