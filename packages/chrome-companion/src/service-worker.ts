import type { ActionMessage, ActionResponse } from "./messages.js";

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
  tabs: {
    query: (
      queryInfo: { active: boolean; currentWindow: boolean },
      callback: (tabs: Array<{ id?: number }>) => void
    ) => void;
    sendMessage: (
      tabId: number,
      message: ActionMessage,
      callback: (response?: ActionResponse) => void
    ) => void;
  };
};

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!isActionMessage(message)) {
    sendResponse({ ok: false, error: "Unsupported Action companion message." });
    return;
  }

  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tabId = tabs[0]?.id;

    if (tabId === undefined) {
      sendResponse({ ok: false, error: "No active tab available." });
      return;
    }

    chrome.tabs.sendMessage(tabId, message, (response) => {
      sendResponse(response ?? { ok: false, error: "No content script response." });
    });
  });

  return true;
});

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
