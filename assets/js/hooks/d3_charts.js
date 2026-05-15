import * as d3 from "d3";

// ─── Shared helpers ──────────────────────────────────────────────────────────

function isDark() {
  return (
    document.documentElement.getAttribute("data-theme") === "dark" ||
    (document.documentElement.getAttribute("data-theme") !== "light" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches)
  );
}

function themeColors() {
  const style = getComputedStyle(document.documentElement);
  const get = (v) => style.getPropertyValue(v).trim();
  return {
    line: isDark() ? "#818cf8" : "#6366f1", // indigo
    area: isDark() ? "rgba(99,102,241,0.12)" : "rgba(99,102,241,0.08)",
    gust: isDark() ? "#f97316" : "#ea580c", // orange
    rain: isDark() ? "#38bdf8" : "#0284c7", // sky
    grid: isDark() ? "rgba(255,255,255,0.07)" : "rgba(0,0,0,0.06)",
    axis: isDark() ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.45)",
    tooltip_bg: isDark() ? "#1e1e2e" : "#ffffff",
    tooltip_border: isDark() ? "#3f3f5a" : "#e2e8f0",
    rose_fill: isDark() ? "rgba(99,102,241,0.65)" : "rgba(99,102,241,0.55)",
    rose_stroke: isDark() ? "#818cf8" : "#6366f1",
    speed_line: isDark() ? "#34d399" : "#059669", // emerald
    no_data: isDark() ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.05)",
  };
}

function margins() {
  return { top: 16, right: 24, bottom: 36, left: 72 };
}

function makeTooltip(container) {
  return d3
    .select(container)
    .append("div")
    .attr("class", "chart-tooltip")
    .style("position", "absolute")
    .style("pointer-events", "none")
    .style("opacity", 0)
    .style("font-size", "12px")
    .style("padding", "6px 10px")
    .style("border-radius", "0")
    .style("white-space", "nowrap")
    .style("z-index", 10);
}

function positionTooltip(tooltip, event, container) {
  const rect = container.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  tooltip.style("left", x + 14 + "px").style("top", y - 28 + "px");
}

function formatTime(d) {
  const h = d.getHours().toString().padStart(2, "0");
  const m = d.getMinutes().toString().padStart(2, "0");
  const day = d.getDate();
  const mon = d.toLocaleString("default", { month: "short" });
  return `${day} ${mon} ${h}:${m}`;
}

function xTickFormat(d) {
  const h = d.getHours();
  const m = d.getMinutes();
  if (h === 0 && m === 0) {
    return `${d.getDate()} ${d.toLocaleString("default", { month: "short" })}`;
  }
  return `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}`;
}

// Gap threshold: 5 minutes (5× typical 1-min reporting interval)
const GAP_MS = 5 * 60 * 1000;

function getNoDataRegions(parsed, fromMs, toMs) {
  const regions = [];
  if (parsed.length === 0) {
    regions.push({ start: fromMs, end: toMs });
    return regions;
  }
  if (parsed[0].t.getTime() - fromMs > GAP_MS)
    regions.push({ start: fromMs, end: parsed[0].t.getTime() });
  for (let i = 0; i < parsed.length - 1; i++) {
    const gap = parsed[i + 1].t.getTime() - parsed[i].t.getTime();
    if (gap > GAP_MS)
      regions.push({
        start: parsed[i].t.getTime(),
        end: parsed[i + 1].t.getTime(),
      });
  }
  if (toMs - parsed[parsed.length - 1].t.getTime() > GAP_MS)
    regions.push({ start: parsed[parsed.length - 1].t.getTime(), end: toMs });
  return regions;
}

function renderNoDataRegions(g, regions, xScale, innerH, c) {
  g.selectAll(".no-data-region,.no-data-label").remove();
  regions.forEach((region) => {
    const x1 = xScale(new Date(region.start));
    const x2 = xScale(new Date(region.end));
    const w = Math.max(0, x2 - x1);
    if (w <= 0) return;
    g.append("rect")
      .attr("class", "no-data-region")
      .attr("x", x1)
      .attr("y", 0)
      .attr("width", w)
      .attr("height", innerH)
      .attr("fill", c.no_data);
    if (w > 64) {
      g.append("text")
        .attr("class", "no-data-label")
        .attr("x", x1 + w / 2)
        .attr("y", innerH / 2)
        .attr("text-anchor", "middle")
        .attr("dominant-baseline", "middle")
        .style("font-size", "11px")
        .style("pointer-events", "none")
        .style("fill", isDark() ? "rgba(255,255,255,0.22)" : "rgba(0,0,0,0.18)")
        .text("no data");
    }
  });
}

// Split data into continuous segments (breaks at gaps > GAP_MS)
function splitIntoSegments(parsed) {
  if (parsed.length === 0) return [];
  const segments = [[parsed[0]]];
  for (let i = 1; i < parsed.length; i++) {
    const gap = parsed[i].t.getTime() - parsed[i - 1].t.getTime();
    if (gap > GAP_MS) segments.push([]);
    segments[segments.length - 1].push(parsed[i]);
  }
  return segments.filter((s) => s.length > 0);
}

// ─── LineChart ────────────────────────────────────────────────────────────────
// Generic for temperature, humidity, pressure, custom scalar measurements.
// Receives: {id, data: [{t: unix_ms, v: float}], unit, label, from: unix_ms, to: unix_ms}

export const LineChart = {
  mounted() {
    this.data = [];
    this.unit = "";
    this.label = "";
    this.from = null;
    this.to = null;
    this._tooltip = null;

    this.handleEvent(
      "line_chart_data",
      ({ id, data, unit, label, from, to }) => {
        if (id !== this.el.id) return;
        this.data = data;
        this.unit = unit;
        this.label = label;
        this.from = from ?? null;
        this.to = to ?? null;
        this.render();
      },
    );

    this.handleEvent("line_chart_append", ({ id, point, from, to }) => {
      if (id !== this.el.id) return;
      this.data.push(point);
      if (from !== undefined) {
        this.from = from;
        this.to = to;
        // Trim points that have slid out of the window
        this.data = this.data.filter((d) => d.t >= from);
      }
      if (this.data.length > 10000) this.data.shift();
      this.render();
    });

    this._ro = new ResizeObserver(() => this.render());
    this._ro.observe(this.el);
  },

  render() {
    if (!this.data || this.data.length === 0) {
      d3.select(this.el)
        .selectAll("svg,.chart-tooltip,.chart-no-data")
        .remove();
      d3.select(this.el)
        .append("div")
        .attr("class", "chart-no-data")
        .text("No data for this period");
      return;
    }

    d3.select(this.el).selectAll(".chart-no-data").remove();

    const m = margins();
    const w = this.el.clientWidth || 600;
    const h = this.el.clientHeight || 280;
    const innerW = w - m.left - m.right;
    const innerH = h - m.top - m.bottom;
    const c = themeColors();

    const parsed = this.data.map((d) => ({ t: new Date(d.t), v: d.v }));

    // Use server-provided window if available, otherwise fall back to data extent
    const domainFrom =
      this.from != null ? new Date(this.from) : d3.min(parsed, (d) => d.t);
    const domainTo =
      this.to != null ? new Date(this.to) : d3.max(parsed, (d) => d.t);

    const xScale = d3
      .scaleTime()
      .domain([domainFrom, domainTo])
      .range([0, innerW]);

    const [minV, maxV] = d3.extent(parsed, (d) => d.v);
    const pad = (maxV - minV) * 0.1 || 1;
    const yScale = d3
      .scaleLinear()
      .domain([minV - pad, maxV + pad])
      .range([innerH, 0])
      .nice();

    // Redraw full SVG
    d3.select(this.el).selectAll("svg").remove();

    const svg = d3
      .select(this.el)
      .append("svg")
      .attr("width", w)
      .attr("height", h);

    const g = svg
      .append("g")
      .attr("transform", `translate(${m.left},${m.top})`);

    // Grid lines
    g.append("g")
      .attr("class", "grid")
      .call(d3.axisLeft(yScale).tickSize(-innerW).tickFormat(""))
      .selectAll("line")
      .style("stroke", c.grid);
    g.select(".grid .domain").remove();

    // No-data shading (before area/line so it renders underneath)
    if (this.from != null) {
      const regions = getNoDataRegions(parsed, this.from, this.to);
      renderNoDataRegions(g, regions, xScale, innerH, c);
    }

    // Split into continuous segments to avoid interpolation across gaps
    const segments = splitIntoSegments(parsed);

    const area = d3
      .area()
      .x((d) => xScale(d.t))
      .y0(innerH)
      .y1((d) => yScale(d.v))
      .curve(d3.curveMonotoneX);

    const line = d3
      .line()
      .x((d) => xScale(d.t))
      .y((d) => yScale(d.v))
      .curve(d3.curveMonotoneX);

    // Render area fill per segment, then line per segment
    segments.forEach((seg) => {
      g.append("path").datum(seg).attr("fill", c.area).attr("d", area);
    });
    segments.forEach((seg) => {
      g.append("path")
        .datum(seg)
        .attr("fill", "none")
        .attr("stroke", c.line)
        .attr("stroke-width", 1.5)
        .attr("d", line);
    });

    // X axis
    const tickCount = Math.max(2, Math.floor(innerW / 80));
    g.append("g")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(xScale).ticks(tickCount).tickFormat(xTickFormat))
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");
    g.select(".domain").style("stroke", c.grid);
    g.selectAll(".tick line").style("stroke", c.grid);

    // Y axis
    g.append("g")
      .call(
        d3
          .axisLeft(yScale)
          .ticks(5)
          .tickFormat((v) => `${v} ${this.unit}`),
      )
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");

    // Tooltip overlay
    d3.select(this.el).selectAll(".chart-tooltip,.hover-line").remove();
    const tooltip = makeTooltip(this.el);

    const bisect = d3.bisector((d) => d.t).left;

    // Vertical hover line
    svg
      .append("line")
      .attr("class", "hover-line")
      .attr("stroke", c.axis)
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "4,4")
      .attr("opacity", 0)
      .attr("y1", m.top)
      .attr("y2", m.top + innerH);

    svg
      .append("rect")
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .attr("x", m.left)
      .attr("y", m.top)
      .attr("width", innerW)
      .attr("height", innerH)
      .on("mousemove", (event) => {
        const [mx] = d3.pointer(event);
        const x0 = xScale.invert(mx - m.left);
        const idx = bisect(parsed, x0, 1);
        const d = parsed[Math.min(idx, parsed.length - 1)];
        if (!d) return;
        const c2 = themeColors();

        // Update vertical line position
        svg
          .select(".hover-line")
          .attr("x1", mx)
          .attr("x2", mx)
          .attr("opacity", 1);

        tooltip
          .style("opacity", 1)
          .style("background", c2.tooltip_bg)
          .style("border", `1px solid ${c2.tooltip_border}`)
          .html(
            `<strong>${d.v} ${this.unit}</strong><br/><span style="opacity:0.65">${formatTime(d.t)}</span>`,
          );
        positionTooltip(tooltip, event, this.el);
      })
      .on("mouseleave", () => {
        tooltip.style("opacity", 0);
        svg.select(".hover-line").attr("opacity", 0);
      });
  },

  destroyed() {
    this._ro?.disconnect();
  },
};

// ─── WindChart ────────────────────────────────────────────────────────────────
// Combines a speed+gust time series with a wind rose.
// Receives: {data: [{t, speed, gust, dir}], unit, rose: [{sector, pct}], from, to}

const SECTORS_ORDER = [
  "N",
  "NNE",
  "NE",
  "ENE",
  "E",
  "ESE",
  "SE",
  "SSE",
  "S",
  "SSW",
  "SW",
  "WSW",
  "W",
  "WNW",
  "NW",
  "NNW",
];

export const WindChart = {
  mounted() {
    this.data = [];
    this.rose = [];
    this.unit = "";
    this.from = null;
    this.to = null;

    this.handleEvent("wind_chart_data", ({ data, unit, rose, from, to }) => {
      this.data = data;
      this.unit = unit;
      this.rose = rose || [];
      this.from = from ?? null;
      this.to = to ?? null;
      this.render();
    });

    this.handleEvent("wind_chart_append", ({ point, rose, from, to }) => {
      this.data.push(point);
      if (from !== undefined) {
        this.from = from;
        this.to = to;
        this.data = this.data.filter((d) => d.t >= from);
      }
      if (this.data.length > 10000) this.data.shift();
      if (rose) this.rose = rose;
      this.render();
    });

    this._ro = new ResizeObserver(() => this.render());
    this._ro.observe(this.el);
  },

  render() {
    d3.select(this.el).selectAll("svg,div").remove();

    if (!this.data || this.data.length === 0) {
      d3.select(this.el)
        .append("div")
        .attr("class", "chart-no-data")
        .text("No data for this period");
      return;
    }

    const c = themeColors();
    const totalW = this.el.clientWidth || 700;
    const h = this.el.clientHeight || 280;
    const mobile = totalW < 500;

    const container = d3
      .select(this.el)
      .append("div")
      .style("display", "flex")
      .style("flex-direction", mobile ? "column" : "row")
      .style("width", "100%")
      .style("height", h + "px");

    if (mobile) {
      // ── Stacked: speed chart on top, rose below ──
      const lineH = Math.floor(h * 0.55);
      const roseH = h - lineH;
      this._renderSpeedChart(
        container
          .append("div")
          .style("height", lineH + "px")
          .style("flex-shrink", "0")
          .node(),
        totalW,
        lineH,
        c,
      );
      this._renderRose(
        container
          .append("div")
          .style("height", roseH + "px")
          .style("flex-shrink", "0")
          .node(),
        totalW,
        roseH,
        c,
      );
    } else {
      // ── Side by side: 70% speed chart, 30% rose ──
      const roseW = Math.min(220, Math.floor(totalW * 0.28));
      const lineW = totalW - roseW;
      this._renderSpeedChart(
        container
          .append("div")
          .style("flex", "1")
          .style("min-width", "0")
          .node(),
        lineW,
        h,
        c,
      );
      this._renderRose(
        container
          .append("div")
          .style("width", roseW + "px")
          .style("flex-shrink", "0")
          .node(),
        roseW,
        h,
        c,
      );
    }
  },

  _renderSpeedChart(el, w, h, c) {
    const m = margins();
    const innerW = w - m.left - m.right;
    const innerH = h - m.top - m.bottom;

    const parsed = this.data.map((d) => ({
      t: new Date(d.t),
      speed: d.speed,
      gust: d.gust,
    }));

    const domainFrom =
      this.from != null ? new Date(this.from) : d3.min(parsed, (d) => d.t);
    const domainTo =
      this.to != null ? new Date(this.to) : d3.max(parsed, (d) => d.t);

    const xScale = d3
      .scaleTime()
      .domain([domainFrom, domainTo])
      .range([0, innerW]);
    const maxVal = d3.max(parsed, (d) => Math.max(d.speed, d.gust ?? 0)) || 1;
    const yScale = d3
      .scaleLinear()
      .domain([0, maxVal * 1.1])
      .range([innerH, 0])
      .nice();

    const svg = d3.select(el).append("svg").attr("width", w).attr("height", h);
    const g = svg
      .append("g")
      .attr("transform", `translate(${m.left},${m.top})`);

    g.append("g")
      .attr("class", "grid")
      .call(d3.axisLeft(yScale).tickSize(-innerW).tickFormat(""))
      .selectAll("line")
      .style("stroke", c.grid);
    g.select(".grid .domain").remove();

    // No-data shading
    if (this.from != null) {
      const regions = getNoDataRegions(parsed, this.from, this.to);
      renderNoDataRegions(g, regions, xScale, innerH, c);
    }

    // Gust dots
    g.selectAll(".gust-dot")
      .data(parsed.filter((d) => d.gust != null))
      .join("circle")
      .attr("class", "gust-dot")
      .attr("cx", (d) => xScale(d.t))
      .attr("cy", (d) => yScale(d.gust))
      .attr("r", 2.5)
      .attr("fill", c.gust)
      .attr("opacity", 0.7);

    // Speed line — segment-based to avoid interpolation across gaps
    const speedLine = d3
      .line()
      .x((d) => xScale(d.t))
      .y((d) => yScale(d.speed))
      .curve(d3.curveMonotoneX);
    splitIntoSegments(parsed).forEach((seg) => {
      g.append("path")
        .datum(seg)
        .attr("fill", "none")
        .attr("stroke", c.speed_line)
        .attr("stroke-width", 1.5)
        .attr("d", speedLine);
    });

    // Axes
    const tickCount = Math.max(2, Math.floor(innerW / 80));
    g.append("g")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(xScale).ticks(tickCount).tickFormat(xTickFormat))
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");
    g.append("g")
      .call(
        d3
          .axisLeft(yScale)
          .ticks(5)
          .tickFormat((v) => `${v} ${this.unit}`),
      )
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");

    // Legend
    const legend = g
      .append("g")
      .attr("transform", `translate(${innerW - 100}, 4)`);
    legend
      .append("line")
      .attr("x1", 0)
      .attr("x2", 16)
      .attr("y1", 6)
      .attr("y2", 6)
      .attr("stroke", c.speed_line)
      .attr("stroke-width", 2);
    legend
      .append("text")
      .attr("x", 20)
      .attr("y", 10)
      .style("fill", c.axis)
      .style("font-size", "11px")
      .text("Speed");
    legend
      .append("circle")
      .attr("cx", 8)
      .attr("cy", 24)
      .attr("r", 3)
      .attr("fill", c.gust);
    legend
      .append("text")
      .attr("x", 20)
      .attr("y", 28)
      .style("fill", c.axis)
      .style("font-size", "11px")
      .text("Gust");

    // Tooltip
    d3.select(el).selectAll(".chart-tooltip,.hover-line").remove();
    const tooltip = makeTooltip(el);
    const bisect = d3.bisector((d) => d.t).left;

    // Vertical hover line
    svg
      .append("line")
      .attr("class", "hover-line")
      .attr("stroke", c.axis)
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "4,4")
      .attr("opacity", 0)
      .attr("y1", m.top)
      .attr("y2", m.top + innerH);

    svg
      .append("rect")
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .attr("x", m.left)
      .attr("y", m.top)
      .attr("width", innerW)
      .attr("height", innerH)
      .on("mousemove", (event) => {
        const [mx] = d3.pointer(event);
        const x0 = xScale.invert(mx - m.left);
        const idx = bisect(parsed, x0, 1);
        const d = parsed[Math.min(idx, parsed.length - 1)];
        if (!d) return;
        const c2 = themeColors();
        const gustStr = d.gust != null ? ` / gust ${d.gust} ${this.unit}` : "";

        // Update vertical line position
        svg
          .select(".hover-line")
          .attr("x1", mx)
          .attr("x2", mx)
          .attr("opacity", 1);

        tooltip
          .style("opacity", 1)
          .style("background", c2.tooltip_bg)
          .style("border", `1px solid ${c2.tooltip_border}`)
          .html(
            `<strong>${d.speed} ${this.unit}${gustStr}</strong><br/><span style="opacity:0.65">${formatTime(d.t)}</span>`,
          );
        positionTooltip(tooltip, event, el);
      })
      .on("mouseleave", () => {
        tooltip.style("opacity", 0);
        svg.select(".hover-line").attr("opacity", 0);
      });
  },

  _renderRose(el, w, h, c) {
    const size = Math.min(w, h);
    const cx = w / 2;
    const cy = h / 2;
    const maxR = size / 2 - 28;

    const svg = d3.select(el).append("svg").attr("width", w).attr("height", h);

    // Rings (always shown)
    [25, 50, 75, 100].forEach((pct) => {
      svg
        .append("circle")
        .attr("cx", cx)
        .attr("cy", cy)
        .attr("r", (maxR * pct) / 100)
        .attr("fill", "none")
        .attr("stroke", c.axis)
        .attr("stroke-width", 1);
    });

    if (!this.rose || this.rose.length === 0) {
      // No directional data — show calm indicator
      svg
        .append("text")
        .attr("x", cx)
        .attr("y", cy - 8)
        .attr("text-anchor", "middle")
        .style("font-size", "13px")
        .style("font-weight", "600")
        .style("fill", c.axis)
        .text("Calm");
      svg
        .append("text")
        .attr("x", cx)
        .attr("y", cy + 10)
        .attr("text-anchor", "middle")
        .style("font-size", "10px")
        .style("fill", c.axis)
        .style("opacity", "0.5")
        .text("no directional data");
      // Still draw compass labels and return
      const labels = [
        { name: "N", angle: -Math.PI / 2 },
        { name: "E", angle: 0 },
        { name: "S", angle: Math.PI / 2 },
        { name: "W", angle: Math.PI },
      ];
      labels.forEach(({ name, angle }) => {
        const lx = cx + (maxR + 14) * Math.cos(angle);
        const ly = cy + (maxR + 14) * Math.sin(angle);
        svg
          .append("text")
          .attr("x", lx)
          .attr("y", ly + 4)
          .attr("text-anchor", "middle")
          .style("fill", c.axis)
          .style("font-size", "11px")
          .style("font-weight", "600")
          .text(name);
      });
      return;
    }

    const maxPct = d3.max(this.rose, (d) => d.pct) || 1;

    // Bars
    const angleStep = (2 * Math.PI) / 16;
    const byName = Object.fromEntries(this.rose.map((d) => [d.sector, d.pct]));

    SECTORS_ORDER.forEach((name, i) => {
      const pct = byName[name] || 0;
      const r = (maxR * pct) / maxPct;
      const angle = i * angleStep - Math.PI / 2;
      const halfW = angleStep * 0.38;

      const arc = d3
        .arc()
        .innerRadius(0)
        .outerRadius(r)
        .startAngle(angle - halfW)
        .endAngle(angle + halfW);

      svg
        .append("path")
        .attr("transform", `translate(${cx},${cy})`)
        .attr("d", arc())
        .attr("fill", c.rose_fill)
        .attr("stroke", c.rose_stroke)
        .attr("stroke-width", 0.5);
    });

    // Compass labels (N, E, S, W)
    const labels = [
      { name: "N", angle: -Math.PI / 2 },
      { name: "E", angle: 0 },
      { name: "S", angle: Math.PI / 2 },
      { name: "W", angle: Math.PI },
    ];
    labels.forEach(({ name, angle }) => {
      const lx = cx + (maxR + 14) * Math.cos(angle);
      const ly = cy + (maxR + 14) * Math.sin(angle);
      svg
        .append("text")
        .attr("x", lx)
        .attr("y", ly + 4)
        .attr("text-anchor", "middle")
        .style("fill", c.axis)
        .style("font-size", "11px")
        .style("font-weight", "600")
        .text(name);
    });
  },

  destroyed() {
    this._ro?.disconnect();
  },
};

// ─── RainChart ────────────────────────────────────────────────────────────────
// Bar chart — each reading is one bar showing its interval_mm.
// Receives: {data: [{t: unix_ms, v: float}], unit, from: unix_ms, to: unix_ms}

export const RainChart = {
  mounted() {
    this.data = [];
    this.unit = "";
    this.from = null;
    this.to = null;

    this.handleEvent("rain_chart_data", ({ data, unit, from, to }) => {
      this.data = data;
      this.unit = unit;
      this.from = from ?? null;
      this.to = to ?? null;
      this.render();
    });

    this.handleEvent("rain_chart_append", ({ point, from, to }) => {
      this.data.push(point);
      if (from !== undefined) {
        this.from = from;
        this.to = to;
        this.data = this.data.filter((d) => d.t >= from);
      }
      if (this.data.length > 10000) this.data.shift();
      this.render();
    });

    this._ro = new ResizeObserver(() => this.render());
    this._ro.observe(this.el);
  },

  render() {
    d3.select(this.el).selectAll("svg,div").remove();

    if (!this.data || this.data.length === 0) {
      d3.select(this.el)
        .append("div")
        .attr("class", "chart-no-data")
        .text("No data for this period");
      return;
    }

    const c = themeColors();
    const m = margins();
    const w = this.el.clientWidth || 600;
    const h = this.el.clientHeight || 280;
    const innerW = w - m.left - m.right;
    const innerH = h - m.top - m.bottom;

    const parsed = this.data.map((d) => ({ t: new Date(d.t), v: d.v }));

    const domainFrom =
      this.from != null ? new Date(this.from) : d3.min(parsed, (d) => d.t);
    const domainTo =
      this.to != null ? new Date(this.to) : d3.max(parsed, (d) => d.t);

    const xScale = d3
      .scaleTime()
      .domain([domainFrom, domainTo])
      .range([0, innerW]);
    const yScale = d3
      .scaleLinear()
      .domain([0, d3.max(parsed, (d) => d.v) * 1.15 || 1])
      .range([innerH, 0])
      .nice();

    const svg = d3
      .select(this.el)
      .append("svg")
      .attr("width", w)
      .attr("height", h);
    const g = svg
      .append("g")
      .attr("transform", `translate(${m.left},${m.top})`);

    g.append("g")
      .attr("class", "grid")
      .call(d3.axisLeft(yScale).tickSize(-innerW).tickFormat(""))
      .selectAll("line")
      .style("stroke", c.grid);
    g.select(".grid .domain").remove();

    // No-data shading
    if (this.from != null) {
      const regions = getNoDataRegions(parsed, this.from, this.to);
      renderNoDataRegions(g, regions, xScale, innerH, c);
    }

    // Bar width: use time gap between readings, default to 4px min
    const barW =
      parsed.length > 1
        ? Math.max(2, (xScale(parsed[1].t) - xScale(parsed[0].t)) * 0.8)
        : 4;

    g.selectAll(".bar")
      .data(parsed)
      .join("rect")
      .attr("class", "bar")
      .attr("x", (d) => xScale(d.t) - barW / 2)
      .attr("y", (d) => yScale(d.v))
      .attr("width", barW)
      .attr("height", (d) => innerH - yScale(d.v))
      .attr("fill", c.rain)
      .attr("rx", 1);

    const tickCount = Math.max(2, Math.floor(innerW / 80));
    g.append("g")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(xScale).ticks(tickCount).tickFormat(xTickFormat))
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");
    g.append("g")
      .call(
        d3
          .axisLeft(yScale)
          .ticks(5)
          .tickFormat((v) => `${v} ${this.unit}`),
      )
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");

    // Tooltip
    d3.select(this.el).selectAll(".chart-tooltip,.hover-line").remove();
    const tooltip = makeTooltip(this.el);
    const bisect = d3.bisector((d) => d.t).left;

    // Vertical hover line
    svg
      .append("line")
      .attr("class", "hover-line")
      .attr("stroke", c.axis)
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "4,4")
      .attr("opacity", 0)
      .attr("y1", m.top)
      .attr("y2", m.top + innerH);

    svg
      .append("rect")
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .attr("x", m.left)
      .attr("y", m.top)
      .attr("width", innerW)
      .attr("height", innerH)
      .on("mousemove", (event) => {
        const [mx] = d3.pointer(event);
        const x0 = xScale.invert(mx - m.left);
        const idx = bisect(parsed, x0, 1);
        const d = parsed[Math.min(idx, parsed.length - 1)];
        if (!d) return;
        const c2 = themeColors();

        // Update vertical line position
        svg
          .select(".hover-line")
          .attr("x1", mx)
          .attr("x2", mx)
          .attr("opacity", 1);

        tooltip
          .style("opacity", 1)
          .style("background", c2.tooltip_bg)
          .style("border", `1px solid ${c2.tooltip_border}`)
          .html(
            `<strong>${d.v} ${this.unit}</strong><br/><span style="opacity:0.65">${formatTime(d.t)}</span>`,
          );
        positionTooltip(tooltip, event, this.el);
      })
      .on("mouseleave", () => {
        tooltip.style("opacity", 0);
        svg.select(".hover-line").attr("opacity", 0);
      });
  },

  destroyed() {
    this._ro?.disconnect();
  },
};

// ─── MultiLineChart ──────────────────────────────────────────────────────────
// Multi-station comparison chart.
// Receives: {series: [{id, name, data: [{t: unix_ms, v: float}], color}], unit, from: unix_ms, to: unix_ms}

export const MultiLineChart = {
  mounted() {
    try {
      this.series = [];
      this.unit = "";
      this.from = null;
      this.to = null;
      this._tooltip = null;

      this.handleEvent(
        "multi_line_chart_data",
        ({ series, unit, from, to }) => {
          this.series = series;
          this.unit = unit;
          this.from = from !== undefined && from !== null ? from : null;
          this.to = to !== undefined && to !== null ? to : null;
          this.render();
        },
      );

      this.handleEvent("multi_line_chart_append", ({ point, from, to }) => {
        const targetSeries = this.series.find((s) => s.id === point.series_id);
        if (targetSeries) {
          targetSeries.data.push(point.point);
          if (from !== undefined) {
            this.from = from;
            this.to = to;
            this.series.forEach((s) => {
              s.data = s.data.filter((d) => d.t >= from);
            });
          }
          this.series.forEach((s) => {
            if (s.data.length > 10000) s.data.shift();
          });
          this.render();
        }
      });

      this._ro = new ResizeObserver(() => this.render());
      this._ro.observe(this.el);
    } catch (error) {
      throw error;
    }
  },

  render() {
    if (!this.series || this.series.length === 0) {
      d3.select(this.el).selectAll("svg,.chart-tooltip").remove();
      return;
    }

    const m = margins();
    const w = this.el.clientWidth || 600;
    const h = this.el.clientHeight || 280;
    const innerW = w - m.left - m.right;
    const innerH = h - m.top - m.bottom;
    const c = themeColors();

    const allData = this.series.flatMap((s) => {
      const parsedData = s.data.map((d) => ({ t: new Date(d.t), v: d.v }));
      return parsedData.map((d) => ({ t: d.t, v: d.v, seriesId: s.id, seriesName: s.name, color: s.color }));
    });

    if (allData.length === 0) {
      d3.select(this.el).selectAll("svg,.chart-tooltip").remove();
      d3.select(this.el)
        .append("div")
        .attr("class", "chart-no-data")
        .text("No data for this period");
      return;
    }

    d3.select(this.el).selectAll(".chart-no-data").remove();

    const domainFrom =
      this.from != null ? new Date(this.from) : d3.min(allData, (d) => d.t);
    const domainTo =
      this.to != null ? new Date(this.to) : d3.max(allData, (d) => d.t);

    const xScale = d3
      .scaleTime()
      .domain([domainFrom, domainTo])
      .range([0, innerW]);

    const [minV, maxV] = d3.extent(allData, (d) => d.v);
    const pad = (maxV - minV) * 0.1 || 1;
    const yScale = d3
      .scaleLinear()
      .domain([minV - pad, maxV + pad])
      .range([innerH, 0])
      .nice();

    d3.select(this.el).selectAll("svg").remove();

    const svg = d3
      .select(this.el)
      .append("svg")
      .attr("width", w)
      .attr("height", h);

    const g = svg
      .append("g")
      .attr("transform", `translate(${m.left},${m.top})`);

    g.append("g")
      .attr("class", "grid")
      .call(d3.axisLeft(yScale).tickSize(-innerW).tickFormat(""))
      .selectAll("line")
      .style("stroke", c.grid);
    g.select(".grid .domain").remove();

    const line = d3
      .line()
      .x((d) => xScale(d.t))
      .y((d) => yScale(d.v))
      .curve(d3.curveMonotoneX);

    this.series.forEach((s) => {
      const parsedData = s.data.map((d) => ({ t: new Date(d.t), v: d.v }));
      g.append("path")
        .datum(parsedData)
        .attr("fill", "none")
        .attr("stroke", s.color)
        .attr("stroke-width", 1.5)
        .attr("d", line);
    });

    const tickCount = Math.max(2, Math.floor(innerW / 80));
    g.append("g")
      .attr("transform", `translate(0,${innerH})`)
      .call(d3.axisBottom(xScale).ticks(tickCount).tickFormat(xTickFormat))
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");
    g.select(".domain").style("stroke", c.grid);
    g.selectAll(".tick line").style("stroke", c.grid);

    g.append("g")
      .call(
        d3
          .axisLeft(yScale)
          .ticks(5)
          .tickFormat((v) => `${v} ${this.unit}`),
      )
      .selectAll("text")
      .style("fill", c.axis)
      .style("font-size", "11px");

    d3.select(this.el).selectAll(".chart-tooltip,.hover-line").remove();
    const tooltip = makeTooltip(this.el);

    svg
      .append("line")
      .attr("class", "hover-line")
      .attr("stroke", c.axis)
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "4,4")
      .attr("opacity", 0)
      .attr("y1", m.top)
      .attr("y2", m.top + innerH);

    svg
      .append("rect")
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .attr("x", m.left)
      .attr("y", m.top)
      .attr("width", innerW)
      .attr("height", innerH)
      .on("mousemove", (event) => {
        const [mx] = d3.pointer(event);
        const x0 = xScale.invert(mx - m.left);

        const tooltipData = [];
        this.series.forEach((s) => {
          if (s.data.length > 0) {
            const parsedData = s.data.map((d) => ({ t: new Date(d.t), v: d.v }));
            const bisect = d3.bisector((d) => d.t).left;
            const idx = bisect(parsedData, x0, 1);
            const d = parsedData[Math.min(idx, parsedData.length - 1)];
            if (d) {
              tooltipData.push({
                name: s.name,
                value: d.v,
                color: s.color,
                t: d.t,
              });
            }
          }
        });

        if (tooltipData.length > 0) {
          const c2 = themeColors();

          svg
            .select(".hover-line")
            .attr("x1", mx)
            .attr("x2", mx)
            .attr("opacity", 1);

          tooltip
            .style("opacity", 1)
            .style("background", c2.tooltip_bg)
            .style("border", `1px solid ${c2.tooltip_border}`)
            .html(
              tooltipData
                .map(
                  (d) =>
                    `<div style="display:flex;align-items:center;gap:6px;margin-bottom:4px;">
                <div style="width:10px;height:10px;border-radius:50%;background-color:${d.color};flex-shrink:0;"></div>
                <div>
                  <strong>${d.value} ${this.unit}</strong>
                  <br/>
                  <span style="opacity:0.65;font-size:11px;">${d.name}</span>
                </div>
              </div>`,
                )
                .join("") +
                `<div style="margin-top:4px;font-size:10px;opacity:0.65;">${formatTime(tooltipData[0].t)}</div>`,
            );
          positionTooltip(tooltip, event, this.el);
        }
      })
      .on("mouseleave", () => {
        tooltip.style("opacity", 0);
        svg.select(".hover-line").attr("opacity", 0);
      });
  },

  destroyed() {
    this._ro?.disconnect();
  },
};
