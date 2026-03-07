import React from "react";

type AgentStatus = "active" | "idle" | "error";

interface AgentStatusCardProps {
  name: string;
  emoji: string;
  status: AgentStatus;
  uptime: string;
  currentTask?: string;
}

const statusConfig: Record<AgentStatus, { color: string; label: string }> = {
  active: { color: "#34b86e", label: "Active" },
  idle: { color: "#e6a040", label: "Idle" },
  error: { color: "#e35252", label: "Error" },
};

export function AgentStatusCard({
  name,
  emoji,
  status,
  uptime,
  currentTask,
}: AgentStatusCardProps) {
  const cfg = statusConfig[status];

  return (
    <div
      style={{
        background: "#2a2a3e",
        borderRadius: 16,
        padding: 16,
        boxShadow: "0 2px 8px rgba(0,0,0,0.25)",
        maxWidth: 375,
        width: "100%",
      }}
    >
      <div style={{ display: "flex", gap: 12 }}>
        {/* Emoji avatar */}
        <div
          style={{
            width: 44,
            height: 44,
            borderRadius: 14,
            background: "rgba(230,160,64,0.10)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 24,
            lineHeight: 1,
            flexShrink: 0,
          }}
        >
          {emoji}
        </div>

        {/* Info */}
        <div style={{ flex: 1, minWidth: 0 }}>
          {/* Name row */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              marginBottom: 2,
            }}
          >
            <span
              style={{
                color: "#f0f0f0",
                fontSize: 15,
                fontWeight: 600,
              }}
            >
              {name}
            </span>

            {/* Status dot */}
            <span
              style={{
                position: "relative",
                display: "inline-flex",
                alignItems: "center",
                gap: 4,
              }}
            >
              <span
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: "50%",
                  background: cfg.color,
                  display: "inline-block",
                  boxShadow: status === "active" ? `0 0 6px ${cfg.color}` : "none",
                  animation: status === "active" ? "perch-pulse 2s infinite" : "none",
                }}
              />
              <span style={{ color: cfg.color, fontSize: 11, fontWeight: 600 }}>
                {cfg.label}
              </span>
            </span>
          </div>

          {/* Uptime */}
          <div style={{ color: "#5a5a70", fontSize: 12, marginBottom: currentTask ? 8 : 0 }}>
            Uptime: {uptime}
          </div>

          {/* Current task */}
          {currentTask && (
            <div
              style={{
                color: "#8b8ba0",
                fontSize: 13,
                lineHeight: 1.4,
                padding: "6px 10px",
                background: "rgba(139,139,160,0.08)",
                borderRadius: 8,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {currentTask}
            </div>
          )}
        </div>
      </div>

      {/* Pulse animation */}
      <style>{`
        @keyframes perch-pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
      `}</style>
    </div>
  );
}
