// Parse stable Alpine branch links from the official releases page.
// Only the official site and Alpine's official download mirror are trusted.
const OFFICIAL_HOSTS = new Set([
  "alpinelinux.org",
  "www.alpinelinux.org",
  "dl-cdn.alpinelinux.org",
]);

export function findStableBranches(html) {
  const versions = new Set();
  for (const match of html.matchAll(/\bhref\s*=\s*(["'])(.*?)\1/gi)) {
    let url;
    try {
      url = new URL(match[2], "https://alpinelinux.org/releases/");
    } catch {
      continue;
    }
    if (!OFFICIAL_HOSTS.has(url.hostname.toLowerCase())) continue;

    const branchMatch = url.pathname.match(/^\/alpine\/v(\d+)\.(\d+)\/?$/)
      ?? url.pathname.match(/^\/releases\/v?(\d+)\.(\d+)\/?$/);
    if (!branchMatch) continue;

    const major = Number(branchMatch[1]);
    const minor = Number(branchMatch[2]);
    if (major < 3 || !Number.isSafeInteger(major) || !Number.isSafeInteger(minor) || minor < 0) continue;
    versions.add(`${major}.${minor}`);
  }

  return [...versions].sort((a, b) => {
    const [aMajor, aMinor] = a.split(".").map(Number);
    const [bMajor, bMinor] = b.split(".").map(Number);
    return aMajor - bMajor || aMinor - bMinor;
  });
}
