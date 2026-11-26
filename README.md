# EOFY 2026 Social Campaign Performance Dashboard

A one-page Power BI dashboard analysing a simulated retail EOFY social media campaign, built to show how a marketing analyst can separate what the data shows from what it cannot show.

[DJ_SocialCampaign_Dashboard.pdf](https://github.com/user-attachments/files/35442103/DJ_SocialCampaign_Dashboard.pdf)

## Business question

Which parts of a social campaign (platform, audience, content type, timing) were associated with stronger engagement and conversion, and how confident can we be in those patterns?

## Data

- Simulated retail dataset with 11 tables covering customers, campaigns, ads, daily ad performance, clicks, sessions, orders, order items and returns.
- Scope: EOFY 2026 campaign, 25 May to 14 Jun 2026 (3 weeks). The campaign was scheduled to run to 30 Jun, but the data covers the first three weeks only.
- Attribution chain: ad → click → session → order. Orders without a session (about 250) are excluded from campaign results.
- Validation: row counts matched the source SQL inserts, no orphan foreign keys, and key dashboard figures were reconciled against an independent calculation.

### Database structure

The campaign attribution chain runs ad → click → session → order.

<img width="2000" height="2800" alt="DJ_ERD_style" src="https://github.com/user-attachments/assets/c1702ef1-5ac4-4a64-a4d4-ec7a19650936" />

## SQL

Before building the dashboard, I wrote SQL queries in MySQL to explore the 11-table schema and check that the attribution chain held together. Examples of the questions answered:

- How many orders could be traced back to a campaign click?
- Were there orphan foreign keys between clicks, sessions and orders?
- What were spend, clicks and orders by platform for the campaign window?

## Approach

1. Exported the 11 tables from MySQL, loaded them into Power BI and typed the date fields.
2. Built relationships along the attribution chain and resolved an ambiguous path (customer to order) by keeping only one active path.
3. Wrote DAX measures. Clicks are counted with `DISTINCTCOUNT`, and conversion counts *converting clicks* so repeat orders in one session do not inflate the rate.
4. Designed the page around five questions, with wording limited to what an observational dataset supports.

Key definitions:

| Metric | Definition |
|---|---|
| Conversion rate | Clicks that led to at least one order ÷ clicks |
| Engagement rate | Engagement ÷ summed daily reach |
| CTR | Clicks ÷ impressions |
| Revenue ROAS | Order total (before returns) ÷ ad spend |

## Key findings (all platforms, EOFY 2026)

Headline numbers: spend $27,720, 421 orders, 19.8% conversion, $65.84 cost per order, ROAS 5.6.

- **Engagement did not track conversion.** TikTok had the highest engagement rate (5.5%) but only 8.3% of its clicks led to an order (95% CI 7 to 10%), against 37.7% on Instagram (34 to 42%). The gap held within all six audiences and all three device types.
- **Budget was spread evenly across audiences ($4.1K to $5.1K each), but results were not.** Cost per order ranged from $43 to $121. Retargeting and Rewards audiences converted at 29 to 34% versus 10 to 23% for the others. Audiences were chosen by the advertiser, so this is not a test of which targeting works better.
- **KOL content ranked first** on engagement (5.2%), conversion (22.4%) and cost per order ($53). Its conversion lead over most other types is within sampling uncertainty.
- **Over the three weeks,** engagement rate fell from 5.3% to 2.8% while conversion stayed between 18% and 21%. Impressions grew about 50% and all ads launched in week 1, so week and ad age overlap.

Worth testing next: a larger KOL budget share in a controlled experiment, and the TikTok post-click experience.

## Limitations

- Observational data, not randomised. Findings describe associations, not causes.
- Attribution is only through click, session and order.
- Three weeks of data; the X platform has only 47 clicks, so its figures are unreliable.
- Revenue is before returns (returns were about 4% of revenue; ROAS after returns is about 5.4).
- Spend covers ad spend only; creator fees and production costs are not in the data.
- Synthetic data, so absolute values (for example the very low CTR) should not be compared with industry benchmarks.

## Tools and skills demonstrated

SQL (MySQL), Power Query, data modelling, DAX, Power BI, confidence intervals and two-proportion tests, data validation, analytical writing.

## Repository contents

| Path | What it is |
|---|---|
| `DJ_Marketing_Analysis.pbix` | Power BI report (data model, DAX measures, dashboard) |
| `DJ_SocialCampaign_Dashboard.pdf` | Full dashboard export |
| `01_schema-sql.sql` | Table definitions (11 tables) |
| `02_dummy_data.sql` | Simulated source data |
| `03_business_concern_queries.sql` | Exploration and validation queries |
| `david_jones_analytics_export.sql` | Analytics export used to load Power BI |
| `images/` | Dashboard, ERD and data model screenshots |
| `dax/measures.md` | DAX measures used in the model |

## Disclaimer

Independent portfolio project using simulated data. Not affiliated with or endorsed by any brand named in the dataset.
