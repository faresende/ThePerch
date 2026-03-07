import React from "react";

interface BookmarkCardProps {
  title: string;
  url: string;
  domain: string;
  faviconUrl?: string;
  readingTime?: number;
  tags?: string[];
}

export function BookmarkCard({
  title,
  url,
  domain,
  faviconUrl,
  readingTime,
  tags = [],
}: BookmarkCardProps) {
  const initial = domain.charAt(0).toUpperCase();

  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      style={{
        textDecoration: "none",
        display: "block",
        background: "#2a2a3e",
        borderRadius: 16,
        padding: 16,
        boxShadow: "0 2px 8px rgba(0,0,0,0.25)",
        maxWidth: 375,
        width: "100%",
        transition: "background 0.2s",
      }}
      onMouseEnter={(e) => (e.currentTarget.style.background = "#32324a")}
      onMouseLeave={(e) => (e.currentTarget.style.background = "#2a2a3e")}
    >
      <div style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
        {/* Favicon */}
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: 10,
            background: "rgba(230,160,64,0.12)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexShrink: 0,
            overflow: "hidden",
          }}
        >
          {faviconUrl ? (
            <img
              src={faviconUrl}
              alt=""
              width={20}
              height={20}
              style={{ borderRadius: 4 }}
            />
          ) : (
            <span
              style={{
                color: "#e6a040",
                fontSize: 16,
                fontWeight: 700,
              }}
            >
              {initial}
            </span>
          )}
        </div>

        {/* Content */}
        <div style={{ flex: 1, minWidth: 0 }}>
          {/* Title */}
          <div
            style={{
              color: "#f0f0f0",
              fontSize: 14,
              fontWeight: 600,
              lineHeight: 1.3,
              marginBottom: 4,
              display: "-webkit-box",
              WebkitLineClamp: 2,
              WebkitBoxOrient: "vertical",
              overflow: "hidden",
            }}
          >
            {title}
          </div>

          {/* Domain + reading time */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              marginBottom: tags.length > 0 ? 10 : 0,
            }}
          >
            <span style={{ color: "#8b8ba0", fontSize: 12 }}>{domain}</span>
            {readingTime && (
              <span
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 3,
                  color: "#8b8ba0",
                  fontSize: 11,
                  background: "rgba(139,139,160,0.12)",
                  padding: "2px 7px",
                  borderRadius: 6,
                }}
              >
                <svg width={10} height={10} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="round">
                  <circle cx={12} cy={12} r={10} />
                  <polyline points="12 6 12 12 16 14" />
                </svg>
                {readingTime} min
              </span>
            )}
          </div>

          {/* Tags */}
          {tags.length > 0 && (
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
              {tags.map((tag) => (
                <span
                  key={tag}
                  style={{
                    fontSize: 11,
                    fontWeight: 500,
                    color: "#e6a040",
                    background: "rgba(230,160,64,0.12)",
                    padding: "2px 8px",
                    borderRadius: 6,
                  }}
                >
                  {tag}
                </span>
              ))}
            </div>
          )}
        </div>
      </div>
    </a>
  );
}
