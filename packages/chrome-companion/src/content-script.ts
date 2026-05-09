import type {
  ActionMessage,
  ActionResponse,
  ElementDescriptor,
  TargetQuery
} from "./messages.js";

declare const chrome: {
  runtime: {
    onMessage: {
      addListener: (
        callback: (
          message: unknown,
          sender: unknown,
          sendResponse: (response: ActionResponse) => void
        ) => boolean | void
      ) => void;
    };
  };
};

const defaultObserveSelector = [
  "a[href]",
  "button",
  "input",
  "select",
  "textarea",
  "[role]",
  "[tabindex]",
  "[contenteditable='true']"
].join(",");

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const response = handleMessage(message);
  sendResponse(response);
});

function handleMessage(message: unknown): ActionResponse {
  if (!isActionMessage(message)) {
    return { ok: false, error: "Unsupported Action companion message." };
  }

  try {
    switch (message.method) {
      case "action.observe":
        return {
          ok: true,
          result: observe(message.params)
        };
      case "action.resolve":
        return {
          ok: true,
          result: describe(resolveElement(message.params))
        };
      case "action.setValue":
        return {
          ok: true,
          result: setValue(message.params, message.params.value)
        };
      case "action.click":
        return {
          ok: true,
          result: clickElement(message.params)
        };
      case "action.rect":
        return {
          ok: true,
          result: describe(resolveElement(message.params))?.rect ?? null
        };
    }
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

function observe(query: (TargetQuery & { limit?: number }) | undefined) {
  const selector = query?.selector ?? defaultObserveSelector;
  const limit = query?.limit ?? 50;
  const elements = Array.from(document.querySelectorAll<HTMLElement>(selector))
    .filter(isVisible)
    .slice(0, limit)
    .map(describe)
    .filter((descriptor): descriptor is ElementDescriptor => descriptor !== null);

  return {
    url: location.href,
    title: document.title,
    activeElement: describe(document.activeElement),
    elements
  };
}

function resolveElement(query: TargetQuery | undefined): HTMLElement | null {
  const candidates = getCandidates(query);
  const index = query?.index ?? 0;
  return candidates[index] ?? null;
}

function getCandidates(query: TargetQuery | undefined): HTMLElement[] {
  if (!query || Object.keys(query).length === 0) {
    return document.activeElement instanceof HTMLElement ? [document.activeElement] : [];
  }

  const selector = query.selector ?? selectorForQuery(query);
  const rootCandidates = selector
    ? Array.from(document.querySelectorAll<HTMLElement>(selector))
    : Array.from(document.querySelectorAll<HTMLElement>(defaultObserveSelector));

  return rootCandidates.filter((element) => {
    if (!isVisible(element)) {
      return false;
    }

    if (query.text && !normalizedText(element).includes(normalize(query.text))) {
      return false;
    }

    if (query.role && element.getAttribute("role") !== query.role) {
      return false;
    }

    if (query.testId && element.getAttribute("data-testid") !== query.testId) {
      return false;
    }

    return true;
  });
}

function selectorForQuery(query: TargetQuery): string | null {
  if (query.testId) {
    return `[data-testid="${cssEscape(query.testId)}"]`;
  }

  if (query.role) {
    return `[role="${cssEscape(query.role)}"]`;
  }

  return null;
}

function setValue(query: TargetQuery, value: string) {
  const element = resolveElement(query);

  if (!element) {
    throw new Error("No element matched setValue target.");
  }

  if (
    element instanceof HTMLInputElement ||
    element instanceof HTMLTextAreaElement ||
    element instanceof HTMLSelectElement
  ) {
    element.focus();
    element.value = value;
    element.dispatchEvent(new InputEvent("input", { bubbles: true, data: value }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
    return describe(element);
  }

  if (element.isContentEditable) {
    element.focus();
    element.textContent = value;
    element.dispatchEvent(new InputEvent("input", { bubbles: true, data: value }));
    return describe(element);
  }

  throw new Error("Matched element does not accept text values.");
}

function clickElement(query: TargetQuery | undefined) {
  const element = resolveElement(query);

  if (!element) {
    throw new Error("No element matched click target.");
  }

  element.scrollIntoView({ block: "center", inline: "center" });
  element.click();
  return describe(element);
}

function describe(element: Element | null): ElementDescriptor | null {
  if (!(element instanceof HTMLElement)) {
    return null;
  }

  const rect = element.getBoundingClientRect();

  return {
    selector: stableSelector(element),
    tagName: element.tagName.toLowerCase(),
    text: normalizedText(element),
    role: element.getAttribute("role"),
    testId: element.getAttribute("data-testid"),
    name: element.getAttribute("aria-label") ?? element.getAttribute("name"),
    value: valueFor(element),
    rect: {
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height
    }
  };
}

function stableSelector(element: HTMLElement): string | null {
  if (element.id) {
    return `#${cssEscape(element.id)}`;
  }

  const testId = element.getAttribute("data-testid");
  if (testId) {
    return `[data-testid="${cssEscape(testId)}"]`;
  }

  const role = element.getAttribute("role");
  if (role) {
    return `${element.tagName.toLowerCase()}[role="${cssEscape(role)}"]`;
  }

  return element.tagName.toLowerCase();
}

function valueFor(element: HTMLElement): string | null {
  if (
    element instanceof HTMLInputElement ||
    element instanceof HTMLTextAreaElement ||
    element instanceof HTMLSelectElement
  ) {
    return element.value;
  }

  return null;
}

function isVisible(element: HTMLElement): boolean {
  const style = getComputedStyle(element);
  const rect = element.getBoundingClientRect();

  return (
    style.visibility !== "hidden" &&
    style.display !== "none" &&
    rect.width > 0 &&
    rect.height > 0
  );
}

function normalizedText(element: HTMLElement): string {
  return normalize(
    element.innerText ||
      element.textContent ||
      element.getAttribute("aria-label") ||
      element.getAttribute("title") ||
      ""
  );
}

function normalize(value: string): string {
  return value.replace(/\s+/g, " ").trim().toLowerCase();
}

function cssEscape(value: string): string {
  return typeof CSS === "undefined" ? value.replace(/"/g, '\\"') : CSS.escape(value);
}

function isActionMessage(message: unknown): message is ActionMessage {
  if (!message || typeof message !== "object") {
    return false;
  }

  const method = (message as { method?: unknown }).method;
  return (
    method === "action.observe" ||
    method === "action.resolve" ||
    method === "action.setValue" ||
    method === "action.click" ||
    method === "action.rect"
  );
}
