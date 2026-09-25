(() => {
  "use strict";
  const data = window.RISK_DATA;
  if (!data) return;
  const { metrics: m, calibration, coefficients, layers, severity_bands: bands } = data;
  const $ = (id) => document.getElementById(id);
  const integer = (n) => Math.round(n).toLocaleString("en-US");
  const amount = (n) => Math.round(n).toLocaleString("en-US");
  const decimal = (n, places = 3) => Number(n).toFixed(places);
  const percent = (n, places = 1) => `${(100 * n).toFixed(places)}%`;
  const set = (id, value) => { $(id).textContent = value; };

  const tail = bands.at(-1);
  set("hero-claim-share", percent(tail.claim_share, 2));
  set("hero-loss-share", percent(tail.loss_share, 1));
  set("tail-count", integer(tail.claims));
  set("all-claims", integer(m.claims));
  $("tiny-fill").style.width = percent(tail.claim_share, 3);
  $("large-fill").style.width = percent(tail.loss_share, 2);
  set("freq-oe", decimal(m.test_freq_oe));
  set("cost-oe", decimal(m.test_cost_oe));
  set("freq-improvement", percent((m.test_poisson_deviance_baseline - m.test_poisson_deviance_model) / m.test_poisson_deviance_baseline, 1));
  set("policy-count", integer(m.policies));
  set("claim-count", integer(m.claims));
  set("exposure-years", integer(m.exposure_years));
  set("split-values", "70 / 15 / 15");
  set("poisson-base", decimal(m.test_poisson_deviance_baseline));
  set("poisson-model", decimal(m.test_poisson_deviance_model));
  set("gamma-base", decimal(m.test_gamma_deviance_baseline));
  set("gamma-model", decimal(m.test_gamma_deviance_model));
  $("poisson-model").classList.add("winner");
  $("gamma-base").classList.add("winner");
  set("train-test-severity", `${amount(m.train_claim_mean_severity)} / ${amount(m.test_claim_mean_severity)}`);
  set("dispersion", decimal(m.train_pearson_dispersion, 2));
  set("bootstrap-interval", `${decimal(m.test_cost_oe_ci_low, 2)}–${decimal(m.test_cost_oe_ci_high, 2)}`);

  const sevChart = $("severity-bars");
  const maxShare = Math.max(...bands.flatMap((b) => [b.claim_share, b.loss_share]));
  for (const band of bands) {
    const row = document.createElement("div"); row.className = "sev-row";
    const label = document.createElement("span"); label.className = "band"; label.textContent = band.band;
    const pair = document.createElement("div"); pair.className = "bar-pair";
    const claims = document.createElement("div"); claims.className = "bar";
    claims.style.width = percent(band.claim_share / maxShare, 2);
    const loss = document.createElement("div"); loss.className = "bar loss";
    loss.style.width = percent(band.loss_share / maxShare, 2);
    pair.append(claims, loss);
    const value = document.createElement("span"); value.className = "bar-value";
    value.textContent = `${percent(band.claim_share, 1)} / ${percent(band.loss_share, 1)}`;
    row.title = `${band.band}: ${integer(band.claims)} claims (${percent(band.claim_share, 1)}) and ${percent(band.loss_share, 1)} of recorded loss`;
    row.append(label, pair, value); sevChart.append(row);
  }

  function drawCalibration(measure) {
    const chart = $("calibration-chart"); chart.replaceChildren();
    const isClaims = measure === "claims";
    const points = calibration.map((c) => ({
      decile: c.decile,
      expected: (isClaims ? c.expected_claims : c.expected_cost) / c.exposure,
      observed: (isClaims ? c.actual_claims : c.actual_cost) / c.exposure,
      exposure: c.exposure
    }));
    const maxValue = Math.max(...points.flatMap((p) => [p.expected, p.observed])) * 1.07;
    points.forEach((p) => {
      const group = document.createElement("div"); group.className = "cal-group";
      const expected = document.createElement("div"); expected.className = "cal-bar expected";
      const observed = document.createElement("div"); observed.className = "cal-bar observed";
      expected.style.height = `${100 * p.expected / maxValue}%`;
      observed.style.height = `${100 * p.observed / maxValue}%`;
      const tick = document.createElement("span"); tick.className = "tick"; tick.textContent = p.decile;
      const unit = isClaims ? "claims" : "amount units";
      group.title = `Risk decile ${p.decile}: expected ${p.expected.toFixed(isClaims ? 3 : 1)} and observed ${p.observed.toFixed(isClaims ? 3 : 1)} ${unit} per exposure-year`;
      group.append(expected, observed, tick); chart.append(group);
    });
    chart.setAttribute("aria-label", `Expected and observed ${isClaims ? "claim counts" : "total loss"} per exposure-year across ten predicted-risk groups`);
  }
  document.querySelectorAll("[data-measure]").forEach((button) => button.addEventListener("click", () => {
    document.querySelectorAll("[data-measure]").forEach((b) => {
      const selected = b === button; b.classList.toggle("selected", selected);
      b.setAttribute("aria-pressed", String(selected));
    });
    drawCalibration(button.dataset.measure);
  }));
  drawCalibration("claims");

  const regions = ["Aquitaine", "Basse-Normandie", "Bretagne", "Centre", "Haute-Normandie", "Ile-de-France", "Limousin", "Nord-Pas-de-Calais", "Pays-de-la-Loire", "Poitou-Charentes"];
  for (const name of regions) {
    const option = document.createElement("option"); option.textContent = name; option.value = name;
    if (name === "Ile-de-France") option.selected = true;
    $("region-select").append(option);
  }
  function updateRisk() {
    const form = $("risk-form");
    const values = Object.fromEntries(new FormData(form));
    const beta = coefficients.frequency;
    const density = Math.max(0, Math.min(30000, Number(values.density) || 0));
    let logRate = beta["(Intercept)"];
    for (const [prefix, value] of [["DriverBand", values.driver], ["CarBand", values.car], ["PowerBand", values.power], ["Gas", values.gas], ["Region", values.region]]) {
      logRate += beta[prefix + value] || 0;
    }
    logRate += beta.LogDensity * Math.log1p(density);
    const rate = Math.exp(logRate);
    const severity = m.train_mean_severity;
    const expectedCost = rate * severity;
    const portfolioCost = m.train_frequency_rate * severity;
    set("annual-cost", amount(expectedCost));
    set("annual-frequency", decimal(rate, 3) + " / year");
    set("selected-severity", amount(severity) + " units");
    set("relative-risk", decimal(expectedCost / portfolioCost, 2) + "× average");
  }
  $("risk-form").addEventListener("input", updateRisk);
  $("risk-form").addEventListener("change", updateRisk);
  updateRisk();

  function updateLayer() {
    const attachment = Number($("attachment").value), limit = Number($("limit").value);
    const row = layers.find((item) => item.attachment === attachment && item.limit === limit);
    if (!row) return;
    set("above-attachment", integer(row.claim_count_above_attachment));
    set("ceded-exposure", decimal(row.ceded_per_exposure, 1));
    set("ceded-share", percent(row.loss_share_ceded, 1));
  }
  $("attachment").addEventListener("change", updateLayer);
  $("limit").addEventListener("change", updateLayer);
  updateLayer();
})();
