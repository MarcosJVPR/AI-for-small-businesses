import type { Category } from "./api";

export const CATEGORY_LABEL: Record<Category, string> = {
  legal: "Legal",
  contable: "Contable",
  administrativo: "Administrativo",
  general: "General",
};

export const CATEGORY_OPTIONS: Category[] = ["legal", "contable", "administrativo", "general"];
