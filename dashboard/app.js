/**
 * Fin-Guard Analytics – Dashboard JavaScript
 * ============================================
 * Manages Chart.js charts, live KPI simulation,
 * AI agent log, regional heatmap, and modal.
 */

'use strict';

// ── Chart.js Global Defaults ────────────────────────────────────────────────
Chart.defaults.color = '#A0AEC0';
Chart.defaults.borderColor = 'rgba(255,255,255,0.06)';
Chart.defaults.font.family = "'Inter', system-ui, sans-serif";
Chart.defaults.font.size = 12;
Chart.defaults.plugins.legend.display = false;

// ── Color Palette ───────────────────────────────────────────────────────────
const COLORS = {
    blue: '#4299E1',
    purple: '#9F7AEA',
    teal: '#38B2AC',
    green: '#48BB78',
    yellow: '#F6AD55',
    red: '#FC8181',
    pink: '#F687B3',
    indigo: '#7F9CF5',
    danger: '#E53E3E',
};

const GRAD = (ctx, colors) => {
    const g = ctx.createLinearGradient(0, 0, 0, 300);
    g.addColorStop(0, colors[0]);
    g.addColorStop(1, colors[1]);
    return g;
};

// ── Helpers ──────────────────────────────────────────────────────────────────
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function genMonthLabels(n = 12) {
    const now = new Date();
    const labels = [];
    for (let i = n - 1; i >= 0; i--) {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        labels.push(months[d.getMonth()] + ' ' + String(d.getFullYear()).slice(2));
    }
    return labels;
}

function genDayLabels(n = 30) {
    const labels = [];
    for (let i = n - 1; i >= 0; i--) {
        const d = new Date(Date.now() - i * 86400000);
        labels.push(`${d.getDate()} ${months[d.getMonth()]}`);
    }
    return labels;
}

function jitter(base, range) {
    return +(base + (Math.random() - 0.5) * 2 * range).toFixed(4);
}

function seedRandom(arr) {
    return arr.map(v => jitter(v, v * 0.15));
}

// ══════════════════════════════════════════════════════════════════════════════
// 1. DEFAULT RATE TREND CHART
// ══════════════════════════════════════════════════════════════════════════════
const defaultRateData = {
    monthly: {
        labels: genMonthLabels(18),
        values: [1.8, 2.0, 2.3, 2.1, 2.5, 2.7, 2.4, 2.8, 2.6, 2.9, 3.1, 2.8, 3.0, 3.2, 3.4, 3.5, 3.6, 3.71],
    },
    quarterly: {
        labels: ['Q1 22', 'Q2 22', 'Q3 22', 'Q4 22', 'Q1 23', 'Q2 23', 'Q3 23', 'Q4 23', 'Q1 24', 'Q2 24'],
        values: [1.9, 2.1, 2.6, 2.7, 2.9, 3.0, 3.2, 3.4, 3.5, 3.71],
    }
};

let defaultRateView = 'monthly';

const defaultRateChart = new Chart(
    document.getElementById('defaultRateChart'),
    {
        type: 'line',
        data: {
            labels: defaultRateData.monthly.labels,
            datasets: [
                {
                    label: 'Default Rate %',
                    data: defaultRateData.monthly.values,
                    borderColor: COLORS.red,
                    backgroundColor: (ctx) => {
                        const g = ctx.chart.ctx.createLinearGradient(0, 0, 0, 260);
                        g.addColorStop(0, 'rgba(229,62,62,0.25)');
                        g.addColorStop(1, 'rgba(229,62,62,0)');
                        return g;
                    },
                    borderWidth: 2.5,
                    fill: true,
                    tension: 0.4,
                    pointRadius: 4,
                    pointHoverRadius: 7,
                    pointBackgroundColor: COLORS.red,
                    pointBorderColor: '#1A2235',
                    pointBorderWidth: 2,
                },
                {
                    label: 'Threshold',
                    data: new Array(18).fill(3.0),
                    borderColor: 'rgba(246,173,85,0.6)',
                    borderWidth: 1.5,
                    borderDash: [6, 4],
                    pointRadius: 0,
                    fill: false,
                    tension: 0,
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'index', intersect: false },
            plugins: {
                tooltip: {
                    backgroundColor: '#1A2235',
                    borderColor: 'rgba(66,153,225,0.3)',
                    borderWidth: 1,
                    padding: 12,
                    callbacks: {
                        label: ctx => `  ${ctx.dataset.label}: ${ctx.parsed.y.toFixed(2)}%`
                    }
                },
                annotation: {
                    annotations: {
                        breachLine: {
                            type: 'line',
                            yMin: 3.0, yMax: 3.0,
                            borderColor: 'rgba(246,173,85,0.8)',
                            borderWidth: 1,
                            borderDash: [5, 5],
                            label: {
                                display: true,
                                content: 'Threshold 3.0%',
                                color: '#F6AD55',
                                font: { size: 10, weight: '600' },
                                position: 'end',
                                backgroundColor: 'rgba(26,34,53,0.9)',
                                padding: { x: 6, y: 3 },
                                yAdjust: -12,
                            }
                        }
                    }
                }
            },
            scales: {
                x: {
                    grid: { color: 'rgba(255,255,255,0.04)' },
                    ticks: { maxRotation: 45 }
                },
                y: {
                    grid: { color: 'rgba(255,255,255,0.04)' },
                    ticks: { callback: v => v.toFixed(1) + '%' },
                    min: 0,
                }
            }
        }
    }
);

// ══════════════════════════════════════════════════════════════════════════════
// 2. RISK TIER DONUT CHART
// ══════════════════════════════════════════════════════════════════════════════
const riskTierConfig = {
    labels: ['Low Risk', 'Medium Risk', 'High Risk', 'Critical'],
    data: [38, 31, 22, 9],
    colors: [COLORS.green, COLORS.blue, COLORS.yellow, COLORS.red],
};

new Chart(document.getElementById('riskTierChart'), {
    type: 'doughnut',
    data: {
        labels: riskTierConfig.labels,
        datasets: [{
            data: riskTierConfig.data,
            backgroundColor: riskTierConfig.colors.map(c => c + 'CC'),
            borderColor: riskTierConfig.colors,
            borderWidth: 2,
            hoverBorderWidth: 3,
            hoverOffset: 8,
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '68%',
        plugins: {
            legend: { display: false },
            tooltip: {
                backgroundColor: '#1A2235',
                borderColor: 'rgba(66,153,225,0.3)',
                borderWidth: 1,
                padding: 12,
                callbacks: { label: ctx => `  ${ctx.label}: ${ctx.parsed}%` }
            }
        }
    }
});

// Build custom legend
const legendEl = document.getElementById('risk-legend');
riskTierConfig.labels.forEach((label, i) => {
    legendEl.innerHTML += `
    <div style="display:flex;align-items:center;gap:6px;font-size:0.75rem;color:#A0AEC0">
      <div style="width:10px;height:10px;border-radius:2px;background:${riskTierConfig.colors[i]};flex-shrink:0"></div>
      <span>${label} (${riskTierConfig.data[i]}%)</span>
    </div>`;
});

// ══════════════════════════════════════════════════════════════════════════════
// 3. PAR BUCKET BAR CHART
// ══════════════════════════════════════════════════════════════════════════════
new Chart(document.getElementById('parBucketChart'), {
    type: 'bar',
    data: {
        labels: ['Current\n(0 days)', 'PAR 1-29', 'PAR 30-59', 'PAR 60-89', 'NPL 90+'],
        datasets: [{
            label: '% of Portfolio',
            data: [71.4, 10.8, 6.2, 4.1, 7.5],
            backgroundColor: [
                'rgba(72,187,120,0.7)',
                'rgba(66,153,225,0.7)',
                'rgba(246,173,85,0.7)',
                'rgba(252,129,129,0.7)',
                'rgba(229,62,62,0.85)',
            ],
            borderColor: [COLORS.green, COLORS.blue, COLORS.yellow, COLORS.red, COLORS.danger],
            borderWidth: 1.5,
            borderRadius: 6,
            borderSkipped: false,
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            tooltip: {
                backgroundColor: '#1A2235',
                borderColor: 'rgba(66,153,225,0.3)',
                borderWidth: 1,
                padding: 10,
                callbacks: { label: ctx => `  Share: ${ctx.parsed.y.toFixed(1)}%` }
            }
        },
        scales: {
            x: { grid: { display: false } },
            y: {
                grid: { color: 'rgba(255,255,255,0.04)' },
                ticks: { callback: v => v + '%', stepSize: 20 },
                max: 100,
            }
        }
    }
});

// ══════════════════════════════════════════════════════════════════════════════
// 4. TRANSACTION VOLUME STACKED BAR
// ══════════════════════════════════════════════════════════════════════════════
const txnLabels = genDayLabels(30);
const txnTypes = ['Repayment', 'Transfer', 'Withdrawal', 'Deposit', 'Disbursement'];
const txnColors = [COLORS.blue, COLORS.teal, COLORS.yellow, COLORS.green, COLORS.purple];
const txnBases = [320, 130, 95, 65, 30];

new Chart(document.getElementById('txnVolumeChart'), {
    type: 'bar',
    data: {
        labels: txnLabels,
        datasets: txnTypes.map((type, i) => ({
            label: type,
            data: txnLabels.map(() => Math.round(txnBases[i] + Math.random() * 60 - 30)),
            backgroundColor: txnColors[i] + '99',
            borderColor: txnColors[i],
            borderWidth: 0.5,
            borderRadius: i === 0 ? { topLeft: 4, topRight: 4 } : 0,
        }))
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                display: true,
                position: 'bottom',
                labels: {
                    boxWidth: 10,
                    font: { size: 10 },
                    color: '#718096',
                    padding: 12,
                }
            },
            tooltip: {
                backgroundColor: '#1A2235',
                borderColor: 'rgba(66,153,225,0.3)',
                borderWidth: 1,
                padding: 10,
            }
        },
        scales: {
            x: {
                stacked: true,
                grid: { display: false },
                ticks: {
                    maxRotation: 45,
                    callback: (_, i) => i % 5 === 0 ? txnLabels[i] : ''
                }
            },
            y: {
                stacked: true,
                grid: { color: 'rgba(255,255,255,0.04)' },
            }
        }
    }
});

// ══════════════════════════════════════════════════════════════════════════════
// 5. ANOMALY TREND AREA CHART
// ══════════════════════════════════════════════════════════════════════════════
const anomalyValues = genDayLabels(30).map(() => Math.round(Math.random() * 60 + 10));
anomalyValues[anomalyValues.length - 1] = 38;  // today

new Chart(document.getElementById('anomalyChart'), {
    type: 'line',
    data: {
        labels: genDayLabels(30),
        datasets: [
            {
                label: 'Anomaly Count',
                data: anomalyValues,
                borderColor: COLORS.purple,
                backgroundColor: (ctx) => {
                    const g = ctx.chart.ctx.createLinearGradient(0, 0, 0, 240);
                    g.addColorStop(0, 'rgba(159,122,234,0.3)');
                    g.addColorStop(1, 'rgba(159,122,234,0)');
                    return g;
                },
                borderWidth: 2,
                fill: true,
                tension: 0.4,
                pointRadius: 0,
                pointHoverRadius: 5,
            },
            {
                label: 'Threshold',
                data: new Array(30).fill(50),
                borderColor: 'rgba(246,173,85,0.5)',
                borderWidth: 1,
                borderDash: [5, 4],
                pointRadius: 0,
                fill: false,
            }
        ]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
            tooltip: {
                backgroundColor: '#1A2235',
                borderColor: 'rgba(66,153,225,0.3)',
                borderWidth: 1,
                padding: 10,
            }
        },
        scales: {
            x: {
                grid: { display: false },
                ticks: {
                    maxRotation: 45,
                    callback: (_, i) => i % 7 === 0 ? genDayLabels(30)[i] : ''
                }
            },
            y: {
                grid: { color: 'rgba(255,255,255,0.04)' },
                min: 0,
            }
        }
    }
});

// ══════════════════════════════════════════════════════════════════════════════
// 6. LOAN STATUS HORIZONTAL BAR
// ══════════════════════════════════════════════════════════════════════════════
new Chart(document.getElementById('loanStatusChart'), {
    type: 'bar',
    data: {
        labels: ['Active', 'Closed', 'Restructured', 'Defaulted'],
        datasets: [{
            label: 'Loans',
            data: [8421, 2156, 634, 789],
            backgroundColor: [
                'rgba(72,187,120,0.7)',
                'rgba(66,153,225,0.7)',
                'rgba(246,173,85,0.7)',
                'rgba(229,62,62,0.7)',
            ],
            borderColor: [COLORS.green, COLORS.blue, COLORS.yellow, COLORS.danger],
            borderWidth: 1.5,
            borderRadius: 6,
        }]
    },
    options: {
        indexAxis: 'y',
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            tooltip: {
                backgroundColor: '#1A2235',
                borderColor: 'rgba(66,153,225,0.3)',
                borderWidth: 1,
                padding: 10,
                callbacks: { label: ctx => `  Loans: ${ctx.parsed.x.toLocaleString()}` }
            }
        },
        scales: {
            x: {
                grid: { color: 'rgba(255,255,255,0.04)' },
                ticks: { callback: v => (v / 1000).toFixed(0) + 'K' }
            },
            y: { grid: { display: false } }
        }
    }
});

// ══════════════════════════════════════════════════════════════════════════════
// REGIONAL HEATMAP TABLE
// ══════════════════════════════════════════════════════════════════════════════
const regionData = [
    { region: 'USA', state: 'Texas', loans: 1842, portfolio: 52.4, defaultRate: 5.2, par30: 7.1, anomalies: 14, score: 'HIGH' },
    { region: 'USA', state: 'California', loans: 2103, portfolio: 68.9, defaultRate: 3.1, par30: 4.8, anomalies: 8, score: 'MEDIUM' },
    { region: 'USA', state: 'New York', loans: 1956, portfolio: 71.2, defaultRate: 2.8, par30: 3.9, anomalies: 6, score: 'LOW' },
    { region: 'USA', state: 'Illinois', loans: 934, portfolio: 28.1, defaultRate: 3.8, par30: 5.6, anomalies: 5, score: 'MEDIUM' },
    { region: 'UK', state: 'England', loans: 748, portfolio: 22.5, defaultRate: 2.1, par30: 3.1, anomalies: 3, score: 'LOW' },
    { region: 'India', state: 'Maharashtra', loans: 612, portfolio: 14.2, defaultRate: 4.3, par30: 6.8, anomalies: 2, score: 'MEDIUM' },
    { region: 'India', state: 'Delhi', loans: 489, portfolio: 11.8, defaultRate: 6.1, par30: 8.9, anomalies: 0, score: 'HIGH' },
    { region: 'Canada', state: 'Ontario', loans: 341, portfolio: 9.7, defaultRate: 1.9, par30: 2.8, anomalies: 0, score: 'LOW' },
];

function renderRegionTable(data) {
    const tbody = document.getElementById('region-tbody');
    tbody.innerHTML = data.map(r => {
        const scoreClass = r.score.toLowerCase();
        const drColor = r.defaultRate > 5 ? '#FC8181' : r.defaultRate > 3 ? '#F6AD55' : '#68D391';
        const par30Color = r.par30 > 7 ? '#FC8181' : r.par30 > 5 ? '#F6AD55' : '#68D391';
        return `
      <tr>
        <td><strong style="color:#90CDF4">${r.region}</strong></td>
        <td>${r.state}</td>
        <td>${r.loans.toLocaleString()}</td>
        <td>$${r.portfolio.toFixed(1)}M</td>
        <td style="color:${drColor};font-family:var(--mono);font-weight:600">${r.defaultRate.toFixed(1)}%</td>
        <td style="color:${par30Color};font-family:var(--mono);font-weight:600">${r.par30.toFixed(1)}%</td>
        <td style="font-family:var(--mono)">${r.anomalies}</td>
        <td><span class="risk-pill ${scoreClass}">${r.score}</span></td>
      </tr>`;
    }).join('');
}

renderRegionTable(regionData);

// ══════════════════════════════════════════════════════════════════════════════
// LIVE CLOCK
// ══════════════════════════════════════════════════════════════════════════════
function updateClock() {
    const now = new Date();
    const utc = now.toUTCString().split(' ');
    document.getElementById('nav-time').textContent =
        `${utc[4]} UTC · ${utc[1]} ${utc[2]} ${utc[3]}`;
}

setInterval(updateClock, 1000);
updateClock();

// ══════════════════════════════════════════════════════════════════════════════
// ALERT BANNER
// ══════════════════════════════════════════════════════════════════════════════
function showAlert(message) {
    document.getElementById('alert-text').textContent = message;
    document.getElementById('alert-banner').style.display = 'flex';
}

function dismissAlert() {
    document.getElementById('alert-banner').style.display = 'none';
}

// Show on load for the breach demo
setTimeout(() => {
    showAlert('⚠️ Default Rate breach detected (3.71% > 3.0%). AI investigation in progress. Slack alert dispatched to #fin-guard-alerts.');
}, 800);

// ══════════════════════════════════════════════════════════════════════════════
// DATA REFRESH SIMULATION
// ══════════════════════════════════════════════════════════════════════════════
function refreshData() {
    const btn = document.getElementById('refresh-btn');
    btn.textContent = '⟳ Refreshing…';
    btn.disabled = true;

    setTimeout(() => {
        btn.textContent = '⟳ Refresh';
        btn.disabled = false;
        document.getElementById('last-refresh').textContent = 'Just now';
        addAgentLogEntry('success', 'REFRESH', `Manual data refresh triggered. KPI poll completed. All metrics re-evaluated.`);
    }, 1500);
}

// ══════════════════════════════════════════════════════════════════════════════
// AGENT LOG LIVE UPDATES
// ══════════════════════════════════════════════════════════════════════════════
function addAgentLogEntry(type, badge, message) {
    const log = document.getElementById('agent-log');
    const now = new Date();
    const ts = `${String(now.getUTCHours()).padStart(2, '0')}:${String(now.getUTCMinutes()).padStart(2, '0')} UTC`;

    const badgeClass = { success: 'ok', critical: 'breach', info: 'investigating' }[type] || 'ok';

    const entry = document.createElement('div');
    entry.className = `log-entry ${type} fade-in`;
    entry.innerHTML = `
    <span class="log-ts">${ts}</span>
    <span class="log-badge ${badgeClass}">${badge}</span>
    <span class="log-msg">${message}</span>`;

    log.prepend(entry);

    // Keep only last 20 entries
    while (log.children.length > 20) log.removeChild(log.lastChild);
}

// Simulate live agent polling
setInterval(() => {
    const pollNum = Math.floor(Math.random() * 900) + 48;
    const par30 = (Math.random() * 2 + 2.8).toFixed(2);
    const defRate = (Math.random() * 1.5 + 2.8).toFixed(2);
    const anomalies = Math.floor(Math.random() * 40 + 15);
    addAgentLogEntry('success', '✓ OK',
        `KPI poll #${pollNum} completed. PAR-30: ${par30}% | Default Rate: ${defRate}% | Anomalies: ${anomalies}`);
}, 15000);

// ══════════════════════════════════════════════════════════════════════════════
// CHART VIEW TOGGLES
// ══════════════════════════════════════════════════════════════════════════════
function setChartView(chart, view) {
    if (chart === 'default') {
        defaultRateView = view;
        const d = defaultRateData[view];
        defaultRateChart.data.labels = d.labels;
        defaultRateChart.data.datasets[0].data = d.values;
        if (view === 'quarterly') {
            defaultRateChart.data.datasets[1].data = new Array(d.labels.length).fill(3.0);
        } else {
            defaultRateChart.data.datasets[1].data = new Array(d.labels.length).fill(3.0);
        }
        defaultRateChart.update('active');

        document.querySelectorAll('.chart-btn').forEach(b => {
            if (b.onclick?.toString().includes(`'default','${view}'`)) b.classList.add('active');
            else if (b.onclick?.toString().includes("'default'")) b.classList.remove('active');
        });
    }
}

function setHeatmap(metric) {
    // Future: sort table by selected metric
    const sorted = [...regionData].sort((a, b) => {
        if (metric === 'default') return b.defaultRate - a.defaultRate;
        if (metric === 'par30') return b.par30 - a.par30;
        if (metric === 'anomaly') return b.anomalies - a.anomalies;
        return 0;
    });
    renderRegionTable(sorted);
}

// ══════════════════════════════════════════════════════════════════════════════
// TIMEFRAME & REGION FILTERS
// ══════════════════════════════════════════════════════════════════════════════
function updateTimeframe(days) {
    addAgentLogEntry('info', 'FILTER', `Dashboard timeframe updated to last ${days} days.`);
}

function updateRegion(region) {
    const filtered = region === 'all' ? regionData
        : regionData.filter(r => r.region.toLowerCase() === region);
    renderRegionTable(filtered.length ? filtered : regionData);
    addAgentLogEntry('info', 'FILTER', `Region filter applied: ${region.toUpperCase()}`);
}

// ══════════════════════════════════════════════════════════════════════════════
// INVESTIGATION MODAL
// ══════════════════════════════════════════════════════════════════════════════
function triggerInvestigation() {
    document.getElementById('investigation-modal').classList.add('open');
    document.getElementById('modal-body').innerHTML = `
    <div class="investigating-spinner">
      <div class="spinner"></div>
      <p>🤖 AI agent is executing <code style="color:#9F7AEA">fn_investigate_default_spike()</code>…</p>
    </div>`;

    setTimeout(() => {
        document.getElementById('modal-body').innerHTML = `
      <div class="fade-in">
        <h4 style="color:#90CDF4;margin-bottom:1rem">🔍 Root-Cause Analysis: Default Rate Breach (3.71%)</h4>

        <p style="color:#A0AEC0;margin-bottom:1.5rem">
          <strong style="color:#F7FAFC">AI Investigation completed</strong> at ${new Date().toUTCString()}
        </p>

        <div style="background:rgba(229,62,62,0.08);border:1px solid rgba(229,62,62,0.2);border-radius:10px;padding:1rem;margin-bottom:1.5rem">
          <strong style="color:#FC8181">⚡ Primary Root Cause</strong>
          <p style="margin-top:0.5rem;color:#FEB2B2">
            High-risk SME loans in Texas have driven a <strong>+32% spike in defaults</strong> over the last 30 days.
            These loans were issued at above-average DTI ratios (> 0.6) to borrowers in the construction sector,
            which has seen significant macro-economic stress.
          </p>
        </div>

        <strong style="color:#F7FAFC">📊 Top 3 Impacted Segments</strong>
        <table style="width:100%;margin-top:0.75rem;border-collapse:collapse;font-size:0.82rem">
          <tr style="background:rgba(255,255,255,0.04)">
            <th style="text-align:left;padding:0.5rem;color:#718096">Segment</th>
            <th style="padding:0.5rem;color:#718096;text-align:right">Default Rate</th>
            <th style="padding:0.5rem;color:#718096;text-align:right">Portfolio $M</th>
          </tr>
          <tr><td style="padding:0.5rem;border-bottom:1px solid rgba(255,255,255,0.04)">SME / Texas (Critical)</td>
              <td style="padding:0.5rem;text-align:right;color:#FC8181;font-weight:700;border-bottom:1px solid rgba(255,255,255,0.04)">9.4%</td>
              <td style="padding:0.5rem;text-align:right;border-bottom:1px solid rgba(255,255,255,0.04)">$14.2M</td></tr>
          <tr><td style="padding:0.5rem;border-bottom:1px solid rgba(255,255,255,0.04)">Personal Loan / Illinois (High)</td>
              <td style="padding:0.5rem;text-align:right;color:#F6AD55;font-weight:700;border-bottom:1px solid rgba(255,255,255,0.04)">5.8%</td>
              <td style="padding:0.5rem;text-align:right;border-bottom:1px solid rgba(255,255,255,0.04)">$8.7M</td></tr>
          <tr><td style="padding:0.5rem">Auto Loan / Arizona (High)</td>
              <td style="padding:0.5rem;text-align:right;color:#F6AD55;font-weight:700">4.9%</td>
              <td style="padding:0.5rem;text-align:right">$6.1M</td></tr>
        </table>

        <div style="margin-top:1.5rem">
          <strong style="color:#F7FAFC">✅ Recommended Actions</strong>
          <ol style="margin:0.75rem 0 0 1.2rem;color:#A0AEC0;line-height:1.8">
            <li>Immediately <strong style="color:#68D391">suspend new SME loan disbursements</strong> to the construction sector in Texas pending credit review.</li>
            <li>Initiate <strong style="color:#68D391">early intervention outreach</strong> for 89 loans in PAR-30 bucket with outstanding balance > $50K.</li>
            <li>Escalate <strong style="color:#68D391">restructuring offers</strong> to 34 high-risk personal loans in Illinois with DTI > 0.55.</li>
          </ol>
        </div>

        <div style="margin-top:1.5rem;padding:0.75rem;background:rgba(159,122,234,0.1);border-radius:8px;font-size:0.8rem;color:#D6BCFA">
          🧠 Analysis generated by <strong>GPT-4o</strong> via LangChain agent framework.
          Slack alert dispatched to <strong>#fin-guard-alerts</strong>.
        </div>
      </div>`;
        addAgentLogEntry('critical', '🚨 BREACH', 'Investigation complete. Root cause: SME Texas defaults +32%. Report sent to Slack.');
    }, 2800);
}

function closeModal() {
    document.getElementById('investigation-modal').classList.remove('open');
}

function viewAgentLog() {
    document.getElementById('agent-log').scrollIntoView({ behavior: 'smooth' });
}

// Click outside modal to close
document.getElementById('investigation-modal').addEventListener('click', function (e) {
    if (e.target === this) closeModal();
});

// ── Keyboard shortcut: ESC to close modal ────────────────────────────────────
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') closeModal();
});

// ── Last refresh counter ─────────────────────────────────────────────────────
let secondsSinceRefresh = 0;
setInterval(() => {
    secondsSinceRefresh++;
    const el = document.getElementById('last-refresh');
    if (secondsSinceRefresh < 60) el.textContent = `${secondsSinceRefresh}s ago`;
    else el.textContent = `${Math.floor(secondsSinceRefresh / 60)}m ago`;
}, 1000);

console.log('%c🛡️ Fin-Guard Analytics Dashboard loaded', 'color:#4299E1;font-weight:bold;font-size:14px');
