import { useMemo, useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import { Card, CardDivider, PageHeader, TextField } from "../../components/ui";
import { ChatIcon, CircleXIcon, SearchIcon } from "../../icons";
import { t } from "../../localization/i18n";
import { searchConversations, type SearchResult } from "./search-model";

interface Props {
  onOpenChat: (sessionId: string) => void;
}

export function SearchView({ onOpenChat }: Props) {
  const [query, setQuery] = useState("");
  const sessions = useBridgeStore((s) => s.sessions);
  const messagesBySession = useBridgeStore((s) => s.searchMessagesBySession);
  const results = useMemo(
    () => searchConversations({ sessions, messagesBySession, query }),
    [messagesBySession, query, sessions],
  );

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[760px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title={t("Search")} />
          <div
            className="flex items-center gap-2 mb-4"
            style={{
              padding: "9px 13px",
              borderRadius: 10,
              background: "var(--color-card)",
              boxShadow: "inset 0 0 0 0.5px var(--color-border)",
            }}
          >
            <SearchIcon size={13} className="text-[var(--color-fg-tertiary)]" />
            <TextField
              autoFocus
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("Search in conversations...")}
              aria-label={t("Search field")}
              className="h-7 px-0 border-0 bg-transparent"
            />
            {query.trim() && (
              <button
                type="button"
                onClick={() => setQuery("")}
                className="grid place-items-center size-6 text-[var(--color-fg-tertiary)] hover:text-[var(--color-fg)]"
                aria-label={t("Clear search")}
              >
                <CircleXIcon size={12} />
              </button>
            )}
          </div>

          {query.trim() === "" ? (
            <SearchEmpty message={t("Type to search your conversations")} />
          ) : results.length === 0 ? (
            <SearchEmpty message={`${t("No results for")} "${query.trim()}"`} />
          ) : (
            <Card>
              {results.map((result, index) => (
                <div key={result.id}>
                  {index > 0 && <CardDivider />}
                  <SearchResultRow result={result} onOpen={() => onOpenChat(result.sessionId)} />
                </div>
              ))}
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}

function SearchResultRow({
  result,
  onOpen,
}: {
  result: SearchResult;
  onOpen: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onOpen}
      className="group flex items-start gap-3 w-full text-left transition-colors hover:bg-[var(--color-card-hover)]"
      style={{ padding: "12px 14px" }}
    >
      <ChatIcon size={14} className="mt-0.5 shrink-0 text-[var(--color-fg-tertiary)]" />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <div className="truncate" style={{ fontSize: 13, fontVariationSettings: '"wght" 700' }}>
            {result.title}
          </div>
          <div className="shrink-0 text-[10.5px] text-[var(--color-fg-tertiary)]">
            {result.kind === "message" ? t("Message") : t("Chat")}
          </div>
        </div>
        <div
          className="mt-1 line-clamp-2"
          style={{ fontSize: 12.5, color: "var(--color-fg-secondary)", lineHeight: 1.45 }}
        >
          {result.snippet}
        </div>
        <div
          className="mt-1 truncate"
          style={{ fontSize: 11, color: "var(--color-fg-tertiary)" }}
        >
          {result.meta}
        </div>
      </div>
    </button>
  );
}

function SearchEmpty({ message }: { message: string }) {
  return (
    <div className="grid place-items-center py-20 text-center">
      <div className="flex flex-col items-center gap-3 text-[var(--color-fg-tertiary)]">
        <SearchIcon size={28} />
        <div style={{ fontSize: 13, fontVariationSettings: '"wght" 600' }}>{message}</div>
      </div>
    </div>
  );
}
