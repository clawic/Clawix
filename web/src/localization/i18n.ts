import messages from "./messages.json";

type Locale = (typeof messages.supportedLocales)[number];

const supported = new Set<string>(messages.supportedLocales);

function currentLocale(): Locale {
  const nav = typeof navigator === "undefined" ? undefined : navigator;
  const candidates = nav?.languages?.length ? nav.languages : [nav?.language ?? "en"];
  for (const candidate of candidates) {
    if (supported.has(candidate)) return candidate as Locale;
    const base = candidate.split("-")[0];
    if (base === "pt" && supported.has("pt-BR")) return "pt-BR";
    if (base === "zh" && supported.has("zh-Hans")) return "zh-Hans";
    if (base && supported.has(base)) return base as Locale;
  }
  return "en";
}

export function t(key: string): string {
  const locale = currentLocale();
  const entry = messages.strings[key as keyof typeof messages.strings] as Record<Locale, string> | undefined;
  return entry?.[locale] || entry?.en || key;
}
