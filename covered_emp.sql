USE Elmer
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* Step 1. Prepare inventory table imported into Sockeye */
    UPDATE Sandbox.Mike.ili20231221 SET Shape = Shape.MakeValid();
    EXEC sp_rename 'Mike.ili20231221.ind_catego', 'ind_type', 'COLUMN'
    
    CREATE SPATIAL INDEX ili20231221_sidx  ON Sandbox.Mike.ili20231221(Shape) USING GEOMETRY_AUTO_GRID
       WITH (BOUNDING_BOX = (xmin = 1098600, ymin = -93400, xmax = 1611500, ymax = 476100));
                
/* Step 2. Create and populate spatial correspondence table */
    -- This enables later queries to be much faster (instead of being spatial queries)
    DROP TABLE IF EXISTS Sandbox.Mike.industrial_lands_workplaces;
    GO
    CREATE TABLE Sandbox.Mike.industrial_lands_workplaces(workplace_location_id bigint, ind_type nvarchar(50));
    GO
    TRUNCATE TABLE Sandbox.Mike.industrial_lands_workplaces;
    GO
    
    INSERT INTO Sandbox.Mike.industrial_lands_workplaces(workplace_location_id, ind_type)
    SELECT wl.workplace_location_id, ili.ind_type
    FROM employment.workplace_location_dims AS wl JOIN Sandbox.Mike.ili20231221 AS ili ON wl.Shape.STIntersects(ili.Shape)=1
    GROUP BY wl.workplace_location_id, ili.ind_type;
    GO

/* Step 3. QC Check */
    SELECT * FROM Sandbox.Mike.industrial_lands_workplaces WHERE ind_type IS NULL;  
    
/* Step 4. Execute individual queries (export resultsets to spreadsheet) */
    
    --Employment breakdown, Manufacturing-Industrial Group x Land Status
        WITH cte AS (
        SELECT wf.data_year,
                CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END AS Industrial_Land_Status , 
                i.manuf_industrial_group ,
                CASE WHEN i.manuf_industrial_group='z Non-Industrial' THEN 'Non-Industrial' ELSE 'Industrial' END AS IndustrialJob ,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                    WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                    WHEN SUM(i.private_sector) IN(1,2) 
                      OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                      OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                    ELSE
                    CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
                FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022) 
                GROUP BY wf.data_year,
                        CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END,
                        CASE WHEN i.manuf_industrial_group='z Non-Industrial' THEN 'Non-Industrial' ELSE 'Industrial' END, i.manuf_industrial_group
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT (max(emp_covered) FOR data_year IN([2005],[2010],[2015],[2020],[2021],[2022])) AS p)
        SELECT * from cte2 ORDER BY Industrial_Land_Status, manuf_industrial_group;
    
    --Totals by Land Status
        WITH cte AS (
        SELECT wf.data_year,
                CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END AS Industrial_Land_Status , 
                CASE WHEN i.manuf_industrial_group='z Non-Industrial' THEN 'Non-Industrial' ELSE 'Industrial' END AS IndustrialJob ,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                    WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                    WHEN SUM(i.private_sector) IN(1,2) 
                      OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                      OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                    ELSE
                    CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
                FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022)
                GROUP BY CUBE(wf.data_year,
                        CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END,
                        CASE WHEN i.manuf_industrial_group='z Non-Industrial' THEN 'Non-Industrial' ELSE 'Industrial' END)
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT (max(emp_covered) FOR data_year IN([2005],[2010],[2015],[2020],[2021],[2022])) AS p)
        SELECT * from cte2 WHERE IndustrialJob <> 'Non-Industrial' OR IndustrialJob IS NULL ORDER BY Industrial_Land_Status;
    
    --Totals by Manufacturing-Industrial Group
        WITH cte AS (
        SELECT wf.data_year,
                i.manuf_industrial_group ,
                CASE WHEN i.manuf_industrial_group='z Non-Industrial' THEN 'Non-Industrial' ELSE 'Industrial' END AS IndustrialJob ,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                    WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                    WHEN SUM(i.private_sector) IN(1,2) 
                      OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                      OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                    ELSE
                    CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
                FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022) 
                GROUP BY wf.data_year, i.manuf_industrial_group
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT (max(emp_covered) FOR data_year IN([2005],[2010],[2015],[2020],[2021],[2022])) AS p)
        SELECT * from cte2 ORDER BY manuf_industrial_group;
    
    --Employment breakdown, Manufacturing-Industrial Detail x Land Status
        WITH cte AS (
        SELECT wf.data_year, CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' ELSE 'Limited or Not Industrial' END AS Industrial_Land_Status ,
        i.manuf_industrial_group ,i.manuf_industrial_detail, 
        CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0'  
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
            FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022)
                GROUP BY wf.data_year, CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' ELSE 'Limited or Not Industrial' END,
                i.manuf_industrial_group ,i.manuf_industrial_detail
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT (max(emp_covered) FOR data_year IN([2005],[2010],[2015],[2020],[2021],[2022])) AS p)
        SELECT * from cte2 ORDER BY Industrial_Land_Status, manuf_industrial_group, manuf_industrial_detail;
    
    --Totals, Manufacturing-Industrial Detail
        WITH cte AS (
        SELECT wf.data_year, i.manuf_industrial_group ,i.manuf_industrial_detail, 
        CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0'  
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
            FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022)
                GROUP BY wf.data_year, i.manuf_industrial_group ,i.manuf_industrial_detail
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT (max(emp_covered) FOR data_year IN([2005],[2010],[2015],[2020],[2021],[2022])) AS p)
        SELECT * from cte2 ORDER BY manuf_industrial_group, manuf_industrial_detail;
    
    --Industrial job totals, Land Status
        WITH cte AS (
        SELECT wf.data_year, CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' ELSE 'Limited or Not Industrial' END AS Industrial_Land_Status ,
        CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0'  
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
            FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022) AND i.manuf_industrial_group<>'z Non-industrial'
                GROUP BY wf.data_year, CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' ELSE 'Limited or Not Industrial' END
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT (max(emp_covered) FOR data_year IN([2005],[2010],[2015],[2020],[2021],[2022])) AS p)
        SELECT * from cte2 ORDER BY Industrial_Land_Status;
    
    --Employment breakdown, Manufacturing group x Land Status x County   
        WITH cte AS (
        SELECT CONCAT(wl.county_id,',',wf.data_year) AS header /*wf.data_year*/,CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END AS Industrial_Land_Status,
                i.manuf_industrial_group ,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022)  
                GROUP BY wf.data_year,wl.county_id , CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END, i.manuf_industrial_group
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        --FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
        FOR header 
        IN([33,2005], [33,2010], [33,2015], [33,2020], [33,2022], 
          [35,2005], [35,2010], [35,2015], [35,2020], [35,2022], 
          [53,2005], [53,2010], [53,2015], [53,2020], [53,2022], 
          [61,2005], [61,2010], [61,2015], [61,2020], [61,2022])) AS p
          )
        SELECT * from cte2 ORDER BY Industrial_Land_Status, manuf_industrial_group;
    
    --Totals, Manufacturing-Industrial Group x County
        WITH cte AS (
        SELECT CONCAT(wl.county_id,',',wf.data_year) AS header, i.manuf_industrial_group ,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022)  
                GROUP BY wf.data_year, wl.county_id, i.manuf_industrial_group 
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        --FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
        FOR header 
        IN([33,2005], [33,2010], [33,2015], [33,2020], [33,2022], 
          [35,2005], [35,2010], [35,2015], [35,2020], [35,2022], 
          [53,2005], [53,2010], [53,2015], [53,2020], [53,2022], 
          [61,2005], [61,2010], [61,2015], [61,2020], [61,2022])) AS p
          )
        SELECT * from cte2 ORDER BY manuf_industrial_group;
    
    --Industrial job totals, Land Status x County
        WITH cte AS (
        SELECT CONCAT(wl.county_id,',',wf.data_year) AS header /*wf.data_year*/,CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END AS Industrial_Land_Status,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022) AND i.manuf_industrial_group<>'z Non-industrial'
                GROUP BY wf.data_year,wl.county_id , CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        --FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
        FOR header 
        IN([33,2005], [33,2010], [33,2015], [33,2020], [33,2022], 
          [35,2005], [35,2010], [35,2015], [35,2020], [35,2022], 
          [53,2005], [53,2010], [53,2015], [53,2020], [53,2022], 
          [61,2005], [61,2010], [61,2015], [61,2020], [61,2022])) AS p
          )
        SELECT * from cte2 ORDER BY Industrial_Land_Status;
    
    --Totals, Land Status x County
        WITH cte AS (
        SELECT CONCAT(wl.county_id,',',wf.data_year) AS header /*wf.data_year*/,CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END AS Industrial_Land_Status,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022)  
                GROUP BY wf.data_year,wl.county_id , CASE WHEN ili.ind_type <>'Limited Industrial' AND ili.ind_type IS NOT NULL THEN 'Industrial' WHEN ili.ind_type='Limited Industrial' THEN 'Limited Industrial' ELSE 'Not Industrial' END
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        --FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
        FOR header 
        IN([33,2005], [33,2010], [33,2015], [33,2020], [33,2022], 
          [35,2005], [35,2010], [35,2015], [35,2020], [35,2022], 
          [53,2005], [53,2010], [53,2015], [53,2020], [53,2022], 
          [61,2005], [61,2010], [61,2015], [61,2020], [61,2022])) AS p
          )
        SELECT * from cte2 ORDER BY Industrial_Land_Status;
    
    --Totals, County
        WITH cte AS (
        SELECT CONCAT(wl.county_id,',',wf.data_year) AS header, 
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022)  
                GROUP BY wf.data_year, wl.county_id
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        --FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
        FOR header 
        IN([33,2005], [33,2010], [33,2015], [33,2020], [33,2022], 
          [35,2005], [35,2010], [35,2015], [35,2020], [35,2022], 
          [53,2005], [53,2010], [53,2015], [53,2020], [53,2022], 
          [61,2005], [61,2010], [61,2015], [61,2020], [61,2022])) AS p
          )
        SELECT * from cte2 
    
    SELECT CONCAT(C.c,'-',Y.y) AS headers FROM (VALUES (2005),(2010),(2015),(2020),(2022)) AS Y(y) JOIN (VALUES (33),(35),(53),(61)) AS C(c) ON 1=1;
    
    --Employment breakdown, Jobtype (Industrial or not) x Industrial Land Category
        with cte AS(
        SELECT  CONCAT(wl.county_id,',',wf.data_year) AS header,--*/ wf.data_year,
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END AS ind_type, 
                CASE WHEN i.manuf_industrial_group='z Non-industrial' THEN 'Non-Industrial' ELSE 'Industrial' END AS IndjobYN,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
            FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022) AND ili.workplace_location_id IS NOT NULL AND ili.ind_type<>'Limited Industrial'
                GROUP BY wf.data_year, wl.county_id, 
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END, 
                CASE WHEN i.manuf_industrial_group='z Non-industrial' THEN 'Non-Industrial' ELSE 'Industrial' END
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        --FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
        FOR header 
        IN([33,2005], [33,2010], [33,2015], [33,2020], [33,2022], 
          [35,2005], [35,2010], [35,2015], [35,2020], [35,2022], 
          [53,2005], [53,2010], [53,2015], [53,2020], [53,2022], 
          [61,2005], [61,2010], [61,2015], [61,2020], [61,2022])) AS p
          )
        SELECT * from cte2 ORDER BY ind_type, IndjobYN;
    
    --Regional totals, Jobtype (Industrial or not) x Industrial Land Category
        with cte AS(
        SELECT  wf.data_year,
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END AS ind_type, 
                CASE WHEN i.manuf_industrial_group='z Non-industrial' THEN 'Non-Industrial' ELSE 'Industrial' END AS IndjobYN,
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
            FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022) AND ili.workplace_location_id IS NOT NULL AND ili.ind_type<>'Limited Industrial'
                GROUP BY wf.data_year,
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END, 
                CASE WHEN i.manuf_industrial_group='z Non-industrial' THEN 'Non-Industrial' ELSE 'Industrial' END
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
          )
        SELECT * from cte2 ORDER BY ind_type, IndjobYN;
    
    --Regional totals, Industrial Land Category
        with cte AS(
        SELECT  wf.data_year,
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END AS ind_type, 
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
            FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022) AND ili.workplace_location_id IS NOT NULL AND ili.ind_type<>'Limited Industrial'
                GROUP BY wf.data_year,
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
          )
        SELECT * from cte2 ORDER BY ind_type;
    
    --Total, Industrial Land Category
        with cte AS(
        SELECT  CONCAT(wl.county_id,',',wf.data_year) AS header,--*/ wf.data_year,
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END AS ind_type, 
                CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
            FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022) AND ili.workplace_location_id IS NOT NULL AND ili.ind_type<>'Limited Industrial'
                GROUP BY wf.data_year, wl.county_id, 
                CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                    WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE 'Other' END
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        --FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p
        FOR header 
        IN([33,2005], [33,2010], [33,2015], [33,2020], [33,2022], 
          [35,2005], [35,2010], [35,2015], [35,2020], [35,2022], 
          [53,2005], [53,2010], [53,2015], [53,2020], [53,2022], 
          [61,2005], [61,2010], [61,2015], [61,2020], [61,2022])) AS p
          )
        SELECT * from cte2 ORDER BY ind_type;
    
    --Employment breakdown, MIC x Industrial Group
        WITH cte AS(
        SELECT wf.data_year,wl.mic ,i.manuf_industrial_group, CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
                FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022) AND wl.mic <>''
                GROUP BY CUBE(wf.data_year,wl.mic ,i.manuf_industrial_group) 
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p)
        SELECT * from cte2 ORDER BY mic, manuf_industrial_group;
    
    --Industrial job total, MIC
        WITH cte AS(
        SELECT wf.data_year, wl.mic, CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
                FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022) AND wl.mic <>'' AND i.manuf_industrial_group<>'z Non-industrial' 
                GROUP BY wf.data_year,wl.mic
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p)
        SELECT * from cte2 ORDER BY mic;
    
    --Regional totals, MIC x Industrial Group
        WITH cte AS(
        SELECT wf.data_year,i.manuf_industrial_group, CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
                FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022) AND wl.mic <>''
                GROUP BY CUBE(wf.data_year, i.manuf_industrial_group) 
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p)
        SELECT * from cte2 ORDER BY manuf_industrial_group;
    
        WITH cte AS(
        SELECT wf.data_year, CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered 
                FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2021,2022) AND wl.mic <>'' AND i.manuf_industrial_group<>'z Non-industrial'
                GROUP BY wf.data_year
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p)
        SELECT * from cte2;
    
    --Employment breakdown, Industrial Land Category x Industrial Group
        WITH cte AS (
        SELECT wf.data_year, CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                                  WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE NULL END AS ind_type, 
                i.manuf_industrial_group,
                  CASE WHEN SUM(wf.jobcount_covered) < 0.4 THEN '0' 
                      WHEN SUM(i.private_sector) = 0 THEN CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar)
                      WHEN SUM(i.private_sector) IN(1,2) 
                        OR MAX(wf.jobcount_raw * i.private_sector) / SUM(wf.jobcount_raw * i.private_sector) > 0.8
                        OR SUM(wf.jobcount_raw * i.private_sector * (CASE WHEN wf.confid_firm_id = 0 THEN 0 ELSE 1 END)) / sum(wf.jobcount_raw * i.private_sector) > 0.8 THEN 'S'
                      ELSE
                      CAST(CAST(ROUND(SUM(wf.jobcount_covered),0) AS int) AS nvarchar) END AS emp_covered FROM employment.workplace_facts AS wf JOIN employment.industry_dims AS i ON wf.industry_id = i.industry_id
                JOIN employment.workplace_location_dims AS wl ON wf.workplace_location_id = wl.workplace_location_id
                LEFT JOIN Sandbox.Mike.industrial_lands_workplaces AS ili ON wl.workplace_location_id=ili.workplace_location_id
                WHERE wf.data_year IN(2005,2010,2015,2020,2022)
                GROUP BY wf.data_year, CASE WHEN ili.ind_type IN('Aviation Operations','Military Industrial') THEN 'Core Industrial' 
                                  WHEN ili.ind_type IS NOT NULL THEN ili.ind_type ELSE NULL END, 
                        i.manuf_industrial_group
                HAVING wf.data_year IS NOT NULL),
        cte2 AS (SELECT * FROM cte PIVOT(max(emp_covered) 
        FOR data_year IN([2005],[2010],[2015],[2020],[2022])) AS p)
        SELECT * from cte2 ORDER BY ind_type, manuf_industrial_group;

