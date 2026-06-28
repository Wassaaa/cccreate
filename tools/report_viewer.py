from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import argparse
import json
import os


ROOT = Path(__file__).resolve().parents[1]
INBOX = ROOT / "inbox"


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

    const tabs = ["overview", "map", "output", "peripherals", "inventory", "files", "raw"];

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
      els.tabs.innerHTML = tabs.map((tab) => {
        const active = tab === state.activeTab ? " active" : "";
        return `<button class="tab${active}" data-tab="${tab}">${escapeHtml(tabLabel(tab))}</button>`;
      }).join("");

      for (const button of els.tabs.querySelectorAll("button[data-tab]")) {
        button.addEventListener("click", () => {
          state.activeTab = button.dataset.tab;
          render();
        });
      }

      if (state.activeTab === "overview") els.view.innerHTML = renderOverview(report);
      if (state.activeTab === "map") els.view.innerHTML = renderRouterMap(report);
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

    function tabLabel(tab) {
      return {
        overview: "Overview",
        map: "Map",
        output: "Output",
        peripherals: "Peripherals",
        inventory: "Inventory",
        files: "Files",
        raw: "Raw JSON"
      }[tab] || tab;
    }

    function renderSummary(report) {
      const values = [
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

      blocks.push(`<div class="grid-2"><section class="block"><h2>Peripherals</h2>${peripheralTable(report)}</section><section class="block"><h2>Inventory</h2>${inventoryTable(report.inventory)}</section></div>`);
      return blocks.join("");
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

    function hasRouterCoordinates(report) {
      return asArray(report.results).some((entry) =>
        Number.isFinite(Number(entry.x)) &&
        Number.isFinite(Number(entry.y)) &&
        Number.isFinite(Number(entry.z))
      );
    }

    function range(start, end) {
      const values = [];
      for (let value = start; value <= end; value += 1) values.push(value);
      return values;
    }

    function routerBounds(report, entries) {
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
      return {
        xs: range(Math.min(...xs), Math.max(...xs)),
        ys: range(Math.min(...ys), Math.max(...ys)),
        zs: range(Math.min(...zs), Math.max(...zs))
      };
    }

    function entryKey(x, y, z) {
      return `${x},${y},${z}`;
    }

    function mapEntryClass(entry) {
      if (!entry) return "empty";
      if (entry.ok === false) return "error";
      return entry.kind || (entry.inventory ? "inventory" : "wrappable");
    }

    function topItems(entry) {
      return asArray(entry.itemTotals)
        .slice(0, 2)
        .map((item) => `${item.name} x${item.count}`)
        .join(", ");
    }

    function mapCell(entry, x, y, z) {
      if (!entry) {
        return `<div class="map-cell empty"><span class="map-coord">${x},${y},${z}</span></div>`;
      }

      const detail = entry.inventory
        ? `${entry.usedSlots ?? 0}/${entry.size ?? "?"} slots${entry.totalItems === undefined ? "" : `, ${entry.totalItems} items`}`
        : `${entry.kind || "wrappable"}${entry.methodCount === undefined ? "" : `, ${entry.methodCount} methods`}`;
      const items = topItems(entry);
      const title = `${entry.label || ""} ${entry.displayName || ""} ${items}`.trim();

      return `
        <div class="map-cell ${escapeHtml(mapEntryClass(entry))}" title="${escapeHtml(title)}">
          <span class="map-coord">${escapeHtml(entry.label || `${x},${y},${z}`)}</span>
          <span class="map-name">${escapeHtml(entry.displayName || (entry.inventory ? "inventory" : entry.kind || "wrappable"))}</span>
          <span class="map-detail">${escapeHtml(detail)}</span>
          ${items ? `<span class="map-detail">${escapeHtml(items)}</span>` : ""}
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
          <thead><tr><th>Coord</th><th>Name</th><th>Kind</th><th>Slots</th><th>Items</th><th>Methods</th></tr></thead>
          <tbody>
            ${entries.map((entry) => `
              <tr>
                <td>${escapeHtml(entry.label || `${entry.x},${entry.y},${entry.z}`)}</td>
                <td>${escapeHtml(entry.displayName || "")}</td>
                <td>${escapeHtml(entry.kind || (entry.inventory ? "inventory" : ""))}</td>
                <td>${entry.inventory ? `${escapeHtml(entry.usedSlots ?? 0)} / ${escapeHtml(entry.size ?? "")}` : ""}</td>
                <td>${escapeHtml(topItems(entry) || entry.totalItems || "")}</td>
                <td>${escapeHtml(entry.methodCount ?? "")}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }

    function renderRouterMap(report) {
      const entries = asArray(report.results).filter((entry) =>
        Number.isFinite(Number(entry.x)) &&
        Number.isFinite(Number(entry.y)) &&
        Number.isFinite(Number(entry.z))
      );

      if (!hasRouterCoordinates(report)) {
        return '<div class="empty">This report does not contain router-relative coordinates. Run <span class="mono">router_inventory_scanner map --radius 8</span>.</div>';
      }

      const bounds = routerBounds(report, entries);
      const byCoord = {};
      for (const entry of entries) {
        byCoord[entryKey(Number(entry.x), Number(entry.y), Number(entry.z))] = entry;
      }

      const layers = [...bounds.ys].sort((left, right) => right - left);
      const metrics = `
        <div class="map-controls">
          <span class="pill">${escapeHtml(report.width || bounds.xs.length)}x${escapeHtml(report.height || bounds.ys.length)}x${escapeHtml(report.depth || bounds.zs.length)}</span>
          <span class="pill">${escapeHtml(report.inspected ?? "")} checked</span>
          <span class="pill">${escapeHtml(report.wrappable ?? entries.length)} wrappable</span>
          <span class="pill">${escapeHtml(report.inventories ?? "")} inventories</span>
          <span class="pill">router ${escapeHtml(report.router || "n/a")}</span>
        </div>
      `;

      return `
        <section class="block">
          <h2>Router Map</h2>
          ${metrics}
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
