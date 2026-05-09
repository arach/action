export type ActionMethod =
  | "action.observe"
  | "action.resolve"
  | "action.setValue"
  | "action.click"
  | "action.rect";

export type TargetQuery = {
  selector?: string;
  text?: string;
  role?: string;
  testId?: string;
  index?: number;
};

export type ActionMessage =
  | {
      method: "action.observe";
      params?: TargetQuery & { limit?: number };
    }
  | {
      method: "action.resolve";
      params?: TargetQuery;
    }
  | {
      method: "action.setValue";
      params: TargetQuery & { value: string };
    }
  | {
      method: "action.click";
      params?: TargetQuery;
    }
  | {
      method: "action.rect";
      params?: TargetQuery;
    };

export type ElementDescriptor = {
  selector: string | null;
  tagName: string;
  text: string;
  role: string | null;
  testId: string | null;
  name: string | null;
  value: string | null;
  rect: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
};

export type ActionResponse<T = unknown> =
  | {
      ok: true;
      result: T;
    }
  | {
      ok: false;
      error: string;
    };
