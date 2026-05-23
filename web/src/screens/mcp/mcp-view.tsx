// MCP mirror.
import { PageHeader, Card } from "../../components/ui";
import { t } from "../../localization/i18n";

export function McpView() {
  return (
    <div className="h-full flex flex-col">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title={t("MCP servers")} subtitle={t("Model Context Protocol endpoints.")} />
          <Card>
            <div className="space-y-2" style={{ padding: 16 }}>
              <div
                style={{ fontSize: 14, fontVariationSettings: '"wght" 800', letterSpacing: "-0.01em" }}
              >
                Connected MCP servers
              </div>
              <p
                style={{
                  fontSize: 12.5,
                  color: "var(--color-fg-secondary)",
                  lineHeight: 1.55,
                }}
              >
                MCP server configuration is managed through the ClawJS MCP route from the signed
                host. Web edits require a dedicated MCP wire frame; until then, manage servers from
                the Mac and the bridge will surface their tools to your sessions automatically.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
