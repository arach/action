#!/usr/bin/env bun

import {
  profileName,
  sleep,
  stopMiraChrome,
  launchMira,
} from "./mira-chrome.mjs";
import {
  copyCookiesToProfile,
  listCookieEntries,
  listPersonalProfiles,
  parseCookieSelectors,
  readCookies,
  resolveSourceProfileDir,
  targetProfileDir,
} from "./chrome-cookies.mjs";

const args = process.argv.slice(2);

function parseArgs(values) {
  const parsed = {
    command: "help",
    sourceProfile: undefined,
    domains: [],
    only: [],
    confirm: false,
    json: false,
    listProfiles: false,
  };

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "list" || value === "list-domains") {
      parsed.command = "list";
    } else if (value === "import") {
      parsed.command = "import";
    } else if (value === "--source") {
      parsed.sourceProfile = values[index + 1];
      index += 1;
    } else if (value === "--domains") {
      parsed.domains = splitList(values[++index]);
    } else if (value === "--only" || value === "--names" || value === "--cookies") {
      parsed.only = splitList(values[++index]);
    } else if (value === "--confirm") {
      parsed.confirm = true;
    } else if (value === "--json") {
      parsed.json = true;
    } else if (value === "--list-profiles") {
      parsed.listProfiles = true;
    }
  }

  parsed.selectors = parseCookieSelectors(parsed.only);
  return parsed;
}

function splitList(raw) {
  return raw.split(",").map((entry) => entry.trim()).filter(Boolean);
}

function printHelp() {
  console.log(`Copy cookies from personal Chrome into the ${profileName} profile.

  bun scripts/import-cookies.mjs list --domains midjourney.com
  bun scripts/import-cookies.mjs import --domains midjourney.com --confirm
  bun scripts/import-cookies.mjs import --domains midjourney.com --only cf_clearance,__Host-Midjourney.AuthUserTokenV3_r --confirm

Options:
  --source <profile>   Default, Profile 1, ... (default: most recently used)
  --domains <sites>    Limit by site
  --only <cookies>     Cookie names, or host:name for one exact cookie
  --confirm            Actually copy them
  --json               Machine-readable output
`);
}

function ensureSelection(parsed) {
  if (!parsed.domains.length && !parsed.selectors.length) {
    throw new Error("Pass --domains and/or --only.");
  }
}

function printCookieList(cookies) {
  for (const cookie of cookies) {
    console.log(`${cookie.hostKey}  ${cookie.name}`);
  }
}

async function main() {
  const parsed = parseArgs(args);

  if (parsed.listProfiles) {
    console.log(JSON.stringify(listPersonalProfiles(), null, 2));
    return;
  }

  if (parsed.command === "help" || args.length === 0) {
    printHelp();
    return;
  }

  const sourceProfilePath = resolveSourceProfileDir(parsed.sourceProfile);
  const destProfilePath = targetProfileDir(profileName);

  if (parsed.command === "list") {
    ensureSelection(parsed);
    const cookies = listCookieEntries(sourceProfilePath, {
      domains: parsed.domains,
      selectors: parsed.selectors,
    });
    if (parsed.json) {
      console.log(JSON.stringify({ sourceProfilePath, cookies }, null, 2));
      return;
    }
    printCookieList(cookies);
    console.log(`\n${cookies.length} cookies`);
    return;
  }

  if (parsed.command !== "import") {
    printHelp();
    process.exit(1);
  }

  ensureSelection(parsed);

  const matches = readCookies(sourceProfilePath, {
    domains: parsed.domains,
    selectors: parsed.selectors,
    decrypt: false,
  });

  if (matches.length === 0) {
    throw new Error("No matching cookies.");
  }

  if (!parsed.confirm) {
    if (parsed.json) {
      console.log(JSON.stringify({
        sourceProfilePath,
        count: matches.length,
        cookies: matches.map((cookie) => `${cookie.hostKey}:${cookie.name}`),
      }, null, 2));
    } else {
      printCookieList(matches);
      console.log(`\n${matches.length} cookies ready. Re-run with --confirm to copy into ${profileName}.`);
    }
    return;
  }

  const stoppedPid = stopMiraChrome();
  if (stoppedPid) {
    await sleep(1500);
  }

  const copied = copyCookiesToProfile(sourceProfilePath, destProfilePath, {
    domains: parsed.domains,
    selectors: parsed.selectors,
  });

  await launchMira("https://www.midjourney.com/imagine");
  console.log(`Copied ${copied.length} cookies into ${profileName}.`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});