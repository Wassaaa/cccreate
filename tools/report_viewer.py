from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import argparse
import gzip
import json
import os
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
INBOX = ROOT / "inbox"


TAG_END = 0
TAG_BYTE = 1
TAG_INT = 3
TAG_STRING = 8
TAG_LIST = 9
TAG_COMPOUND = 10

DATA_VERSION = 3953


HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ComputerCraft Report Viewer</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f6f2;
      --panel: #ffffff;
      --panel-2: #f0f3ee;
      --text: #1f271f;
      --muted: #66705f;
      --line: #d7ddcf;
      --ok: #21764b;
      --bad: #a83232;
      --warn: #8a651d;
      --code-bg: #111711;
      --code-text: #ecf5e9;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      background: var(--bg);
      color: var(--text);
      font-size: 14px;
    }

    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      min-height: 58px;
      padding: 12px 18px;
      border-bottom: 1px solid var(--line);
      background: #fbfcf8;
    }

    h1 {
      margin: 0;
      font-size: 18px;
      line-height: 1.2;
      font-weight: 700;
      letter-spacing: 0;
    }

    .status {
      display: flex;
      align-items: center;
      gap: 10px;
      color: var(--muted);
      white-space: nowrap;
      font-size: 13px;
    }

    .dot {
      width: 9px;
      height: 9px;
      border-radius: 999px;
      background: var(--warn);
    }

    .dot.ok {
      background: var(--ok);
    }

    .dot.bad {
      background: var(--bad);
    }

    main {
      display: grid;
      grid-template-columns: minmax(250px, 320px) minmax(0, 1fr);
      min-height: calc(100vh - 58px);
    }

    aside {
      border-right: 1px solid var(--line);
      background: var(--panel-2);
      min-width: 0;
      overflow: auto;
    }

    .sidebar-head {
      padding: 14px;
      border-bottom: 1px solid var(--line);
    }

    .sidebar-head strong {
      display: block;
      margin-bottom: 8px;
    }

    .search {
      width: 100%;
      height: 34px;
      padding: 6px 9px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: #fff;
      color: var(--text);
      font: inherit;
    }

    .report-list {
      display: grid;
    }

    .report-row {
      display: block;
      width: 100%;
      border: 0;
      border-bottom: 1px solid var(--line);
      padding: 10px 14px;
      background: transparent;
      color: inherit;
      text-align: left;
      font: inherit;
      cursor: pointer;
    }

    .report-row:hover,
    .report-row.active {
      background: #e6eee3;
    }

    .report-row .name {
      display: block;
      font-weight: 650;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .report-row .meta {
      display: flex;
      gap: 8px;
      align-items: center;
      margin-top: 4px;
      color: var(--muted);
      font-size: 12px;
    }

    .ok-text {
      color: var(--ok);
      font-weight: 650;
    }

    .bad-text {
      color: var(--bad);
      font-weight: 650;
    }

    .content {
      min-width: 0;
      overflow: auto;
      padding: 18px;
    }

    .summary {
      display: grid;
      grid-template-columns: repeat(5, minmax(120px, 1fr));
      gap: 10px;
      margin-bottom: 14px;
    }

    .metric {
      padding: 10px 12px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      min-width: 0;
    }

    .metric .label {
      display: block;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 4px;
    }

    .metric .value {
      display: block;
      font-size: 15px;
      font-weight: 700;
      overflow-wrap: anywhere;
    }

    .tabs {
      display: flex;
      gap: 6px;
      padding: 4px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      width: fit-content;
      margin-bottom: 14px;
      flex-wrap: wrap;
    }

    .tab {
      border: 0;
      border-radius: 5px;
      padding: 7px 10px;
      background: transparent;
      color: var(--muted);
      font: inherit;
      cursor: pointer;
    }

    .tab.active {
      background: #dfeade;
      color: var(--text);
      font-weight: 650;
    }

    section.block {
      margin-bottom: 16px;
    }

    section.block h2 {
      margin: 0 0 8px;
      font-size: 15px;
      line-height: 1.3;
      letter-spacing: 0;
    }

    .empty {
      padding: 18px;
      border: 1px dashed var(--line);
      border-radius: 6px;
      background: var(--panel);
      color: var(--muted);
    }

    pre {
      margin: 0;
      padding: 13px;
      border-radius: 6px;
      background: var(--code-bg);
      color: var(--code-text);
      overflow: auto;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      line-height: 1.42;
      font: 13px/1.42 ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 6px;
      overflow: hidden;
    }

    th, td {
      padding: 8px 10px;
      border-bottom: 1px solid var(--line);
      text-align: left;
      vertical-align: top;
      overflow-wrap: anywhere;
    }

    th {
      background: #eef3eb;
      font-size: 12px;
      color: var(--muted);
      font-weight: 700;
    }

    tr:last-child td {
      border-bottom: 0;
    }

    .grid-2 {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      gap: 14px;
    }

    .kv {
      display: grid;
      gap: 8px;
      grid-template-columns: 160px minmax(0, 1fr);
      padding: 12px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
    }

    .kv dt {
      color: var(--muted);
    }

    .kv dd {
      margin: 0;
      overflow-wrap: anywhere;
      font-weight: 600;
    }

    .file-controls {
      display: flex;
      gap: 10px;
      align-items: center;
      margin-bottom: 10px;
      flex-wrap: wrap;
    }

    .pill {
      display: inline-flex;
      align-items: center;
      min-height: 22px;
      padding: 2px 8px;
      border-radius: 999px;
      background: #e5ece1;
      color: var(--muted);
      font-size: 12px;
      font-weight: 650;
    }

    .map-controls {
      display: flex;
      gap: 8px;
      align-items: center;
      flex-wrap: wrap;
      margin-bottom: 12px;
    }

    .map-layer {
      margin-bottom: 18px;
    }

    .map-layer h3 {
      margin: 0 0 8px;
      font-size: 14px;
      letter-spacing: 0;
    }

    .map-scroll {
      max-width: 100%;
      overflow: auto;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      padding: 8px;
    }

    .router-map {
      display: grid;
      gap: 4px;
      width: max-content;
      min-width: 100%;
    }

    .map-axis,
    .map-cell {
      min-height: 54px;
      border: 1px solid var(--line);
      border-radius: 5px;
      padding: 6px;
      overflow: hidden;
    }

    .map-axis {
      min-height: 28px;
      background: #eef3eb;
      color: var(--muted);
      font-size: 12px;
      font-weight: 700;
      text-align: center;
    }

    .map-cell {
      background: #f8faf6;
      font-size: 12px;
      cursor: pointer;
      position: relative;
    }

    .map-cell.has-network {
      border-top: 4px solid var(--network-color, #6f7f8f);
    }

    .map-cell.empty {
      background: #f2f4ef;
      border-style: dashed;
      color: #9aa493;
    }

    .map-cell.inventory {
      background: #e5f1e7;
      border-color: #acc9b0;
    }

    .map-cell.attitude {
      background: #f2eafb;
      border-color: #cbb5e5;
    }

    .map-cell.scalar {
      background: #fff3d8;
      border-color: #dcc17a;
    }

    .map-cell.rotor {
      background: #e0f3ef;
      border-color: #94c6bd;
    }

    .map-cell.display {
      background: #edf1ff;
      border-color: #b8c3e3;
    }

    .map-cell.kinetic {
      background: #eaf3f8;
      border-color: #abc7d6;
    }

    .map-cell.inferred {
      background: #f4f0e7;
      border-color: #c9b98d;
      border-style: dashed;
    }

    .map-cell.wrappable,
    .map-cell.terminal,
    .map-cell.modem,
    .map-cell.redstone,
    .map-cell.energy,
    .map-cell.fluid {
      background: #e7eef7;
      border-color: #b6c7dc;
    }

    .map-cell.error {
      background: #f9e7e3;
      border-color: #d0aaa1;
    }

    .map-cell.scada-warn {
      box-shadow: inset 0 0 0 2px rgba(138, 101, 29, .35);
    }

    .map-cell.scada-bad {
      box-shadow: inset 0 0 0 2px rgba(168, 50, 50, .45);
    }

    .map-coord {
      display: block;
      color: var(--muted);
      font-family: ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace;
      font-size: 11px;
      margin-bottom: 3px;
    }

    .map-name {
      display: block;
      font-weight: 700;
      line-height: 1.25;
      overflow-wrap: anywhere;
    }

    .map-detail {
      display: block;
      margin-top: 3px;
      color: var(--muted);
      line-height: 1.25;
      overflow-wrap: anywhere;
    }

    .copy-btn {
      display: inline-flex;
      align-items: center;
      border: 1px solid var(--line);
      border-radius: 5px;
      padding: 4px 7px;
      background: #fbfcf8;
      color: var(--text);
      font: inherit;
      font-size: 12px;
      cursor: pointer;
      text-decoration: none;
    }

    .copy-btn:hover {
      background: #e6eee3;
    }

    .copy-actions {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
    }

    .copy-status {
      min-height: 20px;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 8px;
    }

    .status-line {
      display: flex;
      gap: 8px;
      align-items: center;
      flex-wrap: wrap;
      margin-bottom: 12px;
    }

    .warn-text {
      color: var(--warn);
      font-weight: 650;
    }

    tr.row-ok td:first-child {
      border-left: 4px solid var(--ok);
    }

    tr.row-warn td:first-child {
      border-left: 4px solid var(--warn);
    }

    tr.row-bad td:first-child {
      border-left: 4px solid var(--bad);
    }

    tr.row-info td:first-child {
      border-left: 4px solid #386fa4;
    }

    tr.row-ok {
      background: #f1f8f1;
    }

    tr.row-warn {
      background: #fbf6e9;
    }

    tr.row-bad {
      background: #fbebe8;
    }

    tr.row-info {
      background: #edf4fb;
    }

    .mono {
      font-family: ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace;
    }

    @media (max-width: 900px) {
      main {
        grid-template-columns: 1fr;
      }

      aside {
        max-height: 260px;
        border-right: 0;
        border-bottom: 1px solid var(--line);
      }

      .summary,
      .grid-2 {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <header>
    <h1>ComputerCraft Report Viewer</h1>
    <div class="status"><span id="pollDot" class="dot"></span><span id="pollStatus">Starting...</span></div>
  </header>
  <main>
    <aside>
      <div class="sidebar-head">
        <strong>Reports</strong>
        <input id="reportSearch" class="search" placeholder="Filter reports" autocomplete="off">
      </div>
      <div id="reportList" class="report-list"></div>
    </aside>
    <div class="content">
      <div id="summary" class="summary"></div>
      <div id="tabs" class="tabs"></div>
      <div id="view"></div>
    </div>
  </main>

  <script>
    const state = {
      latest: null,
      selectedFile: "latest-report.json",
      activeTab: "overview",
      reports: [],
      reportFilter: "",
      fileFilter: ""
    };

    const stackTabs = ["overview", "moves", "raw"];

    const els = {
      dot: document.getElementById("pollDot"),
      poll: document.getElementById("pollStatus"),
      list: document.getElementById("reportList"),
      search: document.getElementById("reportSearch"),
      summary: document.getElementById("summary"),
      tabs: document.getElementById("tabs"),
      view: document.getElementById("view")
    };

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
    }

    function fmtBool(value) {
      if (value === true) return '<span class="ok-text">ok</span>';
      if (value === false) return '<span class="bad-text">failed</span>';
      return '<span>n/a</span>';
    }

    function fmtDate(value) {
      if (!value) return "n/a";
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return value;
      return date.toLocaleString();
    }

    function asArray(value) {
      return Array.isArray(value) ? value : [];
    }

    function typeText(value) {
      if (Array.isArray(value)) return value.join(", ");
      return value ?? "";
    }

    function shortCommand(report) {
      return report?.command || report?.message || report?.kind || "(no command)";
    }

    async function fetchJson(url) {
      const response = await fetch(url, { cache: "no-store" });
      if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
      return response.json();
    }

    async function refreshLatest() {
      try {
        const data = await fetchJson(`/api/report?file=${encodeURIComponent(state.selectedFile)}`);
        state.latest = data.report;
        els.dot.className = "dot ok";
        els.poll.textContent = data.exists ? `Updated ${fmtDate(data.modified)}` : "No report yet";
        render();
      } catch (error) {
        els.dot.className = "dot bad";
        els.poll.textContent = `Viewer error: ${error.message}`;
      }
    }

    async function refreshReports() {
      try {
        const data = await fetchJson("/api/reports");
        state.reports = data.reports || [];
        renderReportList();
      } catch (error) {
        els.poll.textContent = `Report list error: ${error.message}`;
      }
    }

    function renderReportList() {
      const filter = state.reportFilter.toLowerCase();
      const reports = state.reports.filter((item) => {
        const haystack = `${item.name} ${item.kind || ""} ${item.command || ""}`.toLowerCase();
        return haystack.includes(filter);
      });

      els.list.innerHTML = reports.map((item) => {
        const active = item.name === state.selectedFile ? " active" : "";
        const ok = item.ok === true ? "ok" : item.ok === false ? "fail" : item.kind || "report";
        const okClass = item.ok === false ? "bad-text" : item.ok === true ? "ok-text" : "";
        return `
          <button class="report-row${active}" data-file="${escapeHtml(item.name)}">
            <span class="name">${escapeHtml(item.command || item.kind || item.name)}</span>
            <span class="meta"><span class="${okClass}">${escapeHtml(ok)}</span><span>${escapeHtml(fmtDate(item.modified))}</span></span>
          </button>
        `;
      }).join("") || '<div class="empty">No reports found.</div>';

      for (const button of els.list.querySelectorAll("button[data-file]")) {
        button.addEventListener("click", () => {
          state.selectedFile = button.dataset.file;
          refreshLatest();
          renderReportList();
        });
      }
    }

    function render() {
      const report = state.latest;

      if (!report) {
        els.summary.innerHTML = "";
        els.tabs.innerHTML = "";
        els.view.innerHTML = '<div class="empty">No report loaded. Send <span class="mono">report</span> or <span class="mono">report run &lt;program&gt;</span> from ComputerCraft.</div>';
        return;
      }

      els.summary.innerHTML = renderSummary(report);
      const reportTabs = tabsForReport(report);
      if (!reportTabs.includes(state.activeTab)) state.activeTab = reportTabs[0] || "overview";

      els.tabs.innerHTML = reportTabs.map((tab) => {
        const active = tab === state.activeTab ? " active" : "";
        return `<button class="tab${active}" data-tab="${tab}">${escapeHtml(tabLabel(report, tab))}</button>`;
      }).join("");

      for (const button of els.tabs.querySelectorAll("button[data-tab]")) {
        button.addEventListener("click", () => {
          state.activeTab = button.dataset.tab;
          render();
        });
      }

      const customTab = customTabForReport(report, state.activeTab);
      if (customTab) {
        els.view.innerHTML = renderCustomTab(customTab);
        return;
      }

      if (state.activeTab === "overview") els.view.innerHTML = renderOverview(report);
      if (state.activeTab === "moves") els.view.innerHTML = renderStackMoves(report);
      if (state.activeTab === "map") {
        els.view.innerHTML = renderRouterMap(report);
        bindCopyActions();
      }
      if (state.activeTab === "output") els.view.innerHTML = renderOutput(report);
      if (state.activeTab === "peripherals") els.view.innerHTML = renderPeripherals(report);
      if (state.activeTab === "inventory") els.view.innerHTML = renderInventory(report);
      if (state.activeTab === "files") {
        els.view.innerHTML = renderFiles(report);
        const input = document.getElementById("fileFilter");
        if (input) {
          input.value = state.fileFilter;
          input.addEventListener("input", () => {
            state.fileFilter = input.value;
            render();
          });
        }
      }
      if (state.activeTab === "raw") els.view.innerHTML = renderRaw(report);
    }

    function hasObjectValues(value) {
      return value && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length > 0;
    }

    function hasOutputContent(report) {
      return Boolean(report?.output || report?.error);
    }

    function hasInventoryContent(report) {
      return asArray(report?.inventory).length > 0 || hasObjectValues(report?.args);
    }

    function customTabs(report) {
      return asArray(report?.human?.tabs).filter((tab) => tab && tab.id);
    }

    function customTabId(tab) {
      return `custom:${tab.id}`;
    }

    function customTabForReport(report, tabId) {
      if (!String(tabId || "").startsWith("custom:")) return null;
      const id = String(tabId).slice("custom:".length);
      return customTabs(report).find((tab) => String(tab.id) === id) || null;
    }

    function tabsForReport(report) {
      if (report?.kind === "router_stack") return stackTabs;

      const custom = customTabs(report);
      if (custom.length > 0) {
        const reportTabs = custom.map(customTabId);
        if (hasRouterCoordinates(report)) reportTabs.push("map");
        if (hasOutputContent(report)) reportTabs.push("output");
        if (asArray(report?.peripherals).length > 0) reportTabs.push("peripherals");
        if (hasInventoryContent(report)) reportTabs.push("inventory");
        if (asArray(report?.files).length > 0) reportTabs.push("files");
        reportTabs.push("raw");
        return reportTabs;
      }

      const reportTabs = ["overview"];
      if (hasRouterCoordinates(report)) reportTabs.push("map");
      if (hasOutputContent(report)) reportTabs.push("output");
      if (asArray(report?.peripherals).length > 0) reportTabs.push("peripherals");
      if (hasInventoryContent(report)) reportTabs.push("inventory");
      if (asArray(report?.files).length > 0) reportTabs.push("files");
      reportTabs.push("raw");
      return reportTabs;
    }

    function tabLabel(report, tab) {
      const custom = customTabForReport(report, tab);
      if (custom) return custom.label || custom.title || custom.id;

      return {
        overview: "Overview",
        moves: "Moves",
        map: "Map",
        output: "Output",
        peripherals: "Peripherals",
        inventory: "Inventory",
        files: "Files",
        raw: "Raw JSON"
      }[tab] || tab;
    }

    function renderSummary(report) {
      if (report.kind === "router_stack") {
        const stats = report.stats || {};
        const moveVerb = report.dryRun ? "Would Move" : "Moved";
        const fluidLabel = report.dryRun ? "Would Move Fluid" : "Moved Fluid";
        const values = [
          ["Mode", report.dryRun ? "Preview" : "Move"],
          ["Destination", report.destination?.label || "n/a"],
          [moveVerb, stats.movedItems ?? 0],
          [fluidLabel, stats.movedFluid ?? 0],
          ["Errors", asArray(stats.errors).length]
        ];

        return values.map(([label, value]) => `
          <div class="metric">
            <span class="label">${escapeHtml(label)}</span>
            <span class="value">${escapeHtml(value)}</span>
          </div>
        `).join("");
      }

      const humanMetrics = asArray(report?.human?.metrics).slice(0, 5);
      const values = humanMetrics.length > 0
        ? humanMetrics.map((metric) => [metric.label || metric.key || "", metric.value ?? metric.displayValue ?? ""])
        : [
        ["Kind", report.kind || "unknown"],
        ["Result", report.ok === undefined ? "n/a" : report.ok ? "ok" : "failed"],
        ["Computer", report.computerId ?? "n/a"],
        ["Created", report.createdAt || "n/a"],
        ["Command", shortCommand(report)]
      ];

      return values.map(([label, value]) => `
        <div class="metric">
          <span class="label">${escapeHtml(label)}</span>
          <span class="value">${label === "Result" ? fmtBool(report.ok) : escapeHtml(value)}</span>
        </div>
      `).join("");
    }

    function renderOverview(report) {
      if (report.kind === "router_stack") return renderStackOverview(report);

      const blocks = [];

      if (report.error) {
        blocks.push(`<section class="block"><h2>Error</h2><pre>${escapeHtml(report.error)}</pre></section>`);
      }

      blocks.push(`
        <section class="block">
          <h2>Report Details</h2>
          <dl class="kv">
            <dt>Command</dt><dd>${escapeHtml(report.command || "n/a")}</dd>
            <dt>Message</dt><dd>${escapeHtml(report.message || "n/a")}</dd>
            <dt>Label</dt><dd>${escapeHtml(report.label || "n/a")}</dd>
            <dt>Started</dt><dd>${escapeHtml(report.startedAt || "n/a")}</dd>
            <dt>Quiet</dt><dd>${escapeHtml(report.quiet === undefined ? "n/a" : report.quiet)}</dd>
          </dl>
        </section>
      `);

      if (report.output) {
        blocks.push(`<section class="block"><h2>Command Output</h2><pre>${escapeHtml(report.output)}</pre></section>`);
      }

      const overviewCards = [];
      if (asArray(report.peripherals).length > 0) {
        overviewCards.push(`<section class="block"><h2>Peripherals</h2>${peripheralTable(report)}</section>`);
      }

      if (hasInventoryContent(report)) {
        overviewCards.push(`<section class="block"><h2>Inventory</h2>${inventoryTable(report.inventory)}</section>`);
      }

      if (overviewCards.length === 1) {
        blocks.push(overviewCards[0]);
      } else if (overviewCards.length > 1) {
        blocks.push(`<div class="grid-2">${overviewCards.join("")}</div>`);
      }

      return blocks.join("");
    }

    function renderCustomRows(rows) {
      const data = asArray(rows);
      if (data.length === 0) return '<div class="empty">No rows in this section.</div>';

      const hasCommand = data.some((row) => row.command);
      const rowClass = (row) => {
        const tone = String(row.tone || row.status || "").toLowerCase();
        if (["ok", "warn", "bad", "info"].includes(tone)) return ` class="row-${tone}"`;
        return "";
      };

      return `
        <table>
          <thead>
            <tr>
              <th>Setting</th>
              <th>Value</th>
              <th>Meaning</th>
              ${hasCommand ? "<th>Command</th>" : ""}
            </tr>
          </thead>
          <tbody>
            ${data.map((row) => `
              <tr${rowClass(row)}>
                <td class="mono">${escapeHtml(row.key || row.label || "")}</td>
                <td>${escapeHtml(row.displayValue ?? row.value ?? "")}</td>
                <td>${escapeHtml(row.explanation || "")}</td>
                ${hasCommand ? `<td class="mono">${escapeHtml(row.command || "")}</td>` : ""}
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function renderCustomSection(section) {
      return `
        <section class="block">
          <h2>${escapeHtml(section.title || "Section")}</h2>
          ${section.note ? `<p>${escapeHtml(section.note)}</p>` : ""}
          ${section.text ? `<pre>${escapeHtml(section.text)}</pre>` : renderCustomRows(section.rows)}
        </section>
      `;
    }

    function renderCustomTab(tab) {
      const sections = asArray(tab.sections);
      const heading = `
        <section class="block">
          <h2>${escapeHtml(tab.title || tab.label || tab.id || "Report")}</h2>
          ${tab.note ? `<p>${escapeHtml(tab.note)}</p>` : ""}
        </section>
      `;

      if (sections.length === 0) {
        return heading + '<div class="empty">This custom tab has no sections.</div>';
      }

      return heading + sections.map(renderCustomSection).join("");
    }

    function renderStackOverview(report) {
      const stats = report.stats || {};
      const mode = report.dryRun ? "Preview" : "Move";
      const errors = asArray(stats.errors);
      const blocks = [`
        <section class="block">
          <h2>Stack Report</h2>
          <dl class="kv">
            <dt>Mode</dt><dd>${escapeHtml(mode)}</dd>
            <dt>Router</dt><dd>${escapeHtml(report.router || "n/a")}</dd>
            <dt>Destination</dt><dd>${escapeHtml(report.destination?.label || "n/a")}</dd>
            <dt>Source report</dt><dd>${escapeHtml(report.sourceReport || "n/a")}</dd>
            <dt>Items enabled</dt><dd>${escapeHtml(report.includeItems === false ? "no" : "yes")}</dd>
            <dt>Fluids enabled</dt><dd>${escapeHtml(report.includeFluids ? "yes" : "no")}</dd>
          </dl>
        </section>
        <section class="block">
          <h2>Movement Stats</h2>
          <dl class="kv">
            <dt>Sources</dt><dd>${escapeHtml(stats.sources ?? 0)}</dd>
            <dt>Item sources</dt><dd>${escapeHtml(stats.itemSources ?? 0)}</dd>
            <dt>Fluid sources</dt><dd>${escapeHtml(stats.fluidSources ?? 0)}</dd>
            <dt>Item snapshots</dt><dd>${escapeHtml(stats.itemSnapshots ?? 0)}</dd>
            <dt>Fluid snapshots</dt><dd>${escapeHtml(stats.fluidSnapshots ?? 0)}</dd>
            <dt>Item attempts</dt><dd>${escapeHtml(stats.itemAttempts ?? 0)}</dd>
            <dt>Fluid attempts</dt><dd>${escapeHtml(stats.fluidAttempts ?? 0)}</dd>
            <dt>Zero moves</dt><dd>${escapeHtml(stats.zeroMoves ?? 0)}</dd>
          </dl>
        </section>
      `];

      if (errors.length) {
        blocks.push(`
          <section class="block">
            <h2>Errors</h2>
            <table>
              <thead><tr><th>Error</th></tr></thead>
              <tbody>${errors.map((error) => `<tr><td class="bad-text">${escapeHtml(error)}</td></tr>`).join("")}</tbody>
            </table>
          </section>
        `);
      }

      return blocks.join("");
    }

    function numberValue(value) {
      const number = Number(value);
      return Number.isFinite(number) ? number : 0;
    }

    function moveLabel(move) {
      if (move.mode === "fluids") return move.fluid || "(unknown fluid)";
      return move.item || "(unknown item)";
    }

    function moveQuantity(move) {
      return move.mode === "fluids" ? numberValue(move.amount) : numberValue(move.count);
    }

    function modeText(move) {
      return move.mode === "fluids" ? "Fluid" : "Item";
    }

    function groupedMoveTotals(moves, mode) {
      const grouped = {};

      for (const move of moves.filter((entry) => entry.mode === mode)) {
        const label = moveLabel(move);
        if (!grouped[label]) {
          grouped[label] = {
            label,
            total: 0,
            moves: 0,
            sources: new Set()
          };
        }

        grouped[label].total += moveQuantity(move);
        grouped[label].moves += 1;
        grouped[label].sources.add(move.source || "unknown");
      }

      return Object.values(grouped)
        .map((entry) => ({ ...entry, sources: entry.sources.size }))
        .sort((left, right) => {
          if (right.total === left.total) return left.label.localeCompare(right.label);
          return right.total - left.total;
        });
    }

    function sourceMoveTotals(moves) {
      const grouped = {};

      for (const move of moves) {
        const source = move.source || "unknown";
        if (!grouped[source]) {
          grouped[source] = {
            source,
            items: 0,
            fluids: 0,
            moves: 0
          };
        }

        grouped[source].moves += 1;
        if (move.mode === "fluids") {
          grouped[source].fluids += moveQuantity(move);
        } else {
          grouped[source].items += moveQuantity(move);
        }
      }

      return Object.values(grouped).sort((left, right) => left.source.localeCompare(right.source));
    }

    function totalsTable(rows, kind) {
      if (rows.length === 0) return '<div class="empty">No moves recorded for this type.</div>';

      const label = kind === "fluids" ? "Fluid" : "Item";
      const unit = kind === "fluids" ? "Amount" : "Count";
      return `
        <table>
          <thead><tr><th>${label}</th><th>${unit}</th><th>Sources</th><th>Moves</th></tr></thead>
          <tbody>
            ${rows.map((row) => `
              <tr>
                <td>${escapeHtml(row.label)}</td>
                <td>${escapeHtml(row.total)}</td>
                <td>${escapeHtml(row.sources)}</td>
                <td>${escapeHtml(row.moves)}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function sourceTotalsTable(rows) {
      if (rows.length === 0) return '<div class="empty">No source moves recorded.</div>';

      return `
        <table>
          <thead><tr><th>Source</th><th>Items</th><th>Fluid</th><th>Moves</th></tr></thead>
          <tbody>
            ${rows.map((row) => `
              <tr>
                <td>${escapeHtml(row.source)}</td>
                <td>${escapeHtml(row.items)}</td>
                <td>${escapeHtml(row.fluids)}</td>
                <td>${escapeHtml(row.moves)}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function detailMovesTable(moves, dryRun) {
      if (moves.length === 0) return '<div class="empty">No individual moves were recorded.</div>';

      const ordered = [...moves].sort((left, right) => {
        const sourceOrder = String(left.source || "").localeCompare(String(right.source || ""));
        if (sourceOrder !== 0) return sourceOrder;
        return String(moveLabel(left)).localeCompare(String(moveLabel(right)));
      });

      return `
        <table>
          <thead><tr><th>Source</th><th>Type</th><th>Name</th><th>Slot</th><th>Amount</th><th>Method</th></tr></thead>
          <tbody>
            ${ordered.map((move) => `
              <tr>
                <td>${escapeHtml(move.source || "unknown")}</td>
                <td>${escapeHtml(modeText(move))}</td>
                <td>${escapeHtml(moveLabel(move))}</td>
                <td>${escapeHtml(move.slot ?? "")}</td>
                <td>${escapeHtml(moveQuantity(move))}</td>
                <td>${escapeHtml(dryRun || move.dryRun ? "preview" : move.method || "")}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function renderStackMoves(report) {
      const stats = report.stats || {};
      const moves = asArray(stats.moves);
      const errors = asArray(stats.errors);
      const itemTotals = groupedMoveTotals(moves, "items");
      const fluidTotals = groupedMoveTotals(moves, "fluids");
      const sourceTotals = sourceMoveTotals(moves);
      const action = report.dryRun ? "Preview" : "Moved";

      return `
        <section class="block">
          <h2>${escapeHtml(action)} Summary</h2>
          <div class="status-line">
            <span class="pill">destination ${escapeHtml(report.destination?.label || "n/a")}</span>
            <span class="pill">${escapeHtml(stats.sources ?? 0)} source jobs</span>
            <span class="pill">${escapeHtml(stats.movedItems ?? 0)} items</span>
            <span class="pill">${escapeHtml(stats.movedFluid ?? 0)} fluid</span>
            <span class="pill">${escapeHtml(stats.zeroMoves ?? 0)} zero moves</span>
            ${errors.length ? `<span class="pill warn-text">${escapeHtml(errors.length)} errors</span>` : ""}
          </div>
        </section>
        <div class="grid-2">
          <section class="block">
            <h2>Items</h2>
            ${totalsTable(itemTotals, "items")}
          </section>
          <section class="block">
            <h2>Fluids</h2>
            ${totalsTable(fluidTotals, "fluids")}
          </section>
        </div>
        <section class="block">
          <h2>Sources</h2>
          ${sourceTotalsTable(sourceTotals)}
        </section>
        <section class="block">
          <h2>Move Details</h2>
          ${detailMovesTable(moves, report.dryRun)}
        </section>
        ${errors.length ? `
          <section class="block">
            <h2>Errors</h2>
            <table>
              <thead><tr><th>Error</th></tr></thead>
              <tbody>${errors.map((error) => `<tr><td class="bad-text">${escapeHtml(error)}</td></tr>`).join("")}</tbody>
            </table>
          </section>
        ` : ""}
      `;
    }

    function renderOutput(report) {
      if (!report.output && !report.error) return '<div class="empty">This report has no captured output.</div>';
      return `
        ${report.error ? `<section class="block"><h2>Error</h2><pre>${escapeHtml(report.error)}</pre></section>` : ""}
        ${report.output ? `<section class="block"><h2>Output</h2><pre>${escapeHtml(report.output)}</pre></section>` : ""}
      `;
    }

    function peripheralTable(report) {
      const peripherals = asArray(report.peripherals);
      if (peripherals.length === 0) return '<div class="empty">No peripherals reported.</div>';

      return `
        <table>
          <thead><tr><th>Side</th><th>Type</th><th>Inventory</th><th>Slots</th></tr></thead>
          <tbody>
            ${peripherals.map((item) => `
              <tr>
                <td>${escapeHtml(item.side || item.name || "")}</td>
                <td>${escapeHtml(typeText(item.type || item.types))}</td>
                <td>${escapeHtml(item.isInventory === undefined ? "" : item.isInventory)}</td>
                <td>${escapeHtml(item.usedSlots ?? "")}${item.size ? ` / ${escapeHtml(item.size)}` : ""}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function renderPeripherals(report) {
      return `<section class="block"><h2>Peripherals</h2>${peripheralTable(report)}</section>`;
    }

    function inventoryTable(items) {
      const inventory = asArray(items);
      if (inventory.length === 0) return '<div class="empty">No turtle inventory reported.</div>';

      return `
        <table>
          <thead><tr><th>Slot</th><th>Name</th><th>Count</th><th>Damage/NBT</th></tr></thead>
          <tbody>
            ${inventory.map((item) => `
              <tr>
                <td>${escapeHtml(item.slot ?? "")}</td>
                <td>${escapeHtml(item.name ?? "")}</td>
                <td>${escapeHtml(item.count ?? "")}</td>
                <td>${escapeHtml(item.damage ?? item.nbt ?? "")}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function renderInventory(report) {
      const blocks = [`<section class="block"><h2>Turtle Inventory</h2>${inventoryTable(report.inventory)}</section>`];
      if (report.args && Object.keys(report.args).length) {
        blocks.push(`<section class="block"><h2>Args</h2><pre>${escapeHtml(JSON.stringify(report.args, null, 2))}</pre></section>`);
      }
      return blocks.join("");
    }

    function hasFiniteCoord(coord) {
      return coord &&
        Number.isFinite(Number(coord.x)) &&
        Number.isFinite(Number(coord.y)) &&
        Number.isFinite(Number(coord.z));
    }

    function coordinateKey(coord) {
      return entryKey(Number(coord.x), Number(coord.y), Number(coord.z));
    }

    function uniqueStrings(values) {
      return [...new Set(asArray(values).filter((value) => value !== undefined && value !== null).map(String))];
    }

    function shortId(value) {
      if (value === undefined || value === null || value === "") return "nil";
      const text = String(value);
      if (text.length <= 12) return text;
      return `${text.slice(0, 6)}...${text.slice(-4)}`;
    }

    function primaryMapKind(entry, scadaNode) {
      const categories = asArray(entry?.categories);
      const hasScada = scadaNode && Object.keys(scadaNode).length > 0;
      if (categories.includes("attitudeSensor")) return "attitude";
      if (categories.includes("rotorBearing")) return "rotor";
      if (categories.includes("scalarActuator")) return "scalar";
      if (categories.includes("displaySink")) return "display";
      if (categories.includes("kineticScada") || hasScada) return "kinetic";
      return entry?.kind || (entry?.inventory ? "inventory" : "wrappable");
    }

    function scadaNodesByCoord(report) {
      const byCoord = {};
      const nodes = report?.kineticScada?.nodes || {};

      for (const [id, node] of Object.entries(nodes)) {
        if (!hasFiniteCoord(node?.coord)) continue;
        byCoord[coordinateKey(node.coord)] = { ...node, id: node.id || id };
      }

      return byCoord;
    }

    function decodeScadaBlockPos(id) {
      const text = String(id || "").trim();
      if (!/^[0-9a-fA-F]{16}$/.test(text)) return null;

      try {
        const packed = BigInt(`0x${text}`);
        const mask26 = (1n << 26n) - 1n;
        const mask12 = (1n << 12n) - 1n;
        return {
          x: Number(BigInt.asIntN(26, (packed >> 38n) & mask26)),
          y: Number(BigInt.asIntN(12, packed & mask12)),
          z: Number(BigInt.asIntN(26, (packed >> 12n) & mask26))
        };
      } catch {
        return null;
      }
    }

    function offsetKey(offset) {
      return `${offset.x},${offset.y},${offset.z}`;
    }

    function inferScadaFrame(report) {
      const candidates = {};
      const nodes = report?.kineticScada?.nodes || {};

      for (const [id, node] of Object.entries(nodes)) {
        if (!hasFiniteCoord(node?.coord)) continue;
        const world = decodeScadaBlockPos(node.id || id);
        if (!world) continue;

        const offset = {
          x: world.x - Number(node.coord.x),
          y: world.y - Number(node.coord.y),
          z: world.z - Number(node.coord.z)
        };
        const key = offsetKey(offset);

        if (!candidates[key]) {
          candidates[key] = {
            offset,
            count: 0,
            examples: []
          };
        }

        candidates[key].count += 1;
        if (candidates[key].examples.length < 5) candidates[key].examples.push(node.id || id);
      }

      let best = null;
      for (const candidate of Object.values(candidates)) {
        if (!best || candidate.count > best.count) best = candidate;
      }

      if (!best) return null;

      return {
        ...best,
        candidateCount: Object.keys(candidates).length
      };
    }

    function worldToRelative(world, frame) {
      if (!world || !frame?.offset) return null;
      return {
        x: world.x - frame.offset.x,
        y: world.y - frame.offset.y,
        z: world.z - frame.offset.z
      };
    }

    function aircraftRolesByCoord(report) {
      const byCoord = {};
      const orientation = report?.orientation || report?.scan?.orientation || {};
      const roles = orientation.roles || {};

      for (const [family, roleMap] of Object.entries(roles)) {
        for (const [role, value] of Object.entries(roleMap || {})) {
          if (!hasFiniteCoord(value?.coord)) continue;
          const key = coordinateKey(value.coord);
          if (!byCoord[key]) byCoord[key] = [];
          byCoord[key].push(`${family}:${role}`);
        }
      }

      return byCoord;
    }

    function normalizeRouterResult(entry) {
      return {
        ...entry,
        x: Number(entry.x),
        y: Number(entry.y),
        z: Number(entry.z),
        label: entry.label || `${entry.x},${entry.y},${entry.z}`,
        mapKind: entry.kind || (entry.inventory ? "inventory" : "wrappable"),
        mapSource: "router_result"
      };
    }

    function normalizeAircraftPeripheral(entry, rolesByCoord, scadaByCoord) {
      const coord = entry.coord || {};
      const key = coordinateKey(coord);
      const scadaNode = scadaByCoord[key] || {};
      const scada = { ...scadaNode, ...(entry.kineticScada || {}) };
      const categories = asArray(entry.categories);
      const roles = rolesByCoord[key] || [];
      const name = roles.length
        ? roles.join(", ")
        : categories.length
          ? categories.join(", ")
          : scada.kind || "peripheral";

      return {
        x: Number(coord.x),
        y: Number(coord.y),
        z: Number(coord.z),
        label: entry.coord?.key || key,
        displayName: name,
        kind: scada.kind || categories[0] || "peripheral",
        mapKind: primaryMapKind(entry, scada),
        mapSource: "aircraft_peripheral",
        categories,
        roles,
        methods: asArray(entry.methods),
        methodCount: entry.methodCount,
        kineticScada: scada,
        networkId: scada.networkId,
        subnetworkAnchorId: scada.subnetworkAnchorId,
        sourceId: scada.sourceId,
        scadaKind: scada.kind,
        isOverstressed: scada.isOverstressed === true,
        hasMissingSource: scadaNode.hasMissingSource === true,
        isLeaf: scadaNode.isLeaf === true,
        isDriver: scadaNode.isDriver === true
      };
    }

    function normalizeScadaNode(node, rolesByCoord) {
      const key = coordinateKey(node.coord);
      const roles = rolesByCoord[key] || [];
      return {
        x: Number(node.coord.x),
        y: Number(node.coord.y),
        z: Number(node.coord.z),
        label: node.coord?.key || key,
        displayName: roles.length ? roles.join(", ") : `${node.kind || "scada"} ${shortId(node.id)}`,
        kind: node.kind || "scada",
        mapKind: node.isDriver ? "scalar" : node.isConsumer ? "kinetic" : "kinetic",
        mapSource: "kinetic_scada",
        categories: asArray(node.categories),
        roles,
        methods: asArray(node.controlMethods),
        methodCount: node.methodCount,
        kineticScada: node,
        networkId: node.networkId,
        subnetworkAnchorId: node.subnetworkAnchorId,
        sourceId: node.sourceId,
        scadaKind: node.kind,
        isOverstressed: node.isOverstressed === true,
        hasMissingSource: node.hasMissingSource === true,
        isLeaf: node.isLeaf === true,
        isDriver: node.isDriver === true
      };
    }

    function normalizeMissingScadaId(report, id, entry, kind, frame) {
      const world = decodeScadaBlockPos(id);
      const rel = worldToRelative(world, frame);
      if (!hasFiniteCoord(rel)) return null;

      const referencedBy = asArray(entry?.referencedBy);
      const firstRef = referencedBy[0];
      const refNode = firstRef && report?.kineticScada?.nodes && report.kineticScada.nodes[firstRef];

      return {
        x: Number(rel.x),
        y: Number(rel.y),
        z: Number(rel.z),
        label: `${rel.x},${rel.y},${rel.z}`,
        displayName: `${kind} ${shortId(id)}`,
        kind,
        mapKind: "inferred",
        mapSource: "inferred_scada_id",
        inferred: true,
        inferredWorld: world,
        categories: ["inferredScada"],
        roles: [],
        methods: [],
        methodCount: "",
        networkId: refNode?.networkId,
        subnetworkAnchorId: refNode?.subnetworkAnchorId,
        sourceId: kind === "missing_source" ? id : undefined,
        scadaKind: "inferred",
        isOverstressed: false,
        hasMissingSource: true,
        isLeaf: false,
        isDriver: false,
        referencedBy
      };
    }

    function inferredMissingEntries(report, frame) {
      if (!frame) return [];

      const entries = [];
      const missingSources = report?.kineticScada?.missingSourceIds || {};
      const missingAnchors = report?.kineticScada?.missingAnchorIds || {};

      for (const [id, entry] of Object.entries(missingSources)) {
        const normalized = normalizeMissingScadaId(report, id, entry, "missing_source", frame);
        if (normalized) entries.push(normalized);
      }

      for (const [id, entry] of Object.entries(missingAnchors)) {
        const normalized = normalizeMissingScadaId(report, id, entry, "missing_anchor", frame);
        if (normalized) entries.push(normalized);
      }

      return entries;
    }

    function mergeMapEntry(existing, entry) {
      existing.displayName = existing.displayName || entry.displayName;
      existing.kind = existing.kind || entry.kind;
      existing.mapKind = existing.mapKind || entry.mapKind;
      existing.categories = uniqueStrings([...(existing.categories || []), ...(entry.categories || [])]);
      existing.roles = uniqueStrings([...(existing.roles || []), ...(entry.roles || [])]);
      existing.methods = existing.methods?.length ? existing.methods : entry.methods;
      existing.methodCount = Math.max(Number(existing.methodCount) || 0, Number(entry.methodCount) || 0) || undefined;
      existing.kineticScada = existing.kineticScada || entry.kineticScada;
      existing.networkId = existing.networkId || entry.networkId;
      existing.subnetworkAnchorId = existing.subnetworkAnchorId || entry.subnetworkAnchorId;
      existing.sourceId = existing.sourceId || entry.sourceId;
      existing.scadaKind = existing.scadaKind || entry.scadaKind;
      existing.isOverstressed = existing.isOverstressed || entry.isOverstressed;
      existing.hasMissingSource = existing.hasMissingSource || entry.hasMissingSource;
      existing.isLeaf = existing.isLeaf || entry.isLeaf;
      existing.isDriver = existing.isDriver || entry.isDriver;
      existing.inferred = existing.inferred || entry.inferred;
      existing.inferredWorld = existing.inferredWorld || entry.inferredWorld;
      existing.referencedBy = uniqueStrings([...(existing.referencedBy || []), ...(entry.referencedBy || [])]);
      existing.extraCount = (existing.extraCount || 1) + 1;
      return existing;
    }

    function coordinateEntries(report) {
      const byCoord = {};
      const usedScadaCoords = new Set();
      const scadaByCoord = scadaNodesByCoord(report);
      const rolesByCoord = aircraftRolesByCoord(report);
      const frame = inferScadaFrame(report);

      function addEntry(entry) {
        if (!hasFiniteCoord(entry)) return;
        const key = coordinateKey(entry);
        if (byCoord[key]) {
          mergeMapEntry(byCoord[key], entry);
        } else {
          byCoord[key] = entry;
        }
      }

      for (const entry of asArray(report.results)) {
        if (hasFiniteCoord(entry)) addEntry(normalizeRouterResult(entry));
      }

      for (const entry of asArray(report.peripherals)) {
        if (!hasFiniteCoord(entry.coord)) continue;
        const normalized = normalizeAircraftPeripheral(entry, rolesByCoord, scadaByCoord);
        usedScadaCoords.add(coordinateKey(entry.coord));
        addEntry(normalized);
      }

      for (const node of Object.values(scadaByCoord)) {
        const key = coordinateKey(node.coord);
        if (!usedScadaCoords.has(key)) addEntry(normalizeScadaNode(node, rolesByCoord));
      }

      for (const entry of inferredMissingEntries(report, frame)) {
        addEntry(entry);
      }

      return Object.values(byCoord).sort((left, right) =>
        left.y - right.y || left.z - right.z || left.x - right.x
      );
    }

    function hasRouterCoordinates(report) {
      return coordinateEntries(report).length > 0;
    }

    function range(start, end) {
      const values = [];
      for (let value = start; value <= end; value += 1) values.push(value);
      return values;
    }

    function routerBounds(report, entries) {
      function boundsFrom(minX, maxX, minY, maxY, minZ, maxZ) {
        for (const entry of entries || []) {
          if (!hasFiniteCoord(entry)) continue;
          minX = Math.min(minX, Number(entry.x));
          maxX = Math.max(maxX, Number(entry.x));
          minY = Math.min(minY, Number(entry.y));
          maxY = Math.max(maxY, Number(entry.y));
          minZ = Math.min(minZ, Number(entry.z));
          maxZ = Math.max(maxZ, Number(entry.z));
        }

        return {
          xs: range(minX, maxX),
          ys: range(minY, maxY),
          zs: range(minZ, maxZ)
        };
      }

      const scanBounds = report.scanBounds || report.mapBounds;
      if (
        Number.isFinite(Number(scanBounds?.xMin)) &&
        Number.isFinite(Number(scanBounds?.xMax)) &&
        Number.isFinite(Number(scanBounds?.yMin)) &&
        Number.isFinite(Number(scanBounds?.yMax)) &&
        Number.isFinite(Number(scanBounds?.zMin)) &&
        Number.isFinite(Number(scanBounds?.zMax))
      ) {
        return boundsFrom(
          Number(scanBounds.xMin),
          Number(scanBounds.xMax),
          Number(scanBounds.yMin),
          Number(scanBounds.yMax),
          Number(scanBounds.zMin),
          Number(scanBounds.zMax)
        );
      }

      if (
        Number.isFinite(Number(report.xMin)) &&
        Number.isFinite(Number(report.xMax)) &&
        Number.isFinite(Number(report.yMin)) &&
        Number.isFinite(Number(report.yMax)) &&
        Number.isFinite(Number(report.zMin)) &&
        Number.isFinite(Number(report.zMax))
      ) {
        return {
          xs: range(Number(report.xMin), Number(report.xMax)),
          ys: range(Number(report.yMin), Number(report.yMax)),
          zs: range(Number(report.zMin), Number(report.zMax))
        };
      }

      if (Number.isFinite(Number(report.xRadius)) && Number.isFinite(Number(report.yRadius)) && Number.isFinite(Number(report.zRadius))) {
        const xr = Number(report.xRadius);
        const yr = Number(report.yRadius);
        const zr = Number(report.zRadius);
        return {
          xs: range(-xr, xr),
          ys: range(-yr, yr),
          zs: range(-zr, zr)
        };
      }

      const xs = entries.map((entry) => Number(entry.x));
      const ys = entries.map((entry) => Number(entry.y));
      const zs = entries.map((entry) => Number(entry.z));
      return boundsFrom(Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys), Math.min(...zs), Math.max(...zs));
    }

    function entryKey(x, y, z) {
      return `${x},${y},${z}`;
    }

    function mapEntryClass(entry) {
      if (!entry) return "empty";
      if (entry.ok === false) return "error";
      const classes = [entry.mapKind || entry.kind || (entry.inventory ? "inventory" : "wrappable")];
      if (entry.networkId) classes.push("has-network");
      if (entry.isOverstressed) classes.push("scada-bad");
      else if (entry.hasMissingSource) classes.push("scada-warn");
      return classes.join(" ");
    }

    function networkColor(value) {
      if (!value) return "#6f7f8f";
      const palette = ["#386fa4", "#55a868", "#c44e52", "#8172b3", "#ccb974", "#64b5cd", "#dd8452", "#4c72b0"];
      const text = String(value);
      let hash = 0;
      for (let index = 0; index < text.length; index += 1) {
        hash = ((hash << 5) - hash + text.charCodeAt(index)) | 0;
      }
      return palette[Math.abs(hash) % palette.length];
    }

    function mapEntryStyle(entry) {
      if (!entry?.networkId) return "";
      return ` style="--network-color: ${networkColor(entry.networkId)}"`;
    }

    function routerLabel(report) {
      if (typeof report.router === "string") return report.router;
      return report.router?.name || "n/a";
    }

    function entryRoleNetworkText(entry) {
      const parts = [];
      if (asArray(entry.roles).length) parts.push(asArray(entry.roles).join(", "));
      if (entry.networkId) parts.push(`net ${shortId(entry.networkId)}`);
      if (entry.subnetworkAnchorId) parts.push(`zone ${shortId(entry.subnetworkAnchorId)}`);
      return parts.join(" | ");
    }

    function entryDetailText(entry) {
      const parts = [];
      const categories = asArray(entry.categories);
      if (categories.length) parts.push(categories.join(", "));
      if (entry.scadaKind) parts.push(`kind=${entry.scadaKind}`);
      if (entry.sourceId) parts.push(`src=${shortId(entry.sourceId)}`);
      if (entry.inferred) parts.push(`inferred world=${entry.inferredWorld ? `${entry.inferredWorld.x},${entry.inferredWorld.y},${entry.inferredWorld.z}` : "?"}`);
      if (asArray(entry.referencedBy).length) parts.push(`referenced by ${asArray(entry.referencedBy).map(shortId).join(", ")}`);
      if (entry.isDriver) parts.push("driver");
      if (entry.isLeaf) parts.push("leaf");
      if (entry.isOverstressed) parts.push("overstressed");
      if (entry.hasMissingSource) parts.push("missing source");
      return parts.join("; ");
    }

    function topItems(entry) {
      return asArray(entry.itemTotals)
        .slice(0, 2)
        .map((item) => `${item.name} x${item.count}`)
        .join(", ");
    }

    function luaString(value) {
      return JSON.stringify(String(value ?? ""));
    }

    function encodeCopy(value) {
      return encodeURIComponent(String(value ?? ""));
    }

    function decodeCopy(value) {
      try {
        return decodeURIComponent(value || "");
      } catch {
        return value || "";
      }
    }

    function routerLua(report) {
      const name = routerLabel(report);
      if (name && name !== "n/a" && !String(name).startsWith("(")) {
        return `assert(peripheral.wrap(${luaString(name)}) or peripheral.find("peripheral_router"))`;
      }

      return 'assert(peripheral.find("peripheral_router"))';
    }

    function wrapSnippet(report, entry) {
      const variable = entry.inventory ? "inv" : entry.kind === "fluid" ? "tank" : "p";
      const lines = [
        `router = ${routerLua(report)}`,
        `${variable} = assert(router.wrap(${Number(entry.x)}, ${Number(entry.y)}, ${Number(entry.z)}))`
      ];

      if (entry.inventory) {
        lines.push(`print(textutils.serialize(${variable}.list()))`);
      } else if (entry.kind === "fluid") {
        lines.push(`print(textutils.serialize(${variable}.tanks()))`);
      } else {
        lines.push(`print(textutils.serialize({${asArray(entry.methods).map((method) => luaString(method)).join(", ")}}))`);
      }

      return lines.join("\n");
    }

    function coordinateWrapSnippet(x, y, z) {
      return `r = peripheral.find("peripheral_router"); p=r.wrap(${Number(x)}, ${Number(y)}, ${Number(z)});`;
    }

    function stackCommand(entry, mode) {
      const base = `router_inventory_scanner ${mode} --to ${Number(entry.x)} ${Number(entry.y)} ${Number(entry.z)}`;
      return base;
    }

    function fluidStackCommand(entry, mode) {
      return `${stackCommand(entry, mode)} --fluids --no-items`;
    }

    function entryHasMethod(entry, method) {
      return asArray(entry.methods).includes(method);
    }

    function entryHasFluid(entry) {
      return entry.kind === "fluid" ||
        entryHasMethod(entry, "tanks") ||
        entryHasMethod(entry, "pushFluid") ||
        entryHasMethod(entry, "pullFluid");
    }

    function stackButtons(entry) {
      const buttons = [copyButton("Wrap", wrapSnippet(state.latest, entry))];

      if (entry.inventory) {
        buttons.push(copyButton("Preview", stackCommand(entry, "stack-preview")));
        buttons.push(copyButton("Stack", stackCommand(entry, "stack")));
      }

      if (entryHasFluid(entry)) {
        buttons.push(copyButton("Fluid Preview", fluidStackCommand(entry, "stack-preview")));
        buttons.push(copyButton("Fluid Stack", fluidStackCommand(entry, "stack")));
      }

      return buttons.join("");
    }

    async function copyText(text, label) {
      try {
        if (navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          const area = document.createElement("textarea");
          area.value = text;
          area.style.position = "fixed";
          area.style.left = "-9999px";
          document.body.appendChild(area);
          area.focus();
          area.select();
          document.execCommand("copy");
          area.remove();
        }

        const status = document.getElementById("copyStatus");
        if (status) status.textContent = `Copied ${label || "command"}`;
      } catch (error) {
        const status = document.getElementById("copyStatus");
        if (status) status.textContent = `Copy failed: ${error.message}`;
      }
    }

    function copyButton(label, text) {
      return `<button class="copy-btn" data-copy="${escapeHtml(encodeCopy(text))}" data-copy-label="${escapeHtml(label)}">${escapeHtml(label)}</button>`;
    }

    function bindCopyActions() {
      for (const node of els.view.querySelectorAll("[data-copy]")) {
        node.addEventListener("click", (event) => {
          event.stopPropagation();
          copyText(decodeCopy(node.dataset.copy), node.dataset.copyLabel || "command");
        });
      }
    }

    function mapCell(entry, x, y, z) {
      const copyText = coordinateWrapSnippet(x, y, z);
      const copyLabel = `p ${x},${y},${z}`;

      if (!entry) {
        return `<div class="map-cell empty" data-copy="${escapeHtml(encodeCopy(copyText))}" data-copy-label="${escapeHtml(copyLabel)}"><span class="map-coord">${x},${y},${z}</span></div>`;
      }

      const detail = entry.inventory
        ? `${entry.usedSlots ?? 0}/${entry.size ?? "?"} slots${entry.totalItems === undefined ? "" : `, ${entry.totalItems} items`}`
        : entryDetailText(entry) || `${entry.kind || "wrappable"}${entry.methodCount === undefined ? "" : `, ${entry.methodCount} methods`}`;
      const items = topItems(entry);
      const roleNetwork = entryRoleNetworkText(entry);
      const title = `${entry.label || ""} ${entry.displayName || ""} ${roleNetwork} ${detail} ${items}`.trim();

      return `
        <div class="map-cell ${escapeHtml(mapEntryClass(entry))}"${mapEntryStyle(entry)} title="${escapeHtml(title)}" data-copy="${escapeHtml(encodeCopy(copyText))}" data-copy-label="${escapeHtml(copyLabel)}">
          <span class="map-coord">${escapeHtml(entry.label || `${x},${y},${z}`)}</span>
          <span class="map-name">${escapeHtml(entry.displayName || (entry.inventory ? "inventory" : entry.kind || "wrappable"))}</span>
          ${roleNetwork ? `<span class="map-detail">${escapeHtml(roleNetwork)}</span>` : ""}
          <span class="map-detail">${escapeHtml(detail)}</span>
          ${items ? `<span class="map-detail">${escapeHtml(items)}</span>` : ""}
          ${entry.extraCount ? `<span class="map-detail">merged ${escapeHtml(entry.extraCount)} entries</span>` : ""}
        </div>
      `;
    }

    function routerMapLayer(y, bounds, byCoord) {
      const columns = Math.max(1, Math.min(99, bounds.xs.length));
      const cells = [
        '<div class="map-axis">z\\x</div>',
        ...bounds.xs.map((x) => `<div class="map-axis">x ${escapeHtml(x)}</div>`)
      ];

      for (const z of bounds.zs) {
        cells.push(`<div class="map-axis">z ${escapeHtml(z)}</div>`);
        for (const x of bounds.xs) {
          cells.push(mapCell(byCoord[entryKey(x, y, z)], x, y, z));
        }
      }

      return `
        <div class="map-layer">
          <h3>Y ${escapeHtml(y)}</h3>
          <div class="map-scroll">
            <div class="router-map" style="grid-template-columns: 44px repeat(${columns}, minmax(72px, 96px));">
              ${cells.join("")}
            </div>
          </div>
        </div>
      `;
    }

    function routerMapTable(entries) {
      if (entries.length === 0) return '<div class="empty">No mapped entries.</div>';

      return `
        <table>
          <thead><tr><th>Coord</th><th>Name</th><th>Kind</th><th>Role / Network</th><th>Details</th><th>Methods</th><th>Copy</th></tr></thead>
          <tbody>
            ${entries.map((entry) => `
              <tr>
                <td>${escapeHtml(entry.label || `${entry.x},${entry.y},${entry.z}`)}</td>
                <td>${escapeHtml(entry.displayName || "")}</td>
                <td>${escapeHtml(entry.kind || entry.mapKind || (entry.inventory ? "inventory" : ""))}</td>
                <td>${escapeHtml(entryRoleNetworkText(entry))}</td>
                <td>${escapeHtml(entry.inventory ? `${entry.usedSlots ?? 0}/${entry.size ?? "?"} slots ${topItems(entry) || ""}` : entryDetailText(entry))}</td>
                <td>${escapeHtml(entry.methodCount ?? "")}</td>
                <td>
                  <div class="copy-actions">
                    ${stackButtons(entry)}
                  </div>
                </td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function renderRouterMap(report) {
      const entries = coordinateEntries(report);

      if (!hasRouterCoordinates(report)) {
        return '<div class="empty">This report does not contain router-relative coordinates. Run an aircraft scan or <span class="mono">router_inventory_scanner map --radius 8</span>.</div>';
      }

      const bounds = routerBounds(report, entries);
      const byCoord = {};
      for (const entry of entries) {
        byCoord[entryKey(Number(entry.x), Number(entry.y), Number(entry.z))] = entry;
      }

      const layers = [...bounds.ys].sort((left, right) => right - left);
      const networks = uniqueStrings(entries.map((entry) => entry.networkId).filter(Boolean));
      const drivers = entries.filter((entry) => entry.isDriver || asArray(entry.categories).includes("scalarActuator")).length;
      const consumers = entries.filter((entry) => asArray(entry.categories).includes("rotorBearing") || entry.scadaKind === "consumer").length;
      const warnings = entries.filter((entry) => entry.isOverstressed || entry.hasMissingSource).length;
      const inferred = entries.filter((entry) => entry.inferred).length;
      const frame = inferScadaFrame(report);
      const structureUrl = `/api/structure?file=${encodeURIComponent(state.selectedFile)}`;
      const metrics = `
        <div class="map-controls">
          <span class="pill">${escapeHtml(report.width || bounds.xs.length)}x${escapeHtml(report.height || bounds.ys.length)}x${escapeHtml(report.depth || bounds.zs.length)}</span>
          <span class="pill">${escapeHtml(entries.length)} mapped</span>
          <span class="pill">${escapeHtml(networks.length)} networks</span>
          <span class="pill">${escapeHtml(drivers)} drivers</span>
          <span class="pill">${escapeHtml(consumers)} consumers/rotors</span>
          ${inferred ? `<span class="pill warn-text">${escapeHtml(inferred)} inferred missing</span>` : ""}
          ${warnings ? `<span class="pill warn-text">${escapeHtml(warnings)} warnings</span>` : ""}
          ${frame ? `<span class="pill">SCADA offset ${escapeHtml(frame.offset.x)},${escapeHtml(frame.offset.y)},${escapeHtml(frame.offset.z)} from ${escapeHtml(frame.count)} ids</span>` : ""}
          <span class="pill">router ${escapeHtml(routerLabel(report))}</span>
          <a class="copy-btn" href="${escapeHtml(structureUrl)}">Download NBT</a>
        </div>
      `;

      return `
        <section class="block">
          <h2>Coordinate Map</h2>
          ${metrics}
          <div id="copyStatus" class="copy-status">Click any cell to copy a quick Lua router-wrap snippet. Cell color shows role family; top stripe color groups SCADA networks. Dashed cells are inferred from decoded SCADA IDs, not confirmed peripherals.</div>
          ${layers.map((y) => routerMapLayer(y, bounds, byCoord)).join("")}
        </section>
        <section class="block">
          <h2>Mapped Entries</h2>
          ${routerMapTable(entries)}
        </section>
      `;
    }

    function renderFiles(report) {
      const files = asArray(report.files);
      const filter = state.fileFilter.toLowerCase();
      const projectFiles = files.filter((file) => !String(file).startsWith("rom/"));
      const romFiles = files.filter((file) => String(file).startsWith("rom/"));
      const shown = files.filter((file) => String(file).toLowerCase().includes(filter)).slice(0, 500);

      return `
        <section class="block">
          <h2>Files</h2>
          <div class="file-controls">
            <input id="fileFilter" class="search" style="max-width: 360px" placeholder="Filter files" autocomplete="off">
            <span class="pill">${files.length} total</span>
            <span class="pill">${projectFiles.length} project</span>
            <span class="pill">${romFiles.length} ROM</span>
            <span class="pill">${shown.length} shown</span>
          </div>
          ${shown.length ? `<pre>${escapeHtml(shown.join("\n"))}</pre>` : '<div class="empty">No files match the filter.</div>'}
        </section>
      `;
    }

    function renderRaw(report) {
      return `<section class="block"><h2>Raw JSON</h2><pre>${escapeHtml(JSON.stringify(report, null, 2))}</pre></section>`;
    }

    els.search.addEventListener("input", () => {
      state.reportFilter = els.search.value;
      renderReportList();
    });

    refreshReports();
    refreshLatest();
    setInterval(refreshLatest, 2000);
    setInterval(refreshReports, 6000);
  </script>
</body>
</html>
"""


def read_report(path: Path):
    if not path.exists():
        return None

    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return {
            "kind": "parse-error",
            "ok": False,
            "error": str(exc),
            "output": path.read_text(encoding="utf-8", errors="replace"),
        }


def report_summary(path: Path):
    report = read_report(path) or {}
    stat = path.stat()

    return {
        "name": path.name,
        "modified": stat.st_mtime * 1000,
        "kind": report.get("kind"),
        "ok": report.get("ok"),
        "command": report.get("command") or report.get("message"),
        "computerId": report.get("computerId"),
        "createdAt": report.get("createdAt"),
    }


def has_coord(value):
    if not isinstance(value, dict):
        return False
    try:
        int(value.get("x"))
        int(value.get("y"))
        int(value.get("z"))
        return True
    except (TypeError, ValueError):
        return False


def coord_tuple(value):
    return (int(value["x"]), int(value["y"]), int(value["z"]))


def list_value(value):
    return value if isinstance(value, list) else []


def dict_value(value):
    return value if isinstance(value, dict) else {}


def object_items(value):
    if isinstance(value, dict):
        return value.items()
    if isinstance(value, list):
        pairs = []
        for index, item in enumerate(value):
            if isinstance(item, dict) and item.get("id"):
                pairs.append((str(item["id"]), item))
            elif isinstance(item, str):
                pairs.append((item, {}))
            else:
                pairs.append((str(index), item))
        return pairs
    return ()


def decode_scada_block_pos(block_id):
    text = str(block_id or "").strip()
    if not re.fullmatch(r"[0-9a-fA-F]{16}", text):
        return None

    packed = int(text, 16)
    x = (packed >> 38) & ((1 << 26) - 1)
    y = packed & ((1 << 12) - 1)
    z = (packed >> 12) & ((1 << 26) - 1)

    if x >= 1 << 25:
        x -= 1 << 26
    if y >= 1 << 11:
        y -= 1 << 12
    if z >= 1 << 25:
        z -= 1 << 26

    return {"x": x, "y": y, "z": z}


def infer_scada_frame(report):
    candidates = {}

    for node_id, node in object_items(dict_value(report.get("kineticScada")).get("nodes")):
        node = dict_value(node)
        coord = node.get("coord")
        if not has_coord(coord):
            continue

        world = decode_scada_block_pos(node.get("id") or node_id)
        if not world:
            continue

        offset = (
            world["x"] - int(coord["x"]),
            world["y"] - int(coord["y"]),
            world["z"] - int(coord["z"]),
        )
        candidates[offset] = candidates.get(offset, 0) + 1

    if not candidates:
        return None

    offset, count = max(candidates.items(), key=lambda item: item[1])
    return {"offset": {"x": offset[0], "y": offset[1], "z": offset[2]}, "count": count}


def world_to_relative(world, frame):
    if not world or not frame:
        return None
    offset = frame["offset"]
    return {
        "x": world["x"] - offset["x"],
        "y": world["y"] - offset["y"],
        "z": world["z"] - offset["z"],
    }


def scada_nodes_by_coord(report):
    by_coord = {}

    for node_id, node in object_items(dict_value(report.get("kineticScada")).get("nodes")):
        node = dict_value(node)
        coord = node.get("coord")
        if has_coord(coord):
            by_coord[coord_tuple(coord)] = {**node, "id": node.get("id") or node_id}

    return by_coord


def map_kind_for_entry(entry, scada=None):
    categories = set(list_value(entry.get("categories")))
    scada = dict_value(scada)

    if entry.get("inferred"):
        return "inferred"
    if "attitudeSensor" in categories:
        return "attitude"
    if "rotorBearing" in categories:
        return "rotor"
    if "scalarActuator" in categories:
        return "scalar"
    if "displaySink" in categories:
        return "display"
    if "kineticScada" in categories or scada:
        return "kinetic"
    if entry.get("inventory"):
        return "inventory"
    return entry.get("kind") or "wrappable"


def add_map_entry(entries, entry):
    if not has_coord(entry):
        return

    key = coord_tuple(entry)
    existing = entries.get(key)
    if not existing:
        entries[key] = entry
        return

    existing["categories"] = sorted(set(list_value(existing.get("categories"))) | set(list_value(entry.get("categories"))))
    existing["networkId"] = existing.get("networkId") or entry.get("networkId")
    existing["mapKind"] = existing.get("mapKind") or entry.get("mapKind")
    existing["inferred"] = existing.get("inferred") or entry.get("inferred")
    existing["isOverstressed"] = existing.get("isOverstressed") or entry.get("isOverstressed")
    existing["hasMissingSource"] = existing.get("hasMissingSource") or entry.get("hasMissingSource")
    existing["merged"] = existing.get("merged", 1) + 1


def coordinate_entries(report):
    entries = {}
    scada_by_coord = scada_nodes_by_coord(report)
    used_scada = set()

    for raw in list_value(report.get("results")):
        if not has_coord(raw):
            continue
        entry = {
            **dict_value(raw),
            "x": int(raw["x"]),
            "y": int(raw["y"]),
            "z": int(raw["z"]),
            "mapKind": raw.get("kind") or ("inventory" if raw.get("inventory") else "wrappable"),
        }
        add_map_entry(entries, entry)

    for raw in list_value(report.get("peripherals")):
        raw = dict_value(raw)
        coord = raw.get("coord")
        if not has_coord(coord):
            continue

        key = coord_tuple(coord)
        scada_node = scada_by_coord.get(key, {})
        scada = {**scada_node, **dict_value(raw.get("kineticScada"))}
        used_scada.add(key)
        entry = {
            "x": int(coord["x"]),
            "y": int(coord["y"]),
            "z": int(coord["z"]),
            "categories": list_value(raw.get("categories")),
            "methods": list_value(raw.get("methods")),
            "methodCount": raw.get("methodCount"),
            "networkId": scada.get("networkId"),
            "subnetworkAnchorId": scada.get("subnetworkAnchorId"),
            "sourceId": scada.get("sourceId"),
            "scadaKind": scada.get("kind"),
            "isOverstressed": scada.get("isOverstressed") is True,
            "hasMissingSource": scada_node.get("hasMissingSource") is True,
        }
        entry["mapKind"] = map_kind_for_entry(entry, scada)
        add_map_entry(entries, entry)

    for key, node in scada_by_coord.items():
        if key in used_scada:
            continue
        entry = {
            "x": key[0],
            "y": key[1],
            "z": key[2],
            "categories": list_value(node.get("categories")),
            "networkId": node.get("networkId"),
            "subnetworkAnchorId": node.get("subnetworkAnchorId"),
            "sourceId": node.get("sourceId"),
            "scadaKind": node.get("kind"),
            "isOverstressed": node.get("isOverstressed") is True,
            "hasMissingSource": node.get("hasMissingSource") is True,
            "mapKind": "scalar" if node.get("isDriver") else "kinetic",
        }
        add_map_entry(entries, entry)

    frame = infer_scada_frame(report)
    nodes = dict(object_items(dict_value(report.get("kineticScada")).get("nodes")))
    missing_groups = [
        ("missing_source", dict_value(report.get("kineticScada")).get("missingSourceIds")),
        ("missing_anchor", dict_value(report.get("kineticScada")).get("missingAnchorIds")),
    ]
    for kind, missing in missing_groups:
        for missing_id, data in object_items(missing):
            world = decode_scada_block_pos(missing_id)
            rel = world_to_relative(world, frame)
            if not rel:
                continue
            data = dict_value(data)
            referenced_by = list_value(data.get("referencedBy"))
            ref_node = dict_value(nodes.get(referenced_by[0])) if referenced_by else {}
            entry = {
                "x": rel["x"],
                "y": rel["y"],
                "z": rel["z"],
                "mapKind": "inferred",
                "inferred": True,
                "inferredKind": kind,
                "networkId": ref_node.get("networkId"),
                "subnetworkAnchorId": ref_node.get("subnetworkAnchorId"),
                "sourceId": missing_id if kind == "missing_source" else None,
                "categories": ["inferredScada"],
                "hasMissingSource": True,
            }
            add_map_entry(entries, entry)

    return list(entries.values())


BLOCK_BY_KIND = {
    "attitude": "minecraft:purple_concrete",
    "rotor": "minecraft:lime_concrete",
    "scalar": "minecraft:orange_concrete",
    "display": "minecraft:light_blue_concrete",
    "kinetic": "minecraft:cyan_concrete",
    "inventory": "minecraft:green_concrete",
    "fluid": "minecraft:blue_concrete",
    "energy": "minecraft:redstone_block",
    "redstone": "minecraft:red_concrete",
    "terminal": "minecraft:white_concrete",
    "modem": "minecraft:gray_concrete",
    "inferred": "minecraft:yellow_concrete",
    "error": "minecraft:red_concrete",
    "wrappable": "minecraft:stone",
    "origin": "minecraft:black_concrete",
}


def block_for_entry(entry):
    if entry.get("isOverstressed"):
        return "minecraft:red_concrete"
    if entry.get("inferredKind") == "missing_anchor":
        return "minecraft:gold_block"
    return BLOCK_BY_KIND.get(entry.get("mapKind"), "minecraft:stone")


def nbt_string(value):
    data = str(value).encode("utf-8")
    return struct.pack(">H", len(data)) + data


def nbt_named_header(tag_type, name):
    return struct.pack(">B", tag_type) + nbt_string(name)


def tag_int(value):
    return (TAG_INT, int(value))


def tag_string(value):
    return (TAG_STRING, str(value))


def tag_list(element_type, values):
    return (TAG_LIST, (element_type, values))


def tag_compound(values):
    return (TAG_COMPOUND, values)


def write_nbt_payload(tag_type, value):
    if tag_type == TAG_BYTE:
        return struct.pack(">b", int(value))
    if tag_type == TAG_INT:
        return struct.pack(">i", int(value))
    if tag_type == TAG_STRING:
        return nbt_string(value)
    if tag_type == TAG_LIST:
        element_type, values = value
        body = struct.pack(">Bi", element_type, len(values))
        payloads = []
        for child in values:
            if isinstance(child, tuple) and len(child) == 2 and child[0] == element_type:
                child = child[1]
            payloads.append(write_nbt_payload(element_type, child))
        return body + b"".join(payloads)
    if tag_type == TAG_COMPOUND:
        body = b""
        for name, child in value.items():
            child_type, child_value = child
            body += nbt_named_header(child_type, name)
            body += write_nbt_payload(child_type, child_value)
        return body + struct.pack(">B", TAG_END)
    raise ValueError(f"unsupported NBT tag type {tag_type}")


def block_state(name, properties=None):
    data = {"Name": tag_string(name)}
    if properties:
        data["Properties"] = tag_compound({key: tag_string(value) for key, value in sorted(properties.items())})
    return data


def structure_nbt_bytes(entries, author="Codex"):
    if not entries:
        raise ValueError("report has no coordinate entries")

    coords = [(int(entry["x"]), int(entry["y"]), int(entry["z"])) for entry in entries]
    coords.append((0, 0, 0))
    min_x = min(x for x, _, _ in coords)
    min_y = min(y for _, y, _ in coords)
    min_z = min(z for _, _, z in coords)
    max_x = max(x for x, _, _ in coords)
    max_y = max(y for _, y, _ in coords)
    max_z = max(z for _, _, z in coords)

    palette = []
    palette_index = {}
    blocks = {}

    def state_index(name, properties=None):
        key = (name, tuple(sorted((properties or {}).items())))
        if key not in palette_index:
            palette_index[key] = len(palette)
            palette.append(tag_compound(block_state(name, properties)))
        return palette_index[key]

    def set_block(x, y, z, name, properties=None):
        pos = (x - min_x, y - min_y, z - min_z)
        blocks[pos] = state_index(name, properties)

    for entry in entries:
        set_block(int(entry["x"]), int(entry["y"]), int(entry["z"]), block_for_entry(entry))

    set_block(0, 0, 0, BLOCK_BY_KIND["origin"])

    block_entries = []
    for (x, y, z), state in sorted(blocks.items()):
        block_entries.append(
            tag_compound(
                {
                    "pos": tag_list(TAG_INT, [x, y, z]),
                    "state": tag_int(state),
                }
            )
        )

    root = {
        "DataVersion": tag_int(DATA_VERSION),
        "author": tag_string(author),
        "size": tag_list(TAG_INT, [max_x - min_x + 1, max_y - min_y + 1, max_z - min_z + 1]),
        "palette": tag_list(TAG_COMPOUND, palette),
        "blocks": tag_list(TAG_COMPOUND, block_entries),
        "entities": tag_list(TAG_COMPOUND, []),
    }

    payload = nbt_named_header(TAG_COMPOUND, "") + write_nbt_payload(TAG_COMPOUND, root)
    return gzip.compress(payload)


def report_structure_nbt(report):
    entries = coordinate_entries(report)
    return structure_nbt_bytes(entries, author="ComputerCraft report viewer")


def nbt_download_name(filename: str):
    stem = Path(filename).stem.replace("latest-report", "cc-map")
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", stem).strip("._-") or "cc-map"
    return f"{stem}.nbt"


class ReportViewerHandler(BaseHTTPRequestHandler):
    def send_json(self, payload, status=200):
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self):
        body = HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_bytes(self, body: bytes, content_type: str, filename: str):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path in ("/", "/index.html"):
            self.send_html()
            return

        if parsed.path == "/api/latest":
            self.send_report("latest-report.json")
            return

        if parsed.path == "/api/report":
            query = parse_qs(parsed.query)
            filename = query.get("file", ["latest-report.json"])[0]
            self.send_report(filename)
            return

        if parsed.path == "/api/reports":
            self.send_reports()
            return

        if parsed.path == "/api/structure":
            query = parse_qs(parsed.query)
            filename = query.get("file", ["latest-report.json"])[0]
            self.send_structure(filename)
            return

        self.send_error(404, "not found")

    def send_report(self, filename: str):
        safe_name = Path(filename).name
        path = INBOX / safe_name

        if not path.exists():
            self.send_json({"exists": False, "name": safe_name, "report": None})
            return

        stat = path.stat()
        self.send_json({
            "exists": True,
            "name": safe_name,
            "modified": stat.st_mtime * 1000,
            "report": read_report(path),
        })

    def send_reports(self):
        INBOX.mkdir(exist_ok=True)
        reports = sorted(INBOX.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
        summaries = [report_summary(path) for path in reports[:100]]
        self.send_json({"reports": summaries})

    def send_structure(self, filename: str):
        safe_name = Path(filename).name
        path = INBOX / safe_name

        if not path.exists():
            self.send_json({"ok": False, "error": f"report not found: {safe_name}"}, status=404)
            return

        report = read_report(path)
        try:
            body = report_structure_nbt(report)
        except Exception as exc:
            self.send_json({"ok": False, "error": str(exc)}, status=400)
            return

        self.send_bytes(body, "application/octet-stream", nbt_download_name(safe_name))

    def log_message(self, format, *args):
        print("%s - %s" % (self.address_string(), format % args))


def main():
    parser = argparse.ArgumentParser(description="Serve a live ComputerCraft report viewer.")
    parser.add_argument("--host", default=os.environ.get("CC_REPORT_VIEWER_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("CC_REPORT_VIEWER_PORT", "8786")))
    args = parser.parse_args()

    INBOX.mkdir(exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), ReportViewerHandler)
    print(f"Report viewer: http://{args.host}:{args.port}")
    print(f"Reading reports from {INBOX}")
    server.serve_forever()


if __name__ == "__main__":
    main()
