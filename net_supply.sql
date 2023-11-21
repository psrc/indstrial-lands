/* scripts for Industrial Lands net supply */

/* Step 1. Bring MySQL data into Sockeye */
    -- Modelsrv3 MySQL database
    /*
    CREATE TABLE sandbox_mjj.prclbldg_values (parcel_id int(11), prcl_sqft int(11), gross_sqft int(11), land_value int(11), combined_improvement_value bigint(20), flag char(1), land_use_type_id int(11), plan_type_id int(11));

    INSERT INTO sandbox_mjj.prclblg_values (parcel_id, prcl_sqft, gross_sqft, land_value, combined_improvement_value, land_use_type_id, plan_type_id, x_coord_sp, y_coord_sp)
    SELECT p.parcel_id, p.parcel_sqft, p.gross_sqft, p.land_value, sum(b.improvement_value) AS combined_improvement_value, p.land_use_type_id, p.plan_type_id, p.x_coord_sp, p.y_coord_sp
    FROM 2018_parcel_baseyear.parcels AS p JOIN 2018_parcel_baseyear.buildings AS b ON p.parcel_id=b.parcel_id GROUP BY p.parcel_id;

    INSERT INTO sandbox_mjj.prclbldg_values (parcel_id, prcl_sqft, gross_sqft, land_value, combined_improvement_value, flag, land_use_type_id, plan_type_id, x_coord_sp, y_coord_sp)
    SELECT p.parcel_id, p.parcel_sqft, p.gross_sqft, p.land_value, 0.00 AS combined_improvement_value, 'v' AS flag, p.land_use_type_id, p.plan_type_id, round(p.x_coord_sp,2), round(p.y_coord_sp,2)
    FROM 2018_parcel_baseyear.parcels AS p WHERE NOT EXISTS (SELECT 1 FROM 2018_parcel_baseyear.buildings AS b WHERE b.parcel_id=p.parcel_id);

    SELECT * FROM sandbox_mjj.prclbldg_values
    INTO OUTFILE 'by18_prcl_bldg.csv';
    */
    -- import into Sockeye (e.g. flat file import tool).

/* Step 2. Generate correct correspondence between ElmerGeo.dbo.parcels_urbansim_2018 and baseyear parcel_id */
    -- This doesn't need to be done again, but was a major item in 2023; ElmerGeo.dbo.parcels_urbansim_2018.PIN had been erroneously assigned, along with coordinates, to many parcels
    -- We can now use the ElmerGeo.dbo.parcels_urbansim_2018.parcel_id field, which is accurate.
    -- The following query was repeated with increasing buffer distance until all UrbanSim parcel attribute records were matched with an ElmerGeo parcel geometry with the correct area.
    /*  UPDATE r 
        SET r.Shape=p.Shape,
            r.elmergeo_oid=p.OBJECTID
        FROM Sandbox.Mike.ilx_indprcl_net AS r JOIN ElmerGeo.dbo.PARCELS_URBANSIM_2018 AS p ON p.Shape.STCentroid().STIntersects(r.CentroidShape.STBuffer(10))=1
        WHERE ABS(p.Shape.STArea() - r.gross_sqft) <= 1 AND r.elmergeo_oid IS NULL AND NOT EXISTS(SELECT 1 FROM Sandbox.Mike.ilx_indprcl_net AS r2 WHERE r2.elmergeo_oid=p.OBJECTID);
    */

/* Step 3. Create a net acreage layer by erasing the largest_waterbodies layer, and all other exclusions (wetlands, CAI tiers, public use) from ElmerGeo.dbo.parcels_urbansim_2018 in ArcGIS */
    --Faster than using OGC queries to intersect such detailed geometry
    --import via ogr2ogr into Sockeye as prcl_xcluderase

/* Step 4. Create primary table with necessary fields */
    -- Faster to import all parcels, spatially update, and then drop those which don't match, than to selectively insert those which do match (go figure)
    DROP TABLE IF EXISTS Sandbox.Mike.ilx_indprcl_net;
    GO
    CREATE TABLE Sandbox.Mike.ilx_indprcl_net(parcel_id int PRIMARY KEY NOT NULL, 
                                              ind_type nvarchar(25), 
                                              county_id smallint, 
                                              mic nvarchar(40), 
                                              impval int, 
                                              gross_sqft int, 
                                              land_use_type_id smallint,
                                              net_flag nchar(1),
                                              value_ratio decimal(11,2),
                                              urban nchar(3),
                                              Shape geometry,
                                              CentroidShape geometry);

    -- Makes UrbanSim land_use_type_id exclusions
    INSERT INTO Sandbox.Mike.ilx_indprcl_net (parcel_id, gross_sqft, impval, net_flag, land_use_type_id, Shape, CentroidShape)
    SELECT x.parcel_id, x.parcel_sqft, x.gross_sqft, x.land_value, x.improvements_value AS impval, 
           CASE WHEN x.improvements_value <=0.00107 THEN 'v' 
                WHEN x.gross_sqft >0 AND x.improvements_value/x.gross_sqft < 0.00107 THEN 'v' 
                WHEN x.gross_sqft >0 AND x.improvements_value/x.gross_sqft < 5.35 THEN 'r' ELSE '' END AS net_flag,
           CASE WHEN  x.improvements_value <=0 THEN 0 ELSE x.improvements_value/x.gross_sqft END as value_ratio,
           x.land_use_type_id, p.Shape, p.CentroidShape
    FROM Sandbox.Mike.by18_prcl_bldg AS x JOIN Sandbox.Mike.prcl_xcluderase AS p ON x.parcel_id=p.parcel_id 
    WHERE x.land_use_type_id NOT IN(2,6,7,8,19,22,23,29);

    --Add spatial index
    CREATE SPATIAL INDEX ilx_ipr_ctrsidx ON Sandbox.Mike.ilx_indprcl_net(CentroidShape)  
    USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (xmin = 1111000, ymin = -92400, xmax = 1520420, ymax = 476385));
    GO

    --Spatial join with the 2023 Industrial Lands Inventory
    UPDATE x
    SET x.ind_type=i.ind_type 
    FROM Sandbox.Mike.ilx_indprcl_net AS x JOIN Sandbox.Mike.ili20231023 AS i ON x.CentroidShape.STIntersects(i.Shape)=1 
    WHERE i.ind_type NOT IN('Aviation Operations','Military Industrial','Limited Industrial');
    GO
    --Reduce table to relevant subset
    DELETE FROM Sandbox.Mike.ilx_indprcl_net WHERE ind_type IS NULL OR net_flag <>'' ;
    GO

    --Attach geographic assignments
    UPDATE x 
    SET x.county_id=CAST(county_fip AS smallint)
    FROM Sandbox.Mike.ilx_indprcl_net AS x JOIN ElmerGeo.dbo.COUNTY_BACKGROUND AS c ON x.CentroidShape.STIntersects(c.Shape)=1
    WHERE c.county_fip IN('033','035','053','061');
    GO
    UPDATE x 
    SET x.mic=m.mic
    FROM Sandbox.Mike.ilx_indprcl_net AS x JOIN ElmerGeo.dbo.MICEN AS m ON x.CentroidShape.STIntersects(m.Shape)=1;    
    GO
    UPDATE x 
    SET x.urban=CASE WHEN r.class_desc='Metro' AND r.Juris<>'Bremerton' THEN 'Y' ELSE 'N' END
    FROM Sandbox.Mike.ilx_indprcl_net AS x JOIN ElmerGeo.dbo.PSRC_REGION AS r ON x.CentroidShape.STIntersects(r.Shape)=1;    
    GO  

/* Step 5. 2023 net supply queries */

    --Replicates 2015 method of market factor and ROI set-asides through a multiplier

    WITH cte AS (SELECT x.mic, x.net_flag, round(sum(x.Shape.STArea() * (CASE WHEN x.urban='Y' THEN .88 ELSE .85 END))/43560,2) AS acres 
                FROM Sandbox.Mike.ilx_indprcl_net AS x 
                WHERE x.mic<>''
                GROUP BY x.net_flag, x.mic)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([v], [r])) AS p;

    WITH cte AS (SELECT x.county_id, x.net_flag, round(sum(x.Shape.STArea() * (CASE WHEN x.urban='Y' THEN .88 ELSE .85 END))/43560,2) AS acres 
                FROM Sandbox.Mike.ilx_indprcl_net AS x 
                GROUP BY x.net_flag, x.county_id)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([v], [r])) AS p;

    WITH cte AS (SELECT x.ind_type, x.net_flag, round(sum(x.Shape.STArea() * (CASE WHEN x.urban='Y' THEN .88 ELSE .85 END))/43560,2) AS acres 
                FROM Sandbox.Mike.ilx_indprcl_net AS x         
                GROUP BY x.net_flag, x.ind_type)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([v], [r])) AS p;


/* -- For comparison estimates from 2015 CAI files 
   --import combined net supply geometry with exclusions erased into Sockeye via ogr2ogr as ili_2013_net 

    UPDATE Sandbox.Mike.ili_2013_net SET Shape=Shape.MakeValid();

    WITH cte AS(SELECT i.net_flag, c.county_nm, 
                round(sum(c.Shape.STDifference(e.Shape).STIntersection(i.Shape).STArea())/43560,2) AS acres
                FROM ElmerGeo.dbo.COUNTY_BACKGROUND AS c LEFT JOIN Sandbox.Mike.ili_2013_net AS i ON 1=1 JOIN Sandbox.Mike.ili_2013_net_exclude AS e ON 1=1
                WHERE c.county_fip IN('033','035','053','061')
                GROUP BY i.net_flag, c.county_nm)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([vacant], [redevelopable])) AS p;

    WITH cte AS(SELECT i.net_flag, m.mic, 
                round(sum(m.Shape.STIntersection(i.Shape).STArea())/43560 * .87,2) AS acres
                FROM ElmerGeo.dbo.MICEN AS m LEFT JOIN Sandbox.Mike.ili_2013_net AS i ON 1=1
                GROUP BY i.net_flag, m.mic)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([vacant], [redevelopable])) AS p;

    --query 2013 CAI estimates

    WITH cte AS(SELECT i.net_flag, c.county_nm,     
                round(sum(c.Shape.STIntersection(i.Shape).STArea()* CASE WHEN rg.class_desc='Metro' THEN .98 ELSE .95 END)/43560 * .9,2) AS acres
                FROM ElmerGeo.dbo.COUNTY_BACKGROUND AS c 
                JOIN Sandbox.Mike.ili_2013_net AS i ON 1=1
                LEFT JOIN ElmerGeo.dbo.REGIONAL_GEOGRAPHIES AS rg ON 1=1
                WHERE c.county_fip IN('033','035','053','061')
                GROUP BY i.net_flag, c.county_nm)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([vacant], [redevelopable])) AS p;

    WITH cte AS(SELECT i.net_flag, rg.class_desc,     
                round(sum(rg.Shape.STIntersection(i.Shape()).STArea())/43560 * .9,2) AS acres
                FROM Sandbox.Mike.ili_2013_net AS i
                JOIN ElmerGeo.dbo.REGIONAL_GEOGRAPHIES AS rg ON 1=1
                GROUP BY i.net_flag, rg.class_desc)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([vacant], [redevelopable])) AS p;

    WITH cte AS(SELECT i.net_flag, m.mic, 
                round(sum(m.Shape.STIntersection(i.Shape).STArea())/43560 * .88,2) AS acres
                FROM ElmerGeo.dbo.MICEN AS m LEFT JOIN Sandbox.Mike.ili_2013_net AS i ON 1=1
                GROUP BY i.net_flag, m.mic)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([vacant], [redevelopable])) AS p;
    */
