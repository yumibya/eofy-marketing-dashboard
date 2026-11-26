-- ============================================================
-- Table Implementation
-- Translates the 11-entity Chen's notation ERD into MySQL DDL
-- Creation order respects foreign key dependencies.
-- Note: CHECK constraints require MySQL 8.0.16+ to be enforced.
-- ============================================================

DROP DATABASE IF EXISTS david_jones_analytics;
CREATE DATABASE david_jones_analytics;
USE david_jones_analytics;

-- ------------------------------------------------------------
-- 1. CUSTOMER
-- ------------------------------------------------------------
CREATE TABLE CUSTOMER (
    Customer_ID       INT AUTO_INCREMENT PRIMARY KEY,
    First_Name        VARCHAR(50)  NOT NULL,
    Last_Name         VARCHAR(50)  NOT NULL,
    Email             VARCHAR(100) NOT NULL UNIQUE,
    Phone             VARCHAR(20),
    Join_Date         DATE NOT NULL,
    Marketing_Opt_In  BOOLEAN NOT NULL DEFAULT FALSE
);

-- ------------------------------------------------------------
-- 2. CAMPAIGN
-- ------------------------------------------------------------
CREATE TABLE CAMPAIGN (
    Campaign_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Campaign_Name  VARCHAR(100) NOT NULL,
    Campaign_Type  VARCHAR(20)  NOT NULL,
    Start_Date     DATE NOT NULL,
    End_Date       DATE NOT NULL,
    Total_Budget   DECIMAL(10,2) NOT NULL,
    CHECK (Campaign_Type IN ('EOFY','BAU','Seasonal_Sale')),
    CHECK (End_Date >= Start_Date)
);

-- ------------------------------------------------------------
-- 3. PRODUCT
-- (CATEGORY folded in as an attribute - see section 1.1:
--  no other entity needs to reference category alone)
-- SKU is the natural key (e.g. WOM-0001), not a surrogate integer
-- ------------------------------------------------------------
CREATE TABLE PRODUCT (
    SKU            VARCHAR(12) PRIMARY KEY,
    Category_Name  VARCHAR(30) NOT NULL,
    Product_Name   VARCHAR(100) NOT NULL,
    Brand          VARCHAR(50),
    RRP            DECIMAL(10,2) NOT NULL,
    Sale_Price     DECIMAL(10,2) NOT NULL,
    -- Cost_Price is what David Jones pays the supplier. Without it the
    -- database can report revenue but not profit, so campaign return could
    -- only be judged on sales value rather than on the margin the CMO
    -- actually defends. No constraint ties it below Sale_Price, because
    -- clearance lines can legitimately be sold at or under cost.
    Cost_Price     DECIMAL(10,2) NOT NULL,
    CHECK (Sale_Price <= RRP),
    CHECK (Cost_Price > 0)
);

-- ------------------------------------------------------------
-- 4. MEMBERSHIP
-- 1:1 with CUSTOMER, partial participation on CUSTOMER side
-- (UNIQUE on Customer_ID enforces the 1:1 cardinality)
-- ------------------------------------------------------------
CREATE TABLE MEMBERSHIP (
    Membership_ID           INT AUTO_INCREMENT PRIMARY KEY,
    Customer_ID             INT NOT NULL UNIQUE,
    Tier                    VARCHAR(10) NOT NULL,
    Points_Balance          INT NOT NULL DEFAULT 0,
    Annual_Spend            DECIMAL(10,2) NOT NULL DEFAULT 0,
    Points_Preference       VARCHAR(10) NOT NULL,
    Membership_Start_Date   DATE NOT NULL,
    CHECK (Tier IN ('Bronze','Silver','Gold')),
    CHECK (Points_Preference IN ('Rewards','Qantas')),
    FOREIGN KEY (Customer_ID) REFERENCES CUSTOMER(Customer_ID)
        ON DELETE CASCADE
);

-- Assumed business rule (not confirmed in David Jones' published
-- terms): a customer must be opted in to marketing communications
-- to become a member. This is a cross-table rule, so a CHECK
-- constraint can't express it - enforced with a trigger instead.
DELIMITER $$
CREATE TRIGGER trg_membership_requires_optin
BEFORE INSERT ON MEMBERSHIP
FOR EACH ROW
BEGIN
    DECLARE v_opt_in BOOLEAN;
    SELECT Marketing_Opt_In INTO v_opt_in
    FROM CUSTOMER WHERE Customer_ID = NEW.Customer_ID;
    IF v_opt_in = FALSE OR v_opt_in IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Customer must opt in to marketing communications to become a David Jones Rewards member';
    END IF;
END$$
DELIMITER ;

-- ------------------------------------------------------------
-- 5. AD
-- (PLATFORM folded in as an attribute - see section 1.1)
-- ------------------------------------------------------------
-- AD holds only the creative definition of an advertisement. The delivery
-- measures (spend, impressions, reach, engagement) are NOT stored here:
-- they vary day by day and are held in AD_PERFORMANCE, so that a campaign
-- still in flight can be monitored and optimised rather than only reviewed
-- once it has finished. Storing them in both places would duplicate data.
-- Featured_Category records which product category the creative promotes.
-- Read together with Landing_Page_URL, it shows whether an advertisement
-- sends shoppers to the page that matches its offer. It replaces a
-- free-text theme field, whose campaign-name prefix merely duplicated
-- CAMPAIGN.Campaign_Name and which no analysis could group on reliably.
-- Target_Audience and Landing_Page_URL are the two settings the CMO can
-- change mid-campaign, so they are recorded to make that decision testable.
CREATE TABLE AD (
    Ad_ID            INT AUTO_INCREMENT PRIMARY KEY,
    Campaign_ID      INT NOT NULL,
    Platform_Name    VARCHAR(20) NOT NULL,
    Ad_Format        VARCHAR(30),
    Content_Type     VARCHAR(30),
    Featured_Category VARCHAR(30),
    Target_Audience  VARCHAR(40),
    Landing_Page_URL VARCHAR(255),
    Publish_Date     DATE NOT NULL,
    CHECK (Platform_Name IN ('Instagram','Facebook','TikTok','X')),
    CHECK (Content_Type IN ('KOL_Collaboration','UGC_Style','Product_Only','Lifestyle_Editorial','AI_Generated')),
    CHECK (Featured_Category IN ('Womenswear','Menswear','Beauty','Homewares','Appliances')),
    CHECK (Target_Audience IN ('Broad','Lookalike_Purchasers','Retargeting_Site_Visitors','Rewards_Members','Interest_Fashion','Interest_Home')),
    FOREIGN KEY (Campaign_ID) REFERENCES CAMPAIGN(Campaign_ID)
        ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 5b. AD_PERFORMANCE
-- One row per advertisement per day of delivery. This is what makes
-- in-flight campaign management possible: budget pacing, day-on-day
-- trends, and the point at which a creative starts to fatigue.
-- ------------------------------------------------------------
CREATE TABLE AD_PERFORMANCE (
    Performance_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Ad_ID             INT NOT NULL,
    Performance_Date  DATE NOT NULL,
    Impressions       INT NOT NULL DEFAULT 0,
    Reach             INT NOT NULL DEFAULT 0,
    Engagement        INT NOT NULL DEFAULT 0,
    Spend             DECIMAL(10,2) NOT NULL DEFAULT 0,
    UNIQUE KEY uq_ad_day (Ad_ID, Performance_Date),
    CHECK (Reach <= Impressions),
    FOREIGN KEY (Ad_ID) REFERENCES AD(Ad_ID)
        ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 6. CLICK  (associative entity resolving CUSTOMER <-> AD, M:M)
-- ------------------------------------------------------------
CREATE TABLE CLICK (
    Click_ID        INT AUTO_INCREMENT PRIMARY KEY,
    Customer_ID     INT NOT NULL,
    Ad_ID           INT NOT NULL,
    Click_Datetime  DATETIME NOT NULL,
    Device_Type     VARCHAR(20),
    FOREIGN KEY (Customer_ID) REFERENCES CUSTOMER(Customer_ID)
        ON DELETE CASCADE,
    FOREIGN KEY (Ad_ID) REFERENCES AD(Ad_ID)
        ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 7. SESSION
-- 1:1 with CLICK, total participation both sides
-- ------------------------------------------------------------
CREATE TABLE `SESSION` (
    Session_ID      INT AUTO_INCREMENT PRIMARY KEY,
    Click_ID        INT NOT NULL UNIQUE,
    Session_Start   DATETIME NOT NULL,
    Session_End     DATETIME,
    Pages_Viewed    INT NOT NULL DEFAULT 1,
    Bounced         BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (Click_ID) REFERENCES CLICK(Click_ID)
        ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 8. ORDER
-- Session_ID nullable: partial participation - some orders
-- (in-store, direct traffic) have no tracked social session
-- ------------------------------------------------------------
CREATE TABLE `ORDER` (
    Order_ID           INT AUTO_INCREMENT PRIMARY KEY,
    Customer_ID        INT NOT NULL,
    Session_ID         INT NULL,
    Order_Date         DATETIME NOT NULL,
    Order_Total        DECIMAL(10,2) NOT NULL,
    Discount_Applied   DECIMAL(10,2) NOT NULL DEFAULT 0,
    Channel            VARCHAR(20) NOT NULL,
    CHECK (Channel IN ('Online','In-store')),
    FOREIGN KEY (Customer_ID) REFERENCES CUSTOMER(Customer_ID)
        ON DELETE CASCADE,
    FOREIGN KEY (Session_ID) REFERENCES `SESSION`(Session_ID)
        ON DELETE SET NULL
);

-- ------------------------------------------------------------
-- 9. ORDER_ITEM (associative entity resolving ORDER <-> PRODUCT, M:M)
-- Composite primary key
-- ------------------------------------------------------------
CREATE TABLE ORDER_ITEM (
    Order_ID             INT NOT NULL,
    SKU                  VARCHAR(12) NOT NULL,
    Quantity             INT NOT NULL DEFAULT 1,
    Unit_Price_At_Sale   DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (Order_ID, SKU),
    FOREIGN KEY (Order_ID) REFERENCES `ORDER`(Order_ID)
        ON DELETE CASCADE,
    FOREIGN KEY (SKU) REFERENCES PRODUCT(SKU)
        ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 10. `RETURN`
-- A returned product line. RETURN is a reserved word in MySQL and is
-- therefore escaped with backticks, as ORDER and SESSION are.
-- Returns are recorded against the order line rather than the whole
-- order, because a customer may return part of a basket. This lets
-- revenue be reported net of returns, which matters for a retailer
-- offering free returns: gross sales overstate what was actually kept.
-- A line may be returned in more than one instalment, so the
-- relationship is 1:M and Return_ID is its own primary key.
-- ------------------------------------------------------------
CREATE TABLE `RETURN` (
    Return_ID          INT AUTO_INCREMENT PRIMARY KEY,
    Order_ID           INT NOT NULL,
    SKU                VARCHAR(12) NOT NULL,
    Return_Date        DATETIME NOT NULL,
    Quantity_Returned  INT NOT NULL,
    Return_Reason      VARCHAR(40),
    CHECK (Quantity_Returned > 0),
    CHECK (Return_Reason IN ('Size_Fit','Changed_Mind','Faulty','Not_As_Described','Late_Delivery')),
    FOREIGN KEY (Order_ID, SKU) REFERENCES ORDER_ITEM(Order_ID, SKU)
        ON DELETE CASCADE
);
