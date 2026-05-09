#!/usr/bin/env bun

const command = process.argv[2] || "status";
const args = parseArgs(process.argv.slice(3));
const debugPort = args.debugPort || process.env.ACTION_MIRA_DEBUG_PORT || "9335";
const targetURL = args.url || process.env.ACTION_MIDJOURNEY_URL || "https://www.midjourney.com/imagine";
const prompt = args.prompt || process.env.ACTION_MIDJOURNEY_PROMPT || "";
const timeoutMs = Number(args.timeoutMs || process.env.ACTION_MIDJOURNEY_TIMEOUT_MS || 240000);
const minImageCount = Number(args.minImageCount || process.env.ACTION_MIDJOURNEY_MIN_IMAGE_COUNT || 0);

switch (command) {
  case "status":
    await withPage(async (page) => {
      console.log(JSON.stringify(await page.status(), null, 2));
    });
    break;
  case "submit":
    if (!prompt) {
      throw new Error("Missing --prompt");
    }
    await withPage(async (page) => {
      const before = await page.status();
      if (!before.promptReady) {
        console.log(JSON.stringify(before, null, 2));
        throw new Error("Midjourney prompt box is not ready. Sign in to Midjourney in the mira profile first.");
      }
      await page.focusPrompt();
      await page.clearPrompt();
      await page.typeText(prompt);
      await page.pressEnter();
      const after = await page.status();
      console.log(JSON.stringify({ before, after, prompt }, null, 2));
    });
    break;
  case "wait-result":
    await withPage(async (page) => {
      const startedAt = Date.now();
      let last;
      while (Date.now() - startedAt < timeoutMs) {
        last = await page.status();
        if (last.imageCount > minImageCount || (minImageCount === 0 && last.resultLikelyReady)) {
          console.log(JSON.stringify(last, null, 2));
          return;
        }
        await sleep(5000);
      }
      console.log(JSON.stringify(last ?? await page.status(), null, 2));
      process.exitCode = 2;
    });
    break;
  default:
    console.error(`Unknown command: ${command}`);
    console.error("Usage: mira-midjourney-cdp.mjs status|submit|wait-result [--debug-port PORT] [--prompt TEXT]");
    process.exit(1);
}

async function withPage(callback) {
  const target = await findOrOpenTarget();
  const client = await CDPClient.connect(target.webSocketDebuggerUrl);
  try {
    await client.send("Page.enable");
    await client.send("Runtime.enable");
    await client.send("Page.bringToFront");
    await sleep(250);
    await callback(new MidjourneyPage(client));
  } finally {
    client.close();
  }
}

async function findOrOpenTarget() {
  let targets = await listTargets();
  let target = chooseTarget(targets);
  if (target) {
    return target;
  }

  await fetch(`http://127.0.0.1:${debugPort}/json/new?${encodeURIComponent(targetURL)}`, {
    method: "PUT",
  }).catch(() => undefined);
  await sleep(1500);
  targets = await listTargets();
  target = chooseTarget(targets);
  if (!target) {
    throw new Error(`Unable to find or open Midjourney target on Chrome debug port ${debugPort}`);
  }
  return target;
}

async function listTargets() {
  const response = await fetch(`http://127.0.0.1:${debugPort}/json/list`);
  if (!response.ok) {
    throw new Error(`Chrome debug port ${debugPort} is not reachable`);
  }
  return await response.json();
}

function chooseTarget(targets) {
  return targets.find((target) => target.type === "page" && /midjourney\.com\/imagine/.test(target.url || ""))
    ?? targets.find((target) => target.type === "page" && /midjourney\.com/.test(target.url || ""))
    ?? targets.find((target) => target.type === "page" && /discord\.com\/oauth2/.test(target.url || ""));
}

class MidjourneyPage {
  constructor(client) {
    this.client = client;
  }

  async status() {
    return await this.evaluate(pageStatusExpression());
  }

  async focusPrompt() {
    const result = await this.evaluate(`
      (() => {
        const element = window.__actionFindPromptBox?.() ?? (${findPromptBoxSource()})();
        if (!element) return { ok: false, reason: "prompt box missing" };
        element.scrollIntoView({ block: "center", inline: "center" });
        element.focus();
        element.click();
        return { ok: true };
      })()
    `);
    if (!result.ok) {
      throw new Error(result.reason || "Unable to focus prompt box");
    }
  }

  async clearPrompt() {
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Meta",
      code: "MetaLeft",
      modifiers: 4,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "a",
      code: "KeyA",
      text: "a",
      unmodifiedText: "a",
      modifiers: 4,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "a",
      code: "KeyA",
      modifiers: 4,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Meta",
      code: "MetaLeft",
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Backspace",
      code: "Backspace",
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Backspace",
      code: "Backspace",
    });
  }

  async typeText(text) {
    for (const character of text) {
      await this.client.send("Input.dispatchKeyEvent", {
        type: "char",
        text: character,
        unmodifiedText: character,
      });
      await sleep(8);
    }
  }

  async pressEnter() {
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 36,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 36,
    });
  }

  async evaluate(expression) {
    const response = await this.client.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (response.exceptionDetails) {
      throw new Error(response.exceptionDetails.text || "Runtime.evaluate failed");
    }
    return response.result?.value;
  }
}

class CDPClient {
  static async connect(url) {
    const socket = new WebSocket(url);
    const client = new CDPClient(socket);
    await new Promise((resolve, reject) => {
      socket.addEventListener("open", resolve, { once: true });
      socket.addEventListener("error", reject, { once: true });
    });
    return client;
  }

  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data));
      const pending = this.pending.get(message.id);
      if (!pending) {
        return;
      }
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(new Error(message.error.message));
      } else {
        pending.resolve(message.result || {});
      }
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    this.socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }

  close() {
    this.socket.close();
  }
}

function pageStatusExpression() {
  return `
    (() => {
      ${findPromptBoxSource({ assign: true })}
      const text = document.body?.innerText || "";
      const promptBox = window.__actionFindPromptBox();
      const images = [...document.images]
        .map((image) => image.currentSrc || image.src || "")
        .filter((src) => /midjourney|cdn\\.discordapp|cdn\\.midjourney/i.test(src));
      const buttons = [...document.querySelectorAll("button,[role='button'],a")]
        .map((element) => (element.innerText || element.getAttribute("aria-label") || "").trim())
        .filter(Boolean)
        .slice(0, 30);
      return {
        url: location.href,
        title: document.title,
        promptReady: Boolean(promptBox),
        promptText: promptBox ? readText(promptBox) : "",
        imageCount: images.length,
        resultLikelyReady: images.length > 0 || /upscale|vary|rerun|download/i.test(text),
        needsLogin: /auth\\/signin|discord\\.com\\/oauth2|log in|sign up|authorize/i.test(location.href + "\\n" + text),
        buttons,
        textSample: text.replace(/\\s+/g, " ").slice(0, 500),
      };

      function readText(element) {
        if ("value" in element) return element.value || "";
        return element.innerText || element.textContent || "";
      }
    })()
  `;
}

function findPromptBoxSource(options = {}) {
  const body = `
    function isVisible(element) {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return rect.width > 80
        && rect.height > 18
        && style.visibility !== "hidden"
        && style.display !== "none";
    }
    function score(element) {
      const text = [
        element.getAttribute("aria-label"),
        element.getAttribute("placeholder"),
        element.getAttribute("data-placeholder"),
        element.innerText,
      ].filter(Boolean).join(" ").toLowerCase();
      let value = 0;
      if (/imagine|prompt|describe|what/.test(text)) value += 10;
      if (element.matches("textarea,[contenteditable='true'],[role='textbox']")) value += 6;
      if (element.matches("input")) value += 2;
      const rect = element.getBoundingClientRect();
      if (rect.bottom > window.innerHeight * 0.45) value += 2;
      return value;
    }
    const candidates = [...document.querySelectorAll("textarea,[contenteditable='true'],[role='textbox'],input[type='text'],input:not([type])")]
      .filter(isVisible)
      .sort((a, b) => score(b) - score(a));
    return candidates[0] || null;
  `;

  if (options.assign) {
    return `
      window.__actionFindPromptBox = function __actionFindPromptBox() {
        ${body}
      };
    `;
  }

  return `function () { ${body} }`;
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--debug-port") {
      parsed.debugPort = values[++index];
    } else if (value === "--url") {
      parsed.url = values[++index];
    } else if (value === "--prompt") {
      parsed.prompt = values[++index];
    } else if (value === "--timeout-ms") {
      parsed.timeoutMs = values[++index];
    } else if (value === "--min-image-count") {
      parsed.minImageCount = values[++index];
    }
  }
  return parsed;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
