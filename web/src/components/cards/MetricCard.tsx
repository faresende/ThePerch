import React from "react";

interface MetricCardProps {
  label: string;
  value: number | string;
  unit: string;
  trend?: number[];
  timestamp: string;
  sourceIcon?: string;
  trendDirection?: "up" | "down" | "stable";
}

function Sparkline({ data, color }: { data: number[]; color: string }) {
  if (data.length < 2) return null;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const w = 64;
  const h = 24;
  const pad = 2;

  const points = data
    .map((v, i) => {
      const x = pad + (i / (data.length - 1)) * (w - pad * 2);
      const y = h - pad - ((v - min) / range) * (h - pad * 2);
      return `${x},${y}`;
    })
    .join(" ");

  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} fill="none">
      <polyline
        points={points}
        stroke={color}
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
      <polyline
        points={`${pad},${h} ${points} ${w - pad},${h}`}
        fill={`${color}22`}
        stroke="none"
      />
    </svg>
  );
}

const trendArrow: Record<string, { symbol: string; color: string }> = {
  up: { symbol: "\u2191", color: "#34b86e" },
  down: { symbol: "\u2193", color: "#e35252" },
  stable: { symbol: "\u2192", color: "#8b8ba0" },
};

export function MetricCard({
  label,
  value,
  unit,
  trend = [],
  timestamp,
  sourceIcon = "\u2764\uFE0F",
  trendDirection = "stable",
}: MetricCardProps) {
  const arrow = trendArrow[trendDirection];

  return (
    <div
      style={{
        background: "#2a2a3e",
        borderRadius: 16,
        padding: "14px 16px",
        display: "flex",
        alignItems: "center",
        gap: 12,
        boxShadow: "0 2px 8px rgba(0,0,0,0.25)",
        maxWidth: 375,
        width: "100%",
      }}
    >
      {/* Source icon */}
      <span style={{ fontSize: 20, lineHeight: 1, flexShrink: 0 }}>
        {sourceIcon}
      </span>

      {/* Label + value */}
      <div style={{ display: "flex", alignItems: "baseline", gap: 6, minWidth: 0 }}>
        <span
          style={{
            color: "#8b8ba0",
            fontSize: 13,
            fontWeight: 500,
            whiteSpace: "nowrap",
          }}
        >
          {label}
        </span>
        <span
          style={{
            color: "#f0f0f0",
            fontSize: 18,
            fontWeight: 700,
            whiteSpace: "nowrap",
          }}
        >
          {value}
        </span>
        <span
          style={{
            color: "#8b8ba0",
            fontSize: 13,
            fontWeight: 400,
          }}
        >
          {unit}
        </span>
      </div>

      {/* Spacer */}
      <div style={{ flex: 1 }} />

      {/* Sparkline */}
      {trend.length >= 2 && (
        <div style={{ flexShrink: 0 }}>
          <Sparkline data={trend} color="#e6a040" />
        </div>
      )}

      {/* Trend arrow */}
      <span
        style={{
          color: arrow.color,
          fontSize: 14,
          fontWeight: 600,
          flexShrink: 0,
        }}
      >
        {arrow.symbol}
      </span>

      {/* Timestamp */}
      <span
        style={{
          color: "#5a5a70",
          fontSize: 11,
          whiteSpace: "nowrap",
          flexShrink: 0,
        }}
      >
        {timestamp}
      </span>
    </div>
  );
}
