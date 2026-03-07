import React from "react";

interface EventCardProps {
  title: string;
  startTime: string;
  endTime?: string;
  location?: string;
  borderColor?: string;
  agentNote?: string;
}

export function EventCard({
  title,
  startTime,
  endTime,
  location,
  borderColor = "#e6a040",
  agentNote,
}: EventCardProps) {
  return (
    <div
      style={{
        background: "#2a2a3e",
        borderRadius: 16,
        padding: 0,
        boxShadow: "0 2px 8px rgba(0,0,0,0.25)",
        maxWidth: 375,
        width: "100%",
        overflow: "hidden",
        display: "flex",
      }}
    >
      {/* Colored left border */}
      <div
        style={{
          width: 4,
          background: borderColor,
          borderRadius: "16px 0 0 16px",
          flexShrink: 0,
        }}
      />

      {/* Content */}
      <div style={{ padding: "14px 16px", flex: 1, minWidth: 0 }}>
        {/* Time */}
        <div
          style={{
            color: "#8b8ba0",
            fontSize: 12,
            fontWeight: 500,
            marginBottom: 4,
          }}
        >
          {startTime}
          {endTime && ` \u2013 ${endTime}`}
        </div>

        {/* Title */}
        <div
          style={{
            color: "#f0f0f0",
            fontSize: 15,
            fontWeight: 600,
            marginBottom: location ? 6 : 0,
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {title}
        </div>

        {/* Location */}
        {location && (
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 4,
              color: "#8b8ba0",
              fontSize: 12,
            }}
          >
            <svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
              <circle cx={12} cy={10} r={3} />
            </svg>
            <span>{location}</span>
          </div>
        )}

        {/* Agent note */}
        {agentNote && (
          <div
            style={{
              marginTop: 10,
              padding: "8px 10px",
              background: "rgba(230,160,64,0.08)",
              borderRadius: 8,
              display: "flex",
              alignItems: "flex-start",
              gap: 6,
            }}
          >
            <span style={{ fontSize: 12, lineHeight: 1, flexShrink: 0, marginTop: 1 }}>
              {"\uD83E\uDD16"}
            </span>
            <span
              style={{
                color: "#8b8ba0",
                fontSize: 12,
                fontStyle: "italic",
                lineHeight: 1.4,
              }}
            >
              {agentNote}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
