import React from "react";

type DeliveryStatus = "ordered" | "shipped" | "out_for_delivery" | "delivered";

interface DeliveryCardProps {
  itemName: string;
  carrier: string;
  carrierEmoji?: string;
  status: DeliveryStatus;
  eta?: string;
  trackingNumber?: string;
}

const steps: { key: DeliveryStatus; label: string }[] = [
  { key: "ordered", label: "Ordered" },
  { key: "shipped", label: "Shipped" },
  { key: "out_for_delivery", label: "Out" },
  { key: "delivered", label: "Delivered" },
];

export function DeliveryCard({
  itemName,
  carrier,
  carrierEmoji = "\uD83D\uDCE6",
  status,
  eta,
  trackingNumber,
}: DeliveryCardProps) {
  const activeIndex = steps.findIndex((s) => s.key === status);
  const amber = "#e6a040";
  const gray = "#3a3a52";
  const grayText = "#5a5a70";

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
          gap: 10,
          marginBottom: 14,
        }}
      >
        <span
          style={{
            fontSize: 28,
            lineHeight: 1,
            width: 40,
            height: 40,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: "rgba(230,160,64,0.12)",
            borderRadius: 10,
            flexShrink: 0,
          }}
        >
          {carrierEmoji}
        </span>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div
            style={{
              color: "#f0f0f0",
              fontSize: 15,
              fontWeight: 600,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {itemName}
          </div>
          <div
            style={{
              color: "#8b8ba0",
              fontSize: 12,
              display: "flex",
              gap: 8,
            }}
          >
            <span>{carrier}</span>
            {trackingNumber && (
              <span style={{ color: grayText }}>#{trackingNumber.slice(-6)}</span>
            )}
          </div>
        </div>
        {eta && (
          <div
            style={{
              color: amber,
              fontSize: 12,
              fontWeight: 600,
              whiteSpace: "nowrap",
              flexShrink: 0,
            }}
          >
            ETA {eta}
          </div>
        )}
      </div>

      {/* Progress bar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 0,
          padding: "0 4px",
        }}
      >
        {steps.map((step, i) => {
          const isComplete = i <= activeIndex;
          const isCurrent = i === activeIndex;
          return (
            <React.Fragment key={step.key}>
              {/* Connector line (before dot, except first) */}
              {i > 0 && (
                <div
                  style={{
                    flex: 1,
                    height: 2,
                    background: i <= activeIndex ? amber : gray,
                    transition: "background 0.3s",
                  }}
                />
              )}
              {/* Dot */}
              <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                <div
                  style={{
                    width: isCurrent ? 14 : 10,
                    height: isCurrent ? 14 : 10,
                    borderRadius: "50%",
                    background: isComplete ? amber : gray,
                    border: isCurrent ? `2px solid ${amber}` : "none",
                    boxShadow: isCurrent ? `0 0 8px ${amber}55` : "none",
                    transition: "all 0.3s",
                  }}
                />
                <span
                  style={{
                    fontSize: 10,
                    color: isComplete ? "#f0f0f0" : grayText,
                    fontWeight: isCurrent ? 600 : 400,
                    whiteSpace: "nowrap",
                  }}
                >
                  {step.label}
                </span>
              </div>
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}
