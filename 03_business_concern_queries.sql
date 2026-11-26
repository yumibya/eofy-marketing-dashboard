-- ============================================================
-- Part B: Business concern queries (EOFY 2026 campaign, in flight)
--
-- Every query below is a stand-alone SELECT statement.
-- To run one: highlight it in MySQL Workbench and press
-- Ctrl+Enter (Cmd+Enter on Mac). The result grid appears at once.
--
-- Campaign_ID 6 = EOFY 2026 Sale (the live campaign).
-- Snapshot date for "so far" figures = 15 June 2026.
-- Every query is limited to the EOFY 2026 campaign, either through
-- Campaign_ID = 6 (advertising data) or through the campaign's order
-- window, 25 May to 15 June 2026 (sales data). The only exceptions are
-- Query 5E, which reads each member's current annual spend, and Query 7,
-- whose purpose is to compare EOFY 2026 with earlier campaigns.
--
-- Four calculation rules used throughout:
-- 1) AD_PERFORMANCE holds one row per ad per day, and CLICK holds
--    one row per click. Joining both to AD in one step would repeat
--    each daily row once per click and inflate impressions and spend.
--    Where both are needed, each side is summarised first in a small
--    GROUP BY inside the FROM clause, then joined.
-- 2) A customer may return part of an order line, possibly in more
--    than one instalment. Returns are therefore summed per order line
--    first (derived table r), then joined to ORDER_ITEM.
-- 3) Discount_Applied is recorded once per order. Derived table d turns
--    it into each order's discount share, so that every line's revenue
--    is the price the customer actually paid:
--    Unit_Price_At_Sale * (1 - Discount_Share).
--    Net revenue = units kept (sold minus returned) x price paid.
--    Gross profit = net revenue - units kept x Cost_Price.
-- 4) Return on ad spend (ROAS) sets attributed results against media
--    spend (the sum of AD_PERFORMANCE.Spend):
--    Revenue ROAS = attributed net revenue / spend
--    Profit ROAS  = attributed gross profit / spend (break-even = 1.00)
-- ============================================================
USE david_jones_analytics;


-- ============================================================
-- HOW REVENUE IS MEASURED
-- ============================================================

-- Query 0: How revenue is measured - EOFY 2026 revenue waterfall
-- Scope: orders attributed to EOFY 2026 advertising (click -> session -> order).
SELECT s.Gross_Sales, s.Order_Discounts, s.Returns_Value, s.Net_Revenue,
       s.Cost_Of_Goods, s.Gross_Profit, m.Media_Spend,
       ROUND(s.Gross_Profit - m.Media_Spend, 2) AS Profit_After_Media
FROM (SELECT a.Campaign_ID,
             ROUND(SUM(oi.Quantity * oi.Unit_Price_At_Sale), 2) AS Gross_Sales,
             ROUND(SUM(oi.Quantity * oi.Unit_Price_At_Sale * d.Discount_Share), 2)
                 AS Order_Discounts,
             ROUND(SUM(COALESCE(r.Qty_Returned, 0)
                   * oi.Unit_Price_At_Sale * (1 - d.Discount_Share)), 2)
                 AS Returns_Value,
             ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                   * oi.Unit_Price_At_Sale * (1 - d.Discount_Share)), 2)
                 AS Net_Revenue,
             ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                   * p.Cost_Price), 2) AS Cost_Of_Goods,
             ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                       * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share)
                             - p.Cost_Price)), 2) AS Gross_Profit
      FROM AD a
      JOIN CLICK c       ON c.Ad_ID = a.Ad_ID
      JOIN `SESSION` s   ON s.Click_ID = c.Click_ID
      JOIN `ORDER` o     ON o.Session_ID = s.Session_ID
      JOIN ORDER_ITEM oi ON oi.Order_ID = o.Order_ID
      JOIN PRODUCT p     ON p.SKU = oi.SKU
      JOIN (SELECT Order_ID,
                   Discount_Applied / (Order_Total + Discount_Applied) AS Discount_Share
            FROM `ORDER`) d ON d.Order_ID = oi.Order_ID
      LEFT JOIN (SELECT Order_ID, SKU, SUM(Quantity_Returned) AS Qty_Returned
                 FROM `RETURN`
                 GROUP BY Order_ID, SKU) r
             ON r.Order_ID = oi.Order_ID AND r.SKU = oi.SKU
      WHERE a.Campaign_ID = 6
      GROUP BY a.Campaign_ID) s
JOIN (SELECT a.Campaign_ID, ROUND(SUM(ap.Spend), 2) AS Media_Spend
      FROM AD a
      JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
      WHERE a.Campaign_ID = 6
      GROUP BY a.Campaign_ID) m
  ON m.Campaign_ID = s.Campaign_ID;


-- ============================================================
-- CONCERN 1: AWARENESS & ENGAGEMENT
-- ============================================================

-- Query 1A: Platform reach and cost efficiency, EOFY 2026
SELECT a.Platform_Name,
       COUNT(DISTINCT a.Ad_ID) AS Num_Ads,
       SUM(ap.Impressions)     AS Total_Impressions,
       SUM(ap.Reach)           AS Total_Reach,
       SUM(ap.Engagement)      AS Total_Engagement,
       ROUND(SUM(ap.Spend), 2) AS Total_Spend,
       ROUND(SUM(ap.Spend) / SUM(ap.Impressions) * 1000, 2) AS CPM,
       ROUND(SUM(ap.Spend) / SUM(ap.Engagement), 2)         AS CPE,
       ROUND(SUM(ap.Engagement) / SUM(ap.Reach) * 100, 2)   AS Engagement_Rate_Percent
FROM AD a
JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Platform_Name
ORDER BY Total_Reach DESC;

-- Query 1B: Best-performing content type and format on each platform
-- (EOFY 2026). Each bracketed block ranks every content type
-- and format combination on one platform by engagement rate and keeps
-- the top one (LIMIT 1 is MySQL's equivalent of TOP 1). UNION ALL then
-- stacks the four platform winners into one table.
(SELECT a.Platform_Name, a.Content_Type, a.Ad_Format,
        COUNT(DISTINCT a.Ad_ID) AS Num_Ads,
        SUM(ap.Reach)           AS Total_Reach,
        SUM(ap.Engagement)      AS Total_Engagement,
        ROUND(SUM(ap.Engagement) / SUM(ap.Reach) * 100, 2) AS Engagement_Rate_Percent,
        ROUND(SUM(ap.Spend) / SUM(ap.Engagement), 2)       AS CPE
 FROM AD a
 JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
 WHERE a.Campaign_ID = 6 AND a.Platform_Name = 'TikTok'
 GROUP BY a.Platform_Name, a.Content_Type, a.Ad_Format
 ORDER BY Engagement_Rate_Percent DESC
 LIMIT 1)
UNION ALL
(SELECT a.Platform_Name, a.Content_Type, a.Ad_Format,
        COUNT(DISTINCT a.Ad_ID), SUM(ap.Reach), SUM(ap.Engagement),
        ROUND(SUM(ap.Engagement) / SUM(ap.Reach) * 100, 2) AS Engagement_Rate_Percent,
        ROUND(SUM(ap.Spend) / SUM(ap.Engagement), 2)
 FROM AD a
 JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
 WHERE a.Campaign_ID = 6 AND a.Platform_Name = 'Instagram'
 GROUP BY a.Platform_Name, a.Content_Type, a.Ad_Format
 ORDER BY Engagement_Rate_Percent DESC
 LIMIT 1)
UNION ALL
(SELECT a.Platform_Name, a.Content_Type, a.Ad_Format,
        COUNT(DISTINCT a.Ad_ID), SUM(ap.Reach), SUM(ap.Engagement),
        ROUND(SUM(ap.Engagement) / SUM(ap.Reach) * 100, 2) AS Engagement_Rate_Percent,
        ROUND(SUM(ap.Spend) / SUM(ap.Engagement), 2)
 FROM AD a
 JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
 WHERE a.Campaign_ID = 6 AND a.Platform_Name = 'Facebook'
 GROUP BY a.Platform_Name, a.Content_Type, a.Ad_Format
 ORDER BY Engagement_Rate_Percent DESC
 LIMIT 1)
UNION ALL
(SELECT a.Platform_Name, a.Content_Type, a.Ad_Format,
        COUNT(DISTINCT a.Ad_ID), SUM(ap.Reach), SUM(ap.Engagement),
        ROUND(SUM(ap.Engagement) / SUM(ap.Reach) * 100, 2) AS Engagement_Rate_Percent,
        ROUND(SUM(ap.Spend) / SUM(ap.Engagement), 2)
 FROM AD a
 JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
 WHERE a.Campaign_ID = 6 AND a.Platform_Name = 'X'
 GROUP BY a.Platform_Name, a.Content_Type, a.Ad_Format
 ORDER BY Engagement_Rate_Percent DESC
 LIMIT 1)
ORDER BY Engagement_Rate_Percent DESC;


-- ============================================================
-- CONCERN 2: CONSIDERATION - CTR, bounce, and the landing page
-- ============================================================

-- Query 2A: Click-through rate by platform, EOFY 2026
-- Impressions and clicks are each summed per ad first, then joined, so
-- that one ad's daily rows are not repeated once per click.
SELECT a.Platform_Name,
       SUM(d.Impressions) AS Total_Impressions,
       SUM(c.Clicks)      AS Total_Clicks,
       ROUND(SUM(c.Clicks) / SUM(d.Impressions) * 100, 3) AS CTR_Percent
FROM AD a
JOIN (SELECT Ad_ID, SUM(Impressions) AS Impressions
      FROM AD_PERFORMANCE
      GROUP BY Ad_ID) d ON d.Ad_ID = a.Ad_ID
LEFT JOIN (SELECT Ad_ID, COUNT(*) AS Clicks
           FROM CLICK
           GROUP BY Ad_ID) c ON c.Ad_ID = a.Ad_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Platform_Name
ORDER BY CTR_Percent DESC;

-- Query 2B: Bounce rate by platform, EOFY 2026
SELECT a.Platform_Name,
       COUNT(s.Session_ID) AS Total_Sessions,
       SUM(s.Bounced)      AS Bounced_Sessions,
       ROUND(SUM(s.Bounced) / COUNT(s.Session_ID) * 100, 2) AS Bounce_Rate_Percent,
       ROUND(AVG(s.Pages_Viewed), 2) AS Avg_Pages_Viewed,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, s.Session_Start, s.Session_End)), 1)
           AS Avg_Session_Minutes
FROM AD a
JOIN CLICK c     ON c.Ad_ID = a.Ad_ID
JOIN `SESSION` s ON s.Click_ID = c.Click_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Platform_Name
ORDER BY Bounce_Rate_Percent ASC;

-- Query 2C: Does sending paid traffic to the generic homepage, rather
-- than to the offer the ad promised, explain bounce?
SELECT a.Landing_Page_URL,
       COUNT(s.Session_ID) AS Sessions,
       ROUND(SUM(s.Bounced) / COUNT(s.Session_ID) * 100, 2) AS Bounce_Rate_Percent,
       ROUND(AVG(s.Pages_Viewed), 2) AS Avg_Pages_Viewed
FROM AD a
JOIN CLICK c     ON c.Ad_ID = a.Ad_ID
JOIN `SESSION` s ON s.Click_ID = c.Click_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Landing_Page_URL
ORDER BY Bounce_Rate_Percent ASC;


-- ============================================================
-- CONCERN 3: CONVERSION - platform, content type, audience
-- ============================================================

-- Query 3A: Conversion rate by platform, EOFY 2026
SELECT a.Platform_Name,
       COUNT(c.Click_ID)  AS Total_Clicks,
       SUM(1 - s.Bounced) AS Engaged_Sessions,
       COUNT(o.Order_ID)  AS Orders,
       ROUND(COUNT(o.Order_ID) / COUNT(c.Click_ID) * 100, 2) AS Conversion_Rate_Percent
FROM AD a
JOIN CLICK c        ON c.Ad_ID = a.Ad_ID
JOIN `SESSION` s    ON s.Click_ID = c.Click_ID
LEFT JOIN `ORDER` o ON o.Session_ID = s.Session_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Platform_Name
ORDER BY Conversion_Rate_Percent DESC;

-- Query 3B: Conversion rate by content type
SELECT a.Content_Type,
       COUNT(c.Click_ID) AS Total_Clicks,
       COUNT(o.Order_ID) AS Orders,
       ROUND(COUNT(o.Order_ID) / COUNT(c.Click_ID) * 100, 2) AS Conversion_Rate_Percent
FROM AD a
JOIN CLICK c        ON c.Ad_ID = a.Ad_ID
JOIN `SESSION` s    ON s.Click_ID = c.Click_ID
LEFT JOIN `ORDER` o ON o.Session_ID = s.Session_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Content_Type
ORDER BY Conversion_Rate_Percent DESC;

-- Query 3C: Conversion rate and order value by target audience
SELECT a.Target_Audience,
       COUNT(c.Click_ID) AS Total_Clicks,
       COUNT(o.Order_ID) AS Orders,
       ROUND(COUNT(o.Order_ID) / COUNT(c.Click_ID) * 100, 2) AS Conversion_Rate_Percent,
       ROUND(AVG(o.Order_Total), 2) AS Avg_Order_Value
FROM AD a
JOIN CLICK c        ON c.Ad_ID = a.Ad_ID
JOIN `SESSION` s    ON s.Click_ID = c.Click_ID
LEFT JOIN `ORDER` o ON o.Session_ID = s.Session_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Target_Audience
ORDER BY Conversion_Rate_Percent DESC;


-- ============================================================
-- CONCERN 4: CATEGORY CONTRIBUTION - revenue, returns, profit
-- ============================================================

-- Query 4A: Revenue, returns and gross profit by category (EOFY 2026 window)
SELECT p.Category_Name,
       COUNT(DISTINCT oi.Order_ID) AS Orders_Containing_Category,
       SUM(oi.Quantity)            AS Units_Sold,
       SUM(COALESCE(r.Qty_Returned, 0)) AS Units_Returned,
       ROUND(SUM(oi.Quantity * oi.Unit_Price_At_Sale), 2) AS Gross_Revenue,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0)) * oi.Unit_Price_At_Sale
             * (1 - d.Discount_Share)), 2)
           AS Net_Revenue,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                 * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share)
                       - p.Cost_Price)), 2) AS Gross_Profit,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                 * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share) - p.Cost_Price))
             / SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                   * oi.Unit_Price_At_Sale * (1 - d.Discount_Share)) * 100, 1)
           AS Gross_Margin_Percent
FROM ORDER_ITEM oi
JOIN PRODUCT p ON p.SKU = oi.SKU
JOIN `ORDER` o ON o.Order_ID = oi.Order_ID
JOIN (SELECT Order_ID,
             Discount_Applied / (Order_Total + Discount_Applied) AS Discount_Share
      FROM `ORDER`) d ON d.Order_ID = oi.Order_ID
LEFT JOIN (SELECT Order_ID, SKU, SUM(Quantity_Returned) AS Qty_Returned
           FROM `RETURN`
           GROUP BY Order_ID, SKU) r
       ON r.Order_ID = oi.Order_ID AND r.SKU = oi.SKU
WHERE o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
GROUP BY p.Category_Name
ORDER BY Gross_Profit DESC;

-- Query 4B: The two most common return reasons in each category
-- (orders placed during EOFY 2026). Same technique as Query 1B: rank within one
-- category, keep the top two, then stack the five categories with UNION ALL.
-- Return_Reason breaks ties, so that equal counts always appear in the same order.
(SELECT p.Category_Name, r.Return_Reason,
        SUM(r.Quantity_Returned) AS Units_Returned
 FROM `RETURN` r
 JOIN PRODUCT p ON p.SKU = r.SKU
 JOIN `ORDER` o ON o.Order_ID = r.Order_ID
 WHERE p.Category_Name = 'Appliances'
   AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
 GROUP BY p.Category_Name, r.Return_Reason
 ORDER BY SUM(r.Quantity_Returned) DESC, r.Return_Reason
 LIMIT 2)
UNION ALL
(SELECT p.Category_Name, r.Return_Reason, SUM(r.Quantity_Returned)
 FROM `RETURN` r
 JOIN PRODUCT p ON p.SKU = r.SKU
 JOIN `ORDER` o ON o.Order_ID = r.Order_ID
 WHERE p.Category_Name = 'Beauty'
   AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
 GROUP BY p.Category_Name, r.Return_Reason
 ORDER BY SUM(r.Quantity_Returned) DESC, r.Return_Reason
 LIMIT 2)
UNION ALL
(SELECT p.Category_Name, r.Return_Reason, SUM(r.Quantity_Returned)
 FROM `RETURN` r
 JOIN PRODUCT p ON p.SKU = r.SKU
 JOIN `ORDER` o ON o.Order_ID = r.Order_ID
 WHERE p.Category_Name = 'Homewares'
   AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
 GROUP BY p.Category_Name, r.Return_Reason
 ORDER BY SUM(r.Quantity_Returned) DESC, r.Return_Reason
 LIMIT 2)
UNION ALL
(SELECT p.Category_Name, r.Return_Reason, SUM(r.Quantity_Returned)
 FROM `RETURN` r
 JOIN PRODUCT p ON p.SKU = r.SKU
 JOIN `ORDER` o ON o.Order_ID = r.Order_ID
 WHERE p.Category_Name = 'Menswear'
   AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
 GROUP BY p.Category_Name, r.Return_Reason
 ORDER BY SUM(r.Quantity_Returned) DESC, r.Return_Reason
 LIMIT 2)
UNION ALL
(SELECT p.Category_Name, r.Return_Reason, SUM(r.Quantity_Returned)
 FROM `RETURN` r
 JOIN PRODUCT p ON p.SKU = r.SKU
 JOIN `ORDER` o ON o.Order_ID = r.Order_ID
 WHERE p.Category_Name = 'Womenswear'
   AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
 GROUP BY p.Category_Name, r.Return_Reason
 ORDER BY SUM(r.Quantity_Returned) DESC, r.Return_Reason
 LIMIT 2)
ORDER BY Category_Name, Units_Returned DESC, Return_Reason;


-- ============================================================
-- CONCERN 5: LOYALTY
-- ============================================================

-- Query 5A: Members against non-members
SELECT 'Member' AS Segment,
       COUNT(DISTINCT c.Customer_ID) AS Num_Customers,
       COUNT(o.Order_ID)             AS Total_Orders,
       ROUND(COUNT(o.Order_ID) / COUNT(DISTINCT c.Customer_ID), 2)
             AS Orders_Per_Customer,
       ROUND(AVG(o.Order_Total), 2)  AS Avg_Order_Value
FROM CUSTOMER c
JOIN MEMBERSHIP m   ON m.Customer_ID = c.Customer_ID
LEFT JOIN `ORDER` o ON o.Customer_ID = c.Customer_ID
                    AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
UNION
SELECT 'Non-Member',
       COUNT(DISTINCT c.Customer_ID), COUNT(o.Order_ID),
       ROUND(COUNT(o.Order_ID) / COUNT(DISTINCT c.Customer_ID), 2),
       ROUND(AVG(o.Order_Total), 2)
FROM CUSTOMER c
LEFT JOIN MEMBERSHIP m ON m.Customer_ID = c.Customer_ID
LEFT JOIN `ORDER` o    ON o.Customer_ID = c.Customer_ID
                       AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
WHERE m.Customer_ID IS NULL;

-- Query 5B: Value of each membership tier
SELECT m.Tier,
       COUNT(DISTINCT m.Customer_ID) AS Num_Members,
       COUNT(o.Order_ID)             AS Total_Orders,
       ROUND(COUNT(o.Order_ID) / COUNT(DISTINCT m.Customer_ID), 2) AS Orders_Per_Member,
       ROUND(AVG(o.Order_Total), 2)  AS Avg_Order_Value,
       ROUND(SUM(o.Order_Total) / COUNT(DISTINCT m.Customer_ID), 2)
             AS Revenue_Per_Member
FROM MEMBERSHIP m
LEFT JOIN `ORDER` o ON o.Customer_ID = m.Customer_ID
                    AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
GROUP BY m.Tier
ORDER BY Revenue_Per_Member DESC;

-- Query 5C: Rewards points against Qantas points members
SELECT m.Points_Preference,
       COUNT(DISTINCT m.Customer_ID) AS Num_Members,
       ROUND(AVG(m.Annual_Spend), 2) AS Avg_Annual_Spend,
       COUNT(o.Order_ID)             AS Total_Orders,
       ROUND(COUNT(o.Order_ID) / COUNT(DISTINCT m.Customer_ID), 2) AS Orders_Per_Member,
       ROUND(AVG(o.Order_Total), 2)  AS Avg_Order_Value
FROM MEMBERSHIP m
LEFT JOIN `ORDER` o ON o.Customer_ID = m.Customer_ID
                    AND o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
GROUP BY m.Points_Preference;

-- Query 5D: What does each points group buy, and how profitable is it?
SELECT m.Points_Preference, p.Category_Name,
       SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))) AS Net_Units,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0)) * oi.Unit_Price_At_Sale
             * (1 - d.Discount_Share)), 2)
           AS Net_Revenue,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                 * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share)
                       - p.Cost_Price)), 2) AS Gross_Profit
FROM MEMBERSHIP m
JOIN `ORDER` o      ON o.Customer_ID = m.Customer_ID
JOIN ORDER_ITEM oi  ON oi.Order_ID = o.Order_ID
JOIN PRODUCT p      ON p.SKU = oi.SKU
JOIN (SELECT Order_ID,
             Discount_Applied / (Order_Total + Discount_Applied) AS Discount_Share
      FROM `ORDER`) d ON d.Order_ID = oi.Order_ID
LEFT JOIN (SELECT Order_ID, SKU, SUM(Quantity_Returned) AS Qty_Returned
           FROM `RETURN`
           GROUP BY Order_ID, SKU) r
       ON r.Order_ID = oi.Order_ID AND r.SKU = oi.SKU
WHERE o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
GROUP BY m.Points_Preference, p.Category_Name
ORDER BY m.Points_Preference, Gross_Profit DESC;

-- Query 5E: Members close to the next tier (within 20% of the threshold).
-- David Jones Rewards tiers are set by annual spend: Silver from $2,000 and
-- Gold from $5,000. "Within 20%" therefore means Bronze members on $1,600 or
-- more and Silver members on $4,000 or more.
SELECT 'Bronze' AS Tier,
       COUNT(*) AS Members_Near_Next_Tier,
       ROUND(AVG(Annual_Spend), 2) AS Avg_Current_Spend,
       'Silver' AS Next_Tier,
       2000 AS Next_Tier_Threshold
FROM MEMBERSHIP
WHERE Tier = 'Bronze' AND Annual_Spend >= 1600
UNION
SELECT 'Silver', COUNT(*), ROUND(AVG(Annual_Spend), 2), 'Gold', 5000
FROM MEMBERSHIP
WHERE Tier = 'Silver' AND Annual_Spend >= 4000;


-- ============================================================
-- CONCERN 6: MARKDOWN DEPTH AGAINST MARGIN EARNED
-- ============================================================

-- Query 6: Discount given away against margin kept, by category.
-- Markdown given away = value of the units kept at full RRP minus the
-- net revenue actually received (sale-price markdown plus order discounts).
SELECT p.Category_Name,
       SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))) AS Net_Units_Sold,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0)) * p.RRP), 2)
             AS Revenue_At_Full_RRP,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0)) * oi.Unit_Price_At_Sale
             * (1 - d.Discount_Share)), 2)
           AS Net_Revenue,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0)) * (p.RRP
             - oi.Unit_Price_At_Sale * (1 - d.Discount_Share))), 2)
           AS Markdown_Given_Away,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0)) * (p.RRP
             - oi.Unit_Price_At_Sale * (1 - d.Discount_Share)))
             / SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0)) * p.RRP) * 100, 2)
           AS Markdown_Depth_Percent,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                 * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share)
                       - p.Cost_Price)), 2) AS Gross_Profit,
       ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                 * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share) - p.Cost_Price))
             / SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                   * oi.Unit_Price_At_Sale * (1 - d.Discount_Share)) * 100, 1)
           AS Gross_Margin_Percent
FROM ORDER_ITEM oi
JOIN PRODUCT p ON p.SKU = oi.SKU
JOIN `ORDER` o ON o.Order_ID = oi.Order_ID
JOIN (SELECT Order_ID,
             Discount_Applied / (Order_Total + Discount_Applied) AS Discount_Share
      FROM `ORDER`) d ON d.Order_ID = oi.Order_ID
LEFT JOIN (SELECT Order_ID, SKU, SUM(Quantity_Returned) AS Qty_Returned
           FROM `RETURN`
           GROUP BY Order_ID, SKU) r
       ON r.Order_ID = oi.Order_ID AND r.SKU = oi.SKU
WHERE o.Order_Date BETWEEN '2026-05-25' AND '2026-06-15 23:59:59'
GROUP BY p.Category_Name
ORDER BY Markdown_Depth_Percent DESC;


-- ============================================================
-- CONCERN 7: CAMPAIGN RETURN ON REVENUE AND ON PROFIT
-- sp  = advertising spend per campaign
-- rev = attributed net revenue and gross profit per campaign
-- ============================================================

-- Query 7: Revenue ROAS and Profit ROAS, all campaigns
-- Revenue_ROAS = attributed net revenue / spend
-- Profit_ROAS  = attributed gross profit / spend (break-even = 1.00)
SELECT cam.Campaign_Name, cam.Campaign_Type, cam.Total_Budget,
       sp.Total_Spend, rev.Attributed_Orders,
       rev.Attributed_Net_Revenue, rev.Attributed_Gross_Profit,
       ROUND(rev.Attributed_Net_Revenue / sp.Total_Spend, 2)  AS Revenue_ROAS,
       ROUND(rev.Attributed_Gross_Profit / sp.Total_Spend, 2) AS Profit_ROAS
FROM CAMPAIGN cam
JOIN (SELECT a.Campaign_ID, ROUND(SUM(ap.Spend), 2) AS Total_Spend
      FROM AD a
      JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
      GROUP BY a.Campaign_ID) sp
  ON sp.Campaign_ID = cam.Campaign_ID
JOIN (SELECT a.Campaign_ID,
             COUNT(DISTINCT o.Order_ID) AS Attributed_Orders,
             ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                   * oi.Unit_Price_At_Sale * (1 - d.Discount_Share)), 2)
                 AS Attributed_Net_Revenue,
             ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                       * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share)
                             - p.Cost_Price)), 2)
                 AS Attributed_Gross_Profit
      FROM AD a
      JOIN CLICK c       ON c.Ad_ID = a.Ad_ID
      JOIN `SESSION` s   ON s.Click_ID = c.Click_ID
      JOIN `ORDER` o     ON o.Session_ID = s.Session_ID
      JOIN ORDER_ITEM oi ON oi.Order_ID = o.Order_ID
      JOIN PRODUCT p     ON p.SKU = oi.SKU
      JOIN (SELECT Order_ID,
                   Discount_Applied / (Order_Total + Discount_Applied) AS Discount_Share
            FROM `ORDER`) d ON d.Order_ID = oi.Order_ID
      LEFT JOIN (SELECT Order_ID, SKU, SUM(Quantity_Returned) AS Qty_Returned
                 FROM `RETURN`
                 GROUP BY Order_ID, SKU) r
             ON r.Order_ID = oi.Order_ID AND r.SKU = oi.SKU
      GROUP BY a.Campaign_ID) rev
  ON rev.Campaign_ID = cam.Campaign_ID
ORDER BY cam.Start_Date;


-- ============================================================
-- CONCERN 8: IN-FLIGHT MANAGEMENT of the live EOFY 2026 campaign.
-- Only possible because delivery is recorded per ad per day.
-- Each week is read at every stage of the funnel: engagement rate
-- (attention), CTR (clicks / impressions), conversion rate (orders /
-- clicks) and cost per order, so that a fall in engagement is not
-- mistaken for a fall in sales.
-- ============================================================

-- Query 8A: Week-by-week funnel, whole campaign
-- Campaign_Week is the week number of the year (weeks start on Monday).
-- Delivery (AD_PERFORMANCE, one row per ad per day) and clicks/orders
-- (CLICK, one row per click) are each summed per week in their own
-- derived table, then joined on the week, so daily rows are not
-- repeated once per click. Clicks are placed in the week they were made,
-- and each order is counted in the week of the click that led to it.
SELECT d.Campaign_Week,
       d.Week_Starting,
       d.Impressions,
       d.Engagement,
       d.Spend,
       ROUND(d.Engagement / d.Reach * 100, 2)      AS Engagement_Rate_Percent,
       c.Clicks,
       ROUND(c.Clicks / d.Impressions * 100, 3)    AS CTR_Percent,
       c.Orders,
       ROUND(c.Orders / c.Clicks * 100, 2)         AS Conversion_Rate_Percent,
       ROUND(d.Spend / d.Engagement, 2)            AS CPE,
       ROUND(d.Spend / c.Orders, 2)                AS Cost_Per_Order
FROM (SELECT WEEK(ap.Performance_Date, 1) AS Campaign_Week,
             MIN(ap.Performance_Date)     AS Week_Starting,
             SUM(ap.Impressions)          AS Impressions,
             SUM(ap.Reach)                AS Reach,
             SUM(ap.Engagement)           AS Engagement,
             ROUND(SUM(ap.Spend), 2)      AS Spend
      FROM AD a
      JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
      WHERE a.Campaign_ID = 6
      GROUP BY WEEK(ap.Performance_Date, 1)) d
JOIN (SELECT WEEK(c.Click_Datetime, 1) AS Campaign_Week,
             COUNT(c.Click_ID)         AS Clicks,
             COUNT(o.Order_ID)         AS Orders
      FROM AD a
      JOIN CLICK c        ON c.Ad_ID = a.Ad_ID
      JOIN `SESSION` s    ON s.Click_ID = c.Click_ID
      LEFT JOIN `ORDER` o ON o.Session_ID = s.Session_ID
      WHERE a.Campaign_ID = 6
      GROUP BY WEEK(c.Click_Datetime, 1)) c
  ON c.Campaign_Week = d.Campaign_Week
ORDER BY d.Campaign_Week;

-- Query 8B: Week-by-week funnel for each platform
-- Campaign_Week: 22 = week of 25 May, 23 = week of 1 June, 24 = week of 8 June 2026.
-- Same construction as 8A, grouped by platform as well as week.
-- Clicks and Orders are shown beside the rates so that the size of each
-- sample is visible (X records only a handful of orders each week).
SELECT d.Platform_Name,
       d.Campaign_Week,
       d.Spend,
       ROUND(d.Engagement / d.Reach * 100, 2)      AS Engagement_Rate_Percent,
       c.Clicks,
       ROUND(c.Clicks / d.Impressions * 100, 3)    AS CTR_Percent,
       c.Orders,
       ROUND(c.Orders / c.Clicks * 100, 2)         AS Conversion_Rate_Percent,
       ROUND(d.Spend / d.Engagement, 2)            AS CPE,
       ROUND(d.Spend / c.Orders, 2)                AS Cost_Per_Order
FROM (SELECT a.Platform_Name,
             WEEK(ap.Performance_Date, 1) AS Campaign_Week,
             SUM(ap.Impressions)          AS Impressions,
             SUM(ap.Reach)                AS Reach,
             SUM(ap.Engagement)           AS Engagement,
             ROUND(SUM(ap.Spend), 2)      AS Spend
      FROM AD a
      JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
      WHERE a.Campaign_ID = 6
      GROUP BY a.Platform_Name, WEEK(ap.Performance_Date, 1)) d
JOIN (SELECT a.Platform_Name,
             WEEK(c.Click_Datetime, 1) AS Campaign_Week,
             COUNT(c.Click_ID)         AS Clicks,
             COUNT(o.Order_ID)         AS Orders
      FROM AD a
      JOIN CLICK c        ON c.Ad_ID = a.Ad_ID
      JOIN `SESSION` s    ON s.Click_ID = c.Click_ID
      LEFT JOIN `ORDER` o ON o.Session_ID = s.Session_ID
      WHERE a.Campaign_ID = 6
      GROUP BY a.Platform_Name, WEEK(c.Click_Datetime, 1)) c
  ON c.Platform_Name = d.Platform_Name
 AND c.Campaign_Week = d.Campaign_Week
ORDER BY d.Platform_Name, d.Campaign_Week;


-- ============================================================
-- CONCERN 9: PLATFORM PROFITABILITY - where should the remaining
-- EOFY 2026 budget go?
-- ============================================================

-- Query 9A: The full path from impression to purchase, by platform.
-- Social_Media_CTR_Percent follows the case study's own definition of
-- CTR: the share of people shown an advertisement who click it and then
-- complete a purchase (orders / impressions).
SELECT a.Platform_Name,
       SUM(d.Impressions) AS Impressions,
       SUM(c.Clicks)      AS Clicks,
       SUM(c.Orders)      AS Orders,
       ROUND(SUM(c.Clicks) / SUM(d.Impressions) * 100, 3) AS Click_Through_Rate_Percent,
       ROUND(SUM(c.Orders) / SUM(c.Clicks) * 100, 2)      AS Conversion_Rate_Percent,
       ROUND(SUM(c.Orders) / SUM(d.Impressions) * 100, 4) AS Social_Media_CTR_Percent
FROM AD a
JOIN (SELECT Ad_ID, SUM(Impressions) AS Impressions
      FROM AD_PERFORMANCE
      GROUP BY Ad_ID) d ON d.Ad_ID = a.Ad_ID
JOIN (SELECT c.Ad_ID, COUNT(c.Click_ID) AS Clicks, COUNT(o.Order_ID) AS Orders
      FROM CLICK c
      JOIN `SESSION` s    ON s.Click_ID = c.Click_ID
      LEFT JOIN `ORDER` o ON o.Session_ID = s.Session_ID
      GROUP BY c.Ad_ID) c ON c.Ad_ID = a.Ad_ID
WHERE a.Campaign_ID = 6
GROUP BY a.Platform_Name
ORDER BY Social_Media_CTR_Percent DESC;

-- Query 9B: What each platform earns on its media spend
-- sp  = advertising spend per platform
-- rev = attributed orders, net revenue and gross profit per platform
-- Revenue_ROAS       = attributed net revenue / spend (dollars of revenue per $1 of media)
-- Profit_ROAS        = attributed gross profit / spend (break-even = 1.00)
-- Cost_Per_Order     = spend / attributed orders
-- Profit_After_Media = gross profit - spend (positive when Profit_ROAS > 1)
SELECT sp.Platform_Name, sp.Spend, rev.Attributed_Orders,
       ROUND(sp.Spend / rev.Attributed_Orders, 2) AS Cost_Per_Order,
       rev.Attributed_Net_Revenue, rev.Attributed_Gross_Profit,
       ROUND(rev.Attributed_Net_Revenue / sp.Spend, 2)  AS Revenue_ROAS,
       ROUND(rev.Attributed_Gross_Profit / sp.Spend, 2) AS Profit_ROAS,
       ROUND(rev.Attributed_Gross_Profit - sp.Spend, 2) AS Profit_After_Media
FROM (SELECT a.Platform_Name, ROUND(SUM(ap.Spend), 2) AS Spend
      FROM AD a
      JOIN AD_PERFORMANCE ap ON ap.Ad_ID = a.Ad_ID
      WHERE a.Campaign_ID = 6
      GROUP BY a.Platform_Name) sp
JOIN (SELECT a.Platform_Name,
             COUNT(DISTINCT o.Order_ID) AS Attributed_Orders,
             ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                   * oi.Unit_Price_At_Sale * (1 - d.Discount_Share)), 2)
                 AS Attributed_Net_Revenue,
             ROUND(SUM((oi.Quantity - COALESCE(r.Qty_Returned, 0))
                       * (oi.Unit_Price_At_Sale * (1 - d.Discount_Share)
                             - p.Cost_Price)), 2)
                 AS Attributed_Gross_Profit
      FROM AD a
      JOIN CLICK c       ON c.Ad_ID = a.Ad_ID
      JOIN `SESSION` s   ON s.Click_ID = c.Click_ID
      JOIN `ORDER` o     ON o.Session_ID = s.Session_ID
      JOIN ORDER_ITEM oi ON oi.Order_ID = o.Order_ID
      JOIN PRODUCT p     ON p.SKU = oi.SKU
      JOIN (SELECT Order_ID,
                   Discount_Applied / (Order_Total + Discount_Applied) AS Discount_Share
            FROM `ORDER`) d ON d.Order_ID = oi.Order_ID
      LEFT JOIN (SELECT Order_ID, SKU, SUM(Quantity_Returned) AS Qty_Returned
                 FROM `RETURN`
                 GROUP BY Order_ID, SKU) r
             ON r.Order_ID = oi.Order_ID AND r.SKU = oi.SKU
      WHERE a.Campaign_ID = 6
      GROUP BY a.Platform_Name) rev
  ON rev.Platform_Name = sp.Platform_Name
ORDER BY Profit_ROAS DESC;
