import React, { useState } from "react";
import { MetricCard } from "./MetricCard";
import { DeliveryCard } from "./DeliveryCard";
import { EventCard } from "./EventCard";
import { BookmarkCard } from "./BookmarkCard";
import { ChecklistCard } from "./ChecklistCard";
import { AgentStatusCard } from "./AgentStatusCard";

export function CardShowcase() {
  const [checklist, setChecklist] = useState([
    { text: "Review Supabase RLS policies", completed: true },
    { text: "Set up realtime subscriptions", completed: true },
    { text: "Design card components", completed: true },
    { text: "Implement Safari extension", completed: false },
    { text: "Deploy to TestFlight", completed: false },
  ]);

  const handleToggle = (index: number) => {
    setChecklist((prev) =>
      prev.map((item, i) =>
        i === index ? { ...item, completed: !item.completed } : item
      )
    );
  };

  return (
    <div
      style={{
        background: "#1a1a2e",
        minHeight: "100vh",
        padding: "24px 16px",
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      }}
    >
      <div
        style={{
          maxWidth: 375,
          margin: "0 auto",
          display: "flex",
          flexDirection: "column",
          gap: 12,
        }}
      >
        {/* Header */}
        <div style={{ marginBottom: 8 }}>
          <h1
            style={{
              color: "#f0f0f0",
              fontSize: 24,
              fontWeight: 700,
              margin: 0,
            }}
          >
            The Perch
          </h1>
          <p style={{ color: "#8b8ba0", fontSize: 13, margin: "4px 0 0" }}>
            Dashboard Cards
          </p>
        </div>

        {/* Metric Cards */}
        <MetricCard
          label="Weight"
          value={78.5}
          unit="kg"
          trend={[80.2, 79.8, 79.5, 79.1, 78.9, 78.7, 78.5]}
          timestamp="2h ago"
          sourceIcon={"\u2764\uFE0F"}
          trendDirection="down"
        />
        <MetricCard
          label="Steps"
          value="8,432"
          unit="steps"
          trend={[6200, 7100, 5800, 8400, 9200, 7600, 8432]}
          timestamp="Today"
          sourceIcon={"\uD83D\uDC5F"}
          trendDirection="up"
        />

        {/* Delivery Card */}
        <DeliveryCard
          itemName="MacBook Pro 16-inch M4 Max"
          carrier="FedEx"
          carrierEmoji={"\uD83D\uDE9A"}
          status="shipped"
          eta="Mar 8"
          trackingNumber="FX1234567890"
        />

        {/* Event Cards */}
        <EventCard
          title="Sprint Planning"
          startTime="2:00 PM"
          endTime="3:30 PM"
          location="Zoom Meeting Room"
          borderColor="#6366f1"
          agentNote="Archie prepared the sprint backlog summary for this meeting."
        />
        <EventCard
          title="Dentist Appointment"
          startTime="10:00 AM"
          endTime="10:45 AM"
          location="Clínica Dental, Rua Augusta 42"
          borderColor="#34b86e"
        />

        {/* Bookmark Card */}
        <BookmarkCard
          title="Building Personal AI Agents with Claude and Supabase"
          url="https://example.com/article"
          domain="anthropic.com"
          readingTime={8}
          tags={["AI", "agents", "supabase"]}
        />

        {/* Checklist Card */}
        <ChecklistCard
          title="The Perch MVP"
          items={checklist}
          onToggle={handleToggle}
        />

        {/* Agent Status Cards */}
        <AgentStatusCard
          name="Archie"
          emoji={"\uD83E\uDD89"}
          status="active"
          uptime="5d 3h"
          currentTask="Processing bookmark: React Server Components deep dive"
        />
        <AgentStatusCard
          name="Claudinho"
          emoji={"\uD83E\uDDA4"}
          status="idle"
          uptime="12d 7h"
        />
        <AgentStatusCard
          name="Sentinel"
          emoji={"\uD83D\uDEE1\uFE0F"}
          status="error"
          uptime="0d 0h"
          currentTask="Connection lost — retrying in 30s"
        />
      </div>
    </div>
  );
}
