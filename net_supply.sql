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
    -- import both files into MSSQL via flat file import tool.

/* Step 2. Generate correct correspondence between ElmerGeo.dbo.parcels_urbansim_2018 and baseyear parcel_id */
    -- This doesn't need to be done again, but was a major issue; ElmerGeo.dbo.parcels_urbansim_2018.PIN had been erroneously assigned, along with coordinates, to many parcels
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
    --import via ogr2ogr into Sockeye

/* Step 4. Create primary table with necessary fields */
    UPDATE Sandbox.Mike.prcl18_netx
    SET Shape = Shape.MakeValid();
    GO

    DROP TABLE IF EXISTS Sandbox.Mike.ilx_indprcl_all;
    GO
    CREATE TABLE Sandbox.Mike.ilx_indprcl_all(parcel_id int PRIMARY KEY NOT NULL, 
                                              ind_type nvarchar(25), 
                                              county_id smallint, 
                                              mic nvarchar(40), 
                                              impval int, 
                                              gross_sqft int, 
                                              land_use_type_id smallint,
                                              net_flag nchar(1), 
                                              urban nchar(3),
                                              Shape geometry,
                                              CentroidShape geometry);
    GO 
    INSERT INTO Sandbox.Mike.ilx_indprcl_all(parcel_id, Shape, CentroidShape)
    SELECT p.OBJECTID AS parcel_id, p.Shape, p.Shape.STPointOnSurface()
    FROM ElmerGeo.dbo.PARCELS_URBANSIM_2018 AS p;
    GO
    CREATE SPATIAL INDEX ilxs_all_ind_parcels ON Sandbox.Mike.ilx_indprcl_all(CentroidShape)  
    USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (xmin = 1111000, ymin = -92400, xmax = 1520420, ymax = 476385));
    GO
    UPDATE x
    SET x.ind_type=i.ind_type 
    FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN Sandbox.Mike.ili20231221 AS i ON x.CentroidShape.STIntersects(i.Shape)=1;
    GO
    DELETE FROM Sandbox.Mike.ilx_indprcl_all WHERE ind_type IS NULL;
    GO
 
  -- Add key fields and stored geographic labels
    UPDATE x
    SET x.impval=i.improvements_value,
        x.gross_sqft=i.gross_sqft,
        x.land_use_type_id=i.land_use_type_id
    FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN Sandbox.Mike.by18_prcl_bldg AS i ON i.Shape.STIntersects(x.Shape)=1;
    GO
    UPDATE x 
    SET x.county_id=CAST(county_fip AS smallint)
    FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN ElmerGeo.dbo.COUNTY_BACKGROUND AS c ON x.CentroidShape.STIntersects(c.Shape)=1;
    GO
    UPDATE x 
    SET x.mic=m.mic
    FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN ElmerGeo.dbo.MICEN AS m ON x.CentroidShape.STIntersects(m.Shape)=1;    
    GO
    UPDATE x 
    SET x.urban=CASE WHEN r.class_desc='Metro' AND r.Juris<>'Bremerton' THEN 'Y' ELSE 'N' END
    FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN ElmerGeo.dbo.PSRC_REGION AS r ON x.CentroidShape.STIntersects(r.Shape)=1;    
    GO  
    
   --Add vacant and redevelopment flags
    UPDATE Sandbox.Mike.ilx_indprcl_all
    SET net_flag='v' WHERE impval IS NULL OR impval < 0.01 AND net_flag IS NULL;

    UPDATE Sandbox.Mike.ilx_indprcl_all
    SET net_flag='v' WHERE impval/gross_sqft < 0.01 AND gross_sqft<>0 AND net_flag IS NULL;    
    
    UPDATE Sandbox.Mike.ilx_indprcl_all
    SET net_flag='r' WHERE impval/gross_sqft < 5.35 AND gross_sqft<>0 AND net_flag IS NULL;        
    GO
    
/* Step 5. 2023 net supply queries */

    --Replicates 2015 method of market factor and ROI set-asides through a multiplier

    WITH cte AS (SELECT x.mic, x.net_flag, round(sum(p.Shape.STDifference(w.Shape).STArea() * (CASE WHEN x.urban='Y' THEN .88 ELSE .85 END))/43560,2) AS acres 
                FROM Sandbox.Mike.ilx_indprcl_net AS x JOIN Sandbox.Mike.prcl18_netx AS p ON x.parcel_id=p.parcel_id JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
                WHERE x.mic<>'' AND x.ind_type<>'Limited Industrial'
                GROUP BY x.net_flag, x.mic)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([v], [r])) AS pv;

    WITH cte AS (SELECT x.county_id, x.net_flag, round(sum(p.Shape.STDifference(w.Shape).STArea() * (CASE WHEN x.urban='Y' THEN .88 ELSE .85 END))/43560,2) AS acres 
                FROM Sandbox.Mike.ilx_indprcl_net AS x JOIN Sandbox.Mike.prcl18_netx AS p ON x.parcel_id=p.parcel_id JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
                WHERE x.ind_type<>'Limited Industrial'
                GROUP BY x.net_flag, x.county_id) 
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([v], [r])) AS pv;

    WITH cte AS (SELECT x.ind_type, x.net_flag, round(sum(p.Shape.STDifference(w.Shape).STArea() * (CASE WHEN x.urban='Y' THEN .88 ELSE .85 END))/43560,2) AS acres 
                FROM Sandbox.Mike.ilx_indprcl_net AS x  JOIN Sandbox.Mike.prcl18_netx AS p ON x.parcel_id=p.parcel_id JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
                WHERE x.ind_type<>'Limited Industrial'     
                GROUP BY x.net_flag, x.ind_type)
    SELECT * FROM cte PIVOT (max(acres) FOR net_flag IN([v], [r])) AS pv;
