# 🔍 Environmental Data Quality Framework for Business Risk Mitigation

A data-driven framework designed to quantify environmental data reliability and transform raw station records into structured risk intelligence.

This project operationalizes a **scoring-based reliability model** to assess environmental monitoring stations and mitigate downstream modeling, financial, and operational risks.

---

## 🚩 Problem Context

In climate-sensitive industries (energy, insurance, infrastructure, agriculture), environmental datasets are frequently assumed to be reliable without structured validation.

However, station networks typically suffer from:

* Incomplete temporal records
* Seasonal measurement bias
* Operational outages
* Uneven historical depth
* Silent data degradation

Using low-quality stations in predictive models, risk pricing, or infrastructure planning introduces **model risk, financial mispricing, and operational blind spots**.

This framework converts raw daily environmental observations into a **quantitative risk-based reliability index**.

---

## 🧠 Data Science Architecture

The system implements an end-to-end analytical pipeline:

1. **Data ingestion** (metadata + daily time series)
2. **Automated validation checks**
3. **Feature engineering of data quality indicators**
4. **Temporal aggregation at multiple scales**
5. **Metric standardization**
6. **Weighted risk scoring**
7. **Tier-based segmentation**
8. **Executive-level diagnostics visualization**
9. **BI-ready dataset export**

The core output is the:

### 📊 Station Reliability Score (STRS)

A composite metric derived from five orthogonal quality dimensions:

| Metric                  | Risk Dimension Captured      |
| ----------------------- | ---------------------------- |
| Total Coverage (TC)     | Structural data availability |
| Mean Completeness (MC)  | Operational continuity       |
| Seasonal Depth (SD)     | Calendar representativeness  |
| Seasonal Stability (SS) | Intra-annual consistency     |
| Temporal Depth (TD)     | Historical robustness        |

---

## 📐 Scoring Methodology

The final reliability score is computed as a weighted linear aggregation:

$$
STRS =
w_{TC} \cdot TC +
w_{MC} \cdot MC +
w_{SD} \cdot SD +
w_{SS} \cdot SS +
w_{TD} \cdot TD
$$

Default weights reflect operational risk priorities:

* Structural availability (30%): $$ w_{TC} = 0.30 $$
* Operational continuity (25%): $$ w_{MC} = 0.25 $$
* Seasonal representativeness (15%): $$ w_{SD} = 0.15 $$
* Stability (10%): $$ w_{SS} = 0.10 $$
* Historical robustness (20%): $$ w_{TD} = 0.20 $$

The Temporal Depth component applies an exponential saturation function to prevent overweighting extremely long records while rewarding fully complete years.

This design mirrors risk scoring approaches used in:

* Credit scoring systems
* Asset quality ratings
* Infrastructure risk profiling

---

## 🏷️ Risk Segmentation Framework

Stations are classified into five reliability tiers:

* Very Good
* Good
* Moderate
* Low
* Very Low

This tiering enables:

* Risk-adjusted station selection for modeling
* Data filtering before ML training
* Weighted ensemble modeling strategies
* Portfolio-level monitoring dashboards
* Governance reporting for data quality compliance

---

## 📊 Executive Outputs

The workflow generates:

### 1️⃣ BI-Ready Dataset

`outputs/station_quality_scores.csv`

Each row represents a monitoring station with engineered reliability features.

**Dataset Structure**

| Column                | Description                              |
|-----------------------|------------------------------------------|
| station_id            | Unique station identifier                |
| gauge_name            | Station name                             |
| institution           | Operating institution                    |
| gauge_lat             | Latitude                                 |
| gauge_lon             | Longitude                                |
| gauge_alt             | Elevation (m)                            |
| total_days_calendar   | Full calendar span (days)                |
| total_days_valid      | Valid observed days                      |
| TC                    | Total Coverage score                     |
| MC                    | Mean Monthly Completeness                |
| SD                    | Seasonal Depth                           |
| SS                    | Seasonal Stability                       |
| TD                    | Temporal Depth                           |
| STRS                  | Composite reliability score               |
| reliability           | Tier classification                      |

**Overview:**
```
> scores_export
# A tibble: 124 × 15
   station_id gauge_name                        institution gauge_lat gauge_lon gauge_alt total_days_calendar total_days_valid    TC    MC    SD    SS    TD  STRS reliability
   <chr>      <chr>                             <chr>           <dbl>     <dbl>     <int>               <dbl>            <int> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <ord>      
 1 X00000010  Remehue                           INIA            -40.5     -73.1        74               26298             4053 0.154 0.154     0 0.994 0     0.184 Very Low   
 2 X10360002  Adolfo Matthei                    DGA             -40.6     -73.1        56               26298            13822 0.526 0.526     0 0.991 1     0.588 Moderate   
 3 X00400009  Canal Bajo Osorno Ad.             DMC             -40.6     -73.1        59               26298            25617 0.974 0.974     1 0.987 1     0.984 Very Good  
 4 X10356001  Rio Negro En Chahuilco            DGA             -40.7     -73.2        40               26298             6203 0.236 0.236     0 0.992 0     0.229 Low        
 5 X00000012  Desague_Rupanco                   INIA            -40.8     -72.7       259               26298             2774 0.105 0.105     0 0.993 0     0.157 Very Low   
 6 X10340001  Rio Rahue En Desague Lago Rupanco DGA             -40.8     -72.7       123               26298             4020 0.153 0.153     0 0.989 1.000 0.383 Low        
 7 X00000013  La_Pampa                          INIA            -40.9     -73.2        95               26298             3984 0.151 0.152     0 0.998 1     0.383 Low        
 8 X00000014  Octay                             INIA            -41.0     -72.9       174               26298             3546 0.135 0.135     0 0.994 1.000 0.374 Low        
 9 X00000015  Quilanto                          INIA            -41.0     -73.0       161               26298             3430 0.130 0.130     0 0.993 1     0.371 Low        
10 X00000016  Polizones                         INIA            -41.1     -73.4       182               26298             3546 0.135 0.135     0 0.994 1     0.374 Low        
# ℹ 114 more rows 
```


This structure is designed for:

* Risk-based filtering before modeling
* Dashboard integration (Power BI / Tableau)
* Portfolio-level monitoring
* Governance reporting
* Feature selection pipelines in ML workflows

### 2️⃣ Operational Risk Dashboard

A combined executive visualization including:

* Score distribution histogram
* Reliability segmentation analysis
* Geographic tier mapping

Enabling both technical validation and stakeholder communication.

---

## 🧩 Key Data Science Features

* Parameterized completeness thresholds
* Configurable weighting scheme
* Exponential reward modeling
* Active-station filtering logic
* Robust NA handling
* Fully reproducible R pipeline
* Business-oriented output design

The framework is modular and extensible to other environmental variables (temperature, wind, hydrology) or sensor-based IoT networks.

---

## 🎯 Strategic Applications

This methodology supports:

* Renewable energy resource assessment
* Insurance risk underwriting
* Climate exposure modeling
* Infrastructure resilience planning
* ESG reporting and environmental governance
* Data pipeline risk control before predictive modeling

---

## 👤 Author

**Santino Adduca**  
Data & Risk Modeling | Environmental Analytics | Data Science  

If you would like to discuss this project or explore potential collaboration opportunities, feel free to reach out via email or connect with me on [LinkedIn](https://www.linkedin.com/in/santino-adduca/).
