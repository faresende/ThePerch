import React from "react";

interface ChecklistItem {
  text: string;
  completed: boolean;
}

interface ChecklistCardProps {
  title: string;
  items: ChecklistItem[];
  onToggle?: (index: number) => void;
}

export function ChecklistCard({ title, items, onToggle }: ChecklistCardProps) {
  const done = items.filter((i) => i.completed).length;
  const total = items.length;
  const pct = total > 0 ? (done / total) * 100 : 0;
  const amber = "#e6a040";

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
      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 12,
        }}
      >
        <span style={{ color: "#f0f0f0", fontSize: 15, fontWeight: 600 }}>
          {title}
        </span>
        <span style={{ color: "#8b8ba0", fontSize: 12, fontWeight: 500 }}>
          {done}/{total} done
        </span>
      </div>

      {/* Progress bar */}
      <div
        style={{
          height: 4,
          background: "#3a3a52",
          borderRadius: 2,
          marginBottom: 14,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: "100%",
            width: `${pct}%`,
            background: amber,
            borderRadius: 2,
            transition: "width 0.3s ease",
          }}
        />
      </div>

      {/* Items */}
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {items.map((item, i) => (
          <button
            key={i}
            onClick={() => onToggle?.(i)}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 10,
              background: "none",
              border: "none",
              padding: "4px 0",
              cursor: onToggle ? "pointer" : "default",
              textAlign: "left",
              width: "100%",
            }}
          >
            {/* Checkbox circle */}
            <div
              style={{
                width: 20,
                height: 20,
                borderRadius: "50%",
                border: item.completed ? "none" : "2px solid #3a3a52",
                background: item.completed ? amber : "transparent",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexShrink: 0,
                transition: "all 0.2s",
              }}
            >
              {item.completed && (
                <svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="#1a1a2e" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
              )}
            </div>

            {/* Text */}
            <span
              style={{
                color: item.completed ? "#5a5a70" : "#f0f0f0",
                fontSize: 14,
                textDecoration: item.completed ? "line-through" : "none",
                transition: "color 0.2s",
              }}
            >
              {item.text}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}
