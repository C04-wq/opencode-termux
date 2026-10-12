import assert from "node:assert/strict";
import { findStableBranches } from "./alpine-release-branches.mjs";

const officialPage = `
  <a href="https://dl-cdn.alpinelinux.org/alpine/v3.24/">v3.24</a>
  <a href="https://dl-cdn.alpinelinux.org/alpine/v3.23/">v3.23</a>
  <a href="https://dl-cdn.alpinelinux.org/alpine/v3.22/">v3.22</a>
  <a href="/releases/v3.21/">v3.21</a>
  <a href="https://example.com/alpine/v99.99/">untrusted</a>
  <a href="https://dl-cdn.alpinelinux.org/alpine/edge/">edge</a>
`;

assert.deepEqual(findStableBranches(officialPage), ["3.21", "3.22", "3.23", "3.24"]);
assert.deepEqual(findStableBranches("<html><body>No branch links</body></html>"), []);
console.log("Alpine release branch parser tests passed.");
